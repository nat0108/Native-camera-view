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
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return CameraPlatformView(frame: frame, viewIdentifier: viewId, arguments: args, binaryMessenger: messenger)
    }
    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
          return FlutterStandardMessageCodec.sharedInstance()
    }
}


class CameraPlatformView: NSObject, FlutterPlatformView, AVCapturePhotoCaptureDelegate {
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

    private let sessionQueue = DispatchQueue(label: "com.plugin.camera_native.native_camera_view.sessionQueue")
    private var isDeinitializing = false

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        self.viewId = viewId
        self._hostView = CameraHostView(frame: frame)
        self.methodChannel = FlutterMethodChannel(name: "com.plugin.camera_native.native_camera_view/camera_method_channel_ios_\(viewId)", binaryMessenger: messenger)
        super.init()

        print("[CameraPlatformView-\(viewId)] INIT, initial frame: \(frame)")

        self.methodChannel?.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async {
                    print("[CameraPlatformView-\(viewId)] Method call on deinitialized or deinitializing instance: \(call.method)")
                    result(FlutterError(code: "INSTANCE_GONE", message: "Platform view instance was deallocated or is deinitializing.", details: nil))
                }
                return
            }
            strongSelf.handleMethodCall(call, result: result)
        })

        if let params = args as? [String: Any] {
            if let fitMode = params["cameraPreviewFit"] as? String { currentPreviewFit = fitMode }
            if let useFront = params["isFrontCamera"] as? Bool, useFront { currentCameraPosition = .front }
            print("[CameraPlatformView-\(viewId)] Parsed arguments: fitMode=\(currentPreviewFit), useFront=\(currentCameraPosition == .front)")
        }
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
            print("[CameraPlatformView-\(viewId)] Permission not determined. Requesting...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let strongSelf = self, !strongSelf.isDeinitializing else { return }
                DispatchQueue.main.async {
                    print("[CameraPlatformView-\(strongSelf.viewId)] Permission request completed. Granted: \(granted)")
                    if granted { strongSelf.setupCamera() }
                    else { print("[CameraPlatformView-\(strongSelf.viewId)] Permission denied by user.") }
                }
            }
        case .denied:
            print("[CameraPlatformView-\(viewId)] Permission denied previously.")
            DispatchQueue.main.async { if let channel = self.methodChannel, !self.isDeinitializing { channel.invokeMethod("onError", arguments: "camera_permission_denied_previously") } }
        case .restricted:
             print("[CameraPlatformView-\(viewId)] Permission restricted.")
             DispatchQueue.main.async { if let channel = self.methodChannel, !self.isDeinitializing { channel.invokeMethod("onError", arguments: "camera_permission_restricted") } }
        @unknown default:
            fatalError("Unknown camera authorization status for viewId: \(viewId)")
        }
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else { return }
            print("[CameraPlatformView-\(strongSelf.viewId)] setupCamera on sessionQueue, lens: \(strongSelf.currentCameraPosition == .front ? "FRONT" : "BACK")")

            let newSession = AVCaptureSession()
            
            if let oldSession = strongSelf.captureSession, oldSession.isRunning {
                oldSession.stopRunning()
            }
            strongSelf.captureSession = newSession
            newSession.sessionPreset = .photo

            var configurationSuccess = true
            newSession.beginConfiguration()
            
            do {
                guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: strongSelf.currentCameraPosition) else {
                    print("[CameraPlatformView-\(strongSelf.viewId)] Failed to get camera device.")
                    configurationSuccess = false
                    // commitConfiguration sẽ được gọi ở cuối khối newSession.beginConfiguration()
                    // không cần return sớm ở đây nếu không có commit.
                    // Để an toàn, chúng ta sẽ commit và return nếu không có device.
                    newSession.commitConfiguration()
                    print("[CameraPlatformView-\(strongSelf.viewId)] Session configuration committed (early exit due to no device).")
                    return
                }

                // Xóa input cũ khỏi newSession nếu nó đã từng được thêm vào
                if let currentInput = strongSelf.currentCameraInput, newSession.inputs.contains(currentInput) {
                     newSession.removeInput(currentInput)
                }
                // SỬA LỖI: Bỏ dấu ! khi captureDevice đã là non-optional
                let input = try AVCaptureDeviceInput(device: captureDevice)
                strongSelf.currentCameraInput = input
                if newSession.canAddInput(input) { newSession.addInput(input) } else { configurationSuccess = false }

                // Xóa output cũ khỏi newSession nếu nó đã từng được thêm vào
                if let existingPhotoOutput = strongSelf.photoOutput, newSession.outputs.contains(existingPhotoOutput) {
                    newSession.removeOutput(existingPhotoOutput)
                }
                let newPhotoOutput = AVCapturePhotoOutput()
                strongSelf.photoOutput = newPhotoOutput
                if newSession.canAddOutput(newPhotoOutput) { newSession.addOutput(newPhotoOutput) } else { configurationSuccess = false }
                
            } catch {
                print("[CameraPlatformView-\(strongSelf.viewId)] Error during session IO config: \(error)")
                configurationSuccess = false
            }
            
            newSession.commitConfiguration()
            print("[CameraPlatformView-\(strongSelf.viewId)] Session configuration committed. Success: \(configurationSuccess)")
            
            guard configurationSuccess else {
                print("[CameraPlatformView-\(strongSelf.viewId)] Aborting setup due to configuration error.")
                return
            }

            DispatchQueue.main.async {
                guard !strongSelf.isDeinitializing else { return }
                let newPreviewLayer = AVCaptureVideoPreviewLayer(session: newSession)
                strongSelf._hostView.previewLayer?.removeFromSuperlayer()
                strongSelf._hostView.previewLayer = newPreviewLayer
                strongSelf.applyPreviewFitToLayer(layer: newPreviewLayer)
                strongSelf._hostView.layer.insertSublayer(newPreviewLayer, at: 0)
                strongSelf._hostView.setNeedsLayout()
                print("[CameraPlatformView-\(strongSelf.viewId)] New previewLayer configured.")

                if let connection = newPreviewLayer.connection, connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = true
                }
            }

            if !strongSelf.isCameraPausedManually {
                if strongSelf.captureSession === newSession {
                    newSession.startRunning()
                    print("[CameraPlatformView-\(strongSelf.viewId)] New camera session started.")
                } else {
                    print("[CameraPlatformView-\(strongSelf.viewId)] Session changed before startRunning. Aborting start.")
                }
            } else {
                 print("[CameraPlatformView-\(strongSelf.viewId)] New camera session is manually paused, not starting.")
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
        switch call.method {
        case "captureImage": capturePhoto(result: result)
        case "pauseCamera": pauseCameraNative(result: result)
        case "resumeCamera": resumeCameraNative(result: result)
        case "switchCamera":
            if let args = call.arguments as? [String: Any], let useFront = args["useFrontCamera"] as? Bool {
                switchCameraNative(useFront: useFront, result: result)
            } else { DispatchQueue.main.async { result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'useFrontCamera' for viewId: \(self.viewId)", details: nil)) } }
        case "deleteAllCapturedPhotos": deleteAllPhotosNative(result: result)
        default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
    }

    private func deleteAllPhotosNative(result: @escaping FlutterResult) {
            print("[CameraPlatformView-\(viewId)] deleteAllPhotosNative called.")
            let fileManager = FileManager.default
            let tempDirectory = NSTemporaryDirectory()
            var allDeleted = true
            var filesFound = false

            do {
                let fileURLs = try fileManager.contentsOfDirectory(atPath: tempDirectory)
                for fileName in fileURLs {
                    // Điều kiện để xác định file ảnh của plugin
                    // Ví dụ: nếu tên file luôn bắt đầu bằng "photo_ios_" (như trong hàm capturePhoto)
                    if fileName.hasPrefix("photo_ios_") && fileName.hasSuffix(".jpg") {
                        filesFound = true
                        let filePath = URL(fileURLWithPath: tempDirectory).appendingPathComponent(fileName)
                        do {
                            try fileManager.removeItem(at: filePath)
                            print("[CameraPlatformView-\(viewId)] Deleted photo: \(fileName)")
                        } catch {
                            print("[CameraPlatformView-\(viewId)] Failed to delete photo \(fileName): \(error)")
                            allDeleted = false
                        }
                    }
                }

                if allDeleted {
                     if (filesFound) {
                        DispatchQueue.main.async { result(true) }
                     } else {
                        print("[CameraPlatformView-\(viewId)] No photos found in temp directory to delete.")
                        DispatchQueue.main.async { result(true) } // Không có file, coi như thành công
                     }
                } else {
                    DispatchQueue.main.async { result(false) } // Có lỗi khi xóa
                }

            } catch {
                print("[CameraPlatformView-\(viewId)] Error listing files in temp directory: \(error)")
                DispatchQueue.main.async { result(FlutterError(code: "LIST_FILES_FAILED", message: "Error listing files: \(error.localizedDescription)", details: nil)) }
            }
        }

    private func capturePhoto(result: @escaping FlutterResult) {
        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(FlutterError(code: "INSTANCE_GONE_CAPTURE", message: "Self nil or deinitializing", details: nil)) }
                return
            }
            guard let photoOutput = strongSelf.photoOutput, let session = strongSelf.captureSession, session.isRunning else {
                DispatchQueue.main.async { result(FlutterError(code: "CAMERA_UNAVAILABLE", message: "Camera not ready for viewId: \(strongSelf.viewId)", details: nil)) }
                return
            }
            if strongSelf.isCameraPausedManually {
                DispatchQueue.main.async { result(FlutterError(code: "CAMERA_PAUSED", message: "Camera is paused for viewId: \(strongSelf.viewId)", details: nil)) }
                return
            }
            let photoSettings = AVCapturePhotoSettings()
            strongSelf.pendingPhotoCaptureResult = result
            photoOutput.capturePhoto(with: photoSettings, delegate: strongSelf)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("[CameraPlatformView-\(viewId)] photoOutput delegate called")
        guard let resultCallback = self.pendingPhotoCaptureResult else { return }
        self.pendingPhotoCaptureResult = nil
        if let error = error {
            DispatchQueue.main.async { resultCallback(FlutterError(code: "CAPTURE_FAILED", message: "Error capturing photo for viewId \(self.viewId): \(error.localizedDescription)", details: nil)) }
            return
        }
        guard let imageData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { resultCallback(FlutterError(code: "CAPTURE_FAILED", message: "No image data for viewId: \(self.viewId)", details: nil)) }
            return
        }
        let tempDir = NSTemporaryDirectory()
        let fileName = "photo_ios_\(viewId)_\(Date().timeIntervalSince1970).jpg"
        let filePath = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        do {
            try imageData.write(to: filePath)
            DispatchQueue.main.async { resultCallback(filePath.path) }
        } catch {
            DispatchQueue.main.async { resultCallback(FlutterError(code: "SAVE_FAILED", message: "Error saving photo for viewId \(self.viewId): \(error.localizedDescription)", details: nil)) }
        }
    }

    private func pauseCameraNative(result: @escaping FlutterResult) {
        print("[CameraPlatformView-\(viewId)] pauseCameraNative called.")
        isCameraPausedManually = true
        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            if let session = strongSelf.captureSession, session.isRunning {
                session.stopRunning()
                print("[CameraPlatformView-\(strongSelf.viewId)] Session stopped via pauseCameraNative.")
            } else {
                print("[CameraPlatformView-\(strongSelf.viewId)] Session already stopped or nil when pausing.")
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func resumeCameraNative(result: @escaping FlutterResult) {
        print("[CameraPlatformView-\(viewId)] resumeCameraNative called.")
        isCameraPausedManually = false
        sessionQueue.async { [weak self] in
            guard let strongSelf = self, !strongSelf.isDeinitializing else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            if strongSelf.captureSession == nil {
                 print("[CameraPlatformView-\(strongSelf.viewId)] Session is nil on resume. Re-running setup.")
                 strongSelf.setupCamera()
            } else if !(strongSelf.captureSession!.isRunning) {
                print("[CameraPlatformView-\(strongSelf.viewId)] Session not running on resume. Starting it.")
                strongSelf.captureSession!.startRunning()
            } else {
                 print("[CameraPlatformView-\(strongSelf.viewId)] Session already running on resume.")
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func switchCameraNative(useFront: Bool, result: @escaping FlutterResult) {
        print("[CameraPlatformView-\(viewId)] switchCameraNative called. Requested front: \(useFront). Current: \(currentCameraPosition == .front)")
        
        let newPosition: AVCaptureDevice.Position = useFront ? .front : .back
        
        if newPosition == currentCameraPosition && (captureSession?.isRunning ?? false) && !isCameraPausedManually {
            print("[CameraPlatformView-\(viewId)] No camera switch needed. Already on \(newPosition == .front ? "Front" : "Back") and running.")
            DispatchQueue.main.async { result(nil) }
            return
        }
        
        currentCameraPosition = newPosition
        print("[CameraPlatformView-\(viewId)] Set currentCameraPosition to \(currentCameraPosition == .front ? "Front" : "Back").")
        
        if isCameraPausedManually {
            print("[CameraPlatformView-\(viewId)] Camera is manually paused. New camera selection will apply when resumed by the new view instance.")
        } else {
            print("[CameraPlatformView-\(viewId)] Switch command received. Flutter will recreate view with new camera setting.")
        }
        
        DispatchQueue.main.async { result(nil) }
    }
    
    deinit {
        isDeinitializing = true
        print("[CameraPlatformView-\(viewId)] DEINIT CALLED")

        let sessionToStop = self.captureSession
        let channelToNil = self.methodChannel
        let hostViewToClean = self._hostView
        let localViewId = self.viewId

        self.captureSession = nil
        self.photoOutput = nil
        self.currentCameraInput = nil
        self.pendingPhotoCaptureResult = nil
        self.methodChannel = nil

        sessionQueue.async {
            if sessionToStop?.isRunning ?? false {
                sessionToStop?.stopRunning()
                print("[CameraPlatformView-\(localViewId)] Session stopped asynchronously in deinit.")
            }
        }
        
        DispatchQueue.main.async {
            channelToNil?.setMethodCallHandler(nil)
            
            if hostViewToClean.window != nil || hostViewToClean.superview != nil {
                hostViewToClean.previewLayer?.removeFromSuperlayer()
                print("[CameraPlatformView-\(localViewId)] DEINIT: hostView.previewLayer removed from superlayer.")
            } else {
                print("[CameraPlatformView-\(localViewId)] DEINIT: hostView not in window/superview, layer might already be gone.")
            }
            hostViewToClean.previewLayer = nil
            
            print("[CameraPlatformView-\(localViewId)] MethodChannel handler nillified and previewLayer cleaned on main thread.")
        }
    }
}
