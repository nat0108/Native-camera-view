import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../camera_controller.dart';
import '../display_picture_screen.dart';

part 'camera_preview_bloc.dart';

part 'camera_preview_event.dart';

part 'camera_preview_state.dart';

class CameraPreviewView extends StatelessWidget {
  final CameraPreviewFit? cameraPreviewFit;
  final bool? isFrontCamera;
  final Function(CameraController controller) setCameraController;

  const CameraPreviewView({super.key, required this.setCameraController, this.cameraPreviewFit, this.isFrontCamera}); // phải là const để khai báo route

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (BuildContext context) => _CameraPreviewBloc()..add(InitEvent()), // khởi tạo bloc
      child: Builder(builder: (context) => _buildPage(context)),
    );
  }

  Widget _buildPage(BuildContext context) {
    final bloc = BlocProvider.of<_CameraPreviewBloc>(context);

    return BlocConsumer<_CameraPreviewBloc, _CameraPreviewState>(
      listener: (context, state) {
        if (state is ShowSnackBarState) {
          // sự kiện hiển SnackBar
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          return;
        }
      },
      buildWhen: (previous, current) => current is _CompleteState, // chỉ rebuild lại với những state này
      builder: (context, state) {
        return _buildBody(bloc); // giao diện chính của màn hình
      },
    );
  }
}

extension _WidgetBuilder on CameraPreviewView {
  // giao diện chính
  Widget _buildBody(_CameraPreviewBloc bloc) {
    return ListenableBuilder(listenable: Listenable.merge([bloc._isLoading, bloc._isPermissionGranted]), builder: (context, child) => _buildCameraPreviewWidget(bloc));
  }

  // xây thêm các hàm giao diện khác tại đây

  Widget _buildCameraPreviewWidget(_CameraPreviewBloc bloc) {
    if (bloc._isLoading.value) {
      return const CircularProgressIndicator();
    }

    // Đối với iOS, _isPermissionGranted sẽ được đặt là true
    // để cho phép UiKitView được build. Native code sẽ xử lý dialog xin quyền thực tế.
    // Nếu native code không thể setup camera (do từ chối quyền), UiKitView sẽ hiển thị
    // nhưng có thể là một view trống.
    // UI hiển thị "Quyền bị từ chối" này sẽ chỉ áp dụng cho Android nếu permission_handler báo lỗi.
    if (!bloc._isPermissionGranted.value && Platform.isAndroid) {
      return Column(
        // UI xin quyền cho Android
        mainAxisAlignment: MainAxisAlignment.center,
        children: [const Padding(padding: EdgeInsets.all(16.0), child: Text('Quyền truy cập camera là bắt buộc để sử dụng tính năng này.', textAlign: TextAlign.center))],
      );
    }

    // Nếu là iOS và _isPermissionGranted là true (do giả định ở _requestCameraPermission),
    // hoặc là Android và _isPermissionGranted là true, thì build PlatformView.
    if ((Platform.isIOS && bloc._isPermissionGranted.value) || (Platform.isAndroid && bloc._isPermissionGranted.value)) {
      final Map<String, dynamic> creationParams = {'cameraPreviewFit': cameraPreviewFit?.name ?? CameraPreviewFit.contain.name, 'isFrontCamera': bloc._cameraController?.isFrontCamera ?? false};
      String platformViewKeyBase = "camera_preview_${cameraPreviewFit?.name ?? CameraPreviewFit.contain.name}_front_${isFrontCamera ?? false}";

      if (Platform.isAndroid) {
        return AndroidView(
          key: ValueKey("android_$platformViewKeyBase"),
          viewType: bloc._androidViewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (id) => _onPlatformViewCreated(id, bloc),
          gestureRecognizers: null,
        );
      } else if (Platform.isIOS) {
        return UiKitView(
          key: ValueKey("ios_$platformViewKeyBase"),
          viewType: bloc._iosViewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (id) => _onPlatformViewCreated(id, bloc),
        );
      }
    }

    // Fallback nếu không phải Android/iOS hoặc có trường hợp chưa xử lý
    return const Text('Không thể hiển thị camera hoặc quyền chưa được cấp.');
  }

  void _onPlatformViewCreated(int id, _CameraPreviewBloc bloc) {
    String channelName;
    String baseChannelName = "com.plugin.camera_native.native_camera_view/camera_method_channel";

    if (Platform.isAndroid) {
      channelName = '${baseChannelName}_$id';
    } else if (Platform.isIOS) {
      channelName = '${baseChannelName}_ios_$id';
    } else {
      debugPrint("Nền tảng không hỗ trợ camera view.");
      return;
    }

    MethodChannel platformChannel = MethodChannel(channelName);
    bloc._cameraController = CameraController(channel: platformChannel);
    setCameraController.call(bloc._cameraController!);
    debugPrint('PlatformView (id: $id, platform: ${Platform.operatingSystem}) created. CameraController initialized with channel: $channelName');
  }
}
