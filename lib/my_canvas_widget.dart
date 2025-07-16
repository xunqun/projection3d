import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:projection3d/projection3d.dart';
import 'package:image/image.dart' as img;

class MyCanvasWidget extends StatelessWidget {
  final List<GeoPoint> polyline;
  final GeoPoint camera;
  final GeoPoint lookAt;

  final void Function(Uint8List jpgBytes)? drawCallback;

  const MyCanvasWidget({
    Key? key,
    required this.polyline,
    required this.camera,
    required this.lookAt,
    this.drawCallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final painter = _MyPainter(
      projectCanvas: ThreeDProjectCanvas(
        camera: camera,
        lookAt: lookAt,
        polyline: polyline,
      ),
      drawCallback: drawCallback,
    );

    return CustomPaint(size: Size(400, 400), painter: painter);
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
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final paint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;
    projectCanvas.draw(canvas, paint);

    // ��中央底部繪製目前位置三角形標記
    final markerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    const markerRadius = 24.0;
    final markerCenter = Offset(size.width / 2, size.height - markerRadius - 10);
    final trianglePath = Path()
      ..moveTo(markerCenter.dx, markerCenter.dy - markerRadius)
      ..lineTo(markerCenter.dx - markerRadius, markerCenter.dy + markerRadius /5)
      ..lineTo(markerCenter.dx + markerRadius, markerCenter.dy + markerRadius /5)
      ..close();
    canvas.drawPath(trianglePath, markerPaint);
    canvas.restore();

    // 若有 drawCallback，產生 jpg 圖片
    if (drawCallback != null) {
      _exportJpg(size);
    }
  }

  Future<void> _exportJpg(Size size) async {
    final recorder = PictureRecorder();
    final exportCanvas = Canvas(recorder);
    // clip & 背景
    exportCanvas.save();
    exportCanvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final backgroundPaint = Paint()
      ..color = Colors.black
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    exportCanvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
    // polyline
    final paint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;
    projectCanvas.draw(exportCanvas, paint);
    // marker
    final markerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    const markerRadius = 24.0;
    final markerCenter = Offset(size.width / 2, size.height - markerRadius - 10);
    final trianglePath = Path()
      ..moveTo(markerCenter.dx, markerCenter.dy - markerRadius)
      ..lineTo(markerCenter.dx - markerRadius, markerCenter.dy + markerRadius /5)
      ..lineTo(markerCenter.dx + markerRadius, markerCenter.dy + markerRadius /5)
      ..close();
    exportCanvas.drawPath(trianglePath, markerPaint);
    exportCanvas.restore();
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ImageByteFormat.png);
    if (byteData != null) {
      final jpgBytes = await encodeJpgFromPng(byteData.buffer.asUint8List());
      drawCallback?.call(jpgBytes);
    }
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