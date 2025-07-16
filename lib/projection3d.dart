import 'dart:math';
import 'dart:ui';

class GeoPoint {
  final double lat, lon, alt;
  GeoPoint(this.lat, this.lon, [this.alt = 0]);

  List<double> toECEF() {
    // 忽略地球曲率，���設所有點在平面上
    // 緯度 1 度約 111320 米
    const double metersPerDegreeLat = 111320.0;
    final double x = (lon - 0) * metersPerDegreeLat * cos(lat * pi / 180);
    final double y = (lat - 0) * metersPerDegreeLat;
    final double z = alt;
    return [x, y, z];
  }
}

class ThreeDProjectCanvas {
  final GeoPoint camera;
  final GeoPoint lookAt;
  final List<GeoPoint> polyline;
  final double thickness;
  final Size screenSize;

  ThreeDProjectCanvas({
    required this.camera,
    required this.lookAt,
    required this.polyline,
    this.thickness = 20,
    this.screenSize = const Size(400, 400),
  });

  void draw(Canvas canvas, Paint paint) {
    final viewMatrix = _lookAt(camera.toECEF(), lookAt.toECEF());
    if (polyline.length < 2) return;

    // 計算每個點的平均法線
    final normals = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      List<double> n;
      if (i == 0) {
        // 第一個點，取第一段法線
        final dir = _normalize(_sub(polyline[1].toECEF(), polyline[0].toECEF()));
        n = _normalize(_cross(dir, [0, 0, 1]));
      } else if (i == polyline.length - 1) {
        // 最後一個點，取最後一段法線
        final dir = _normalize(_sub(polyline[i].toECEF(), polyline[i - 1].toECEF()));
        n = _normalize(_cross(dir, [0, 0, 1]));
      } else {
        // 取前後段法線平均
        final dir1 = _normalize(_sub(polyline[i].toECEF(), polyline[i - 1].toECEF()));
        final dir2 = _normalize(_sub(polyline[i + 1].toECEF(), polyline[i].toECEF()));
        final n1 = _normalize(_cross(dir1, [0, 0, 1]));
        final n2 = _normalize(_cross(dir2, [0, 0, 1]));
        n = _normalize([n1[0] + n2[0], n1[1] + n2[1], n1[2] + n2[2]]);
      }
      normals.add(n);
    }

    // 建立 offset 點
    final left = <List<double>>[];
    final right = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      final offset = normals[i].map((v) => v * (thickness / 2)).toList();
      left.add(_add(polyline[i].toECEF(), offset));
      right.add(_sub(polyline[i].toECEF(), offset));
    }

    // 畫每一段
    for (int i = 0; i < polyline.length - 1; i++) {
      final quad = [
        left[i],
        right[i],
        right[i + 1],
        left[i + 1],
      ];
      final projected = quad.map((v) => _project(v, viewMatrix)).toList();
      if (projected.any((p) => p == null)) continue;
      final path = Path()..moveTo(projected[0]!.dx, projected[0]!.dy);
      for (int j = 1; j < projected.length; j++) {
        path.lineTo(projected[j]!.dx, projected[j]!.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }


  List<List<double>> _lookAt(List<double> eye, List<double> center) {
    final f = _normalize(_sub(center, eye));
    final s = _normalize(_cross(f, [0, 0, 1]));
    final u = _cross(s, f);

    final List<List<double>> M = [
      [s[0], s[1], s[2], -_dot(s, eye)],
      [u[0], u[1], u[2], -_dot(u, eye)],
      [-f[0], -f[1], -f[2], _dot(f, eye)],
      [0, 0, 0, 1],
    ];
    return M;
  }

  Offset? _project(List<double> point, List<List<double>> viewMatrix) {
    final width = screenSize.width;
    final height = screenSize.height;
    final fov = pi / 2; // 90 deg
    final aspect = width / height;

    List<double> mul(List<List<double>> m, List<double> v) {
      return List.generate(4, (i) =>
        m[i][0]*v[0] + m[i][1]*v[1] + m[i][2]*v[2] + m[i][3]*v[3]
      );
    }

    final p = [...point, 1.0];
    final v = mul(viewMatrix, p);

    final z = v[2];
    if (z == 0) return null;

    final xNDC = v[0] / -z;
    final yNDC = v[1] / -z;

    final xScreen = width / 2 + xNDC * width / 2;
    final yScreen = height / 2 - yNDC * height / 2;

    return Offset(xScreen, yScreen);
  }

  // Vector helpers
  List<double> _sub(List<double> a, List<double> b) => [a[0]-b[0], a[1]-b[1], a[2]-b[2]];
  List<double> _add(List<double> a, List<double> b) => [a[0]+b[0], a[1]+b[1], a[2]+b[2]];
  double _dot(List<double> a, List<double> b) => a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
  List<double> _cross(List<double> a, List<double> b) => [
    a[1]*b[2] - a[2]*b[1],
    a[2]*b[0] - a[0]*b[2],
    a[0]*b[1] - a[1]*b[0],
  ];
  List<double> _normalize(List<double> v) {
    final len = sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
    return [v[0]/len, v[1]/len, v[2]/len];
  }
}