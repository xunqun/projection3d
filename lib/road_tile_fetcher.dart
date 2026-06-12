import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'projection3d.dart';

/// Fetches nearby road geometries from Mapbox Vector Tiles.
/// Results are cached in memory by tile key to avoid repeated API calls.
class RoadTileFetcher {
  static const String _apiKey =
      'ZjbkQ0Gcs3felzVZFzwoO1P7UPaClnauivumM0HZ5ZQ';
  static const int _zoom = 16;

  // Memory cache: "$z/$x/$y" → roads
  static final Map<String, List<List<GeoPoint>>> _cache = {};
  static final List<String> _cacheKeys = [];
  static const int _maxCacheSize = 50;

  /// For unit testing only. If set, this directory will be used instead of [getTemporaryDirectory].
  static Directory? cacheDirectoryOverride;

  static void _saveToCache(String key, List<List<GeoPoint>> roads) {
    if (_cache.containsKey(key)) {
      _cacheKeys.remove(key);
    }
    _cache[key] = roads;
    _cacheKeys.add(key);
    if (_cacheKeys.length > _maxCacheSize) {
      final oldest = _cacheKeys.removeAt(0);
      _cache.remove(oldest);
    }
  }

  static void clearMemoryCache() {
    _cache.clear();
    _cacheKeys.clear();
  }

  /// 回傳 [lat],[lon] 在 zoom=16 下對應的 tile key（格式："z/x/y"）。
  /// 供外部判斷是否已移入新 tile，決定是否重新抓取。
  static String tileKeyFor(double lat, double lon) {
    final (tx, ty) = _latLonToTile(lat, lon, _zoom);
    return '$_zoom/$tx/$ty';
  }

  /// Returns road polylines (in GeoPoint) within the 3x3 tiles surrounding [lat],[lon].
  static Future<(List<List<GeoPoint>> roads, bool success)> fetchNearbyRoads(
      double lat, double lon) async {
    final (tx, ty) = _latLonToTile(lat, lon, _zoom);
    final allRoads = <List<GeoPoint>>[];
    final futures = <Future<List<List<GeoPoint>>?>>[];

    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        futures.add(_fetchSingleTile(tx + dx, ty + dy, _zoom));
      }
    }

    final results = await Future.wait(futures);
    bool success = true;
    for (final roads in results) {
      if (roads == null) {
        success = false;
      } else {
        allRoads.addAll(roads);
      }
    }
    return (allRoads, success);
  }

  static Future<List<List<GeoPoint>>?> _fetchSingleTile(
      int tx, int ty, int z) async {
    final key = '$z/$tx/$ty';

    // 1. 檢查記憶體快取 (Memory Cache)
    if (_cache.containsKey(key)) {
      _cacheKeys.remove(key);
      _cacheKeys.add(key);
      return _cache[key]!;
    }

    // 2. 檢查持久化本機檔案快取 (Persistent File Cache)
    File? cacheFile;
    try {
      final tempDir = cacheDirectoryOverride ?? await getTemporaryDirectory();
      final roadsCacheDir = Directory('${tempDir.path}/roads_cache');
      if (!await roadsCacheDir.exists()) {
        await roadsCacheDir.create(recursive: true);
      }
      cacheFile = File('${roadsCacheDir.path}/${z}_${tx}_$ty.omv');
    } catch (e) {
      print('RoadTileFetcher: failed to init persistent cache dir: $e');
    }

    if (cacheFile != null && await cacheFile.exists()) {
      try {
        final lastModified = await cacheFile.lastModified();
        final age = DateTime.now().difference(lastModified);
        if (age.inDays < 14) {
          final bodyBytes = await cacheFile.readAsBytes();
          final roads = _parseMvt(bodyBytes, tx, ty, z);
          _saveToCache(key, roads);
          print('RoadTileFetcher: loaded $key from persistent cache (age: ${age.inDays} days)');
          return roads;
        } else {
          print('RoadTileFetcher: persistent cache expired for $key (${age.inDays} days old)');
        }
      } catch (e) {
        print('RoadTileFetcher: failed to read cache file: $e');
      }
    }

    // 3. 快取未命中，從 HERE API 下載
    final url =
        'https://vector.hereapi.com/v2/vectortiles/base/mc/$z/$tx/$ty/omv'
        '?apikey=$_apiKey';

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        print('RoadTileFetcher: HTTP ${response.statusCode} for $key');
        return null;
      }
      final bodyBytes = response.bodyBytes;
      final roads = _parseMvt(bodyBytes, tx, ty, z);
      
      // 寫入記憶體與檔案快取
      _saveToCache(key, roads);
      if (cacheFile != null) {
        try {
          await cacheFile.writeAsBytes(bodyBytes);
          print('RoadTileFetcher: saved $key to persistent cache');
        } catch (e) {
          print('RoadTileFetcher: failed to write cache file: $e');
        }
      }

      print('RoadTileFetcher: fetched ${roads.length} roads for tile $key');
      return roads;
    } catch (e) {
      print('RoadTileFetcher error for $key: $e');
      return null;
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
  //   field 3 (repeated string keys)
  //   field 4 (repeated Value values)
  //   field 5 (uint32 extent, default 4096)
  //
  // Feature message:
  //   field 2 (packed uint32 tags)
  //   field 3 (GeomType): 1=Point, 2=LineString, 3=Polygon
  //   field 4 (packed uint32 geometry)
  //
  // Geometry encoding:
  //   Each command integer = (count << 3) | cmdId
  //   cmdId 1 = MoveTo,  params: count × (zigzag dx, zigzag dy)
  //   cmdId 2 = LineTo,  params: count × (zigzag dx, zigzag dy)
  //   cmdId 7 = ClosePath, no params

  static const List<String> _roadLayerNames = ['roads'];

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
    final keys = <String>[];
    final values = <dynamic>[];
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
        case 3: // keys
          keys.add(reader.readString());
          break;
        case 4: // values (repeated Value)
          final valueBytes = reader.readLengthDelimited();
          values.add(_parseValue(valueBytes));
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

      // Extract kind and check if it's a drivable road
      String? roadKind;
      for (int i = 0; i < f.tags.length - 1; i += 2) {
        final keyIdx = f.tags[i];
        final valIdx = f.tags[i + 1];
        if (keyIdx < keys.length && valIdx < values.length) {
          if (keys[keyIdx] == 'kind') {
            final val = values[valIdx];
            if (val is String) {
              roadKind = val;
            }
            break;
          }
        }
      }

      // Filter out non-drivable kinds to reduce rendering overhead
      const nonDrivableKinds = {
        'path',
        'pedestrian',
        'railway',
        'ferry',
        'runway',
        'taxiway',
        'pier',
        'leisure'
      };

      if (roadKind != null && nonDrivableKinds.contains(roadKind)) {
        continue;
      }

      final lines = _decodeGeometry(f.geometry, tileX, tileY, z, extent);
      roads.addAll(lines);
    }
    return roads;
  }

  static _RawFeature _parseFeature(Uint8List bytes) {
    int geomType = 0;
    List<int> geometry = [];
    List<int> tags = [];
    final reader = _ProtoReader(bytes);

    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x7;

      switch (fieldNum) {
        case 2: // tags (packed uint32)
          tags = reader.readPackedVarint();
          break;
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
    return _RawFeature(geomType, geometry, tags);
  }

  static dynamic _parseValue(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    while (reader.hasMore) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x7;

      switch (fieldNum) {
        case 1: // string_value
          return reader.readString();
        case 2: // float_value
          reader.skipField(wireType);
          break;
        case 3: // double_value
          reader.skipField(wireType);
          break;
        case 4: // int_value
          return reader.readVarint();
        case 5: // uint_value
          return reader.readVarint();
        case 6: // sint_value
          final v = reader.readVarint();
          return (v >> 1) ^ -(v & 1); // zigzag decode for sint
        case 7: // bool_value
          return reader.readVarint() != 0;
        default:
          reader.skipField(wireType);
      }
    }
    return null;
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
  final List<int> tags;
  _RawFeature(this.geomType, this.geometry, this.tags);
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
