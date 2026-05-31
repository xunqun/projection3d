import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'projection3d.dart';

/// Fetches nearby road geometries from Mapbox Vector Tiles.
/// Results are cached in memory by tile key to avoid repeated API calls.
class RoadTileFetcher {
  static const String _accessToken =
      'pk.eyJ1IjoieHVucXVuIiwiYSI6ImFkV1dEYncifQ.NlYe3nK_4rIOkMUlTTnOWQ';
  static const int _zoom = 16;

  // Memory cache: "$z/$x/$y" → roads
  static final Map<String, List<List<GeoPoint>>> _cache = {};

  /// 回傳 [lat],[lon] 在 zoom=16 下對應的 tile key（格式："z/x/y"）。
  /// 供外部判斷是否已移入新 tile，決定是否重新抓取。
  static String tileKeyFor(double lat, double lon) {
    final (tx, ty) = _latLonToTile(lat, lon, _zoom);
    return '$_zoom/$tx/$ty';
  }

  /// Returns road polylines (in GeoPoint) within the tile that contains [lat],[lon].
  static Future<List<List<GeoPoint>>> fetchNearbyRoads(
      double lat, double lon) async {
    final (tx, ty) = _latLonToTile(lat, lon, _zoom);
    final key = '$_zoom/$tx/$ty';

    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    final url =
        'https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/$_zoom/$tx/$ty.mvt'
        '?access_token=$_accessToken';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('RoadTileFetcher: HTTP ${response.statusCode}');
        return [];
      }
      final roads = _parseMvt(response.bodyBytes, tx, ty, _zoom);
      _cache[key] = roads;
      print('RoadTileFetcher: fetched ${roads.length} roads for tile $key');
      return roads;
    } catch (e) {
      print('RoadTileFetcher error: $e');
      return [];
    }
  }

  // ── Tile coordinate helpers ──────────────────────────────────────────────

  static (int x, int y) _latLonToTile(double lat, double lon, int z) {
    final n = pow(2, z).toInt();
    final x = ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
    final latRad = lat * pi / 180.0;
    final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n)
        .floor()
        .clamp(0, n - 1);
    return (x, y);
  }

  static GeoPoint _tilePixelToGeoPoint(
      double px, double py, int tileX, int tileY, int z, int extent) {
    final n = pow(2, z);
    final lon = (tileX + px / extent) / n * 360.0 - 180.0;
    final latRad =
        atan(_sinh(pi * (1.0 - 2.0 * (tileY + py / extent) / n)));
    return GeoPoint(latRad * 180.0 / pi, lon);
  }

  // ── Minimal Mapbox Vector Tile (protobuf) parser ─────────────────────────
  //
  // MVT spec: https://github.com/mapbox/vector-tile-spec
  //
  // Tile message:
  //   field 3 (repeated Layer): length-delimited
  //
  // Layer message:
  //   field 1 (string name)
  //   field 2 (repeated Feature)
  //   field 5 (uint32 extent, default 4096)
  //
  // Feature message:
  //   field 3 (GeomType): 1=Point, 2=LineString, 3=Polygon
  //   field 4 (packed uint32 geometry)
  //
  // Geometry encoding:
  //   Each command integer = (count << 3) | cmdId
  //   cmdId 1 = MoveTo,  params: count × (zigzag dx, zigzag dy)
  //   cmdId 2 = LineTo,  params: count × (zigzag dx, zigzag dy)
  //   cmdId 7 = ClosePath, no params

  static const List<String> _roadLayerNames = ['road'];

  static List<List<GeoPoint>> _parseMvt(
      Uint8List bytes, int tileX, int tileY, int z) {
    final roads = <List<GeoPoint>>[];
    final reader = _ProtoReader(bytes);

    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x7;

      if (fieldNum == 3 && wireType == 2) {
        // Layer
        final layerBytes = reader.readLengthDelimited();
        final layerRoads =
            _parseLayer(layerBytes, tileX, tileY, z);
        roads.addAll(layerRoads);
      } else {
        reader.skipField(wireType);
      }
    }
    return roads;
  }

  static List<List<GeoPoint>> _parseLayer(
      Uint8List bytes, int tileX, int tileY, int z) {
    String layerName = '';
    int extent = 4096;
    final features = <_RawFeature>[];
    final reader = _ProtoReader(bytes);

    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x7;

      switch (fieldNum) {
        case 1: // name
          layerName = reader.readString();
          break;
        case 2: // feature
          final featureBytes = reader.readLengthDelimited();
          features.add(_parseFeature(featureBytes));
          break;
        case 5: // extent
          extent = reader.readVarint();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    if (!_roadLayerNames.contains(layerName)) return [];

    final roads = <List<GeoPoint>>[];
    for (final f in features) {
      if (f.geomType != 2) continue; // LineString only
      final lines = _decodeGeometry(f.geometry, tileX, tileY, z, extent);
      roads.addAll(lines);
    }
    return roads;
  }

  static _RawFeature _parseFeature(Uint8List bytes) {
    int geomType = 0;
    List<int> geometry = [];
    final reader = _ProtoReader(bytes);

    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x7;

      switch (fieldNum) {
        case 3: // type
          geomType = reader.readVarint();
          break;
        case 4: // geometry (packed uint32)
          geometry = reader.readPackedVarint();
          break;
        default:
          reader.skipField(wireType);
      }
    }
    return _RawFeature(geomType, geometry);
  }

  static List<List<GeoPoint>> _decodeGeometry(
      List<int> cmds, int tileX, int tileY, int z, int extent) {
    final lines = <List<GeoPoint>>[];
    List<GeoPoint>? current;
    int cx = 0, cy = 0;
    int i = 0;

    while (i < cmds.length) {
      final cmd = cmds[i++];
      final cmdId = cmd & 0x7;
      final count = cmd >> 3;

      if (cmdId == 1) {
        // MoveTo
        if (current != null && current.length >= 2) lines.add(current);
        current = [];
        for (int j = 0; j < count; j++) {
          if (i + 1 >= cmds.length) break;
          cx += _zigzagDecode(cmds[i++]);
          cy += _zigzagDecode(cmds[i++]);
          current.add(_tilePixelToGeoPoint(
              cx.toDouble(), cy.toDouble(), tileX, tileY, z, extent));
        }
      } else if (cmdId == 2) {
        // LineTo
        for (int j = 0; j < count; j++) {
          if (i + 1 >= cmds.length) break;
          cx += _zigzagDecode(cmds[i++]);
          cy += _zigzagDecode(cmds[i++]);
          current?.add(_tilePixelToGeoPoint(
              cx.toDouble(), cy.toDouble(), tileX, tileY, z, extent));
        }
      } else if (cmdId == 7) {
        // ClosePath
        if (current != null && current.length >= 2) {
          current.add(current.first); // close ring
        }
      } else {
        break; // unknown command, stop
      }
    }
    if (current != null && current.length >= 2) lines.add(current);
    return lines;
  }

  static int _zigzagDecode(int n) => (n >> 1) ^ -(n & 1);

  /// dart:math 不含雙曲函數，手動實作 sinh
  static double _sinh(double x) => (exp(x) - exp(-x)) / 2.0;
}

class _RawFeature {
  final int geomType;
  final List<int> geometry;
  _RawFeature(this.geomType, this.geometry);
}

// ── Minimal protobuf binary reader ──────────────────────────────────────────

class _ProtoReader {
  final Uint8List _bytes;
  int _pos = 0;

  _ProtoReader(this._bytes);

  bool get hasMore => _pos < _bytes.length;

  int readVarint() {
    int result = 0;
    int shift = 0;
    while (_pos < _bytes.length) {
      final b = _bytes[_pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  Uint8List readLengthDelimited() {
    final len = readVarint();
    final slice = _bytes.sublist(_pos, _pos + len);
    _pos += len;
    return slice;
  }

  String readString() {
    final bytes = readLengthDelimited();
    return String.fromCharCodes(bytes);
  }

  List<int> readPackedVarint() {
    final bytes = readLengthDelimited();
    final reader = _ProtoReader(bytes);
    final result = <int>[];
    while (reader.hasMore) {
      result.add(reader.readVarint());
    }
    return result;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0: // varint
        readVarint();
        break;
      case 1: // 64-bit
        _pos += 8;
        break;
      case 2: // length-delimited
        final len = readVarint();
        _pos += len;
        break;
      case 5: // 32-bit
        _pos += 4;
        break;
      default:
        _pos = _bytes.length; // unknown, abort
    }
  }
}
