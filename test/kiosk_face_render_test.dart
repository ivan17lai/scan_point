import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/app_controller.dart';
import 'package:scan_point/src/scanner/scan_decoder.dart';
import 'package:scan_point/src/ui/kiosk_face.dart';

/// Renders each kiosk state to a PNG so the screen can be reviewed without a
/// scanner, an audio device, or a machine at a control point.
///
/// Set `KIOSK_RENDER_DIR` to collect the images; without it the test still runs
/// and asserts the states build and lay out, it just writes nothing.
void main() {
  final outputDir = Platform.environment['KIOSK_RENDER_DIR'];

  final frozen = DateTime(2026, 8, 3, 10, 24, 32);

  // flutter_test ships a font that draws every glyph as a box, which is fine
  // for layout assertions and useless for reviewing a screen. When a real font
  // is available, load it so the captured PNGs show actual text.
  setUpAll(() async {
    const candidates = [
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      'C:/Windows/Fonts/msjh.ttc',
    ];
    final path = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '',
    );
    if (path.isEmpty) return;
    final bytes = File(path).readAsBytesSync().buffer.asByteData();
    for (final family in ['renderFont', 'monospace']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });

  final cases = <String, KioskFace>{
    '1-idle': KioskFace(
      state: KioskState.idle,
      stationId: 'CP3',
      stationName: '水源地',
      recordedCount: 128,
      clockOverride: frozen,
    ),
    '2-scanning': KioskFace(
      state: KioskState.scanning,
      stationId: 'CP3',
      stationName: '水源地',
      recordedCount: 128,
      clockOverride: frozen,
    ),
    '3-success': KioskFace(
      state: KioskState.success,
      stationId: 'CP3',
      stationName: '水源地',
      recordedCount: 129,
      cardId: 'A7F3C210',
      recordedAt: frozen,
      clockOverride: frozen,
    ),
    '4-duplicate': KioskFace(
      state: KioskState.duplicate,
      stationId: 'CP3',
      stationName: '水源地',
      recordedCount: 129,
      cardId: 'A7F3C210',
      firstSeenAt: frozen,
      clockOverride: frozen,
    ),
    '5-error': KioskFace(
      state: KioskState.error,
      stationId: 'CP3',
      stationName: '水源地',
      recordedCount: 129,
      fault: ScanFault.timeout,
      clockOverride: frozen,
    ),
  };

  for (final entry in cases.entries) {
    testWidgets('renders ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'renderFont'),
          home: RepaintBoundary(key: boundaryKey, child: entry.value),
        ),
      );
      // Land part-way through the morph cycle so the animated states are shown
      // mid-movement rather than at their rest pose.
      await tester.pump(const Duration(milliseconds: 380));

      expect(find.byType(KioskFace), findsOneWidget);

      if (outputDir == null) return;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(outputDir).createSync(recursive: true);
      File(
        '$outputDir/${entry.key}.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
}
