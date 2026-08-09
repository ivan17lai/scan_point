import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_point/src/scanner/scan_decoder.dart';

/// Drives the decoder the way a keyboard-wedge reader drives the app: physical
/// key events only, never a text field, so these tests also stand in for "does
/// it still work with 注音 switched on" — an IME can only interfere where a text
/// input client exists, and there isn't one anywhere in this path.
void main() {
  late List<ScanFrame> frames;
  late List<ScanFault> faults;
  late int starts;
  late ScanDecoder decoder;

  setUp(() {
    frames = [];
    faults = [];
    starts = 0;
    decoder = ScanDecoder(
      onFrameStart: () => starts++,
      onFrame: frames.add,
      onFault: faults.add,
    );
  });

  tearDown(() => decoder.dispose());

  /// Sends one physical key, optionally with shift held, as the reader would.
  Future<void> press(PhysicalKeyboardKey key, {bool shift = false}) async {
    if (shift) {
      await simulateKeyDownEvent(
        LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
      );
    }
    decoder.handleKeyEvent(
      KeyDownEvent(
        physicalKey: key,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
      ),
    );
    if (shift) {
      await simulateKeyUpEvent(
        LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
      );
    }
  }

  /// A reader emits `;<payload>?` — semicolon unshifted to open, shift+slash
  /// to close.
  Future<void> sendFrame(String payload, {bool terminate = true}) async {
    await press(PhysicalKeyboardKey.semicolon); // ';'
    for (final char in payload.split('')) {
      final key = _keyFor(char);
      await press(key.$1, shift: key.$2);
    }
    if (terminate) {
      await press(PhysicalKeyboardKey.slash, shift: true); // '?'
    }
  }

  testWidgets('decodes a complete frame', (tester) async {
    await sendFrame('A7F3C210');

    expect(starts, 1);
    expect(faults, isEmpty);
    expect(frames.single.payload, 'A7F3C210');
    expect(frames.single.terminator, FrameTerminator.questionMark);
  });

  testWidgets('uppercases a payload the reader sent without shift', (
    tester,
  ) async {
    await sendFrame('a7f3c210');
    expect(frames.single.payload, 'A7F3C210');
  });

  testWidgets('ignores keystrokes outside a frame', (tester) async {
    await press(PhysicalKeyboardKey.keyH);
    await press(PhysicalKeyboardKey.keyI);

    expect(starts, 0);
    expect(frames, isEmpty);
    expect(faults, isEmpty);
  });

  testWidgets('accepts Enter as a terminator', (tester) async {
    await sendFrame('BEEF01', terminate: false);
    await press(PhysicalKeyboardKey.enter);

    expect(frames.single.payload, 'BEEF01');
    expect(frames.single.terminator, FrameTerminator.enterKey);
  });

  testWidgets('faults when the terminator never arrives', (tester) async {
    await sendFrame('BEEF01', terminate: false);
    await tester.pump(const Duration(seconds: 2));

    expect(frames, isEmpty);
    expect(faults.single, ScanFault.timeout);
  });

  testWidgets('faults when the card is pulled away mid-frame', (tester) async {
    decoder = ScanDecoder(
      onFrameStart: () => starts++,
      onFrame: frames.add,
      onFault: faults.add,
      timing: const ScanTiming(maxKeyGap: Duration(milliseconds: 20)),
    );
    await sendFrame('AB', terminate: false);
    // The gap check reads the wall clock, so this has to be a real pause rather
    // than a pumped one.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await press(PhysicalKeyboardKey.keyC);

    expect(frames, isEmpty);
    expect(faults.single, ScanFault.interrupted);
  });

  testWidgets('a restarted frame wins over the abandoned one', (tester) async {
    await press(PhysicalKeyboardKey.semicolon);
    await press(PhysicalKeyboardKey.keyZ);
    await sendFrame('CAFE');

    expect(frames.single.payload, 'CAFE');
    expect(faults, isEmpty);
  });

  testWidgets('rejects an empty payload', (tester) async {
    await sendFrame('');

    expect(frames, isEmpty);
    expect(faults.single, ScanFault.malformed);
  });

  testWidgets('rejects a payload longer than the limit', (tester) async {
    await sendFrame('A' * 70, terminate: false);

    expect(frames, isEmpty);
    expect(faults.single, ScanFault.malformed);
  });
}

/// Physical key and shift state that produce [char] on a US layout.
(PhysicalKeyboardKey, bool) _keyFor(String char) {
  const letters = {
    'a': PhysicalKeyboardKey.keyA,
    'b': PhysicalKeyboardKey.keyB,
    'c': PhysicalKeyboardKey.keyC,
    'd': PhysicalKeyboardKey.keyD,
    'e': PhysicalKeyboardKey.keyE,
    'f': PhysicalKeyboardKey.keyF,
    'z': PhysicalKeyboardKey.keyZ,
  };
  const digits = {
    '0': PhysicalKeyboardKey.digit0,
    '1': PhysicalKeyboardKey.digit1,
    '2': PhysicalKeyboardKey.digit2,
    '3': PhysicalKeyboardKey.digit3,
    '7': PhysicalKeyboardKey.digit7,
  };
  final lower = char.toLowerCase();
  if (letters.containsKey(lower)) {
    return (letters[lower]!, char != lower);
  }
  if (digits.containsKey(char)) {
    return (digits[char]!, false);
  }
  throw ArgumentError('test helper has no mapping for "$char"');
}
