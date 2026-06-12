import 'dart:math';
import 'package:flutter/material.dart';
import 'package:projection3d/canvas3d_widget.dart';

import 'projection3d.dart';
import 'road_tile_fetcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  List<List<GeoPoint>> _nearbyRoads = [];

  // 導航起點（camera 所在位置）
  final GeoPoint _camera = GeoPoint(22.963207, 120.219099, 50);
  final GeoPoint _lookAt = GeoPoint(22.9632, 120.21989, 0);

  final List<GeoPoint> _polyline = [
    GeoPoint(22.963207, 120.219099),
    GeoPoint(22.9632, 120.21989),
    GeoPoint(22.96474, 120.21985),
    GeoPoint(22.96474, 120.22016),
    GeoPoint(22.96475, 120.22077),
    GeoPoint(22.96476, 120.22104),
    GeoPoint(22.96476, 120.22128),
    GeoPoint(22.96477, 120.22205),
    GeoPoint(22.96479, 120.2228),
    GeoPoint(22.96479, 120.22316),
  ];

  @override
  void initState() {
    super.initState();
    _loadNearbyRoads();
  }

  Future<void> _loadNearbyRoads() async {
    // 以 camera 位置為中心抓取附近道路
    final (roads, _) = await RoadTileFetcher.fetchNearbyRoads(
        _camera.lat, _camera.lon);
    if (mounted) {
      setState(() {
        _nearbyRoads = roads;
      });
    }
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  // 計算 camera 到 polyline 的最近點
  GeoPoint? closestPointOnPolyline(List<GeoPoint> polyline, GeoPoint camera) {
    double minDist = double.infinity;
    GeoPoint? closest;
    List<double> cam = camera.toECEF();
    for (int i = 0; i < polyline.length - 1; i++) {
      List<double> a = polyline[i].toECEF();
      List<double> b = polyline[i + 1].toECEF();
      List<double> ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      List<double> ac = [cam[0] - a[0], cam[1] - a[1], cam[2] - a[2]];
      double abLen2 = ab[0]*ab[0] + ab[1]*ab[1] + ab[2]*ab[2];
      double t = abLen2 == 0 ? 0 : (ab[0]*ac[0] + ab[1]*ac[1] + ab[2]*ac[2]) / abLen2;
      t = t.clamp(0, 1);
      List<double> proj = [a[0]+ab[0]*t, a[1]+ab[1]*t, a[2]+ab[2]*t];
      double dist = sqrt(pow(cam[0]-proj[0], 2) + pow(cam[1]-proj[1], 2) + pow(cam[2]-proj[2], 2));
      if (dist < minDist) {
        minDist = dist;
        closest = GeoPoint(
          polyline[i].lat + (polyline[i+1].lat - polyline[i].lat) * t,
          polyline[i].lon + (polyline[i+1].lon - polyline[i].lon) * t,
          polyline[i].alt + (polyline[i+1].alt - polyline[i].alt) * t,
        );
      }
    }
    return closest;
  }

  @override
  Widget build(BuildContext context) {
    final GeoPoint? closest = closestPointOnPolyline(_polyline, _camera);
    int startIdx = 0;
    for (int i = 0; i < _polyline.length - 1; i++) {
      if (closest != null &&
          ((_polyline[i].lat - closest.lat) * (_polyline[i+1].lat - closest.lat) <= 0) &&
          ((_polyline[i].lon - closest.lon) * (_polyline[i+1].lon - closest.lon) <= 0)) {
        startIdx = i + 1;
        break;
      }
    }
    final filteredPolyline = [
      if (closest != null) closest,
      ..._polyline.sublist(startIdx),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            // 道路載入狀態提示
            Text(
              _nearbyRoads.isEmpty
                  ? '載入附近道路中...'
                  : '已載入 ${_nearbyRoads.length} 條附近道路',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 400,
              height: 400,
              child: Canvas3dWidget(
                polyline: filteredPolyline,
                camera: _camera,
                lookAt: _lookAt,
                currentPosition: _lookAt,
                nearbyRoads: _nearbyRoads,
                size: const Size(400, 400),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
