import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio/tone_player.dart';
import 'model/scan_record.dart';
import 'model/station_config.dart';
import 'platform/kiosk_lock.dart';
import 'scanner/scan_decoder.dart';
import 'storage/config_store.dart';
import 'storage/scan_store.dart';

/// What the runner-facing screen is showing.
enum KioskState { idle, scanning, success, duplicate, error }

/// Which surface owns the keyboard.
enum AppMode { kiosk, pinEntry, admin }

class KioskTiming {
  const KioskTiming();

  /// A wedge reader finishes a frame in well under 100ms. Without a floor the
  /// "掃描中" screen would flash for one frame and read as a glitch, so it is
  /// held long enough to be seen as a step.
  static const Duration minScanning = Duration(milliseconds: 400);
  static const Duration holdSuccess = Duration(milliseconds: 2500);
  static const Duration holdDuplicate = Duration(milliseconds: 3000);
  static const Duration holdError = Duration(milliseconds: 3500);
}

class AppController extends ChangeNotifier {
  AppController._(this._store, this._configStore, this._tones, this._config) {
    _decoder = ScanDecoder(
      onFrameStart: _handleFrameStart,
      onFrame: _handleFrame,
      onFault: _handleFault,
    );
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  final ScanStore _store;
  final ConfigStore _configStore;
  final TonePlayer _tones;

  late final ScanDecoder _decoder;

  StationConfig _config;
  StationConfig get config => _config;

  AppMode _mode = AppMode.kiosk;
  AppMode get mode => _mode;

  KioskState _state = KioskState.idle;
  KioskState get state => _state;

  String? _cardId;
  String? get cardId => _cardId;

  DateTime? _recordedAt;
  DateTime? get recordedAt => _recordedAt;

  DateTime? _firstSeenAt;
  DateTime? get firstSeenAt => _firstSeenAt;

  ScanFault? _fault;
  ScanFault? get fault => _fault;

  int get recordedCount => _store.countFor(_config.stationId);
  ScanStore get store => _store;
  String get configSource => _configStore.loadedFrom;

  /// Bumped on every new frame so a slow disk write from a previous scan cannot
  /// overwrite the screen of the scan that replaced it.
  int _generation = 0;
  Timer? _revertTimer;
  DateTime? _scanningSince;

  /// Set when the operator asks to leave the app; main.dart tears down on it.
  bool exitRequested = false;

  static Future<AppController> create() async {
    final store = await ScanStore.open();
    final (configStore, config) = await ConfigStore.open();
    final tones = await TonePlayer.create();
    return AppController._(store, configStore, tones, config);
  }

  // --- keyboard ------------------------------------------------------------

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && _isAdminHotkey(event)) {
      requestAdmin();
      return true;
    }
    // The PIN screen and the admin panel read the keyboard themselves.
    if (_mode != AppMode.kiosk) return false;
    return _decoder.handleKeyEvent(event);
  }

  bool _isAdminHotkey(KeyDownEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return event.physicalKey == PhysicalKeyboardKey.keyX &&
        keyboard.isControlPressed &&
        keyboard.isShiftPressed &&
        keyboard.isAltPressed;
  }

  // --- scan pipeline -------------------------------------------------------

  void _handleFrameStart() {
    _generation++;
    _revertTimer?.cancel();
    _scanningSince = DateTime.now();
    _state = KioskState.scanning;
    _cardId = null;
    _fault = null;
    notifyListeners();
  }

  Future<void> _handleFrame(ScanFrame frame) async {
    final generation = _generation;
    final outcome = await _store.record(
      cardId: frame.payload,
      stationId: _config.stationId,
      stationName: _config.stationName,
      terminator: frame.terminator,
      raw: frame.raw,
    );
    if (generation != _generation) return;

    await _holdScanningFloor();
    if (generation != _generation) return;

    if (outcome.failed) {
      _settle(KioskState.error, fault: ScanFault.storageFailure);
      return;
    }

    _cardId = outcome.record!.cardId;
    _recordedAt = outcome.record!.at;
    _firstSeenAt = outcome.firstSeenAt;
    _settle(outcome.isDuplicate ? KioskState.duplicate : KioskState.success);
  }

  Future<void> _handleFault(ScanFault fault) async {
    final generation = _generation;
    await _holdScanningFloor();
    if (generation != _generation) return;
    _settle(KioskState.error, fault: fault);
  }

  Future<void> _holdScanningFloor() async {
    final since = _scanningSince;
    if (since == null) return;
    final elapsed = DateTime.now().difference(since);
    if (elapsed < KioskTiming.minScanning) {
      await Future<void>.delayed(KioskTiming.minScanning - elapsed);
    }
  }

  void _settle(KioskState state, {ScanFault? fault}) {
    _state = state;
    _fault = fault;
    notifyListeners();

    switch (state) {
      case KioskState.success:
        _tones.play(Tone.success);
      case KioskState.duplicate:
        _tones.play(Tone.duplicate);
      case KioskState.error:
        _tones.play(Tone.error);
      case KioskState.idle:
      case KioskState.scanning:
        break;
    }

    final hold = switch (state) {
      KioskState.success => KioskTiming.holdSuccess,
      KioskState.duplicate => KioskTiming.holdDuplicate,
      _ => KioskTiming.holdError,
    };
    final generation = _generation;
    _revertTimer?.cancel();
    _revertTimer = Timer(hold, () {
      if (generation != _generation) return;
      _state = KioskState.idle;
      _cardId = null;
      _fault = null;
      _firstSeenAt = null;
      notifyListeners();
    });
  }

  // --- mode ----------------------------------------------------------------

  void requestAdmin() {
    if (_mode != AppMode.kiosk) return;
    _decoder.cancel();
    _revertTimer?.cancel();
    _generation++;
    _state = KioskState.idle;
    _mode = AppMode.pinEntry;
    notifyListeners();
  }

  bool submitPin(String pin) {
    if (pin != _config.pin) return false;
    _mode = AppMode.admin;
    // Admin has text fields, so the IME is allowed to wake up here — and the
    // native keyboard block has to come off or the operator cannot Alt+Tab to
    // anything they might need.
    KioskLock.suspendKeyboardBlocking();
    notifyListeners();
    return true;
  }

  void returnToKiosk() {
    _mode = AppMode.kiosk;
    _state = KioskState.idle;
    _cardId = null;
    _fault = null;
    _decoder.cancel();
    KioskLock.resumeKeyboardBlocking();
    notifyListeners();
  }

  Future<void> updateConfig(StationConfig config) async {
    _config = config;
    await _configStore.save(config);
    notifyListeners();
  }

  List<ScanRecord> get recentScans => _store.recentFor(_config.stationId);

  void requestExit() {
    exitRequested = true;
    notifyListeners();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _revertTimer?.cancel();
    _decoder.dispose();
    _tones.dispose();
    super.dispose();
  }
}
