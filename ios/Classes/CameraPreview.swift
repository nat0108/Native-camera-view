// File: ios/Runner/SwiftCameraPreview.swift
import Flutter
import UIKit
import AVFoundation

// Lớp UIView tùy chỉnh để quản lý frame của previewLayer
class CameraHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = self.bounds
    }
    deinit {
        print("[CameraHostView-\(ObjectIdentifier(self))] DEINIT: Dọn dẹp previewLayer.")
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
}

class CameraPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    // ... (Giữ nguyên)
    private var messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }
    func create( withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return CameraPlatformView( frame: frame, viewIdentifier: viewId, arguments: args, binaryMessenger: messenger)
    }
    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

enum CameraSetupError: Error, LocalizedError {
    // ... (Giữ nguyên)
    case failedToGetCaptureDevice
    case couldNotAddInput
    case couldNotAddPhotoOutput
    case couldNotAddVideoDataOutput

    var errorDescription: String? {
        switch self {
        case .failedToGetCaptureDevice: return "Failed to get capture device."
        case .couldNotAddInput: return "Could not add input to session."
        case .couldNotAddPhotoOutput: return "Could not add PhotoOutput to session."
        case .couldNotAddVideoDataOutput: return "Could not add VideoDataOutput to session."
        }
    }
}

class CameraPlatformView: NSObject, FlutterPlatformView,
    AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate
{
    // ... (Các properties giữ nguyên như phiên bản trước bạn cung cấp)
    private var _hostView: CameraHostView
    private var messenger: FlutterBinaryMessenger
    private var viewId: Int64
    private var methodChannel: FlutterMethodChannel?

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentCameraInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var isCameraPausedManually = false
    private var currentPreviewFit: String = "cover"
    private var pendingPhotoCaptureResult: FlutterResult?

    private let sessionQueue = DispatchQueue(label: "com.plugin.camera_native.native_camera_view.sessionQueue.view-\(UUID().uuidString)")
    private var isDeinitializing = false
    private var lastPausedFrameImage: UIImage?

    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let videoDataOutputQueue = DispatchQueue(label: "com.plugin.camera_native.native_camera_view.videoDataOutputQueue.view-\(UUID().uuidString)", qos: .userInitiated)
    private var lastFrameAsUIImage: UIImage?
    private lazy var ciContext = CIContext()


    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        self.messenger = messenger
        self.viewId = viewId
        self._hostView = CameraHostView(frame: frame)
        
        if let params = args as? [String: Any] {
            if let useFront = params["isFrontCamera"] as? Bool, useFront {
                self.currentCameraPosition = .front
            } else {
                self.currentCameraPosition = .back
            }
            if let fitMode = params["cameraPreviewFit"] as? String {
                self.currentPreviewFit = fitMode
            }
        }
        
        self.methodChannel = FlutterMethodChannel(
            name: "com.plugin.camera_native.native_camera_view/camera_method_channel_ios_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        print("[CameraPlatformView-\(viewId)] INIT with lens: \(self.currentCameraPosition == .front ? "FRONT":"BACK"). Frame: \(frame), Thread: \(Thread.current)")

        self.methodChannel?.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let strongSelf = self else {
                DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE", message: "Platform view instance was deallocated.", details: nil)) }
                return
            }
            guard !strongSelf.isDeinitializing else {
                 DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_DEINITIALIZING", message: "Platform view instance is deinitializing.", details: nil)) }
                return
            }
            strongSelf.handleMethodCall(call, result: result)
        })
        
        print("[CameraPlatformView-\(viewId)] Parsed arguments: fitMode=\(self.currentPreviewFit), useFront=\(self.currentCameraPosition == .front)")
        checkCameraPermissionsAndSetup()
    }

    func view() -> UIView { return _hostView }

    private func checkCameraPermissionsAndSetup() {
        print("[CameraPlatformView-\(viewId)] checkCameraPermissionsAndSetup CALLED")
        guard !isDeinitializing else {
            print("[CameraPlatformView-\(viewId)] checkCameraPermissionsAndSetup: Instance is deinitializing, aborting.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("[CameraPlatformView-\(viewId)] Permission authorized.")
            self.setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let strongSelf = self, !strongSelf.isDeinitializing else { return }
                DispatchQueue.main.async {
                    if granted { strongSelf.setupCamera() } else { /* Xử lý từ chối */ }
                }
            }
        default:
            print("[CameraPlatformView-\(viewId)] Camera permission not granted or restricted.")
            DispatchQueue.main.async {
                self.methodChannel?.invokeMethod("onError", arguments: "camera_permission_issue")
            }
        }
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                print("[CameraPlatformView-AGGREGATED] setupCamera: strongSelf is nil or deinitializing.")
                return
            }
            let viewId = strongSelf.viewId
            let targetLens = strongSelf.currentCameraPosition

            print("[CameraPlatformView-\(viewId)] setupCamera: Called on sessionQueue. Target lens: \(targetLens == .front ? "FRONT" : "BACK")")

            if let existingSession = strongSelf.captureSession {
                print("[CameraPlatformView-\(viewId)] setupCamera: Cleaning up existing session.")
                if existingSession.isRunning { existingSession.stopRunning() }
                existingSession.inputs.forEach { existingSession.removeInput($0) }
                existingSession.outputs.forEach { existingSession.removeOutput($0) }
                if let videoOutput = strongSelf.videoDataOutput {
                    videoOutput.setSampleBufferDelegate(nil, queue: nil)
                }
                strongSelf.videoDataOutput = nil
                strongSelf.lastFrameAsUIImage = nil
                strongSelf.photoOutput = nil
                strongSelf.currentCameraInput = nil
            }
            strongSelf.captureSession = nil

            print("[CameraPlatformView-\(viewId)] setupCamera: Creating new session for \(targetLens == .front ? "FRONT" : "BACK").")
            let newSession = AVCaptureSession()
            strongSelf.captureSession = newSession
            newSession.sessionPreset = .photo

            var configurationSuccess = true
            newSession.beginConfiguration()
            print("[CameraPlatformView-\(viewId)] setupCamera: newSession.beginConfiguration() called.")

            do {
                guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: targetLens) else {
                    print("[CameraPlatformView-\(viewId)] setupCamera: Failed to get camera device for \(targetLens).")
                    throw CameraSetupError.failedToGetCaptureDevice
                }
                print("[CameraPlatformView-\(viewId)] setupCamera: Obtained capture device: \(captureDevice.localizedName) for \(targetLens)")

                let input = try AVCaptureDeviceInput(device: captureDevice)
                if newSession.canAddInput(input) { newSession.addInput(input); strongSelf.currentCameraInput = input }
                else { throw CameraSetupError.couldNotAddInput }
                
                let newPhotoOutput = AVCapturePhotoOutput()
                if newSession.canAddOutput(newPhotoOutput) { newSession.addOutput(newPhotoOutput); strongSelf.photoOutput = newPhotoOutput }
                else { throw CameraSetupError.couldNotAddPhotoOutput }

                let newVideoDataOutput = AVCaptureVideoDataOutput()
                newVideoDataOutput.alwaysDiscardsLateVideoFrames = true
                newVideoDataOutput.setSampleBufferDelegate(strongSelf, queue: strongSelf.videoDataOutputQueue)
                if newSession.canAddOutput(newVideoDataOutput) {
                    newSession.addOutput(newVideoDataOutput)
                    strongSelf.videoDataOutput = newVideoDataOutput
                    if let connection = newVideoDataOutput.connection(with: .video) {
                        if connection.isVideoOrientationSupported { /* TODO: Set orientation */ }
                        if connection.isVideoMirroringSupported && targetLens == .front { connection.isVideoMirrored = true }
                    }
                } else { throw CameraSetupError.couldNotAddVideoDataOutput }

            } catch let errorDescribable as LocalizedError {
                print("[CameraPlatformView-\(viewId)] setupCamera: Error during I/O setup: \(errorDescribable.localizedDescription)")
                configurationSuccess = false
            } catch {
                print("[CameraPlatformView-\(viewId)] setupCamera: Unknown error during I/O setup: \(error)")
                configurationSuccess = false
            }

            newSession.commitConfiguration()
            print("[CameraPlatformView-\(viewId)] setupCamera: newSession.commitConfiguration() called. configurationSuccess: \(configurationSuccess)")

            guard configurationSuccess else {
                print("[CameraPlatformView-\(viewId)] setupCamera: Configuration failed. Cleaning up.")
                if strongSelf.captureSession === newSession { strongSelf.captureSession = nil }
                strongSelf.videoDataOutput?.setSampleBufferDelegate(nil, queue: nil); strongSelf.videoDataOutput = nil
                strongSelf.photoOutput = nil; strongSelf.currentCameraInput = nil
                return
            }

            if !strongSelf.isCameraPausedManually {
                if strongSelf.captureSession === newSession && !newSession.isRunning {
                    newSession.startRunning()
                    print("[CameraPlatformView-\(viewId)] setupCamera: newSession started for \(targetLens).")
                }
            } else {
                print("[CameraPlatformView-\(viewId)] setupCamera: Camera manually paused, not starting session for \(targetLens).")
            }
            
            DispatchQueue.main.async {
                guard let sSelf = self, !sSelf.isDeinitializing, sSelf.captureSession === newSession else { return }
                let previewLayer = AVCaptureVideoPreviewLayer(session: newSession)
                sSelf._hostView.previewLayer?.removeFromSuperlayer()
                sSelf._hostView.previewLayer = previewLayer
                sSelf.applyPreviewFitToLayer(layer: previewLayer)
                sSelf._hostView.layer.insertSublayer(previewLayer, at: 0)
                sSelf._hostView.setNeedsLayout()
                print("[CameraPlatformView-\(sSelf.viewId)] setupCamera: Preview layer configured for \(targetLens).")
            }
        }
    }
    
    private func applyPreviewFitToLayer(layer: AVCaptureVideoPreviewLayer) {
        switch currentPreviewFit.lowercased() {
        case "fitwidth", "fitheight": layer.videoGravity = .resizeAspectFill
        case "contain": layer.videoGravity = .resizeAspect
        case "cover": layer.videoGravity = .resizeAspectFill
        default: layer.videoGravity = .resizeAspectFill
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("[CameraPlatformView-\(viewId)] handleMethodCall: \(call.method)")
        guard !isDeinitializing else {
             DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_DEINITIALIZING_HANDLER", message: "Instance is deinitializing.", details: nil)) }
            return
        }
        switch call.method {
        case "captureImage": capturePhoto(result: result)
        case "pauseCamera": pauseCameraNative(result: result)
        case "resumeCamera": resumeCameraNative(result: result)
        case "switchCamera":
            if let args = call.arguments as? [String: Any],
               let useFront = args["useFrontCamera"] as? Bool
            {
                switchCameraNative(useFront: useFront, result: result)
            } else {
                DispatchQueue.main.async { result(FlutterError(code: "INVALID_ARGUMENT",message: "Missing 'useFrontCamera'", details: nil)) }
            }
        default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
    }

    private func switchCameraNative(useFront: Bool, result: @escaping FlutterResult) {
        let localViewId = self.viewId // Capture for logging, self might be gone if called weirdly
        print("[CameraPlatformView-\(localViewId)] switchCameraNative received. Requested front: \(useFront). Current instance's position: \(self.currentCameraPosition == .front ? "FRONT" : "BACK")")
        
        guard !isDeinitializing else {
            print("[CameraPlatformView-\(localViewId)] switchCameraNative on deinitializing instance. Aborting.")
            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE_SWITCH", message: "Switching on deinitializing instance", details: nil)) }
            return
        }

        // Logic mới:
        // 1. Phương thức này chỉ cần báo cho Flutter biết rằng việc chuyển đổi đã được yêu cầu.
        // 2. Flutter (phía Dart) sẽ chịu trách nhiệm rebuild widget CameraPreview
        //    với tham số isFrontCamera mới.
        // 3. Việc rebuild này sẽ khiến Flutter dispose PlatformView hiện tại (trigger deinit)
        //    và tạo một PlatformView mới với arguments mới.
        // 4. PlatformView mới sẽ tự động init và setupCamera với đúng camera từ arguments.

        // KHÔNG gọi self.setupCamera() tại đây nữa.
        // KHÔNG thay đổi self.currentCameraPosition của instance này nữa, vì nó sắp bị dispose.

        print("[CameraPlatformView-\(localViewId)] switchCameraNative: Acknowledging request. Flutter is expected to recreate the PlatformView with 'isFrontCamera: \(useFront)'. This instance (\(localViewId)) will likely be deallocated soon.")
        
        DispatchQueue.main.async {
            result(nil) // Trả về nil để báo hiệu lệnh đã được xử lý thành công ở native.
        }
    }

    private func capturePhoto(result: @escaping FlutterResult) {
        guard !isDeinitializing else {
            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE", message: "Capturing on deinitializing instance", details: nil)) }
            return
        }
        if self.isCameraPausedManually {
            guard let pausedImage = self.lastPausedFrameImage else {
                DispatchQueue.main.async { result(FlutterError(code: "NO_PAUSED_FRAME", message: "Camera paused, no last frame.", details: nil)) }
                return
            }
            guard let imageData = pausedImage.jpegData(compressionQuality: 0.9) else {
                DispatchQueue.main.async { result(FlutterError(code: "IMAGE_DATA_ERROR", message: "Failed to get JPEG data from paused image.", details: nil)) }
                return
            }
            let tempDir = NSTemporaryDirectory()
            let fileName = "paused_photo_ios_\(viewId)_\(Date().timeIntervalSince1970).jpg"
            let filePath = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
            do {
                try imageData.write(to: filePath)
                DispatchQueue.main.async { result(filePath.path) }
            } catch {
                DispatchQueue.main.async { result(FlutterError(code: "SAVE_FAILED", message: "Error saving paused photo: \(error.localizedDescription)", details: nil)) }
            }
            return
        }

        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE_CAPTURE", message: "Instance gone for live capture.", details: nil)) }
                return
            }
            guard let photoOutput = strongSelf.photoOutput, let session = strongSelf.captureSession, session.isRunning else {
                DispatchQueue.main.async { result(FlutterError(code: "CAMERA_UNAVAILABLE_CAPTURE", message: "Camera not ready for live capture.", details: nil)) }
                return
            }
            let photoSettings = AVCapturePhotoSettings()
            strongSelf.pendingPhotoCaptureResult = result
            photoOutput.capturePhoto(with: photoSettings, delegate: strongSelf)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard !isDeinitializing else {
            if self.pendingPhotoCaptureResult != nil { self.pendingPhotoCaptureResult = nil }
            return
        }
        guard let resultCallback = self.pendingPhotoCaptureResult else { return }
        self.pendingPhotoCaptureResult = nil
        if let error = error {
            DispatchQueue.main.async { resultCallback(FlutterError(code: "CAPTURE_FAILED_PHOTO", message: "Error capturing photo: \(error.localizedDescription)", details: nil)) }
            return
        }
        guard let imageData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { resultCallback(FlutterError(code: "CAPTURE_NO_DATA", message: "No image data from capture.", details: nil)) }
            return
        }
        let tempDir = NSTemporaryDirectory()
        let fileName = "photo_ios_\(viewId)_\(Date().timeIntervalSince1970).jpg"
        let filePath = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        do {
            try imageData.write(to: filePath)
            DispatchQueue.main.async { resultCallback(filePath.path) }
        } catch {
            DispatchQueue.main.async { resultCallback(FlutterError(code: "SAVE_FAILED_PHOTO", message: "Error saving photo: \(error.localizedDescription)", details: nil)) }
        }
    }

    private func pauseCameraNative(result: @escaping FlutterResult) {
        guard !isDeinitializing else {
            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE", message: "Pausing on deinitializing instance", details: nil)) }
            return
        }
        videoDataOutputQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_NIL_PAUSE", message: "Instance dealloc/deinit during pause.", details: nil)) }
                return
            }
            let imageToPauseWith = strongSelf.lastFrameAsUIImage
            DispatchQueue.main.async {
                guard !strongSelf.isDeinitializing else {
                    strongSelf.sessionQueue.async { strongSelf.stopSessionForPauseInternal(); DispatchQueue.main.async { result(nil) } }
                    return
                }
                strongSelf.lastPausedFrameImage = imageToPauseWith
                strongSelf.isCameraPausedManually = true
                strongSelf.sessionQueue.async { strongSelf.stopSessionForPauseInternal(); DispatchQueue.main.async { result(nil) } }
            }
        }
    }

    private func stopSessionForPauseInternal() {
        guard !isDeinitializing else { return }
        if let session = self.captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    private func resumeCameraNative(result: @escaping FlutterResult) {
        guard !isDeinitializing else {
            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE", message: "Resuming on deinitializing instance", details: nil)) }
            return
        }
        isCameraPausedManually = false
        lastPausedFrameImage = nil
        videoDataOutputQueue.async { [weak self] in self?.lastFrameAsUIImage = nil }

        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            if strongSelf.captureSession == nil {
                strongSelf.setupCamera()
            } else if !(strongSelf.captureSession!.isRunning) {
                strongSelf.captureSession!.startRunning()
            }
            DispatchQueue.main.async { result(nil) }
        }
    }
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isDeinitializing else { return }
        guard output == self.videoDataOutput else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        self.lastFrameAsUIImage = UIImage(cgImage: cgImage)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isDeinitializing else { return }
    }
    
    deinit {
        isDeinitializing = true
        let currentViewId = self.viewId
        print("[CameraPlatformView-\(currentViewId)] DEINIT: Running on thread: \(Thread.current)")
        print("[CameraPlatformView-\(currentViewId)] DEINIT: Bắt đầu quá trình giải phóng.")

        let capturedSession = self.captureSession
        let capturedPhotoOutput = self.photoOutput
        let capturedVideoDataOutput = self.videoDataOutput // Tham chiếu mạnh đến output
        let capturedCurrentCameraInput = self.currentCameraInput
        let capturedMethodChannel = self.methodChannel

        // Tất cả thao tác dọn dẹp AVFoundation nên được đưa lên sessionQueue và thực hiện đồng bộ
        // để đảm bảo chúng hoàn tất trước khi deinit kết thúc.
        print("[CameraPlatformView-\(currentViewId)] DEINIT: Dispatching all AVFoundation cleanup to sessionQueue (SYNC)...")
        self.sessionQueue.sync { // SYNC block lớn cho tất cả AVFoundation cleanup
            print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Starting AVFoundation cleanup...")

            // 1. Dừng session
            if capturedSession?.isRunning ?? false {
                capturedSession?.stopRunning()
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session đã dừng.")
            } else {
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session không chạy hoặc đã nil.")
            }

            // 2. Gỡ bỏ I/O khỏi session
            if let session = capturedSession {
                if let photoOut = capturedPhotoOutput, session.outputs.contains(photoOut) {
                    session.removeOutput(photoOut)
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) PhotoOutput removed.")
                }
                if let videoOut = capturedVideoDataOutput, session.outputs.contains(videoOut) {
                    session.removeOutput(videoOut) // Gỡ output khỏi session
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) VideoDataOutput removed from session.")

                    // 3. Gỡ delegate của VideoDataOutput SAU KHI đã gỡ nó khỏi session
                    //    Và thực hiện trên cùng sessionQueue này (hoặc videoDataOutputQueue nếu bạn muốn, nhưng sessionQueue có vẻ hợp lý hơn cho việc quản lý vòng đời output)
                    //    Không cần dispatch riêng lên videoDataOutputQueue nữa nếu làm ở đây.
                    videoOut.setSampleBufferDelegate(nil, queue: nil)
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Delegate của VideoDataOutput đã gỡ (nil).")
                }
                if let camInput = capturedCurrentCameraInput, session.inputs.contains(camInput) {
                    session.removeInput(camInput)
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) CameraInput removed.")
                }
            } else {
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session đã nil, không gỡ I/O.")
            }
            print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) AVFoundation cleanup finished.")
        } // Kết thúc sessionQueue.sync

        // Hủy method channel handler không đồng bộ trên main thread
        DispatchQueue.main.async {
            capturedMethodChannel?.setMethodCallHandler(nil)
            print("[CameraPlatformView-\(currentViewId)] DEINIT: MethodChannel handler đã gỡ (async).")
        }

        // Gán nil cho các property để giải phóng tham chiếu mạnh
        // Các đối tượng AVFoundation đã được captured và xử lý trong sessionQueue.sync
        self.captureSession = nil
        self.photoOutput = nil
        self.videoDataOutput = nil // Property này sẽ được ARC giải phóng sau khi capturedVideoDataOutput ra khỏi scope
        self.currentCameraInput = nil
        self.methodChannel = nil
        self.pendingPhotoCaptureResult = nil
        self.lastPausedFrameImage = nil
        self.lastFrameAsUIImage = nil

        print("[CameraPlatformView-\(currentViewId)] DEINIT: Hoàn tất quá trình giải phóng (synchronous part).")
    }
}
