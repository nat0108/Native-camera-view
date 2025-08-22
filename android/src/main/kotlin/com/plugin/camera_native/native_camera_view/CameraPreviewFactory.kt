// File: android/app/src/main/kotlin/com/plugin/camera_native/native_camera_view/CameraPreviewFactory.kt
package com.plugin.camera_native.native_camera_view // Cập nhật package name
import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.app.Activity
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import android.view.MotionEvent
import android.view.View
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.appcompat.app.AlertDialog
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface

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
) : PlatformView, DefaultLifecycleObserver, LifecycleOwner by lifecycleOwner {

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
    private var currentPreviewFitStr: String = "cover"

    // Biến để tránh hiển thị nhiều dialog cùng lúc
    private var isDialogShowing = false
    private var hasRequestedPermission = false
    private var bypassPermissionCheck: Boolean = false

    companion object {
        private const val REQUEST_CODE_PERMISSIONS = 10
    }

    init {
        previewView = PreviewView(context)
        lifecycleOwner.lifecycle.addObserver(this) // Đăng ký observer

        val useFrontInitially = creationParams?.get("isFrontCamera") as? Boolean ?: false
        currentLensFacing = if (useFrontInitially) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        bypassPermissionCheck = creationParams?.get("bypassPermissionCheck") as? Boolean ?: false
        Log.d(TAG, "Initial lens facing for viewId $viewId: ${if (currentLensFacing == CameraSelector.LENS_FACING_FRONT) "FRONT" else "BACK"}")

        if (creationParams != null) {
            val fitObj = creationParams["cameraPreviewFit"]
            if (fitObj is String) {
                currentPreviewFitStr = fitObj.lowercase(Locale.getDefault())
            }
        }
        applyPreviewFit() // Truyền creationParams

        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        cameraExecutor = Executors.newSingleThreadExecutor()

        // Sử dụng package name mới cho channel
        val channelName = "com.plugin.camera_native.native_camera_view/camera_method_channel_$viewId"
        methodChannel = MethodChannel(binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        setupTapToFocus()
    }

    override fun onResume(owner: LifecycleOwner) {
        super.onResume(owner)
        Log.d(TAG, "onResume triggered for viewId $viewId. Checking permissions.")
//        checkPermissionsAndSetup()
    }

    private fun findActivity(): Activity? {
        var currentContext = context
        while (currentContext is ContextWrapper) {
            if (currentContext is Activity) {
                return currentContext
            }
            currentContext = currentContext.baseContext
        }
        return null
    }

    // Logic kiểm tra quyền được cập nhật hoàn toàn
    private fun checkPermissionsAndSetup() {
        if (bypassPermissionCheck) {
            Log.d(TAG, "Permission check is BYPASSED for viewId $viewId. Proceeding to setup camera.")
            setupCamera()
            return // Thoát khỏi hàm sớm
        }

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            // Trường hợp 1: Đã có quyền -> Thiết lập camera
            setupCamera()
        } else {
            val activity = findActivity()
            if (activity == null) {
                Log.e(TAG, "Could not find activity to request permissions.")
                return
            }

            if (hasRequestedPermission) {
                // Trường hợp 2: Đã hỏi quyền trước đó và vẫn bị từ chối -> Hiển thị dialog "Mở Cài đặt"
                showPermissionDeniedDialog()
            } else {
                // Trường hợp 3: Chưa hỏi quyền lần nào -> Hiển thị dialog của hệ thống
                hasRequestedPermission = true
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.CAMERA),
                    REQUEST_CODE_PERMISSIONS
                )
            }
        }
    }

    // Hàm mới để hiển thị dialog khi không có quyền
    private fun showPermissionDeniedDialog() {
        if (isDialogShowing) return
        isDialogShowing = true

        AlertDialog.Builder(context, R.style.RoundedAlertDialog)
            .setTitle(context.getString(R.string.permission_denied_title))
            .setMessage(context.getString(R.string.permission_denied_message))
            .setCancelable(false)
            .setPositiveButton(context.getString(R.string.open_settings_button)) { _, _ ->
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                val uri = Uri.fromParts("package", context.packageName, null)
                intent.data = uri
                context.startActivity(intent)
                isDialogShowing = false
            }
            .setNegativeButton(context.getString(R.string.close_button)) { _, _ ->
                isDialogShowing = false
            }
            .show()
    }


    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                Log.d(TAG, "Initialization requested from Flutter for viewId $viewId.")
                checkPermissionsAndSetup()
                result.success(null)
            }
            "captureImage" -> takePhoto(result)
            "pauseCamera" -> pauseCameraNative(result)
            "resumeCamera" -> resumeCameraNative(result)
            "switchCamera" -> {
                val args = call.arguments as? Map<String, Any>
                val useFront = args?.get("useFrontCamera") as? Boolean ?: false
                switchCameraNative(useFront, result)
            }
            "deleteAllCapturedPhotos" -> deleteAllPhotosNative(result)
            "setPreviewFit" -> { // Xử lý thay đổi fit mode từ Flutter
                val fitName = call.arguments as? String
                if (fitName != null) {
                    currentPreviewFitStr = fitName.lowercase(Locale.getDefault())
                    applyPreviewFit() // Áp dụng ngay lập tức
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Missing 'fitName'", null)
                }
            }
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

    private fun applyPreviewFit() {
        Log.d(TAG, "Applying cameraPreviewFit for viewId $viewId: $currentPreviewFitStr")
        previewView.scaleType = when (currentPreviewFitStr) {
            "fitwidth" -> PreviewView.ScaleType.FILL_START
            "fitheight" -> PreviewView.ScaleType.FILL_END
            "contain" -> PreviewView.ScaleType.FIT_START // Hoặc FIT_CENTER nếu muốn căn giữa
            "cover" -> PreviewView.ScaleType.FILL_CENTER
            else -> {
                Log.w(TAG, "Unknown cameraPreviewFit value: '$currentPreviewFitStr'. Defaulting to FILL_CENTER.")
                PreviewView.ScaleType.FILL_CENTER
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
            methodChannel.invokeMethod("onCameraReady", null)
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

        // Tạo file tạm để lưu ảnh gốc (chưa crop)
        val originalPhotoFile = File(context.cacheDir, "original_${SimpleDateFormat(FILENAME_FORMAT, Locale.US).format(System.currentTimeMillis())}.jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(originalPhotoFile).build()

        imageCaptureInstance.takePicture(outputOptions, ContextCompat.getMainExecutor(context), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(@NonNull outputFileResults: ImageCapture.OutputFileResults) {
                val savedUri = outputFileResults.savedUri ?: Uri.fromFile(originalPhotoFile)
                val originalFilePath = originalPhotoFile.absolutePath
                Log.d(TAG, "Photo capture saved to: $savedUri, path: $originalFilePath")

                if (currentPreviewFitStr == "cover") {
                    Log.d(TAG, "Cover mode detected. Attempting to crop photo for viewId $viewId.")
                    try {
                        val croppedFilePath = cropPhotoToMatchPreview(originalFilePath, previewView)
                        if (croppedFilePath != null) {
                            Log.d(TAG, "Photo cropped successfully: $croppedFilePath")
                            originalPhotoFile.delete() // Xóa file gốc nếu crop thành công
                            flutterResult.success(croppedFilePath)
                        } else {
                            Log.e(TAG, "Photo cropping failed. Returning original photo for viewId $viewId.")
                            flutterResult.success(originalFilePath) // Trả về ảnh gốc nếu crop lỗi
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception during cropping for viewId $viewId: ${e.message}", e)
                        flutterResult.success(originalFilePath) // Trả về ảnh gốc nếu có exception
                    }
                } else {
                    Log.d(TAG, "Not in cover mode. Returning original photo for viewId $viewId.")
                    flutterResult.success(originalFilePath)
                }
            }

            override fun onError(@NonNull exception: ImageCaptureException) {
                Log.e(TAG, "Photo capture failed for viewId $viewId: ${exception.message}", exception)
                flutterResult.error("CAPTURE_FAILED", "Photo capture failed: ${exception.message}", exception.toString())
            }
        })
    }

    // HÀM MỚI ĐỂ CROP ẢNH
    private fun cropPhotoToMatchPreview(originalPhotoPath: String, previewView: PreviewView): String? {
        try {
            // 1. Lấy Bitmap gốc và xử lý orientation từ EXIF
            val originalBitmapUnrotated = BitmapFactory.decodeFile(originalPhotoPath)
            if (originalBitmapUnrotated == null) {
                Log.e(TAG, "Failed to decode original photo file: $originalPhotoPath")
                return null
            }

            val exif = ExifInterface(originalPhotoPath)
            val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED)
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1.0f, 1.0f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1.0f, -1.0f)
                // Các trường hợp phức tạp hơn có thể cần xử lý thêm
            }
            val originalBitmap = Bitmap.createBitmap(originalBitmapUnrotated, 0, 0, originalBitmapUnrotated.width, originalBitmapUnrotated.height, matrix, true)


            val photoWidth = originalBitmap.width.toFloat()
            val photoHeight = originalBitmap.height.toFloat()
            val photoAspectRatio = photoWidth / photoHeight

            val previewWidth = previewView.width.toFloat()
            val previewHeight = previewView.height.toFloat()
            if (previewWidth == 0f || previewHeight == 0f) {
                Log.e(TAG, "PreviewView dimensions are zero. Cannot calculate crop.")
                return null
            }
            val previewAspectRatio = previewWidth / previewHeight

            Log.d(TAG, "Original Photo: ${photoWidth}x$photoHeight (AR: $photoAspectRatio)")
            Log.d(TAG, "Preview View: ${previewWidth}x$previewHeight (AR: $previewAspectRatio)")

            var cropX = 0f
            var cropY = 0f
            var cropWidth = photoWidth
            var cropHeight = photoHeight

            if (previewView.scaleType == PreviewView.ScaleType.FILL_CENTER) { // "cover" mode
                if (photoAspectRatio > previewAspectRatio) {
                    // Ảnh gốc rộng hơn preview (ví dụ: ảnh 16:9, preview 4:3)
                    // => Preview sẽ fill chiều cao của ảnh, cắt bớt chiều rộng
                    cropHeight = photoHeight
                    cropWidth = photoHeight * previewAspectRatio
                    cropX = (photoWidth - cropWidth) / 2
                } else if (photoAspectRatio < previewAspectRatio) {
                    // Ảnh gốc cao hơn preview (ví dụ: ảnh 4:3, preview 16:9)
                    // => Preview sẽ fill chiều rộng của ảnh, cắt bớt chiều cao
                    cropWidth = photoWidth
                    cropHeight = photoWidth / previewAspectRatio
                    cropY = (photoHeight - cropHeight) / 2
                }
                // Nếu tỷ lệ bằng nhau, không cần crop (cropWidth=photoWidth, cropHeight=photoHeight)
            } else {
                Log.w(TAG, "Cropping is currently only implemented for 'cover' (FILL_CENTER) mode.")
                return originalPhotoPath // Trả về ảnh gốc nếu không phải cover
            }

            if (cropX < 0 || cropY < 0 || cropWidth <= 0 || cropHeight <= 0 || cropX + cropWidth > photoWidth + 0.1 || cropY + cropHeight > photoHeight + 0.1 ) {
                Log.e(TAG, "Invalid crop rectangle calculated: x=$cropX, y=$cropY, w=$cropWidth, h=$cropHeight for photo ${photoWidth}x${photoHeight}. Returning original.")
                return originalPhotoPath
            }


            val croppedBitmap = Bitmap.createBitmap(
                originalBitmap,
                cropX.toInt(),
                cropY.toInt(),
                cropWidth.toInt(),
                cropHeight.toInt()
            )

            // Lưu bitmap đã crop
            val croppedPhotoFile = File(context.cacheDir, "cropped_${SimpleDateFormat(FILENAME_FORMAT, Locale.US).format(System.currentTimeMillis())}.jpg")
            FileOutputStream(croppedPhotoFile).use { out ->
                croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out) // quality 90
            }
            croppedBitmap.recycle() // Giải phóng bộ nhớ của bitmap đã crop
            // originalBitmap.recycle() // originalBitmap đã được xử lý bởi createBitmap với matrix

            Log.d(TAG, "Cropped photo saved to: ${croppedPhotoFile.absolutePath}")
            return croppedPhotoFile.absolutePath

        } catch (e: Exception) {
            Log.e(TAG, "Error during cropPhotoToMatchPreview: ${e.message}", e)
            return null // Trả về null nếu có lỗi, takePhoto sẽ xử lý trả về ảnh gốc
        }
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
        lifecycleOwner.lifecycle.removeObserver(this)
        isCameraPausedManually = false
        cameraExecutor.shutdown()
        cameraProvider?.unbindAll()
        camera = null
        methodChannel.setMethodCallHandler(null)
    }
}
    