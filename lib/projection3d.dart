import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

class GeoPoint {
  double lat = 0; // 緯度
  double lon = 0; // 經度
  double alt = 0; // 海拔高度，默認為 0

  GeoPoint(this.lat, this.lon, [this.alt = 0]);

  List<double> toECEF() {

    const double a = 6378137.0; // 赤道半徑
    const double e2 = 0.00669437999014; // 離心率平方

    final double latRad = lat * pi / 180;
    final double lonRad = lon * pi / 180;
    final double N = a / sqrt(1 - e2 * sin(latRad) * sin(latRad));
    final double x = (N + alt) * cos(latRad) * cos(lonRad);
    final double y = (N + alt) * cos(latRad) * sin(lonRad);
    final double z = (N * (1 - e2) + alt) * sin(latRad);
    // final double z = (N * (1 - e2) + alt) ;
    return [x, y, z];
  }
}

class ThreeDProjectCanvas {
  final GeoPoint camera;
  final GeoPoint lookAt;
  final GeoPoint currentPosition;
  final List<GeoPoint> polyline;
  final double thickness;
  final Size screenSize;

  ThreeDProjectCanvas({
    required this.camera,
    required this.lookAt,
    required this.currentPosition,
    required this.polyline,
    this.thickness = 20,
    required this.screenSize,
  });

  void drawMarker(Canvas canvas, Paint paint) {
    // 以 currentPosition 為三角形中心，並在3D空間建立三角形
    final pos = currentPosition.toECEF();
    final look = lookAt.toECEF();
    final viewMatrix = _lookAt(camera.toECEF(), lookAt.toECEF());
    // 3D方向
    final dir = _normalize(_sub(look, pos));
    // 地心方向
    final up = _normalize(pos);
    // 右手法線
    final right = _normalize(_cross(dir, up));
    // 三角形大小
    const double size = 12.0;
    // 三角形三個頂點（3D）
    final tip3d = [
      pos[0] + dir[0] * size,
      pos[1] + dir[1] * size,
      pos[2] + dir[2] * size,
    ];
    final left3d = [
      pos[0] - right[0] * size * 0.6 - dir[0] * size * 0.6,
      pos[1] - right[1] * size * 0.6 - dir[1] * size * 0.6,
      pos[2] - right[2] * size * 0.6 - dir[2] * size * 0.6,
    ];
    final right3d = [
      pos[0] + right[0] * size * 0.6 - dir[0] * size * 0.6,
      pos[1] + right[1] * size * 0.6 - dir[1] * size * 0.6,
      pos[2] + right[2] * size * 0.6 - dir[2] * size * 0.6,
    ];
    // 投影到2D
    final tip = _project(tip3d, viewMatrix);
    final left = _project(left3d, viewMatrix);
    final rightPt = _project(right3d, viewMatrix);
    if (tip == null || left == null || rightPt == null) return;
    final points = [tip, left, rightPt];
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, paint);
  }

  void draw(Canvas canvas, Paint paint) {

    final viewMatrix = _lookAt(camera.toECEF(), lookAt.toECEF());
    if (polyline.length < 2) return;


    // 建立 offset 點
    // 1. 計算每段 tangent 及法線
    final tangents = <List<double>>[];
    final normals = <List<double>>[];
    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i].toECEF();
      final b = polyline[i + 1].toECEF();
      final tangent = _normalize(_sub(b, a));
      // 地心方向
      final up = _normalize(a);
      // 該段法線
      final normal = _normalize(_cross(tangent, up));
      tangents.add(tangent);
      normals.add(normal);
    }

// 2. 每個頂點的 offset normal
    final offsetNormals = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      if (i == 0) {
        offsetNormals.add(normals[0]);
      } else if (i == polyline.length - 1) {
        offsetNormals.add(normals.last);
      } else {
        // 取前後段法線平均
        final n = _normalize([
          normals[i - 1][0] + normals[i][0],
          normals[i - 1][1] + normals[i][1],
          normals[i - 1][2] + normals[i][2],
        ]);
        offsetNormals.add(n);
      }
    }

// 3. 計算 offset 點
    final left = <List<double>>[];
    final right = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      final offset = offsetNormals[i].map((v) => v * (thickness / 2)).toList();
      left.add(_add(polyline[i].toECEF(), offset));
      right.add(_sub(polyline[i].toECEF(), offset));
    }

    // 建立 viewport Path
    final viewportPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, screenSize.width, screenSize.height));


    // 畫每一段
    for (int i = 0; i < polyline.length - 1; i++) {

      final quad = [
        left[i],
        right[i],
        right[i + 1],
        left[i + 1],
      ];
      final projectedPolygon = _projectAndClipPolygon(quad, viewMatrix, screenSize);
      if (projectedPolygon.length < 3) continue;
      debugPrint('Projected polygon: $projectedPolygon');
      final path = Path()..addPolygon(projectedPolygon, true);
      canvas.drawPath(path, paint);
    }
  }


  List<List<double>> _lookAt(List<double> eye, List<double> center) {
    final f = _normalize(_sub(center, eye));
    // 動態 up vector：camera 的 ECEF 座標歸一化
    final up = _normalize(eye);
    final s = _normalize(_cross(f, up));
    final u = _cross(s, f);

    final List<List<double>> M = [
      [s[0], s[1], s[2], -_dot(s, eye)],
      [u[0], u[1], u[2], -_dot(u, eye)],
      [-f[0], -f[1], -f[2], _dot(f, eye)],
      [0, 0, 0, 1],
    ];
    return M;
  }

  List<Offset> _projectAndClipPolygon(
      List<List<double>> quad, List<List<double>> viewMatrix, Size screenSize) {
    // 1. 投影四個點
    final projected = quad.map((v) => _project(v, viewMatrix)).toList();
    if (projected.any((p) => p == null || p.dx.isNaN || p.dy.isNaN)) return [];

    // 2. Sutherland–Hodgman 多邊形裁剪
    List<Offset> subject = projected.cast<Offset>().toList();
    final double w = screenSize.width, h = screenSize.height;

    List<Offset> clipEdge(
        List<Offset> input,
        bool Function(Offset) inside,
        Offset Function(Offset, Offset) intersect,
        ) {
      final output = <Offset>[];
      for (int i = 0; i < input.length; i++) {
        final curr = input[i];
        final prev = input[(i - 1 + input.length) % input.length];
        final currIn = inside(curr);
        final prevIn = inside(prev);
        if (currIn) {
          if (!prevIn) {
            output.add(intersect(prev, curr));
          }
          output.add(curr);
        } else if (prevIn) {
          output.add(intersect(prev, curr));
        }
      }
      return output;
    }

    // 右邊界 x <= w
    subject = clipEdge(
      subject,
          (p) => p.dx <= w,
          (a, b) {
        final dx = b.dx - a.dx;
        if (dx == 0) return Offset(w, a.dy); // 垂直線
        var t = (w - a.dx) / dx;
        t = t.clamp(0.0, 1.0); // 限制 t 在 0~1
        return Offset(w, a.dy + t * (b.dy - a.dy));
      },
    );

    // 左邊界 x >= 0
    subject = clipEdge(
      subject,
          (p) => p.dx >= 0,
          (a, b) {
        final dx = b.dx - a.dx;
        if (dx == 0) return Offset(0, a.dy); // 垂直線
        var t = (0 - a.dx) / dx;
        t = t.clamp(0.0, 1.0); // 限制 t 在 0~1
        return Offset(0, a.dy + t * (b.dy - a.dy));
      },
    );

    // 上邊界 y >= 0
    subject = clipEdge(
      subject,
          (p) => p.dy >= 0,
          (a, b) {
        final dy = b.dy - a.dy;
        if (dy == 0) return Offset(a.dx, 0); // 水平線
        var t = (0 - a.dy) / dy;
        t = t.clamp(0.0, 1.0); // 限制 t 在 0~1
        return Offset(a.dx + t * (b.dx - a.dx), 0);
      },
    );

    // 下邊界 y <= h
    subject = clipEdge(
      subject,
          (p) => p.dy <= h,
          (a, b) {
        final dy = b.dy - a.dy;
        if (dy == 0) return Offset(a.dx, h); // 水平線
        var t = (h - a.dy) / dy;
        t = t.clamp(0.0, 1.0); // 限制 t 在 0~1
        return Offset(a.dx + t * (b.dx - a.dx), h);
      },
    );
    return subject.length < 3 ? [] : subject;
  }

  Offset? _project(List<double> point, List<List<double>> viewMatrix) {
    final width = screenSize.width;
    final height = screenSize.height;

    List<double> mul(List<List<double>> m, List<double> v) {
      return List.generate(4, (i) =>
      m[i][0]*v[0] + m[i][1]*v[1] + m[i][2]*v[2] + m[i][3]*v[3]
      );
    }

    final p = [...point, 1.0];
    final v = mul(viewMatrix, p);
    var z = v[2];

    // z 太接近 0 或為正（在鏡頭後方），不投影
    if (z.abs() < 1e-6) {
      // 夾住 z，避免除以 0
      z = z.isNegative ? -1e-6 : 1e-6;
    }
    if (z > 0) z = -1e-6; // 鏡頭後方也夾到前方極小值

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
    if (len == 0) return [0, 0, 0]; // 防止 NaN
    return [v[0]/len, v[1]/len, v[2]/len];
  }
}