part of 'camera_preview_view.dart';

class _CameraPreviewBloc extends Bloc<_CameraPreviewEvent, _CameraPreviewState> {
  final String _androidViewType = 'com.plugin.camera_native.native_camera_view/camera_preview_android';
  final String _iosViewType = 'com.plugin.camera_native.native_camera_view/camera_preview_ios';
  final _isPermissionGranted = ValueNotifier(false); // Sẽ được xử lý khác nhau cho iOS và Android
  final _isLoading = ValueNotifier(true);
  CameraController? _cameraController;


  _CameraPreviewBloc() : super(_InitState()) {
    on<InitEvent>(_init);
    on<ShowSnackBarEvent>(_onShowSnackBar);

  }

  /// Sự kiện đóng màn hình
  @override
  Future<void> close() {
    return super.close();
  }
}

extension _Event on _CameraPreviewBloc {
  /// Hàm khởi tạo màn hình
  void _init(InitEvent event, Emitter<_CameraPreviewState> emit) {
    _requestCameraPermission();
  }

  void _onShowSnackBar(ShowSnackBarEvent event, Emitter<_CameraPreviewState> emit) {
    emit(ShowSnackBarState(event.message));
  }
}

extension _Handle on _CameraPreviewBloc {
  Future<void> _requestCameraPermission() async {
    if (Platform.isIOS) {
      // Đối với iOS, chúng ta sẽ không gọi permission_handler ở đây.
      // Quyền sẽ được yêu cầu bởi native code khi UiKitView được tạo.
      // Chúng ta "tạm thời" đặt _isPermissionGranted = true để UI cố gắng build UiKitView.
      // Native code sẽ tự xử lý việc hiển thị dialog xin quyền.
      debugPrint("[Flutter Permission] Skipping Dart permission request for iOS. Native will handle.");
      _isLoading.value = false;
      _isPermissionGranted.value = true; // Giả định quyền sẽ được xử lý bởi native
    } else if (Platform.isAndroid) {
      // Giữ nguyên logic xin quyền cho Android
      debugPrint("[Flutter Permission] Requesting camera permission on Android...");
      PermissionStatus status = await Permission.camera.request();
      debugPrint("[Flutter Permission] Android status received: ${status.name}, isGranted: ${status.isGranted}");
      _isPermissionGranted.value = status.isGranted;
      _isLoading.value = false;
      if (!status.isGranted) {
        add(ShowSnackBarEvent('Quyền truy cập camera bị từ chối (${status.name}). Không thể hiển thị camera.'));
      }
    } else {
      // Các nền tảng khác không được hỗ trợ
      _isLoading.value = false;
      add(ShowSnackBarEvent('Camera không được hỗ trợ trên nền tảng này.'));
    }
  }
}
