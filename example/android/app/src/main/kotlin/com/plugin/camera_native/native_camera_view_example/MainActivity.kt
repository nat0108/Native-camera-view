package com.plugin.camera_native.native_camera_view_example // Thay thế bằng package name đúng của bạn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode // <-- Vẫn cần import này
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    // Ghi đè hàm getRenderMode() để trả về RenderMode.texture
    // Đây là cách chính xác để bảo FlutterActivity sử dụng TextureView.
    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    // Bạn có thể giữ lại hàm này nếu cần đăng ký các plugin khác,
    // nhưng nó không cần thiết cho việc thay đổi RenderMode.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // (Bạn có thể thêm code đăng ký plugin khác ở đây nếu cần)
    }
}