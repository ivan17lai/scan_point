import 'dart:async';

import 'package:flutter/services.dart';

import 'keyboard_layout.dart';

/// Why a frame was thrown away. The code is what the error screen shows in the
/// corner so a failure can be traced after the event.
enum ScanFault {
  /// Gap between two keystrokes was too long — a human typing, or the reader
  /// lost contact halfway through the card.
  interrupted('E-01', '卡片未讀取完整'),

  /// Start marker arrived but the terminator never did.
  timeout('E-02', '卡片未讀取完整'),

  /// Payload was empty, too long, or contained characters a card id never has.
  malformed('E-03', '卡號格式不正確'),

  /// The store failed to persist the scan.
  storageFailure('E-10', '無法寫入紀錄');

  const ScanFault(this.code, this.message);
  final String code;
  final String message;
}

/// How the frame ended, kept in the log because a reader that stops sending the
/// `;` terminator is worth noticing after the event.
enum FrameTerminator { semicolon, enterKey }

class ScanFrame {
  const ScanFrame(this.payload, this.terminator, this.raw);
  final String payload;
  final FrameTerminator terminator;
  final String raw;
}

class ScanTiming {
  const ScanTiming({
    this.maxKeyGap = const Duration(milliseconds: 300),
    this.frameTimeout = const Duration(milliseconds: 1500),
  });

  /// Longest pause tolerated between two characters of one frame. Wedge readers
  /// sit around 5–30ms; a person typing cannot beat this.
  final Duration maxKeyGap;

  /// Hard ceiling from `?` to `;`.
  final Duration frameTimeout;
}

/// Reassembles `?<payload>;` frames out of raw physical key events.
///
/// Deliberately never touches a text field: with no text input client focused,
/// the IME is never engaged, so a running 注音 input method cannot swallow,
/// buffer, or transform the reader's keystrokes.
class ScanDecoder {
  ScanDecoder({
    required this.onFrameStart,
    required this.onFrame,
    required this.onFault,
    this.timing = const ScanTiming(),
    this.maxPayloadLength = 64,
  });

  final void Function() onFrameStart;
  final void Function(ScanFrame frame) onFrame;
  final void Function(ScanFault fault) onFault;
  final ScanTiming timing;
  final int maxPayloadLength;

  static final RegExp _validPayload = RegExp(r'^[A-Za-z0-9\-_.:]{1,64}$');

  final StringBuffer _buffer = StringBuffer();
  bool _open = false;
  DateTime? _lastKeyAt;
  Timer? _timeoutTimer;

  bool get isFrameOpen => _open;

  /// Feed one key event. Returns true when the event belonged to a scan and
  /// should not be handled by anything else.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      // Repeats and key-ups carry no payload; swallow repeats while a frame is
      // open so a stuck key cannot pollute the buffer.
      return _open && event is KeyRepeatEvent;
    }

    final shift = HardwareKeyboard.instance.isShiftPressed;
    final char = UsQwertyLayout.charFor(event.physicalKey, shift: shift);

    if (char == null) {
      if (_open && UsQwertyLayout.isEnter(event.physicalKey)) {
        _complete(FrameTerminator.enterKey);
        return true;
      }
      return false;
    }

    final now = DateTime.now();
    if (_open) {
      final last = _lastKeyAt;
      if (last != null && now.difference(last) > timing.maxKeyGap) {
        _abort(ScanFault.interrupted);
        // The character that arrived late may itself be the start of a new
        // frame, so fall through rather than dropping it.
        if (char != '?') return false;
      }
    }
    _lastKeyAt = now;

    if (!_open) {
      if (char != '?') return false;
      _start();
      return true;
    }

    if (char == '?') {
      // Reader re-sent the start marker mid-frame. Trust the newer frame.
      _buffer.clear();
      return true;
    }
    if (char == ';') {
      _complete(FrameTerminator.semicolon);
      return true;
    }
    if (_buffer.length >= maxPayloadLength) {
      _abort(ScanFault.malformed);
      return true;
    }
    _buffer.write(char);
    return true;
  }

  void _start() {
    _open = true;
    _buffer.clear();
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timing.frameTimeout, () {
      if (_open) _abort(ScanFault.timeout);
    });
    onFrameStart();
  }

  void _complete(FrameTerminator terminator) {
    final raw = _buffer.toString();
    _reset();
    // Card ids are case-insensitive hex or alphanumerics; normalising here means
    // a reader configured with CapsLock instead of Shift still matches.
    final payload = raw.toUpperCase();
    if (!_validPayload.hasMatch(payload)) {
      onFault(ScanFault.malformed);
      return;
    }
    onFrame(ScanFrame(payload, terminator, raw));
  }

  void _abort(ScanFault fault) {
    _reset();
    onFault(fault);
  }

  void _reset() {
    _open = false;
    _buffer.clear();
    _lastKeyAt = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// Drop any half-received frame, e.g. when the admin panel opens.
  void cancel() => _reset();

  void dispose() => _timeoutTimer?.cancel();
}
