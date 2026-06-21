import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
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

    // 黑色底色 (HUD 投影透明底色，維持純黑)
    final backgroundPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // 1. 附近道路（暖沙暗灰色線段）
    final roadPaint = Paint()
      ..color = const Color(0xFF9C9C9C)
      ..isAntiAlias = true
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    projectCanvas.drawRoads(canvas, roadPaint);

    // 2. 導航路線（雙層繪製，塑造琥珀橘描邊效果）
    // 2.1 外層：深琥珀橘 (#D97706)
    final navPaintOuter = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    projectCanvas.draw(canvas, navPaintOuter, thicknessOverride: projectCanvas.thickness * 1);

    // 2.2 內層：溫暖白 (#FFFBF8)
    final navPaintInner = Paint()
      ..color = Colors.red
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    projectCanvas.draw(canvas, navPaintInner, thicknessOverride: projectCanvas.thickness * 0.9);

    // 3. 目前位置（雙層箭頭已在 drawMarker 內部實現，此處傳入基準 Paint）
    final markerPaint = Paint()
      ..isAntiAlias = true;
    projectCanvas.drawMarker(canvas, markerPaint);

    // 4. Debug 序號文字
    projectCanvas.drawDebugSeq(canvas);

    canvas.restore();
  }

  Future<Uint8List> encodeJpgFromPng(Uint8List pngBytes) async {
    final image = img.decodeImage(pngBytes)!;
    return Uint8List.fromList(img.encodeJpg(image));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
