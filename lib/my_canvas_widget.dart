import 'package:flutter/material.dart';
import 'package:projection3d/projection3d.dart';

class MyCanvasWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final polyline = [
      GeoPoint(20.0, 20.0),
      GeoPoint(20.01, 20.01),
      GeoPoint(20.04, 20.02),
    ];


    final camera = GeoPoint(19.999, 19.999, 100); // 上方攝影機
    final lookAt = polyline[0];

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
    // 填滿黑色底色
    final backgroundPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final paint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;
    projectCanvas.draw(canvas, paint);

    // 在中央底部繪製目前位置標記
    final markerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    const markerRadius = 8.0;
    final markerCenter = Offset(size.width / 2, size.height - markerRadius - 10);
    canvas.drawCircle(markerCenter, markerRadius, markerPaint);
    // 可選：加上文字
    final textPainter = TextPainter(
      text: TextSpan(
        text: '目前位置',
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(markerCenter.dx - textPainter.width / 2, markerCenter.dy + markerRadius + 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}