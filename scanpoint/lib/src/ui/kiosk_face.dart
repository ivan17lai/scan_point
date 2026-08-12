import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../scanner/scan_decoder.dart';
import 'm3e/expressive_motion.dart';
import 'm3e/expressive_shape.dart';

/// Fixed per-state palette.
///
/// Hand-picked rather than generated. Hue is the message on this screen — a
/// runner arrives out of breath, glances for well under a second, often from a
/// couple of metres away, and reads the colour before any glyph and long before
/// any text. Green has to mean recorded and red has to mean try again, every
/// time, so nothing gets to reassign these.
///
/// Each background is dark enough for white text at daylight-readable contrast;
/// each container is a light tint of the same hue for the shape at the centre.
class StatePalette {
  const StatePalette({
    required this.background,
    required this.onBackground,
    required this.container,
    required this.onContainer,
  });

  final Color background;
  final Color onBackground;
  final Color container;
  final Color onContainer;
}

const Map<KioskState, StatePalette> _palettes = <KioskState, StatePalette>{
  KioskState.idle: StatePalette(
    background: Color(0xFF0E4BA8),
    onBackground: Color(0xFFFFFFFF),
    container: Color(0xFFA9C9FF),
    onContainer: Color(0xFF062B63),
  ),
  KioskState.scanning: StatePalette(
    background: Color(0xFF9A5200),
    onBackground: Color(0xFFFFFFFF),
    container: Color(0xFFFFD9A0),
    onContainer: Color(0xFF4A2400),
  ),
  KioskState.success: StatePalette(
    background: Color(0xFF16713A),
    onBackground: Color(0xFFFFFFFF),
    container: Color(0xFFADE8BF),
    onContainer: Color(0xFF063D1B),
  ),
  KioskState.duplicate: StatePalette(
    background: Color(0xFF4B3BAE),
    onBackground: Color(0xFFFFFFFF),
    container: Color(0xFFCFC6FF),
    onContainer: Color(0xFF241466),
  ),
  KioskState.error: StatePalette(
    background: Color(0xFFA81E1E),
    onBackground: Color(0xFFFFFFFF),
    container: Color(0xFFFFC7C2),
    onContainer: Color(0xFF5A0A08),
  ),
};

/// Shape per state, in the M3E sense: side count and corner softness carry
/// meaning, so the states differ in silhouette and not only in hue. This is the
/// part of Material 3 Expressive the design actually leans on.
const Map<KioskState, ({double sides, double rounding})> _shapes = {
  KioskState.idle: (sides: 7, rounding: 0.52),
  KioskState.scanning: (sides: 5, rounding: 0.38),
  KioskState.success: (sides: 7, rounding: 0.62),
  // Six clear lobes. A nine-sided shape was tried first and rendered almost
  // circular, which made it indistinguishable in silhouette from the success
  // state — defeating the point of letting shape carry meaning alongside hue.
  KioskState.duplicate: (sides: 6, rounding: 0.40),
  KioskState.error: (sides: 4, rounding: 0.30),
};

/// The runner-facing screen, as pure presentation.
///
/// It takes values rather than the controller so the five states can be
/// rendered and inspected without a store, an audio device, or a scanner —
/// see `test/kiosk_face_render_test.dart`.
class KioskFace extends StatefulWidget {
  const KioskFace({
    super.key,
    required this.state,
    required this.stationId,
    required this.stationName,
    required this.recordedCount,
    this.cardId,
    this.cardLabel,
    this.recordedAt,
    this.firstSeenAt,
    this.fault,
    this.warning,
    this.clockOverride,
  });

  final KioskState state;
  final String stationId;
  final String stationName;
  final int recordedCount;
  final String? cardId;
  final String? cardLabel;
  final DateTime? recordedAt;
  final DateTime? firstSeenAt;
  final ScanFault? fault;
  final String? warning;

  /// Freezes the clock, for deterministic rendering in tests.
  final DateTime? clockOverride;

  @override
  State<KioskFace> createState() => _KioskFaceState();
}

class _KioskFaceState extends State<KioskFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: ExpressiveDurations.idleCycle,
  )..repeat();

  Timer? _clock;
  DateTime _now = DateTime.now();
  KioskState? _lastState;

  @override
  void initState() {
    super.initState();
    if (widget.clockOverride != null) {
      _now = widget.clockOverride!;
      return;
    }
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _morph.dispose();
    super.dispose();
  }

  /// The idle shape drifts slowly; the scanning shape spins fast. Same
  /// controller, retimed on entry to each state.
  void _retimeMorph(KioskState state) {
    if (_lastState == state) return;
    _lastState = state;
    final period = state == KioskState.scanning
        ? ExpressiveDurations.scanCycle
        : ExpressiveDurations.idleCycle;
    if (_morph.duration != period) {
      _morph
        ..stop()
        ..duration = period
        ..repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[widget.state]!;
    _retimeMorph(widget.state);

    // Without a Material ancestor, Flutter marks every Text with a yellow
    // debug underline. Providing it here rather than at the call site means the
    // screen is correct wherever it is mounted, including in the render test.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Everything scales off the short edge, so the same layout holds on a
          // folded-back convertible and on a large external display.
          final unit = constraints.maxHeight / 100;
          return AnimatedContainer(
            duration: ExpressiveDurations.colourChange,
            curve: SpringCurve.effects,
            color: palette.background,
            padding: EdgeInsets.symmetric(
              horizontal: unit * 4.5,
              vertical: unit * 3.5,
            ),
            child: Column(
              children: [
                _EdgeBar(
                  leading: '${widget.stationId}   ${widget.stationName}',
                  trailing: _clockText(_now),
                  palette: palette,
                  unit: unit,
                ),
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: ExpressiveDurations.stateChange,
                      switchInCurve: SpringCurve.spatial,
                      switchOutCurve: Easing.emphasizedAccelerate,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.82,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey<KioskState>(widget.state),
                        child: _StateContent(
                          face: widget,
                          palette: palette,
                          unit: unit,
                          morph: _morph,
                        ),
                      ),
                    ),
                  ),
                ),
                _EdgeBar(
                  leading: '已記錄 ${widget.recordedCount} 筆',
                  trailing: widget.warning ?? '系統正常',
                  palette: palette,
                  unit: unit,
                  muted: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _clockText(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _StateContent extends StatelessWidget {
  const _StateContent({
    required this.face,
    required this.palette,
    required this.unit,
    required this.morph,
  });

  final KioskFace face;
  final StatePalette palette;
  final double unit;
  final Animation<double> morph;

  @override
  Widget build(BuildContext context) {
    final state = face.state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Glyph(state: state, palette: palette, unit: unit, morph: morph),
        SizedBox(height: unit * 4),
        Text(
          switch (state) {
            KioskState.idle => '請掃描',
            KioskState.scanning => '掃描中',
            KioskState.success => '掃描完成',
            KioskState.duplicate => '已記錄過',
            KioskState.error => '請再刷一次',
          },
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.onBackground,
            fontSize: unit * 13,
            height: 1.02,
            fontWeight: FontWeight.w700,
            letterSpacing: unit * 0.5,
          ),
        ),
        ..._detail(state),
      ],
    );
  }

  List<Widget> _detail(KioskState state) {
    switch (state) {
      case KioskState.idle:
        return [_caption('將卡片靠近感應區')];

      case KioskState.scanning:
        return [_caption('請勿移開卡片')];

      case KioskState.success:
        return [
          _cardChip(
            face.cardLabel ?? face.cardId ?? '',
            custom: face.cardLabel != null,
          ),
          if (face.recordedAt != null)
            _caption(_KioskFaceState._clockText(face.recordedAt!)),
        ];

      case KioskState.duplicate:
        return [
          _cardChip(
            face.cardLabel ?? face.cardId ?? '',
            custom: face.cardLabel != null,
          ),
          _caption(
            face.firstSeenAt == null
                ? '這張卡在本站已經有紀錄'
                : '首次刷卡 ${_KioskFaceState._clockText(face.firstSeenAt!)} · 可以前進',
          ),
        ];

      case KioskState.error:
        final fault = face.fault;
        return [
          if (fault != null) _caption(fault.message),
          if (fault != null) _footnote(fault.code),
        ];
    }
  }

  /// With no name list loaded, the card number is the only thing a runner can
  /// verify for themselves, so it gets its own container and the largest type
  /// on the screen — grouped in fours the way it is printed on the card.
  Widget _cardChip(String value, {required bool custom}) => Padding(
    padding: EdgeInsets.only(top: unit * 3),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: unit * 5, vertical: unit * 2.4),
      decoration: ShapeDecoration(
        color: palette.container,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(unit * 6),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          custom ? value : _group(value),
          style: TextStyle(
            color: palette.onContainer,
            fontSize: unit * 14,
            height: 1,
            fontWeight: FontWeight.w700,
            fontFamily: custom ? null : 'monospace',
            letterSpacing: custom ? 0 : unit * 0.4,
          ),
        ),
      ),
    ),
  );

  Widget _caption(String text) => Padding(
    padding: EdgeInsets.only(top: unit * 2.4),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: palette.onBackground.withValues(alpha: 0.86),
        fontSize: unit * 4.4,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _footnote(String text) => Padding(
    padding: EdgeInsets.only(top: unit * 1.4),
    child: Text(
      text,
      style: TextStyle(
        color: palette.onBackground.withValues(alpha: 0.6),
        fontSize: unit * 2.4,
        fontFamily: 'monospace',
      ),
    ),
  );

  static String _group(String value) {
    if (value.length <= 4) return value;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(value[i]);
    }
    return buffer.toString();
  }
}

/// The morphing shape at the centre of every state.
///
/// Idle drifts and breathes — an unattended station that renders a completely
/// static screen is indistinguishable from a crashed one, and a runner who
/// thinks the box is dead will start pressing things or skip the control.
/// Scanning spins and changes its side count, which is the M3 Expressive
/// loading indicator in spirit: shape carries the progress, not a spinner ring.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.state,
    required this.palette,
    required this.unit,
    required this.morph,
  });

  final KioskState state;
  final StatePalette palette;
  final double unit;
  final Animation<double> morph;

  @override
  Widget build(BuildContext context) {
    final base = _shapes[state]!;

    return AnimatedBuilder(
      animation: morph,
      builder: (context, _) {
        final t = morph.value;
        // 0..1..0, so the breath and the side-count morph both reverse
        // smoothly instead of snapping at the loop boundary.
        final swing = 1 - (t * 2 - 1).abs();

        final (sides, rounding, rotation, scale) = switch (state) {
          KioskState.scanning => (
            base.sides + swing * 2.6,
            base.rounding + swing * 0.16,
            t,
            1.0,
          ),
          KioskState.idle => (
            base.sides,
            base.rounding + swing * 0.10,
            t * 0.35,
            0.94 + swing * 0.08,
          ),
          _ => (base.sides, base.rounding, 0.02, 1.0),
        };

        return Transform.scale(
          scale: scale,
          child: ExpressiveShape(
            size: unit * 26,
            color: palette.container,
            sides: sides,
            rounding: rounding,
            rotation: rotation,
            child: Icon(
              switch (state) {
                KioskState.idle => Icons.nfc_rounded,
                KioskState.scanning => Icons.contactless_rounded,
                KioskState.success => Icons.check_rounded,
                KioskState.duplicate => Icons.history_rounded,
                KioskState.error => Icons.priority_high_rounded,
              },
              size: unit * 12,
              color: palette.onContainer,
            ),
          ),
        );
      },
    );
  }
}

class _EdgeBar extends StatelessWidget {
  const _EdgeBar({
    required this.leading,
    required this.trailing,
    required this.palette,
    required this.unit,
    this.muted = false,
  });

  final String leading;
  final String trailing;
  final StatePalette palette;
  final double unit;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: palette.onBackground.withValues(alpha: muted ? 0.6 : 0.82),
      fontSize: unit * (muted ? 2.7 : 3.4),
      fontWeight: FontWeight.w500,
      letterSpacing: unit * 0.08,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(leading, overflow: TextOverflow.ellipsis, style: style),
        ),
        SizedBox(width: unit * 2),
        Text(
          trailing,
          style: style.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
