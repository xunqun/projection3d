import 'package:flutter/material.dart';
import 'package:projection3d/projection3d.dart';

class MyCanvasWidget extends StatelessWidget {
  final List<GeoPoint> polyline;
  final GeoPoint camera;
  final GeoPoint lookAt;

  const MyCanvasWidget({
    Key? key,
    required this.polyline,
    required this.camera,
    required this.lookAt,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final painter = _MyPainter(
      projectCanvas: ThreeDProjectCanvas(
        camera: camera,
        lookAt: lookAt,
        polyline: polyline,
      ),
    );

    return CustomPaint(size: Size(400, 400), painter: painter);
  }
}

class _MyPainter extends CustomPainter {
  final ThreeDProjectCanvas projectCanvas;
  _MyPainter({required this.projectCanvas});

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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}