import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'projection3d.dart';
import 'package:image/image.dart' as img;

class Pic3DGenerator {
  static Pic3DGenerator _instance = Pic3DGenerator._();

  void Function(Uint8List)? drawCallback;

  /// Broadcast stream — UI 元件可訂閱此 stream 取得最新圖片，
  /// 不影響 drawCallback（BLE 傳輸用）。
  final StreamController<Uint8List> _streamController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get bitmapStream => _streamController.stream;

  Pic3DGenerator._();

  setBitmapListener(Function(Uint8List) callback) {
    drawCallback = callback;
  }

  static get() {
    return _instance;
  }

  void update(
    List<GeoPoint> polyline,
    GeoPoint camera,
    GeoPoint lookAt,
    GeoPoint currentPosition,
    Size size, {
    List<List<GeoPoint>> nearbyRoads = const [],
  }) {
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

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    painter.paint(canvas, size);

    final picture = recorder.endRecording();
    final imgFuture = picture.toImage(size.width.toInt(), size.height.toInt());

    imgFuture.then((image) {
      image.toByteData(format: ImageByteFormat.png).then((byteData) async {
        if (byteData == null) return;
        final jpgBytes = await painter.encodeJpgFromPng(byteData.buffer.asUint8List());

        // 1. BLE callback（原有邏輯）
        drawCallback?.call(jpgBytes);

        // 2. Broadcast stream（UI 縮圖用）
        if (!_streamController.isClosed) {
          _streamController.add(jpgBytes);
        }

        print('JPG size: ${jpgBytes.lengthInBytes / 1024} KB');
      });
    });
  }

  void dispose() {
    _streamController.close();
  }
}

class _MyPainter extends CustomPainter {
  final ThreeDProjectCanvas projectCanvas;
  _MyPainter({required this.projectCanvas});

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
      ..strokeWidth = 1
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
