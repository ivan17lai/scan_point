import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rounded polygon that can morph continuously between shapes.
///
/// Shape is the signature of Material 3 Expressive — the loading indicator and
/// the hero containers are rounded polygons that change their number of sides
/// and their corner softness as state changes, rather than staying circles.
/// Flutter has no shape-morph primitive yet, so the outline is generated from a
/// radial function:
///
///   r(θ) = lerp( cos(π/n) / cos(θ mod 2π/n − π/n),  1,  rounding )
///
/// The left term is the exact outline of a regular n-gon, the right term is a
/// circle. Because the formula is continuous in `n`, a *fractional* side count
/// is meaningful — which is what makes a 4↔7 morph animatable rather than a
/// crossfade between two static shapes.
class ExpressiveShape extends StatelessWidget {
  const ExpressiveShape({
    super.key,
    required this.size,
    required this.color,
    this.sides = 7,
    this.rounding = 0.5,
    this.rotation = 0,
    this.child,
  });

  final double size;
  final Color color;

  /// Number of sides. Fractional values are valid and interpolate.
  final double sides;

  /// 0 = hard polygon, 1 = circle.
  final double rounding;

  /// Turns, not radians: 1.0 is a full rotation.
  final double rotation;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ExpressiveShapePainter(
          sides: sides,
          rounding: rounding,
          rotation: rotation,
          color: color,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _ExpressiveShapePainter extends CustomPainter {
  const _ExpressiveShapePainter({
    required this.sides,
    required this.rounding,
    required this.rotation,
    required this.color,
  });

  final double sides;
  final double rounding;
  final double rotation;
  final Color color;

  static const int _samples = 240;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      buildPath(Offset.zero & size, sides, rounding, rotation),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  static Path buildPath(
    Rect rect,
    double sides,
    double rounding,
    double rotation,
  ) {
    final n = sides.clamp(3.0, 16.0);
    final k = rounding.clamp(0.0, 1.0);
    final centre = rect.center;
    final radius = rect.shortestSide / 2;
    final spin = rotation * 2 * math.pi;

    // A fractional side count cannot be fed to the polygon formula directly:
    // 2π/n would not divide 2π evenly and the outline would fail to close,
    // leaving a visible notch at the seam. Blending the two neighbouring
    // *integer* polygons keeps both profiles periodic, so the blend closes too.
    final lower = n.floor();
    final upper = n.ceil();
    final blend = n - lower;

    final path = Path();
    for (var i = 0; i <= _samples; i++) {
      final theta = i / _samples * 2 * math.pi;
      final polygon = lower == upper
          ? _polygonRadius(theta, lower)
          : _polygonRadius(theta, lower) * (1 - blend) +
                _polygonRadius(theta, upper) * blend;
      final r = (polygon * (1 - k) + k) * radius;
      final a = theta + spin;
      final point = Offset(
        centre.dx + r * math.cos(a),
        centre.dy + r * math.sin(a),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  /// Distance from centre to the outline of a unit regular [n]-gon at [theta].
  static double _polygonRadius(double theta, int n) {
    final segment = 2 * math.pi / n;
    // Angle within the current edge, measured from its midpoint.
    final phi = (theta % segment) - segment / 2;
    return math.cos(math.pi / n) / math.cos(phi);
  }

  @override
  bool shouldRepaint(_ExpressiveShapePainter old) =>
      old.sides != sides ||
      old.rounding != rounding ||
      old.rotation != rotation ||
      old.color != color;
}

/// [ExpressiveShape] as a [ShapeBorder], for clipping containers to the same
/// outline the glyphs use.
class ExpressiveShapeBorder extends ShapeBorder {
  const ExpressiveShapeBorder({
    this.sides = 7,
    this.rounding = 0.5,
    this.rotation = 0,
  });

  final double sides;
  final double rounding;
  final double rotation;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _ExpressiveShapePainter.buildPath(rect, sides, rounding, rotation);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ExpressiveShapeBorder(
    sides: sides,
    rounding: rounding,
    rotation: rotation * t,
  );
}
