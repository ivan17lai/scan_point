import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Material 3 Expressive motion.
///
/// The thing that separates M3 Expressive from plain M3 is that transitions are
/// driven by springs rather than by cubic curves — motion overshoots slightly
/// and settles, instead of easing to a dead stop. Flutter ships the M3
/// `Easing` cubics but no spring curve, so this wraps [SpringSimulation] as a
/// [Curve] that any Flutter animation can use.
class SpringCurve extends Curve {
  SpringCurve({
    double stiffness = 380,
    double damping = 26,
    double mass = 1,
    this.seconds = 0.55,
  }) : _simulation = SpringSimulation(
         SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
         0,
         1,
         0,
       );

  final SpringSimulation _simulation;

  /// Wall-clock span the spring is sampled over, mapped onto `t` in 0..1.
  final double seconds;

  /// Enters with a visible overshoot. For things arriving on screen.
  static final SpringCurve spatial = SpringCurve();

  /// Settles without overshooting. For colour and opacity, where a bounce reads
  /// as a flicker rather than as energy.
  static final SpringCurve effects = SpringCurve(stiffness: 420, damping: 42);

  @override
  double transformInternal(double t) {
    if (t >= 1) return 1;
    return _simulation.x(t * seconds);
  }
}

/// Duration tokens, named after the M3 scale.
abstract final class ExpressiveDurations {
  /// Shape morph and content swap between kiosk states.
  static const Duration stateChange = Durations.medium4;

  /// Full-bleed colour crossfade — slower than the content, so the colour leads
  /// and the text lands into it.
  static const Duration colourChange = Durations.long2;

  /// One turn of the idle shape.
  static const Duration idleCycle = Duration(milliseconds: 5200);

  /// One turn of the scanning shape.
  static const Duration scanCycle = Duration(milliseconds: 1100);
}

/// Colour is deliberately *not* generated.
///
/// `ColorScheme.fromSeed` with `DynamicSchemeVariant.expressive` was tried and
/// rejected: that variant rotates hue hard for brand expression, so a blue seed
/// came out green and a green seed came out red-brown. On a screen where hue
/// *is* the message — green means recorded, red means try again — a palette
/// generator that reassigns hues is a hazard, not a feature. The state palette
/// is fixed by hand in `kiosk_face.dart`; what this file provides is the other
/// half of Material 3 Expressive: spring motion, and (in `expressive_shape.dart`)
/// shape.
