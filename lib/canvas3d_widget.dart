import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:projection3d/projection3d.dart';
import 'package:image/image.dart' as img;

class Canvas3dWidget extends StatelessWidget {
  final List<GeoPoint> polyline;
  final GeoPoint camera;
  final GeoPoint lookAt;
  final GeoPoint currentPosition;
  final List<List<GeoPoint>> nearbyRoads;
  final Size size;

  const Canvas3dWidget({
    Key? key,
    required this.polyline,
    required this.camera,
    required this.lookAt,
    required this.currentPosition,
    this.nearbyRoads = const [],
    required this.size,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final painter = _MyPainter(
      projectCanvas: ThreeDProjectCanvas(
        camera: camera,
        lookAt: lookAt,
        currentPosition: currentPosition,
        polyline: polyline,
        nearbyRoads: nearbyRoads,
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
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // 黑色底色
    final backgroundPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // 1. 附近道路（灰色細線）
    final roadPaint = Paint()
      ..color = Colors.grey.shade600
      ..isAntiAlias = false
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    projectCanvas.drawRoads(canvas, roadPaint);

    // 2. 導航路線（白色粗帶）
    final navPaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = false
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
    projectCanvas.draw(canvas, navPaint);

    // 3. 目前位置（紅色三角形）
    final markerPaint = Paint()
      ..color = Colors.red
      ..isAntiAlias = false
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
    projectCanvas.drawMarker(canvas, markerPaint);

    canvas.restore();
  }

  Future<Uint8List> encodeJpgFromPng(Uint8List pngBytes) async {
    final image = img.decodeImage(pngBytes)!;
    return Uint8List.fromList(img.encodeJpg(image));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
