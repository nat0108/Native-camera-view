import 'dart:typed_data';

class AnalysisImage {
  final int width;
  final int height;
  final int rotation; // Độ xoay của ảnh (ví dụ: 0, 90, 180, 270)
  final List<Uint8List> planes; // Dữ liệu bytes cho các plane (Y, U, V)
  final List<int> strides; // Strides (bytes per row) của mỗi plane
  final int format; // Mã định dạng ảnh (ví dụ: image_format_nv21)

  AnalysisImage({
    required this.width,
    required this.height,
    required this.rotation,
    required this.planes,
    required this.strides,
    required this.format,
  });
}