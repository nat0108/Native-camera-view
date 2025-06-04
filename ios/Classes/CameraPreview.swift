// File: ios/Runner/SwiftCameraPreview.swift
import Flutter
import UIKit
import AVFoundation

// Delegate protocol
protocol CameraHostViewLayoutDelegate: AnyObject {
    func cameraHostViewDidLayoutSubviews()
}

class CameraHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var layoutDelegate: CameraHostViewLayoutDelegate?

    override func layoutSubviews() {
        super.layoutSubviews()
        // Thông báo cho delegate để CameraPlatformView có thể cập nhật frame của previewLayer
        layoutDelegate?.cameraHostViewDidLayoutSubviews()
    }

    deinit {
        print("[CameraHostView-\(ObjectIdentifier(self))] DEINIT: Dọn dẹp previewLayer.")
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
}

class CameraPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
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
    AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, CameraHostViewLayoutDelegate // Thêm CameraHostViewLayoutDelegate
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
        self._hostView = CameraHostView(frame: frame) // Khởi tạo _hostView
        
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
        self._hostView.layoutDelegate = self // Gán delegate SAU khi super.init()

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

    // Hàm delegate được gọi từ CameraHostView
    func cameraHostViewDidLayoutSubviews() {
        // print("[CameraPlatformView-\(viewId)] cameraHostViewDidLayoutSubviews triggered.")
        DispatchQueue.main.async { // Đảm bảo thao tác UI trên main thread
             self.updatePreviewLayerFrameAndGravity()
        }
    }

    private func updatePreviewLayerFrameAndGravity() {
            guard let previewLayer = _hostView.previewLayer else { return }
            let hostViewBounds = _hostView.bounds
            if hostViewBounds == .zero { return }

            let fitMode = currentPreviewFit.lowercased()
            print("[CameraPlatformView-\(viewId)] updatePreviewLayerFrameAndGravity: Mode '\(fitMode)', hostBounds: \(hostViewBounds)")

            if fitMode == "contain" {
                // Logic "contain" (top-aligned) như đã sửa ở lần trước
                guard let currentDevice = currentCameraInput?.device, currentDevice.isConnected else {
                    if previewLayer.frame != hostViewBounds { previewLayer.frame = hostViewBounds }
                    if previewLayer.videoGravity != .resizeAspect { previewLayer.videoGravity = .resizeAspect }
                    return
                }
                let activeFormat = currentDevice.activeFormat
                let formatDescription = activeFormat.formatDescription
                let videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                if videoDimensions.width <= 0 || videoDimensions.height <= 0 {
                    if previewLayer.frame != hostViewBounds { previewLayer.frame = hostViewBounds }
                    if previewLayer.videoGravity != .resizeAspect { previewLayer.videoGravity = .resizeAspect }
                    return
                }
                let videoAspectRatio = CGFloat(videoDimensions.width) / CGFloat(videoDimensions.height)
                let viewWidth = hostViewBounds.width
                let viewHeight = hostViewBounds.height
                var finalFrame: CGRect
                var finalGravity: AVLayerVideoGravity
                let potentialLayerHeightIfWidthFilled = viewWidth / videoAspectRatio
                if potentialLayerHeightIfWidthFilled <= viewHeight {
                    finalFrame = CGRect(x: 0, y: 0, width: viewWidth, height: potentialLayerHeightIfWidthFilled)
                    finalGravity = .resizeAspectFill
                } else {
                    let layerHeight = viewHeight
                    let layerWidth = layerHeight * videoAspectRatio
                    let layerX = (viewWidth - layerWidth) / 2
                    finalFrame = CGRect(x: layerX, y: 0, width: layerWidth, height: layerHeight)
                    finalGravity = .resizeAspect
                }
                if previewLayer.frame != finalFrame { previewLayer.frame = finalFrame }
                if previewLayer.videoGravity != finalGravity { previewLayer.videoGravity = finalGravity }
            } else if fitMode == "cover" { // Chế độ COVER
                if previewLayer.frame != hostViewBounds { previewLayer.frame = hostViewBounds }
                if previewLayer.videoGravity != .resizeAspectFill { previewLayer.videoGravity = .resizeAspectFill }
            } else { // Mặc định cho các mode khác (ví dụ: fitWidth, fitHeight sẽ giống cover)
                if previewLayer.frame != hostViewBounds { previewLayer.frame = hostViewBounds }
                if previewLayer.videoGravity != .resizeAspectFill { previewLayer.videoGravity = .resizeAspectFill }
            }
        }

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
                    if granted { strongSelf.setupCamera() } else { print("[CameraPlatformView-\(strongSelf.viewId)] Permission denied by user.") }
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

                let input = try AVCaptureDeviceInput(device: captureDevice) // Corrected: No "!"
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
            
            DispatchQueue.main.async { // Setup preview layer on main thread
                guard let sSelf = self, !sSelf.isDeinitializing, sSelf.captureSession === newSession else { return }
                
                let newPreviewLayer = AVCaptureVideoPreviewLayer(session: newSession)
                sSelf._hostView.previewLayer?.removeFromSuperlayer() // Gỡ layer cũ
                sSelf._hostView.previewLayer = newPreviewLayer     // Gán layer mới cho CameraHostView
                sSelf._hostView.layer.addSublayer(newPreviewLayer) // Thêm vào layer của _hostView
                
                // Gọi hàm cập nhật frame và gravity sau khi layer được tạo và thêm
                sSelf.updatePreviewLayerFrameAndGravity()
                // sSelf._hostView.setNeedsLayout() // Có thể không cần thiết ngay ở đây nữa vì updatePreviewLayerFrameAndGravity sẽ được gọi lại từ layoutDelegate

                print("[CameraPlatformView-\(sSelf.viewId)] setupCamera: Preview layer configured & initial layout updated for \(targetLens).")
                if let connection = newPreviewLayer.connection {
                    if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = true }
                    // TODO: connection.videoOrientation
                }
            }
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
        // Thêm case cho việc thay đổi fit mode từ Flutter
        case "setPreviewFit":
            if let fitName = call.arguments as? String {
                self.currentPreviewFit = fitName
                DispatchQueue.main.async {
                    self.updatePreviewLayerFrameAndGravity() // Cập nhật layout khi fit mode thay đổi
                }
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'fitName' for setPreviewFit", details: nil))
            }
        default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
    }

    private func switchCameraNative(useFront: Bool, result: @escaping FlutterResult) {
        let localViewId = self.viewId
        print("[CameraPlatformView-\(localViewId)] switchCameraNative received. Requested front: \(useFront). Current instance's position: \(self.currentCameraPosition == .front ? "FRONT" : "BACK")")
        
        guard !isDeinitializing else {
            print("[CameraPlatformView-\(localViewId)] switchCameraNative on deinitializing instance. Aborting.")
            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE_SWITCH", message: "Switching on deinitializing instance", details: nil)) }
            return
        }
        print("[CameraPlatformView-\(localViewId)] switchCameraNative: Acknowledging request. Flutter is expected to recreate the PlatformView with 'isFrontCamera: \(useFront)'. This instance (\(localViewId)) will likely be deallocated soon.")
        DispatchQueue.main.async { result(nil) }
    }
    
    // Hàm crop ảnh mới
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
            let pixelCropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

            print("[CameraPlatformView-\(targetViewIdForLog)] cropImage: Original size \(originalWidth)x\(originalHeight), normalizedCropRect: \(cropRect), pixelCropRect: \(pixelCropRect)")

            guard let croppedCGImage = cgImage.cropping(to: pixelCropRect) else {
                print("[CameraPlatformView-\(targetViewIdForLog)] cropImage: cgImage.cropping failed for rect \(pixelCropRect). Image dimensions: w=\(cgImage.width), h=\(cgImage.height)")
                return nil
            }
            return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        }
    
    // Hàm lưu ảnh và trả kết quả về Flutter
        private func saveImageDataAndReturnPath(_ data: Data?, viewId: Int64, resultCallback: @escaping FlutterResult) {
            guard let imageDataToSave = data else {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "PROCESS_FAILED", message: "Failed to get final image data for saving.", details: nil)) }
                return
            }
            let tempDir = NSTemporaryDirectory()
            let fileName = "photo_ios_\(viewId)_\(Date().timeIntervalSince1970).jpg"
            let filePath = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
            do {
                try imageDataToSave.write(to: filePath)
                print("[CameraPlatformView-\(viewId)] Image saved to: \(filePath.path)")
                DispatchQueue.main.async { resultCallback(filePath.path) }
            } catch {
                DispatchQueue.main.async { resultCallback(FlutterError(code: "SAVE_FAILED_PERSIST", message: "Error persisting photo: \(error.localizedDescription)", details: nil)) }
            }
        }

    private func capturePhoto(result: @escaping FlutterResult) {
            guard !isDeinitializing else {
                DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE", message: "Capturing on deinitializing instance", details: nil)) }
                return
            }

            if self.isCameraPausedManually {
                print("[CameraPlatformView-\(viewId)] Attempting to capture PAUSED image.")
                guard let pausedImage = self.lastPausedFrameImage else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NO_PAUSED_FRAME", message: "Camera is paused, but no last frame was stored.", details: nil))
                    }
                    return
                }

                let localViewId = self.viewId
                let fitModeForCrop = self.currentPreviewFit.lowercased()
                let originalImageForPausedCapture = pausedImage // Giữ lại ảnh gốcเผื่อ crop lỗi

                if fitModeForCrop == "cover" {
                    print("[CameraPlatformView-\(localViewId)] Paused capture in 'cover' mode. Attempting to crop.")
                    
                    // Giai đoạn 1: Lấy crop rectangle trên main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let strongSelf = self else {
                            print("[CameraPlatformView-\(localViewId)] Paused capture ('cover'): self deallocated before crop analysis. Saving original paused image.")
                            // Gọi hàm lưu ảnh gốc (nếu self nil, không thể gọi instance method, phải có cách khác hoặc trả lỗi)
                            // Trong trường hợp này, vì không thể crop, chúng ta sẽ lưu ảnh gốc
                            // Cần một cách lưu mà không phụ thuộc vào self, hoặc gọi result với lỗi
                            // Để đơn giản, nếu self nil ở đây, chúng ta không thể tiếp tục crop một cách an toàn.
                            DispatchQueue.main.async {
                                result(FlutterError(code: "INSTANCE_GONE_CROP_PAUSED", message: "Instance deallocated before crop for paused image.", details: nil))
                            }
                            return
                        }

                        var normalizedCropRect = CGRect(x: 0, y: 0, width: 1, height: 1) // Mặc định không crop

                        if let previewLayer = strongSelf._hostView.previewLayer,
                           (previewLayer.session != nil || strongSelf.captureSession != nil) { // Cần previewLayer và session (dù có thể đã stop) để tính toán
                            normalizedCropRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
                            print("[CameraPlatformView-\(localViewId)] Paused capture ('cover'): Calculated normalizedCropRect: \(normalizedCropRect)")
                        } else {
                            print("[CameraPlatformView-\(localViewId)] Paused capture ('cover'): PreviewLayer not usable for crop. Will use full image (no crop).")
                        }

                        // Giai đoạn 2: Crop và Lưu trên background thread
                        // Truyền originalImageForPausedCapture (là ảnh gốc lúc pause)
                        strongSelf.processAndSaveImage(originalImage: originalImageForPausedCapture,
                                                       normalizedCropRect: normalizedCropRect,
                                                       shouldCropBasedOnRect: true, // Luôn crop nếu là 'cover' và có rect hợp lệ
                                                       viewId: localViewId,
                                                       resultCallback: result)
                    }
                } else { // Không phải "cover" mode khi đang pause
                    print("[CameraPlatformView-\(localViewId)] Paused capture (Mode: '\(fitModeForCrop)'): Not 'cover'. Saving original paused image.")
                    // Dispatch việc lưu sang background thread cho nhất quán và tránh block
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let strongSelf = self else {
                            DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE_SAVE_PAUSED_NONCOVER", message: "Instance deallocated before saving non-cover paused image.", details: nil)) }
                            return
                        }
                        strongSelf.saveImageDataAndReturnPath(originalImageForPausedCapture.jpegData(compressionQuality: 0.9), viewId: localViewId, resultCallback: result)
                    }
                }
                // Vì các thao tác trên có thể bất đồng bộ, hàm capturePhoto nên return ở đây.
                // result callback sẽ được gọi bên trong các block async.
                return
            }

            // Nếu camera KHÔNG PAUSE, thực hiện live capture (logic này đã có crop cho "cover")
            print("[CameraPlatformView-\(viewId)] Attempting LIVE capture.")
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
                strongSelf.pendingPhotoCaptureResult = result // Gán resultCallback cho photoOutput delegate
                photoOutput.capturePhoto(with: photoSettings, delegate: strongSelf)
            }
        }

    // SỬA LỖI TRONG HÀM NÀY
        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            guard let resultCallback = self.pendingPhotoCaptureResult else {
                print("[CameraPlatformView-\(self.viewId)] photoOutput: No pending result callback.")
                return
            }
            self.pendingPhotoCaptureResult = nil

            if self.isDeinitializing {
                print("[CameraPlatformView-\(self.viewId)] photoOutput: Instance deinitializing, discarding photo.")
                DispatchQueue.main.async { resultCallback(FlutterError(code: "INSTANCE_DEINIT_CAPTURE", message: "Instance deinitializing during photo capture.", details: nil)) }
                return
            }

            if let error = error {
                print("[CameraPlatformView-\(self.viewId)] photoOutput: Error capturing photo: \(error.localizedDescription)")
                DispatchQueue.main.async { resultCallback(FlutterError(code: "CAPTURE_FAILED_PHOTO", message: "Error capturing photo: \(error.localizedDescription)", details: nil)) }
                return
            }

            guard let imageData = photo.fileDataRepresentation(), let originalImage = UIImage(data: imageData) else {
                print("[CameraPlatformView-\(self.viewId)] photoOutput: No image data or could not create UIImage.")
                DispatchQueue.main.async { resultCallback(FlutterError(code: "IMAGE_DATA_ERROR", message: "No image data or could not create UIImage.", details: nil)) }
                return
            }

            let localViewId = self.viewId
            let fitModeForCrop = self.currentPreviewFit.lowercased()

            DispatchQueue.main.async { [weak self] in // Lấy thông tin layer trên main thread
                guard let strongSelf = self else {
                    print("[CameraPlatformView-\(localViewId)] photoOutput: Instance (self) deallocated before crop analysis. Saving original.")
                   
                    DispatchQueue.main.async {
                         resultCallback(FlutterError(code: "INSTANCE_GONE_CROP_PARAMS", message: "Instance deallocated before crop parameters could be obtained.", details: nil))
                    }
                    return // Thoát khỏi block main.async
                }

                var normalizedCropRect = CGRect(x: 0, y: 0, width: 1, height: 1) // Mặc định không crop

                if fitModeForCrop == "cover" {
                    if let previewLayer = strongSelf._hostView.previewLayer, previewLayer.session != nil {
                        normalizedCropRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
                        print("[CameraPlatformView-\(localViewId)] photoOutput ('cover'): Calculated normalizedCropRect: \(normalizedCropRect)")
                    } else {
                        print("[CameraPlatformView-\(localViewId)] photoOutput ('cover'): PreviewLayer not available or session nil. Will use full image (no crop).")
                        // normalizedCropRect vẫn là (0,0,1,1)
                    }
                } else {
                    print("[CameraPlatformView-\(localViewId)] photoOutput (Mode: '\(fitModeForCrop)'): Not 'cover'. Will use full image (no crop).")
                    // normalizedCropRect vẫn là (0,0,1,1)
                }

                // Gọi hàm xử lý và lưu ảnh (hàm này sẽ dispatch sang background thread)
                strongSelf.processAndSaveImage(originalImage: originalImage,
                                               normalizedCropRect: normalizedCropRect,
                                               shouldCropBasedOnRect: (fitModeForCrop == "cover"),
                                               viewId: localViewId,
                                               resultCallback: resultCallback)
            }
        }

    // Hàm mới để xử lý crop và lưu ảnh, được gọi từ block main.async ở trên
    private func processAndSaveImage(originalImage: UIImage,
                                     normalizedCropRect: CGRect,
                                     shouldCropBasedOnRect: Bool, // Cờ để quyết định có crop hay không
                                     viewId: Int64,
                                     resultCallback: @escaping FlutterResult) {
        // Thực hiện crop và lưu trên background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let strongSelf = self else {
                // Instance 'self' bị giải phóng trước khi kịp xử lý và lưu.
                print("[CameraPlatformView-\(viewId)] processAndSaveImage: Instance (self) deallocated. Cannot save image.")
                DispatchQueue.main.async {
                    resultCallback(FlutterError(code: "INSTANCE_GONE_SAVE", message: "Instance deallocated before image could be processed and saved.", details: nil))
                }
                return
            }

            var imageToSave = originalImage
            var performActualCrop = false

            if shouldCropBasedOnRect {
                // Kiểm tra xem normalizedCropRect có thực sự cần crop không (không phải là full rect)
                // và có hợp lệ không (width/height > 0)
                if !(normalizedCropRect.equalTo(CGRect(x: 0, y: 0, width: 1, height: 1))) &&
                    normalizedCropRect.width > 0 && normalizedCropRect.height > 0 {
                    performActualCrop = true
                } else {
                    print("[CameraPlatformView-\(viewId)] processAndSaveImage: No crop needed based on rect (\(normalizedCropRect)). Using original image for 'cover' mode.")
                }
            }


            if performActualCrop {
                print("[CameraPlatformView-\(viewId)] processAndSaveImage: Attempting crop for 'cover' mode.")
                if let croppedImage = strongSelf.cropImage(originalImage, toNormalizedRect: normalizedCropRect, targetViewIdForLog: viewId) {
                    imageToSave = croppedImage
                } else {
                    print("[CameraPlatformView-\(viewId)] processAndSaveImage: Cropping failed. Using original image.")
                }
            } else if shouldCropBasedOnRect { // Tức là mode là cover nhưng rect không cần crop
                 // Không làm gì, imageToSave vẫn là originalImage
            }
             else { // Không phải cover mode
                print("[CameraPlatformView-\(viewId)] processAndSaveImage: Not 'cover' mode. Using original image.")
            }

            strongSelf.saveImageDataAndReturnPath(imageToSave.jpegData(compressionQuality: 0.9), viewId: viewId, resultCallback: resultCallback)
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
    func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection // connection từ videoDataOutput
        ) {
            guard !isDeinitializing else { return }
            guard output == self.videoDataOutput else { return } // Đảm bảo đây là output của chúng ta

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            // Xác định UIImage.Orientation chính xác để xoay ảnh về chiều dọc (Portrait Up)
            // Giả định phổ biến:
            // - Buffer từ camera sau (Back): Thường là Landscape Right (nếu cầm máy dọc, home button bên phải).
            //   Để thành Portrait Up, cần xoay UIImage 90 độ theo chiều kim đồng hồ -> .right
            // - Buffer từ camera trước (Front): Thường là Landscape Left và đã được mirrored bởi phần cứng/driver.
            //   Để thành Portrait Up và hiển thị đúng (không bị ngược chữ), cần xoay UIImage 90 độ ngược chiều kim đồng hồ và un-mirror
            //   -> .leftMirrored (xoay ngược chiều kim đồng hồ rồi lật ngang)
            // Lưu ý: Giá trị này có thể cần điều chỉnh tùy theo thiết bị và cách preview được hiển thị.
            // Bạn nên thử nghiệm để tìm ra giá trị chính xác.

            let imageOrientation: UIImage.Orientation
            
            // Lấy chiều xoay hiện tại của UI để tham khảo (nên lấy trên main thread nếu có thể, hoặc truyền vào)
            // var currentUIOrientation: UIInterfaceOrientation = .portrait // Mặc định
            // if Thread.isMainThread {
            //     currentUIOrientation = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.windowScene?.interfaceOrientation ?? .portrait
            // } else {
            //     // Nếu không trên main thread, khó lấy chính xác, có thể cần một property lưu trữ orientation từ main thread
            // }
            // Dựa vào videoOrientation của connection nếu đã set trong setupCamera:
            // let connectionOrientation = connection.videoOrientation (ví dụ: .portrait, .landscapeRight)

            // CÁCH TIẾP CẬN ĐƠN GIẢN VÀ PHỔ BIẾN (giả định UI luôn là Portrait):
            if self.currentCameraPosition == .front {
                // Camera trước thường cho buffer Landscape Left, và cần mirror để giống preview.
                // .leftMirrored: Xoay 90 độ ngược chiều kim đồng hồ (thành Portrait) và lật ngang.
                imageOrientation = .leftMirrored
            } else { // Camera sau
                // Camera sau thường cho buffer Landscape Right.
                // .right: Xoay 90 độ theo chiều kim đồng hồ (thành Portrait).
                imageOrientation = .right
            }
            
            // Nếu bạn đã set videoConnection.videoOrientation = .portrait trong setupCamera
            // VÀ điều đó thực sự làm cho buffer được xoay thành portrait:
            // thì imageOrientation ở đây nên là .up (hoặc .upMirrored cho front camera nếu connection không tự mirror).
            // Tuy nhiên, việc connection.videoOrientation có xoay buffer hay chỉ là metadata phụ thuộc vào AVFoundation.
            // Cách tiếp cận ở trên (dựa vào front/back) thường đáng tin cậy hơn khi làm việc với raw buffer.

            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
            self.lastFrameAsUIImage = image // Ảnh này giờ sẽ có chiều dọc
        }

        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard !isDeinitializing else { return }
            // print("[CameraPlatformView-\(viewId)] Dropped video frame.")
        }
    
    // deinit giữ nguyên như phiên bản ổn định gần nhất đã được cung cấp và thảo luận
    deinit {
        isDeinitializing = true
        let currentViewId = self.viewId // Capture viewId cho logging
        // Log thread mà deinit đang chạy
        print("[CameraPlatformView-\(currentViewId)] DEINIT: Running on thread: \(Thread.current)")
        print("[CameraPlatformView-\(currentViewId)] DEINIT: Bắt đầu quá trình giải phóng.")

        // Capture các đối tượng AVFoundation mà self đang giữ tham chiếu mạnh
        // để sử dụng trong block sync, đảm bảo chúng không bị nil bởi ARC quá sớm.
        let capturedSession = self.captureSession
        let capturedPhotoOutput = self.photoOutput
        let capturedVideoDataOutput = self.videoDataOutput // Tham chiếu mạnh này quan trọng
        let capturedCurrentCameraInput = self.currentCameraInput
        let capturedMethodChannel = self.methodChannel

        // Thực hiện TẤT CẢ thao tác dọn dẹp AVFoundation trên sessionQueue và ĐỒNG BỘ
        print("[CameraPlatformView-\(currentViewId)] DEINIT: Dispatching all AVFoundation cleanup to sessionQueue (SYNC)...")
        self.sessionQueue.sync { // SYNC block lớn cho tất cả AVFoundation cleanup
            print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Starting AVFoundation cleanup...")

            // 1. Dừng session
            if capturedSession?.isRunning ?? false {
                capturedSession?.stopRunning()
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session đã dừng.")
            } else {
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session không chạy hoặc đã nil khi yêu cầu dừng.")
            }

            // 2. Gỡ bỏ I/O (Inputs và Outputs) khỏi session
            if let session = capturedSession { // Chỉ thao tác nếu session thực sự tồn tại
                if let photoOut = capturedPhotoOutput, session.outputs.contains(photoOut) {
                    session.removeOutput(photoOut)
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) PhotoOutput removed from session.")
                }

                // Xử lý VideoDataOutput: gỡ khỏi session TRƯỚC, sau đó gỡ delegate NGAY LẬP TỨC
                if let videoOut = capturedVideoDataOutput, session.outputs.contains(videoOut) {
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Removing VideoDataOutput (object: \(videoOut)) from session...")
                    session.removeOutput(videoOut) // Gỡ output khỏi session
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) VideoDataOutput removed from session.")
                    
                    // GỠ DELEGATE NGAY SAU KHI GỠ OUTPUT, TRÊN CÙNG sessionQueue NÀY
                    // Không cần dispatch riêng sang videoDataOutputQueue nữa.
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Setting VideoDataOutput delegate (object: \(videoOut)) to nil...")
                    videoOut.setSampleBufferDelegate(nil, queue: nil) // <--- GỠ DELEGATE Ở ĐÂY
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Delegate của VideoDataOutput đã gỡ (nil).")
                } else if capturedVideoDataOutput != nil {
                     print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) capturedVideoDataOutput existed but was not in session or session was nil. Attempting to nil delegate anyway.")
                     capturedVideoDataOutput!.setSampleBufferDelegate(nil, queue: nil) // Cố gắng nil delegate nếu đối tượng vẫn tồn tại
                }


                if let camInput = capturedCurrentCameraInput, session.inputs.contains(camInput) {
                    session.removeInput(camInput)
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) CameraInput removed from session.")
                }
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) I/O removal attempt finished.")
            } else {
                print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session (capturedSession) was nil, skipping I/O removal.")
                // Nếu session đã nil, có thể các output cũng không còn hợp lệ.
                // Vẫn cố gắng gỡ delegate của capturedVideoDataOutput nếu nó tồn tại.
                if let videoOutput = capturedVideoDataOutput {
                    print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) Session was nil, but capturedVideoDataOutput exists. Attempting to nil its delegate directly.")
                    // Cân nhắc: Việc gọi setSampleBufferDelegate khi không rõ queue có an toàn không?
                    // Vì videoDataOutputQueue là serial, và chúng ta đang ở trên sessionQueue (cũng serial),
                    // việc gọi trực tiếp ở đây có thể ổn hơn là dispatch sang videoDataOutputQueue đã có thể không còn liên quan.
                    // Tuy nhiên, để nhất quán, nên thực hiện trên queue mà delegate được set.
                    // Giải pháp an toàn nhất là nil nó trên videoDataOutputQueue nếu chúng ta không làm trong block sessionQueue.sync ở trên.
                    // Nhưng vì đã gộp, đoạn này có thể không cần.
                    // Để đơn giản, nếu session nil, chúng ta giả định videoOutput cũng không cần xử lý delegate nữa
                    // vì nó không còn được session quản lý.
                }
            }
            print("[CameraPlatformView-\(currentViewId)] DEINIT: (sessionQueue.sync) AVFoundation cleanup finished.")
        } // Kết thúc sessionQueue.sync

        // Hủy method channel handler không đồng bộ trên main thread
        DispatchQueue.main.async {
            capturedMethodChannel?.setMethodCallHandler(nil)
            print("[CameraPlatformView-\(currentViewId)] DEINIT: MethodChannel handler đã được gỡ (async).")
        }

        // Gán nil cho các property của instance để giải phóng tham chiếu mạnh
        // Các đối tượng AVFoundation đã được captured và xử lý trong sessionQueue.sync
        self.captureSession = nil
        self.photoOutput = nil
        self.videoDataOutput = nil // Quan trọng: giải phóng tham chiếu mạnh từ self
        self.currentCameraInput = nil
        self.methodChannel = nil
        self.pendingPhotoCaptureResult = nil
        self.lastPausedFrameImage = nil
        self.lastFrameAsUIImage = nil

        print("[CameraPlatformView-\(currentViewId)] DEINIT: Hoàn tất quá trình giải phóng (phần đồng bộ của deinit).")
    }
}
