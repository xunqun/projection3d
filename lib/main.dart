import 'dart:math';
import 'package:flutter/material.dart';
import 'package:projection3d/canvas3d_widget.dart';

import 'projection3d.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}



class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  var polyline = [
    GeoPoint(25.0330, 121.5654),
    GeoPoint(25.034, 121.5640),
    GeoPoint(25.034, 121.5620),
    GeoPoint(25.035, 121.5600),
    GeoPoint(25.036, 121.5600),
    GeoPoint(25.0388, 121.5567),
  ];

  var camera = GeoPoint(25.0342, 121.5700, 100);
  var lookAt = GeoPoint(25.0388, 121.5567);

  // 計算camera到polyline線段的最近點
  GeoPoint? closestPointOnPolyline(List<GeoPoint> polyline, GeoPoint camera) {
    double minDist = double.infinity;
    GeoPoint? closest;
    int closestSegmentIdx = 0;
    double metersPerDegreeLat = 111320.0;
    List<double> cam = camera.toECEF();
    for (int i = 0; i < polyline.length - 1; i++) {
      List<double> a = polyline[i].toECEF();
      List<double> b = polyline[i + 1].toECEF();
      // 線段ab
      List<double> ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      List<double> ac = [cam[0] - a[0], cam[1] - a[1], cam[2] - a[2]];
      double abLen2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
      double t = abLen2 == 0 ? 0 : (ab[0] * ac[0] + ab[1] * ac[1] + ab[2] * ac[2]) / abLen2;
      t = t.clamp(0, 1);
      List<double> proj = [a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t];
      double dist = sqrt(pow(cam[0] - proj[0], 2) + pow(cam[1] - proj[1], 2) + pow(cam[2] - proj[2], 2));
      if (dist < minDist) {
        minDist = dist;
        closest = GeoPoint(
          polyline[i].lat + (polyline[i + 1].lat - polyline[i].lat) * t,
          polyline[i].lon + (polyline[i + 1].lon - polyline[i].lon) * t,
          polyline[i].alt + (polyline[i + 1].alt - polyline[i].alt) * t,
        );
        closestSegmentIdx = i;
      }
    }
    // 返回最近點和其所在segment index
    return closest;
  }

  @override
  Widget build(BuildContext context) {
    // 找到最近點
    GeoPoint? closest = closestPointOnPolyline(polyline, camera);
    // 找到最近點在polyline的哪個segment
    int startIdx = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      double lat1 = polyline[i].lat, lat2 = polyline[i + 1].lat;
      double lon1 = polyline[i].lon, lon2 = polyline[i + 1].lon;
      if (closest != null &&
          ((closest.lat - lat1) * (closest.lat - lat2) <= 0) &&
          ((closest.lon - lon1) * (closest.lon - lon2) <= 0)) {
        startIdx = i + 1;
        break;
      }
    }
    List<GeoPoint> filteredPolyline = [if (closest != null) closest, ...polyline.sublist(startIdx)];

    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(
              width: 400,
              height: 400,
              child: Canvas3dWidget(
                polyline: filteredPolyline,
                camera: camera,
                lookAt: lookAt,
              ),
              )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
