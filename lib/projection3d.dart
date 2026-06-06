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
    return [x, y, z];
  }
}

class ThreeDProjectCanvas {
  final GeoPoint camera;
  final GeoPoint lookAt;
  final GeoPoint currentPosition;
  final List<GeoPoint> polyline;
  final List<List<GeoPoint>> nearbyRoads; // 附近道路
  final double thickness;
  final Size screenSize;

  ThreeDProjectCanvas({
    required this.camera,
    required this.lookAt,
    required this.currentPosition,
    required this.polyline,
    this.nearbyRoads = const [],
    this.thickness = 20,
    required this.screenSize,
  });

  // ── Public draw methods ────────────────────────────────────────────────

  void drawMarker(Canvas canvas, Paint paint) {
    final pos = currentPosition.toECEF();
    final look = lookAt.toECEF();
    final viewMatrix = _lookAt(camera.toECEF(), lookAt.toECEF());
    final dir = _normalize(_sub(look, pos));
    final up = _normalize(pos);
    final right = _normalize(_cross(dir, up));
    const double size = 12.0;
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

    final tangents = <List<double>>[];
    final normals = <List<double>>[];
    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i].toECEF();
      final b = polyline[i + 1].toECEF();
      final tangent = _normalize(_sub(b, a));
      final up = _normalize(a);
      final normal = _normalize(_cross(tangent, up));
      tangents.add(tangent);
      normals.add(normal);
    }

    final offsetNormals = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      if (i == 0) {
        offsetNormals.add(normals[0]);
      } else if (i == polyline.length - 1) {
        offsetNormals.add(normals.last);
      } else {
        final n = _normalize([
          normals[i - 1][0] + normals[i][0],
          normals[i - 1][1] + normals[i][1],
          normals[i - 1][2] + normals[i][2],
        ]);
        offsetNormals.add(n);
      }
    }

    final left = <List<double>>[];
    final right = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      final offset = offsetNormals[i].map((v) => v * (thickness / 2)).toList();
      left.add(_add(polyline[i].toECEF(), offset));
      right.add(_sub(polyline[i].toECEF(), offset));
    }

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

  /// 繪製附近道路（灰色細線）。
  ///
  /// 安全處理：
  /// 1. 近平面裁切：view space z >= 0 的點在相機後方，直接投影會產生極端座標，需先截斷。
  /// 2. Cohen-Sutherland 螢幕邊界裁切：防止超出畫面的線段送入 Canvas 導致畫面錯誤。
  void drawRoads(Canvas canvas, Paint paint) {
    if (nearbyRoads.isEmpty) return;
    final viewMatrix = _lookAt(camera.toECEF(), lookAt.toECEF());

    for (final road in nearbyRoads) {
      if (road.length < 2) continue;
      for (int i = 0; i < road.length - 1; i++) {
        final aV = _toViewSpace(road[i].toECEF(), viewMatrix);
        final bV = _toViewSpace(road[i + 1].toECEF(), viewMatrix);

        // 近平面裁切
        final clipped = _clipNearPlane(aV, bV);
        if (clipped == null) continue;

        // 投影
        final a2d = _projectViewSpace(clipped.$1);
        final b2d = _projectViewSpace(clipped.$2);
        if (a2d == null || b2d == null) continue;

        // 螢幕邊界裁切
        final sc = _clipLineToScreen(a2d, b2d);
        if (sc == null) continue;

        canvas.drawLine(sc.$1, sc.$2, paint);
      }
    }
  }

  // ── View space helpers ─────────────────────────────────────────────────

  List<double> _toViewSpace(List<double> point, List<List<double>> m) {
    final p = [...point, 1.0];
    return List.generate(4, (i) =>
        m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] * p[3]);
  }

  Offset? _projectViewSpace(List<double> v) {
    final width = screenSize.width;
    final height = screenSize.height;
    final z = v[2];
    if (z >= 0) return null; // 相機後方
    final xNDC = v[0] / -z;
    final yNDC = v[1] / -z;
    return Offset(
      width / 2 + xNDC * width / 2,
      height / 2 - yNDC * height / 2,
    );
  }

  /// 近平面裁切。nearZ 為近平面距離（正值），裁切閾值為 z = -nearZ。
  /// 若整條線段都在相機後方（z >= 0），回傳 null。
  (List<double>, List<double>)? _clipNearPlane(
      List<double> a, List<double> b, {double nearZ = 1.0}) {
    final az = a[2];
    final bz = b[2];

    if (az >= 0 && bz >= 0) return null; // 兩點都在後方

    final threshold = -nearZ;

    List<double> lerp(List<double> p1, List<double> p2, double targetZ) {
      final t = (targetZ - p1[2]) / (p2[2] - p1[2]);
      return [
        p1[0] + t * (p2[0] - p1[0]),
        p1[1] + t * (p2[1] - p1[1]),
        targetZ,
        1.0,
      ];
    }

    final clippedA = az >= threshold ? lerp(a, b, threshold) : a;
    final clippedB = bz >= threshold ? lerp(b, a, threshold) : b;
    return (clippedA, clippedB);
  }

  /// Cohen-Sutherland 螢幕邊界裁切。
  /// 回傳裁切後的端點對；若線段完全在螢幕外，回傳 null。
  (Offset, Offset)? _clipLineToScreen(Offset a, Offset b) {
    const int inside = 0, left = 1, right = 2, bottom = 4, top = 8;
    final xmin = 0.0, xmax = screenSize.width;
    final ymin = 0.0, ymax = screenSize.height;

    int code(double x, double y) {
      int c = inside;
      if (x < xmin) c |= left;
      else if (x > xmax) c |= right;
      if (y < ymin) c |= top;
      else if (y > ymax) c |= bottom;
      return c;
    }

    double ax = a.dx, ay = a.dy;
    double bx = b.dx, by = b.dy;
    int ca = code(ax, ay), cb = code(bx, by);

    while (true) {
      if ((ca | cb) == 0) return (Offset(ax, ay), Offset(bx, by));
      if ((ca & cb) != 0) return null;

      final out = ca != inside ? ca : cb;
      double x = 0, y = 0;
      final dx = bx - ax, dy = by - ay;

      if (out & bottom != 0) {
        x = ax + dx * (ymax - ay) / dy; y = ymax;
      } else if (out & top != 0) {
        x = ax + dx * (ymin - ay) / dy; y = ymin;
      } else if (out & right != 0) {
        y = ay + dy * (xmax - ax) / dx; x = xmax;
      } else {
        y = ay + dy * (xmin - ax) / dx; x = xmin;
      }

      if (out == ca) { ax = x; ay = y; ca = code(ax, ay); }
      else           { bx = x; by = y; cb = code(bx, by); }
    }
  }

  // ── Existing private helpers ───────────────────────────────────────────

  List<List<double>> _lookAt(List<double> eye, List<double> center) {
    final f = _normalize(_sub(center, eye));
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
    final projected = quad.map((v) => _project(v, viewMatrix)).toList();
    if (projected.any((p) => p == null || p.dx.isNaN || p.dy.isNaN)) return [];

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
          if (!prevIn) output.add(intersect(prev, curr));
          output.add(curr);
        } else if (prevIn) {
          output.add(intersect(prev, curr));
        }
      }
      return output;
    }

    subject = clipEdge(subject, (p) => p.dx <= w, (a, b) {
      final dx = b.dx - a.dx;
      if (dx == 0) return Offset(w, a.dy);
      var t = (w - a.dx) / dx; t = t.clamp(0.0, 1.0);
      return Offset(w, a.dy + t * (b.dy - a.dy));
    });
    subject = clipEdge(subject, (p) => p.dx >= 0, (a, b) {
      final dx = b.dx - a.dx;
      if (dx == 0) return Offset(0, a.dy);
      var t = (0 - a.dx) / dx; t = t.clamp(0.0, 1.0);
      return Offset(0, a.dy + t * (b.dy - a.dy));
    });
    subject = clipEdge(subject, (p) => p.dy >= 0, (a, b) {
      final dy = b.dy - a.dy;
      if (dy == 0) return Offset(a.dx, 0);
      var t = (0 - a.dy) / dy; t = t.clamp(0.0, 1.0);
      return Offset(a.dx + t * (b.dx - a.dx), 0);
    });
    subject = clipEdge(subject, (p) => p.dy <= h, (a, b) {
      final dy = b.dy - a.dy;
      if (dy == 0) return Offset(a.dx, h);
      var t = (h - a.dy) / dy; t = t.clamp(0.0, 1.0);
      return Offset(a.dx + t * (b.dx - a.dx), h);
    });
    return subject.length < 3 ? [] : subject;
  }

  Offset? _project(List<double> point, List<List<double>> viewMatrix) {
    final width = screenSize.width;
    final height = screenSize.height;

    List<double> mul(List<List<double>> m, List<double> v) {
      return List.generate(4, (i) =>
      m[i][0]*v[0] + m[i][1]*v[1] + m[i][2]*v[2] + m[i][3]*v[3]);
    }

    final p = [...point, 1.0];
    final v = mul(viewMatrix, p);
    var z = v[2];

    if (z.abs() < 1e-6) z = z.isNegative ? -1e-6 : 1e-6;
    if (z > 0) z = -1e-6;

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
    if (len == 0) return [0, 0, 0];
    return [v[0]/len, v[1]/len, v[2]/len];
  }

  // ── SVG output ─────────────────────────────────────────────────────────

  /// 產生完整 SVG 字串，內容與 Canvas 版本一致（黑底、灰道路、白路線、紅標記）。
  String toSvg() {
    final w = screenSize.width;
    final h = screenSize.height;
    final buf = StringBuffer();
    buf.write(
      '<svg xmlns="http://www.w3.org/2000/svg"'
      ' viewBox="0 0 $w $h"'
      ' width="$w" height="$h">',
    );
    // 黑底
    buf.write('<rect width="$w" height="$h" fill="black"/>');
    // 裁切區（防止超出邊界）
    buf.write('<clipPath id="vp"><rect width="$w" height="$h"/></clipPath>');
    buf.write('<g clip-path="url(#vp)">');

    _svgRoads(buf);
    _svgDraw(buf);
    _svgMarker(buf);

    buf.write('</g></svg>');
    return buf.toString();
  }

  /// SVG 版 drawRoads — 附近道路灰線，含近平面裁切與螢幕邊界裁切
  void _svgRoads(StringBuffer buf) {
    if (nearbyRoads.isEmpty) return;
    final vm = _lookAt(camera.toECEF(), lookAt.toECEF());
    buf.write('<g stroke="#666" stroke-width="3" stroke-linecap="round">');
    for (final road in nearbyRoads) {
      for (int i = 0; i < road.length - 1; i++) {
        final aV = _toViewSpace(road[i].toECEF(), vm);
        final bV = _toViewSpace(road[i + 1].toECEF(), vm);
        final clipped = _clipNearPlane(aV, bV);
        if (clipped == null) continue;
        final a2d = _projectViewSpace(clipped.$1);
        final b2d = _projectViewSpace(clipped.$2);
        if (a2d == null || b2d == null) continue;
        final sc = _clipLineToScreen(a2d, b2d);
        if (sc == null) continue;
        final f = _fmt;
        buf.write(
          '<line x1="${f(sc.$1.dx)}" y1="${f(sc.$1.dy)}"'
          ' x2="${f(sc.$2.dx)}" y2="${f(sc.$2.dy)}"/>',
        );
      }
    }
    buf.write('</g>');
  }

  /// SVG 版 draw — 導航路線白色填充多邊形
  void _svgDraw(StringBuffer buf) {
    if (polyline.length < 2) return;
    final vm = _lookAt(camera.toECEF(), lookAt.toECEF());

    // 計算法線（與 Canvas 版邏輯相同）
    final normals = <List<double>>[];
    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i].toECEF();
      final b = polyline[i + 1].toECEF();
      normals.add(_normalize(_cross(_normalize(_sub(b, a)), _normalize(a))));
    }
    final offsetNormals = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      if (i == 0) {
        offsetNormals.add(normals[0]);
      } else if (i == polyline.length - 1) {
        offsetNormals.add(normals.last);
      } else {
        offsetNormals.add(_normalize([
          normals[i-1][0] + normals[i][0],
          normals[i-1][1] + normals[i][1],
          normals[i-1][2] + normals[i][2],
        ]));
      }
    }

    final left = <List<double>>[];
    final right = <List<double>>[];
    for (int i = 0; i < polyline.length; i++) {
      final off = offsetNormals[i].map((v) => v * (thickness / 2)).toList();
      left.add(_add(polyline[i].toECEF(), off));
      right.add(_sub(polyline[i].toECEF(), off));
    }

    buf.write('<g fill="white">');
    for (int i = 0; i < polyline.length - 1; i++) {
      final pts = _projectAndClipPolygon(
        [left[i], right[i], right[i+1], left[i+1]], vm, screenSize);
      if (pts.length < 3) continue;
      final f = _fmt;
      final pointsStr = pts.map((p) => '${f(p.dx)},${f(p.dy)}').join(' ');
      buf.write('<polygon points="$pointsStr"/>');
    }
    buf.write('</g>');
  }

  /// SVG 版 drawMarker — 紅色三角形
  void _svgMarker(StringBuffer buf) {
    final pos = currentPosition.toECEF();
    final look = lookAt.toECEF();
    final vm = _lookAt(camera.toECEF(), lookAt.toECEF());
    final dir = _normalize(_sub(look, pos));
    final up = _normalize(pos);
    final right = _normalize(_cross(dir, up));
    const double sz = 12.0;

    final tip3d = [pos[0]+dir[0]*sz,   pos[1]+dir[1]*sz,   pos[2]+dir[2]*sz];
    final l3d   = [pos[0]-right[0]*sz*0.6-dir[0]*sz*0.6,
                   pos[1]-right[1]*sz*0.6-dir[1]*sz*0.6,
                   pos[2]-right[2]*sz*0.6-dir[2]*sz*0.6];
    final r3d   = [pos[0]+right[0]*sz*0.6-dir[0]*sz*0.6,
                   pos[1]+right[1]*sz*0.6-dir[1]*sz*0.6,
                   pos[2]+right[2]*sz*0.6-dir[2]*sz*0.6];

    final tip = _project(tip3d, vm);
    final lp  = _project(l3d, vm);
    final rp  = _project(r3d, vm);
    if (tip == null || lp == null || rp == null) return;

    final f = _fmt;
    buf.write(
      '<polygon fill="red"'
      ' points="${f(tip.dx)},${f(tip.dy)}'
      ' ${f(lp.dx)},${f(lp.dy)}'
      ' ${f(rp.dx)},${f(rp.dy)}"/>',
    );
  }

  /// 數字格式化：最多 2 位小數，避免 SVG 過於冗長
  String Function(double) get _fmt => (double v) =>
      v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}
