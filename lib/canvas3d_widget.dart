import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:projection3d/projection3d.dart';
import 'package:image/image.dart' as img;

class Canvas3dWidget extends StatelessWidget {
  final List<GeoPoint> polyline;
  final GeoPoint camera;
  final GeoPoint lookAt;
  final GeoPoint currentPosition;
  final Size size;

  const Canvas3dWidget({
    Key? key,
    required this.polyline,
    required this.camera,
    required this.lookAt,
    required this.currentPosition,
    required this.size
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final painter = _MyPainter(
      projectCanvas: ThreeDProjectCanvas(
        camera: camera,
        lookAt: lookAt,
        currentPosition: currentPosition,
        polyline: polyline,
        screenSize: size,
      ),
    );

    return CustomPaint(size: size, painter: painter);
  }
}

class _MyPainter extends CustomPainter {
  final ThreeDProjectCanvas projectCanvas;
  final void Function(Uint8List jpgBytes)? drawCallback;
  _MyPainter({required this.projectCanvas, this.drawCallback});
  @override
  void paint(Canvas canvas, Size size) {
    // 使用 clipRect 限制繪圖區域不超出 widget
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // 填滿黑色底色
    final backgroundPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final paint = Paint()
      ..color = Colors.white
      ..isAntiAlias = false
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final markerPaint = Paint()
      ..color = Colors.red
      ..isAntiAlias = false
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
    projectCanvas.draw(canvas, paint);
    projectCanvas.drawMarker(canvas, markerPaint);
    canvas.restore();

  }
  // 需引入 image package
  Future<Uint8List> encodeJpgFromPng(Uint8List pngBytes) async {
    // 這裡假設你已經在 pubspec.yaml 加入 image: ^4.0.0

    final image = img.decodeImage(pngBytes)!;
    return Uint8List.fromList(img.encodeJpg(image));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}