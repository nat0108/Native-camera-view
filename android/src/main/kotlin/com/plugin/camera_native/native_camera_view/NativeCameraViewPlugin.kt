// File: android/src/main/kotlin/com/plugin/camera_native/native_camera_view/NativeCameraViewPlugin.kt
package com.plugin.camera_native.native_camera_view // Giữ nguyên package của bạn

import androidx.annotation.NonNull // QUAN TRỌNG: Import cho @NonNull
// import androidx.lifecycle.DefaultLifecycleObserver // Không cần thiết nếu không dùng trực tiếp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
//import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter // QUAN TRỌNG: Import cho FlutterLifecycleAdapter

// Giả sử CameraPreviewFactory được định nghĩa trong cùng package hoặc được import đúng cách
// import com.plugin.camera_native.native_camera_view.CameraPreviewFactory; // Nếu CameraPreviewFactory là Java

class NativeCameraViewPlugin : FlutterPlugin, ActivityAware {
  private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
  private var activityPluginBinding: ActivityPluginBinding? = null // Giữ tham chiếu đến activity binding
  private var cameraPreviewFactory: CameraPreviewFactory? = null
  // private var activityLifecycle: Lifecycle? = null // Không cần lưu trữ activityLifecycle nếu chỉ dùng trong onAttachedToActivity

  // ViewType phải khớp với Dart và là duy nhất cho plugin của bạn
  // Ví dụ: "com.yourcompany.yourplugin/camera_preview_android"
  // Hãy thay thế bằng viewType thực tế bạn đang sử dụng trong Dart.
  private val viewType = "com.plugin.camera_native.native_camera_view/camera_preview_android" // Đảm bảo đây là viewType đúng

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    print("NativeCameraViewPlugin: onAttachedToEngine")
    this.flutterPluginBinding = binding
    // Việc đăng ký factory sẽ được thực hiện trong onAttachedToActivity
    // vì chúng ta cần Activity làm LifecycleOwner cho CameraX.
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    print("NativeCameraViewPlugin: onDetachedFromEngine")
    // Không cần unregister factory ở đây vì nó được quản lý theo activity lifecycle
    this.flutterPluginBinding = null
  }

  // --- ActivityAware Lifecycle Methods ---
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    print("NativeCameraViewPlugin: onAttachedToActivity - Registering CameraPreviewFactory")
    this.activityPluginBinding = binding
    // val activityLifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding.lifecycle) // Lấy lifecycle từ activity

    val messenger = flutterPluginBinding?.binaryMessenger
    if (messenger == null) {
      print("NativeCameraViewPlugin: ERROR - BinaryMessenger is null in onAttachedToActivity. Cannot register factory.")
      return
    }

    val activity = binding.activity
    if (activity !is LifecycleOwner) {
      print("NativeCameraViewPlugin: ERROR - Activity is not a LifecycleOwner. Cannot register factory.")
      return
    }

    // Tạo và đăng ký factory
    // Activity chính là LifecycleOwner cần thiết cho CameraPreviewFactory
    cameraPreviewFactory = CameraPreviewFactory(messenger, activity)
    flutterPluginBinding?.platformViewRegistry?.registerViewFactory(
      viewType, // Sử dụng viewType đã định nghĩa
      cameraPreviewFactory!! // Sử dụng !! vì chúng ta vừa tạo nó
    )
    print("NativeCameraViewPlugin: CameraPreviewFactory registered successfully with viewType: $viewType")
  }

  override fun onDetachedFromActivityForConfigChanges() {
    print("NativeCameraViewPlugin: onDetachedFromActivityForConfigChanges")
    // Gọi onDetachedFromActivity để dọn dẹp
    onDetachedFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    print("NativeCameraViewPlugin: onReattachedToActivityForConfigChanges")
    // Gọi lại onAttachedToActivity để đăng ký lại factory
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    print("NativeCameraViewPlugin: onDetachedFromActivity - Cleaning up")
    // Dọn dẹp khi activity bị hủy hoặc plugin bị detached khỏi activity
    // Việc unregister factory ở đây có thể gây ra vấn đề nếu engine vẫn còn attached
    // và Flutter cố gắng tạo view khi không có activity.
    // Thông thường, Flutter sẽ xử lý việc này.
    // Quan trọng là dọn dẹp các tham chiếu để tránh memory leak.

    // Nếu bạn muốn unregister một cách tường minh (cẩn thận với trường hợp engine vẫn còn)
    // if (flutterPluginBinding != null && cameraPreviewFactory != null) {
    //     flutterPluginBinding!!.platformViewRegistry.registerViewFactory(viewType, null)
    //     print("NativeCameraViewPlugin: CameraPreviewFactory unregistered.")
    // }

    this.activityPluginBinding = null
    // this.activityLifecycle = null // Không cần thiết nếu không lưu trữ
    this.cameraPreviewFactory = null // Gỡ bỏ tham chiếu đến factory
    print("NativeCameraViewPlugin: Cleaned up activity attachments.")
  }
}
