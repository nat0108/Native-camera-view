// File: android/app/src/main/kotlin/com/plugin/camera_native/native_camera_view/CameraPreviewFactory.kt
package com.plugin.camera_native.native_camera_view // Cập nhật package name

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.view.MotionEvent
import android.view.View
import androidx.annotation.NonNull
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
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Locale
import java.io.File
import java.util.concurrent.TimeUnit

class CameraPreviewFactory(
    private val binaryMessenger: BinaryMessenger,
    private val lifecycleOwner: LifecycleOwner
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        requireNotNull(context) { "Context cannot be null when creating CameraPlatformView" }
        return CameraPlatformView(context, binaryMessenger, viewId, lifecycleOwner, creationParams)
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
    private var previewUseCase: Preview? = null
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

        applyPreviewFit(this.creationParams) // Truyền creationParams

        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        cameraExecutor = Executors.newSingleThreadExecutor()

        // Sử dụng package name mới cho channel
        val channelName = "com.plugin.camera_native.native_camera_view/camera_method_channel_$viewId"
        methodChannel = MethodChannel(binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        setupTapToFocus()
        setupCamera()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
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

    @SuppressLint("ClickableViewAccessibility")
    private fun setupTapToFocus() {
        previewView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                if (camera == null) {
                    Log.w(TAG, "Camera object is null, cannot perform tap-to-focus.")
                    return@setOnTouchListener true
                }
                val factory: MeteringPointFactory = previewView.meteringPointFactory
                val point: MeteringPoint = factory.createPoint(event.x, event.y)
                val action: FocusMeteringAction = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF)
                    .setAutoCancelDuration(5, TimeUnit.SECONDS)
                    .build()
                Log.d(TAG, "Attempting tap-to-focus at: (${event.x}, ${event.y})")
                val focusFuture: ListenableFuture<FocusMeteringResult> = camera!!.cameraControl.startFocusAndMetering(action)
                focusFuture.addListener({
                    try {
                        val focusResult = focusFuture.get()
                        if (focusResult.isFocusSuccessful) {
                            Log.d(TAG, "Tap-to-focus successful.")
                        } else {
                            Log.w(TAG, "Tap-to-focus failed.")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error observing tap-to-focus result: ${e.message}", e)
                    }
                }, ContextCompat.getMainExecutor(context))
            }
            true
        }
    }

    private fun applyPreviewFit(creationParams: Map<String?, Any?>?) { // Bỏ @Nullable, dùng kiểu Kotlin nullable
        var cameraPreviewFitStr = "cover"
        if (creationParams != null) {
            val fitObj = creationParams["cameraPreviewFit"]
            if (fitObj is String) {
                cameraPreviewFitStr = fitObj
            }
        }
        Log.d(TAG, "Applying cameraPreviewFit for viewId $viewId: $cameraPreviewFitStr with currentLensFacing: $currentLensFacing")
        when (cameraPreviewFitStr.lowercase(Locale.getDefault())) {
            "fitwidth" -> previewView.scaleType = PreviewView.ScaleType.FILL_START
            "fitheight" -> previewView.scaleType = PreviewView.ScaleType.FILL_END
            "contain" -> previewView.scaleType = PreviewView.ScaleType.FIT_START
            "cover" -> previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
            else -> {
                Log.w(TAG, "Unknown cameraPreviewFit value: '$cameraPreviewFitStr' for viewId $viewId. Defaulting to FILL_CENTER.")
                previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
            }
        }
//        if (currentLensFacing == CameraSelector.LENS_FACING_FRONT) {
//            previewView.scaleX = -1.0f
//        } else {
//            previewView.scaleX = 1.0f
//        }
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
        applyPreviewFit(this.creationParams)
        cameraProvider.unbindAll()

        previewUseCase = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }

        imageCapture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()

        val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(currentLensFacing)
            .build()

        try {
            val useCasesToBind = mutableListOf<UseCase>()
            if (!isCameraPausedManually) {
                previewUseCase?.let { useCasesToBind.add(it) }
            }
            imageCapture?.let { useCasesToBind.add(it) }

            if(useCasesToBind.isEmpty() && imageCapture == null){
                Log.w(TAG, "No use cases to bind for viewId $viewId. ImageCapture is null.")
            } else if (useCasesToBind.isEmpty() && imageCapture != null) {
                Log.d(TAG, "Binding only ImageCapture for viewId $viewId (camera paused)")
                this.camera = cameraProvider.bindToLifecycle(
                    this,
                    cameraSelector,
                    imageCapture!!
                )
            }
            else if (useCasesToBind.isNotEmpty()){
                this.camera = cameraProvider.bindToLifecycle(
                    this,
                    cameraSelector,
                    *useCasesToBind.toTypedArray()
                )
            } else {
                Log.w(TAG, "No use cases were actually bound for viewId $viewId")
            }
            Log.d(TAG, "Camera use cases bound for viewId $viewId. Paused: $isCameraPausedManually")
        } catch (exc: Exception) {
            Log.e(TAG, "Failed to bind camera use cases for viewId $viewId: ${exc.message}", exc)
            this.camera = null
        }
    }

    private fun pauseCameraNative(result: MethodChannel.Result) {
        Log.d(TAG, "Pausing camera for viewId $viewId (only unbinding preview)")
        isCameraPausedManually = true
        try {
            previewUseCase?.let { currentPreviewUseCase ->
                if (cameraProvider?.isBound(currentPreviewUseCase) == true) {
                    cameraProvider?.unbind(currentPreviewUseCase)
                    Log.d(TAG, "Unbound PreviewUseCase for viewId $viewId.")
                } else {
                    Log.d(TAG, "PreviewUseCase not bound or provider null for viewId $viewId.")
                }
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
            bindCameraUseCases(cameraProvider!!)
        } else {
            Log.w(TAG, "CameraProvider not available yet for viewId $viewId on resume.")
        }
        result.success(null)
    }

    private fun switchCameraNative(useFront: Boolean, flutterResult: MethodChannel.Result) {
        val newLensFacing = if (useFront) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK

        val isCurrentlyBound = previewUseCase?.let { cameraProvider?.isBound(it) } ?: false

        if (newLensFacing == currentLensFacing && isCurrentlyBound && !isCameraPausedManually) {
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
        val imageCaptureInstance = this.imageCapture
        if (imageCaptureInstance == null) {
            Log.e(TAG, "ImageCapture not initialized for viewId $viewId.")
            flutterResult.error("UNINITIALIZED", "ImageCapture not initialized.", null)
            return
        }
        val photoFile = File(context.cacheDir, SimpleDateFormat(FILENAME_FORMAT, Locale.US).format(System.currentTimeMillis()) + ".jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()
        imageCaptureInstance.takePicture(outputOptions, ContextCompat.getMainExecutor(context), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(@NonNull outputFileResults: ImageCapture.OutputFileResults) {
                val filePath = photoFile.getAbsolutePath()
                flutterResult.success(filePath)
            }
            override fun onError(@NonNull exception: ImageCaptureException) {
                Log.e(TAG, "Photo capture failed: " + exception.message, exception)
                flutterResult.error("CAPTURE_FAILED", "Photo capture failed: " + exception.message, exception.toString())
            }
        })
    }

    private fun deleteAllPhotosNative(result: MethodChannel.Result) {
        Log.d(TAG, "deleteAllPhotosNative called for viewId $viewId")
        var allDeleted = true
        var filesFound = false
        try {
            val cacheDir = context.cacheDir
            val photoFiles = cacheDir.listFiles { file ->
                file.name.startsWith("photo_") && file.name.endsWith(".jpg")
            }

            if (photoFiles != null && photoFiles.isNotEmpty()) {
                filesFound = true
                for (file in photoFiles) {
                    if (file.delete()) {
                        Log.d(TAG, "Deleted photo: ${file.name}")
                    } else {
                        Log.w(TAG, "Failed to delete photo: ${file.name}")
                        allDeleted = false
                    }
                }
            } else {
                Log.d(TAG, "No photos found in cache directory to delete.")
            }

            if (allDeleted) {
                result.success(true)
            } else {
                result.success(false)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error deleting photos: ${e.message}", e)
            result.error("DELETE_FAILED", "Error deleting photos: ${e.message}", null)
        }
    }

    override fun getView(): View { return previewView }

    override fun dispose() {
        Log.d(TAG, "Disposing CameraPlatformView for viewId $viewId")
        isCameraPausedManually = false
        cameraExecutor.shutdown()
        cameraProvider?.unbindAll()
        camera = null
        methodChannel.setMethodCallHandler(null)
    }
}
    