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
        // ... (Giữ nguyên như trước)
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
        // ... (Giữ nguyên hàm setupCamera như phiên bản đã sửa lỗi 'guard body must not fall through' ở lần trước)
        // Đảm bảo nó dọn dẹp session cũ (của chính instance này) một cách cẩn thận.
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
        // ... (Giữ nguyên)
        switch currentPreviewFit.lowercased() {
        case "fitwidth", "fitheight": layer.videoGravity = .resizeAspectFill
        case "contain": layer.videoGravity = .resizeAspect
        case "cover": layer.videoGravity = .resizeAspectFill
        default: layer.videoGravity = .resizeAspectFill
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // ... (Giữ nguyên)
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
        let newPosition: AVCaptureDevice.Position = useFront ? .front : .back
        print("[CameraPlatformView-\(viewId)] switchCameraNative called. Requested: \(newPosition == .front ? "FRONT" : "BACK")")

        guard !isDeinitializing else {
            result(FlutterError(code: "INSTANCE_GONE", message: "Switching on deinitializing instance", details: nil))
            return
        }

        // Nếu camera đã ở đúng vị trí và session đang chạy thì không cần làm gì
        if self.currentCameraPosition == newPosition && (self.captureSession?.isRunning ?? false) {
            print("[CameraPlatformView-\(viewId)] Camera is already in the requested position and running.")
            result(nil)
            return
        }

        // Cập nhật vị trí camera mong muốn
        self.currentCameraPosition = newPosition
        
        // Gọi lại setupCamera để cấu hình lại toàn bộ session với camera mới.
        // Hàm setupCamera đã được thiết kế để dọn dẹp session cũ một cách an toàn.
        print("[CameraPlatformView-\(viewId)] Triggering setupCamera for new position.")
        self.setupCamera()
        
        result(nil)
    }
    
    private func cropImage(_ image: UIImage, toNormalizedRect cropRect: CGRect, targetViewIdForLog: Int64) -> UIImage? {
        guard let cgImage = image.cgImage else {
            print("[CameraPlatformView-\(targetViewIdForLog)] cropImage: Failed to get CGImage.")
            return nil
        }
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        let cropX = cropRect.origin.x * originalWidth
        let cropY = cropRect.origin.y * originalHeight
        let cropWidth = cropRect.size.width * originalWidth
        let cropHeight = cropRect.size.height * originalHeight
        
        guard cropWidth > 0 && cropHeight > 0 else {
            print("[CameraPlatformView-\(targetViewIdForLog)] cropImage: Invalid crop dimensions (width or height is zero).")
            return nil
        }
        let pixelCropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        guard let croppedCGImage = cgImage.cropping(to: pixelCropRect) else {
            print("[CameraPlatformView-\(targetViewIdForLog)] cropImage: cgImage.cropping failed.")
            return nil
        }
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func capturePhoto(result: @escaping FlutterResult) {
            guard !isDeinitializing else {
                DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE", message: "Capturing on deinitializing instance", details: nil)) }
                return
            }

            if self.isCameraPausedManually {
                print("[CameraPlatformView-\(viewId)] Attempting to capture PAUSED image.")
                guard let pausedAndRotatedImage = self.lastPausedFrameImage else {
                    DispatchQueue.main.async { result(FlutterError(code: "NO_PAUSED_FRAME", message: "Camera is paused, but no last frame was stored/rotated.", details: nil)) }
                    return
                }
                
                let localViewId = self.viewId
                let fitModeForCrop = self.currentPreviewFit.lowercased()

                if fitModeForCrop == "cover" {
                    print("[CameraPlatformView-\(localViewId)] Paused capture in 'cover' mode. Attempting to crop.")
                    DispatchQueue.main.async { [weak self] in
                        guard let strongSelf = self else {
                            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE_CROP_PAUSED", message: "Instance deallocated before crop for paused image.", details: nil)) }
                            return
                        }
                        var normalizedCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        if let previewLayer = strongSelf._hostView.previewLayer {
                            normalizedCropRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
                        }
                        strongSelf.processAndSaveImage(originalImage: pausedAndRotatedImage,
                                                       normalizedCropRect: normalizedCropRect,
                                                       shouldCropBasedOnRect: true,
                                                       viewId: localViewId,
                                                       resultCallback: result)
                    }
                } else {
                    print("[CameraPlatformView-\(localViewId)] Paused capture (Mode: '\(fitModeForCrop)'): Not 'cover'. Saving rotated paused image.")
                    self.processAndSaveImage(originalImage: pausedAndRotatedImage,
                                               normalizedCropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                               shouldCropBasedOnRect: false,
                                               viewId: localViewId,
                                               resultCallback: result)
                }
                return
            }

            // Live capture (không pause)
            print("[CameraPlatformView-\(viewId)] Attempting LIVE capture.")
            sessionQueue.async { [weak self] in
                guard let strongSelf = self, !strongSelf.isDeinitializing else { return }
                guard let photoOutput = strongSelf.photoOutput, let session = strongSelf.captureSession, session.isRunning else { return }
                let photoSettings = AVCapturePhotoSettings()
                strongSelf.pendingPhotoCaptureResult = result
                photoOutput.capturePhoto(with: photoSettings, delegate: strongSelf)
            }
        }
    
    private func processAndSaveImage(originalImage: UIImage,
                                     normalizedCropRect: CGRect,
                                     shouldCropBasedOnRect: Bool,
                                     viewId: Int64,
                                     resultCallback: @escaping FlutterResult) {
        // Thực hiện crop và lưu trên background thread để không block UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let strongSelf = self else {
                // Instance 'self' đã bị giải phóng trước khi kịp xử lý và lưu.
                DispatchQueue.main.async {
                    resultCallback(FlutterError(code: "INSTANCE_GONE_SAVE", message: "Instance deallocated before image could be processed/saved.", details: nil))
                }
                return
            }

            var imageToSave = originalImage
            var performActualCrop = false

            // Chỉ crop nếu được yêu cầu VÀ hình chữ nhật crop hợp lệ/không phải là toàn bộ ảnh
            if shouldCropBasedOnRect {
                if !(normalizedCropRect.equalTo(CGRect(x: 0, y: 0, width: 1, height: 1))) && normalizedCropRect.width > 0 && normalizedCropRect.height > 0 {
                    performActualCrop = true
                } else {
                    print("[CameraPlatformView-\(viewId)] processAndSaveImage: No crop needed based on rect (\(normalizedCropRect)).")
                }
            }

            if performActualCrop {
                print("[CameraPlatformView-\(viewId)] processAndSaveImage: Attempting crop.")
                if let croppedImage = strongSelf.cropImage(originalImage, toNormalizedRect: normalizedCropRect, targetViewIdForLog: viewId) {
                    imageToSave = croppedImage
                } else {
                    print("[CameraPlatformView-\(viewId)] processAndSaveImage: Cropping failed, using original image.")
                }
            }
            
            // Lưu ảnh cuối cùng (đã crop hoặc ảnh gốc)
            strongSelf.saveImageDataAndReturnPath(imageToSave.jpegData(compressionQuality: 0.9), viewId: viewId, resultCallback: resultCallback)
        }
    }
    
    // Hàm trợ giúp để lưu ảnh và trả kết quả về Flutter
        private func saveImageDataAndReturnPath(_ data: Data?, viewId: Int64, resultCallback: @escaping FlutterResult) {
            guard let imageDataToSave = data else {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "PROCESS_FAILED", message: "Failed to get final image data.", details: nil)) }
                return
            }
            let tempDir = NSTemporaryDirectory()
            let fileName = "photo_ios_\(viewId)_\(Date().timeIntervalSince1970).jpg"
            let filePath = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
            do {
                try imageDataToSave.write(to: filePath)
                DispatchQueue.main.async { resultCallback(filePath.path) }
            } catch {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "SAVE_FAILED", message: "Error saving photo: \(error.localizedDescription)", details: nil)) }
            }
        }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard let resultCallback = self.pendingPhotoCaptureResult else {
                // Nếu không có pending result, có thể là một capture không mong muốn, bỏ qua.
                print("[CameraPlatformView-\(viewId)] photoOutput called without a pending result callback.")
                return
            }
            self.pendingPhotoCaptureResult = nil // Luôn dọn dẹp callback
            
            guard !isDeinitializing else {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "INSTANCE_DEINIT_CAPTURE", message: "Instance deinitializing during photo capture.", details: nil)) }
                return
            }
            
            if let error = error {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "CAPTURE_FAILED_PHOTO", message: "Error capturing photo: \(error.localizedDescription)", details: nil)) }
                return
            }
            
            guard let imageData = photo.fileDataRepresentation(), let originalImage = UIImage(data: imageData) else {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "IMAGE_DATA_ERROR", message: "No image data or could not create UIImage.", details: nil)) }
                return
            }
            
            let localViewId = self.viewId
            let fitModeForCrop = self.currentPreviewFit.lowercased()

            // Logic crop cho ảnh live vẫn được giữ nguyên
            if fitModeForCrop == "cover" {
                DispatchQueue.main.async { [weak self] in
                    guard let strongSelf = self else {
                        DispatchQueue.main.async { resultCallback(FlutterError(code: "INSTANCE_GONE_CROP_PARAMS_LIVE", message: "Instance deallocated before crop.", details: nil)) }
                        return
                    }
                    var normalizedCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    if let previewLayer = strongSelf._hostView.previewLayer {
                        normalizedCropRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
                    }
                    strongSelf.processAndSaveImage(originalImage: originalImage,
                                                   normalizedCropRect: normalizedCropRect,
                                                   shouldCropBasedOnRect: true,
                                                   viewId: localViewId,
                                                   resultCallback: resultCallback)
                }
            } else {
                self.processAndSaveImage(originalImage: originalImage,
                                           normalizedCropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                           shouldCropBasedOnRect: false,
                                           viewId: localViewId,
                                           resultCallback: resultCallback)
            }
        }
    
    
    private func pauseCameraNative(result: @escaping FlutterResult) {
        print("[CameraPlatformView-\(viewId)] pauseCameraNative called.")
        isCameraPausedManually = true
        
        // Trên iOS, "pause" có nghĩa là dừng session để tiết kiệm pin.
        // `lastPausedFrameImage` đã được cập nhật liên tục bởi `captureOutput` nên sẽ giữ lại frame cuối.
        sessionQueue.async { [weak self] in
            guard let strongSelf = self else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            if let session = strongSelf.captureSession, session.isRunning {
                session.stopRunning()
                print("[CameraPlatformView-\(strongSelf.viewId)] Session stopped for pause.")
            } else {
                print("[CameraPlatformView-\(strongSelf.viewId)] Session was already stopped or nil when pausing.")
            }
            
            // Báo cho Flutter biết đã pause xong
            DispatchQueue.main.async {
                result(nil)
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
        print("[CameraPlatformView-\(viewId)] resumeCameraNative called.")
        isCameraPausedManually = false
        
        // Khi resume, chúng ta chỉ cần khởi động lại session.
        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            if let session = strongSelf.captureSession, !session.isRunning {
                print("[CameraPlatformView-\(strongSelf.viewId)] Session not running on resume. Starting it.")
                session.startRunning()
            } else if strongSelf.captureSession == nil {
                 // Nếu session bị hủy vì lý do nào đó, hãy thiết lập lại
                print("[CameraPlatformView-\(strongSelf.viewId)] Session is nil on resume. Re-running setup.")
                strongSelf.setupCamera()
            } else {
                print("[CameraPlatformView-\(strongSelf.viewId)] Session was already running on resume.")
            }
            
            DispatchQueue.main.async { result(nil) }
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard !isDeinitializing else { return }
            guard output == self.videoDataOutput else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            // Xoay ảnh về đúng chiều dọc
            let imageOrientation: UIImage.Orientation = self.currentCameraPosition == .front ? .leftMirrored : .right
            let rotatedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
            
            // LUÔN LUÔN cập nhật lastPausedFrameImage với frame mới nhất đã được xoay.
            // Đây là nguồn duy nhất cho ảnh chụp khi pause.
            self.lastPausedFrameImage = rotatedImage
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
