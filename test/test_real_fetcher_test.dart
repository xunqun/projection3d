import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projection3d/projection3d.dart';
import 'package:projection3d/road_tile_fetcher.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('road_tile_fetcher_test_');
    RoadTileFetcher.cacheDirectoryOverride = tempDir;
  });

  tearDown(() async {
    RoadTileFetcher.cacheDirectoryOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Verify RoadTileFetcher fetches and decodes roads, saves to persistent cache, and hits cache', () async {
    final lat = 25.033964;
    final lon = 121.564468;

    // Clear memory cache so we don't hit memory cache
    RoadTileFetcher.clearMemoryCache();

    print('Calling RoadTileFetcher.fetchNearbyRoads (First Fetch - Network Download)...');
    final result1 = await RoadTileFetcher.fetchNearbyRoads(lat, lon);
    final (roads1, success1) = result1;

    print('First Fetch success: $success1');
    print('Total roads fetched: ${roads1.length}');

    expect(success1, isTrue);
    expect(roads1.isNotEmpty, isTrue);

    // Verify files exist in cache directory
    final cacheDir = Directory('${tempDir.path}/roads_cache');
    expect(await cacheDir.exists(), isTrue);
    final files = cacheDir.listSync();
    print('Cache directory files: ${files.map((f) => f.path.split('/').last).toList()}');
    expect(files.isNotEmpty, isTrue);

    // Clear memory cache to force reading from persistent cache
    RoadTileFetcher.clearMemoryCache();

    print('Calling RoadTileFetcher.fetchNearbyRoads (Second Fetch - Persistent Cache hit)...');
    final result2 = await RoadTileFetcher.fetchNearbyRoads(lat, lon);
    final (roads2, success2) = result2;

    print('Second Fetch success: $success2');
    print('Total roads fetched: ${roads2.length}');

    expect(success2, isTrue);
    expect(roads2.isNotEmpty, isTrue);
    expect(roads2.length, equals(roads1.length));

    final latRad = lat * pi / 180.0;
    const double a = 6378137.0;
    const double e2 = 0.00669437999014;
    final double M = a * (1 - e2) / pow(1 - e2 * sin(latRad) * sin(latRad), 1.5);
    final double N = a / sqrt(1 - e2 * sin(latRad) * sin(latRad));
    final double metersPerDegreeLat = M * pi / 180;
    final double metersPerDegreeLon = N * cos(latRad) * pi / 180;

    final headingRad = 90.0 * pi / 180;
    final distance = 10.0;
    double latOffset = (distance * cos(headingRad)) / metersPerDegreeLat;
    double lonOffset = (distance * sin(headingRad)) / metersPerDegreeLon;

    final camera = GeoPoint(lat - latOffset, lon - lonOffset, 60);
    final lookAt = GeoPoint(lat + latOffset * 3, lon + lonOffset * 3, 0);
    final currentPos = GeoPoint(lat, lon, 0);

    final canvas = ThreeDProjectCanvas(
      camera: camera,
      lookAt: lookAt,
      currentPosition: currentPos,
      polyline: [currentPos, lookAt],
      nearbyRoads: roads2,
      screenSize: const Size(240, 136),
    );

    final svg = canvas.toSvg();
    final lineCount = RegExp(r'<line').allMatches(svg).length;
    print('Generated SVG lines: $lineCount');
    expect(lineCount > 0, isTrue);
  });
}
