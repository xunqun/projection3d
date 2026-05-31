import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'projection3d.dart';

/// SVG 版圖片生成器，與 [Pic3DGenerator] 介面對齊。
///
/// 每次 [update] 呼叫後：
/// 1. 將 SVG 字串以 UTF-8 編碼為 [Uint8List]
/// 2. 透過 [svgStream] 廣播給 UI（縮圖預覽）
/// 3. 呼叫 [outputCallback] 傳給 BLE 等外部通道
class Svg3DGenerator {
  static final Svg3DGenerator _instance = Svg3DGenerator._();
  static Svg3DGenerator get() => _instance;

  Svg3DGenerator._();

  /// BLE / 外部傳輸 callback
  void Function(Uint8List)? outputCallback;

  void setOutputListener(void Function(Uint8List) callback) {
    outputCallback = callback;
  }

  /// UI 縮圖訂閱用 stream（SVG UTF-8 bytes）
  final StreamController<Uint8List> _streamController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get svgStream => _streamController.stream;

  void update(
    List<GeoPoint> polyline,
    GeoPoint camera,
    GeoPoint lookAt,
    GeoPoint currentPosition,
    Size size, {
    List<List<GeoPoint>> nearbyRoads = const [],
  }) {
    final canvas = ThreeDProjectCanvas(
      camera: camera,
      lookAt: lookAt,
      currentPosition: currentPosition,
      polyline: polyline,
      nearbyRoads: nearbyRoads,
      screenSize: size,
    );

    final svgString = canvas.toSvg();
    final bytes = Uint8List.fromList(utf8.encode(svgString));

    outputCallback?.call(bytes);

    if (!_streamController.isClosed) {
      _streamController.add(bytes);
    }

    print('SVG size: ${bytes.lengthInBytes / 1024} KB');
  }

  void dispose() {
    _streamController.close();
  }
}
