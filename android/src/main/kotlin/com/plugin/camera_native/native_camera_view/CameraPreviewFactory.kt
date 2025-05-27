package com.plugin.camera_native.native_camera_view

import android.content.Context
import android.net.Uri
import android.view.View
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import androidx.camera.core.*
import androidx.core.content.ContextCompat
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Locale
import java.io.File

class CameraPreviewFactory(
    private val binaryMessenger: BinaryMessenger,
    private val lifecycleOwner: LifecycleOwner
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        return CameraPlatformView(context!!, binaryMessenger, viewId, lifecycleOwner, creationParams)
    }
}

class CameraPlatformView(
    private val context: Context,
    private val binaryMessenger: BinaryMessenger,
    private val viewId: Int,
    private val lifecycleOwner: LifecycleOwner,
    private val creationParams: Map<String?, Any?>?
) : PlatformView, LifecycleOwner by lifecycleOwner {

    private lateinit var previewView: PreviewView
    private lateinit var cameraExecutor: ExecutorService
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var previewUseCase: Preview? = null // Lưu trữ preview use case
    private lateinit var methodChannel: MethodChannel
    private var isCameraPausedManually = false
    private var currentLensFacing: Int = CameraSelector.LENS_FACING_BACK

    private val TAG = "CameraPlatformView"
    private val FILENAME_FORMAT = "yyyy-MM-dd-HH-mm-ss-SSS"

    init {
        previewView = PreviewView(context)
        val useFrontInitially = creationParams?.get("isFrontCamera") as? Boolean ?: false
        currentLensFacing = if (useFrontInitially) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        Log.d(TAG, "Initial lens facing for viewId $viewId: ${if (currentLensFacing == CameraSelector.LENS_FACING_FRONT) "FRONT" else "BACK"}")
        applyPreviewFit()
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        cameraExecutor = Executors.newSingleThreadExecutor()
        val channelName = "com.plugin.camera_native.native_camera_view/camera_method_channel_$viewId"
        methodChannel = MethodChannel(binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "captureImage" -> takePhoto(result)
                "pauseCamera" -> pauseCameraNative(result)
                "resumeCamera" -> resumeCameraNative(result)
                "switchCamera" -> {
                    val args = call.arguments as? Map<String, Any>
                    val useFront = args?.get("useFrontCamera") as? Boolean ?: false
                    switchCameraNative(useFront, result)
                }
                "deleteAllCapturedPhotos" -> deleteAllPhotosNative(result)
                else -> result.notImplemented()
            }
        }
        setupCamera()
    }

    private fun applyPreviewFit() {
        val cameraPreviewFitStr = creationParams?.get("cameraPreviewFit") as? String ?: "cover"
        // Log.d(TAG, "Applying cameraPreviewFit for viewId $viewId: $cameraPreviewFitStr") // Giảm bớt log nếu quá nhiều
        when (cameraPreviewFitStr.lowercase(Locale.getDefault())) {
            "fitwidth" -> previewView.scaleType = PreviewView.ScaleType.FILL_START
            "fitheight" -> previewView.scaleType = PreviewView.ScaleType.FILL_END
            "contain" -> previewView.scaleType = PreviewView.ScaleType.FIT_CENTER
            "cover" -> previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
            else -> {
                Log.w(TAG, "Unknown cameraPreviewFit value: '$cameraPreviewFitStr' for viewId $viewId. Defaulting to FILL_CENTER.")
                previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
            }
        }
    }

    private fun setupCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                if (!isCameraPausedManually) {
                    bindCameraUseCases(cameraProvider!!)
                } else {
                    Log.d(TAG, "Camera for viewId $viewId is manually paused, not binding use cases on setup.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get ProcessCameraProvider for viewId $viewId: ${e.message}", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases(cameraProvider: ProcessCameraProvider) {
        applyPreviewFit()
        cameraProvider.unbindAll() // Luôn unbind tất cả trước khi bind lại để đảm bảo trạng thái sạch

        previewUseCase = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }

        imageCapture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()

        val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(currentLensFacing)
            .build()

        // Điều chỉnh scaleX cho PreviewView dựa trên camera đang sử dụng để unmirror camera trước
        if (currentLensFacing == CameraSelector.LENS_FACING_FRONT) {
            previewView.scaleX = -1.0f // Lật ngược (unmirror) cho camera trước
        } else {
            previewView.scaleX = 1.0f  // Trạng thái bình thường cho camera sau
        }

        try {
            camera = cameraProvider.bindToLifecycle(
                this,
                cameraSelector,
                previewUseCase,
                imageCapture
            )
            Log.d(TAG, "Camera use cases bound successfully for viewId $viewId with lens: ${if (currentLensFacing == CameraSelector.LENS_FACING_FRONT) "FRONT" else "BACK"}")
        } catch (exc: Exception) {
            Log.e(TAG, "Failed to bind camera use cases for viewId $viewId: ${exc.message}", exc)
        }
    }

    // Cập nhật logic pause camera
    private fun pauseCameraNative(result: MethodChannel.Result) {
        Log.d(TAG, "Pausing camera for viewId $viewId (unbinding specific use cases)")
        isCameraPausedManually = true

        try {
            val useCasesToUnbind = mutableListOf<UseCase>()
            previewUseCase?.let {
                // Kiểm tra xem use case có thực sự đang được bind không trước khi cố unbind
                if (cameraProvider?.isBound(it) == true) {
                    useCasesToUnbind.add(it)
                }
            }
            imageCapture?.let {
                if (cameraProvider?.isBound(it) == true) {
                    useCasesToUnbind.add(it)
                }
            }

            if (useCasesToUnbind.isNotEmpty()) {
                cameraProvider?.unbind(*useCasesToUnbind.toTypedArray())
                Log.d(TAG, "Unbound ${useCasesToUnbind.size} use cases for viewId $viewId.")
            } else {
                Log.d(TAG, "No specific use cases (preview, imageCapture) were bound or found to unbind for viewId $viewId.")
                // Nếu không có use case nào được bind, có thể coi như camera đã ở trạng thái "dừng"
                // Hoặc nếu bạn muốn chắc chắn camera tắt hoàn toàn, có thể giữ lại unbindAll() ở đây như một fallback.
                // cameraProvider?.unbindAll() // Fallback nếu cần thiết
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Error during pauseCameraNative for viewId $viewId: ${e.message}", e)
            result.error("PAUSE_FAILED", "Failed to pause camera: ${e.message}", null)
        }
    }

    private fun resumeCameraNative(result: MethodChannel.Result) {
        Log.d(TAG, "Resuming camera for viewId $viewId")
        isCameraPausedManually = false
        if (cameraProvider != null) {
            // bindCameraUseCases sẽ tự động unbindAll() trước, sau đó bind lại
            // điều này đảm bảo camera khởi động lại đúng cách với các use case cần thiết.
            bindCameraUseCases(cameraProvider!!)
        } else {
            Log.w(TAG, "CameraProvider not available yet for viewId $viewId on resume.")
            // setupCamera() sẽ được gọi khi provider sẵn sàng.
        }
        result.success(null)
    }

    private fun switchCameraNative(useFront: Boolean, flutterResult: MethodChannel.Result) {
        val newLensFacing = if (useFront) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        // Kiểm tra nếu không có gì thay đổi và camera đang chạy thì không cần làm gì
        if (newLensFacing == currentLensFacing && cameraProvider?.isBound(previewUseCase!!) == true && !isCameraPausedManually) {
            Log.d(TAG, "Camera for viewId $viewId is already using the requested lens and is active: ${if (useFront) "FRONT" else "BACK"}")
            flutterResult.success(null)
            return
        }

        currentLensFacing = newLensFacing
        Log.d(TAG, "Switching camera for viewId $viewId to: ${if (useFront) "FRONT" else "BACK"}")

        if (cameraProvider != null) {
            if (!isCameraPausedManually) {
                bindCameraUseCases(cameraProvider!!)
            } else {
                Log.d(TAG, "Camera for viewId $viewId is manually paused. Lens selection will apply on resume.")
            }
            flutterResult.success(null)
        } else {
            Log.e(TAG, "CameraProvider not available to switch camera for viewId $viewId.")
            flutterResult.error("PROVIDER_UNAVAILABLE", "CameraProvider not available to switch camera.", null)
        }
    }

    private fun takePhoto(flutterResult: MethodChannel.Result) {
        if (isCameraPausedManually) {
            Log.w(TAG, "Attempted to take photo while camera is paused for viewId $viewId.")
            flutterResult.error("CAMERA_PAUSED", "Camera is paused. Cannot take photo.", null)
            return
        }
        val imageCapture = this.imageCapture ?: run {
            flutterResult.error("UNINITIALIZED", "ImageCapture not initialized.", null)
            return
        }
        val photoFile = File(context.cacheDir, SimpleDateFormat(FILENAME_FORMAT, Locale.US).format(System.currentTimeMillis()) + ".jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()
        imageCapture.takePicture(outputOptions, cameraExecutor, object : ImageCapture.OnImageSavedCallback {
            override fun onError(exc: ImageCaptureException) {
                ContextCompat.getMainExecutor(context).execute {
                    flutterResult.error("CAPTURE_FAILED", "Photo capture failed: ${exc.message}", exc.toString())
                }
            }
            override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                val filePath = photoFile.absolutePath
                ContextCompat.getMainExecutor(context).execute {
                    flutterResult.success(filePath)
                }
            }
        })
    }

    private fun deleteAllPhotosNative(result: MethodChannel.Result) {
        Log.d(TAG, "deleteAllPhotosNative called for viewId $viewId")
        var allDeleted = true
        var filesFound = false
        try {
            val cacheDir = context.cacheDir // Ảnh đang được lưu ở đây
            val photoFiles = cacheDir.listFiles { file ->
                // Điều kiện để xác định file ảnh của plugin
                // Ví dụ: nếu tên file luôn bắt đầu bằng "photo_" và kết thúc bằng ".jpg"
                // Hoặc bạn có thể dùng một prefix cụ thể hơn nếu FILENAME_FORMAT phức tạp
                file.name.startsWith("photo_") && file.name.endsWith(".jpg")
            }

            if (photoFiles != null && photoFiles.isNotEmpty()) {
                filesFound = true
                for (file in photoFiles) {
                    if (file.delete()) {
                        Log.d(TAG, "Deleted photo: ${file.name}")
                    } else {
                        Log.w(TAG, "Failed to delete photo: ${file.name}")
                        allDeleted = false // Đánh dấu nếu có ít nhất một file xóa thất bại
                    }
                }
            } else {
                Log.d(TAG, "No photos found in cache directory to delete.")
            }

            if (allDeleted) {
                if (filesFound) {
                    result.success(true) // Xóa thành công các file đã tìm thấy
                } else {
                    result.success(true) // Không có file nào để xóa, coi như thành công
                }
            } else {
                result.success(false) // Có lỗi khi xóa một hoặc nhiều file
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error deleting photos: ${e.message}", e)
            result.error("DELETE_FAILED", "Error deleting photos: ${e.message}", null)
        }
    }

    override fun getView(): View { return previewView }

    override fun dispose() {
        Log.d(TAG, "Disposing CameraPlatformView for viewId: $viewId")
        isCameraPausedManually = false
        cameraExecutor.shutdown()
        cameraProvider?.unbindAll()
        methodChannel.setMethodCallHandler(null)
    }
}
