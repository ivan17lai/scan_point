import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio/tone_player.dart';
import 'model/scan_record.dart';
import 'model/station_config.dart';
import 'platform/kiosk_lock.dart';
import 'scanner/scan_decoder.dart';
import 'storage/config_store.dart';
import 'storage/event_log.dart';
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
  AppController._(
    this._store,
    this._configStore,
    this._tones,
    this._config,
    this.events,
  ) {
    _decoder = ScanDecoder(
      onFrameStart: _handleFrameStart,
      onFrame: _handleFrame,
      onFault: _handleFault,
    );
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  // Not final: choosing an extra backup folder reopens the store in place.
  ScanStore _store;
  final ConfigStore _configStore;

  /// Everything the software did, as opposed to what the runners did.
  final EventLog events;
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
    // Config first: it decides where the extra and export folders live.
    final (configStore, config) = await ConfigStore.open();
    final store = await ScanStore.open(
      extraDir: config.extraDir,
      exportOverride: config.exportDir,
    );
    final tones = await TonePlayer.create();
    final events = EventLog(_eventTargets(store, config.stationId));

    final controller = AppController._(
      store,
      configStore,
      tones,
      config,
      events,
    );
    await events.record(
      EventType.appStart,
      stationId: config.stationId,
      detail: {
        'station_name': config.stationName,
        'records_loaded': store.totalLines,
        'config_source': configStore.loadedFrom,
      },
    );
    return controller;
  }

  /// The operational log goes everywhere the scan log goes. After an event the
  /// two are read together — a missing punch is explained by the failures and
  /// the settings changes around it — so a copy holding only half of that is a
  /// copy that cannot answer the question.
  static List<Directory> _eventTargets(ScanStore store, String stationId) => [
    store.primaryDir,
    store.mirrorDir,
    ?store.extraDirFor(stationId),
  ];

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
      events.record(
        EventType.writeError,
        stationId: _config.stationId,
        detail: {'card': frame.payload, 'error': _store.lastWriteError},
      );
      _settle(KioskState.error, fault: ScanFault.storageFailure);
      return;
    }

    _cardId = outcome.record!.cardId;
    _recordedAt = outcome.record!.at;
    _firstSeenAt = outcome.firstSeenAt;

    events.record(
      outcome.isDuplicate ? EventType.scanDuplicate : EventType.scanOk,
      stationId: _config.stationId,
      detail: {
        'seq': outcome.record!.sequence,
        'card': outcome.record!.cardId,
        'terminator': frame.terminator.name,
        if (frame.raw != outcome.record!.cardId) 'raw': frame.raw,
        'first_seen_at': ?outcome.firstSeenAt?.toIso8601String(),
        // A write that only partly succeeded still counts as recorded, but the
        // trail should say which copy was missed.
        'write_warning': ?_store.lastWriteError,
      },
    );

    _settle(outcome.isDuplicate ? KioskState.duplicate : KioskState.success);
  }

  Future<void> _handleFault(ScanFault fault) async {
    final generation = _generation;
    // Failed reads are the whole reason for keeping an operational log: a
    // missing punch is usually explained by one of these, not by the successes.
    events.record(
      EventType.scanFail,
      stationId: _config.stationId,
      detail: {'code': fault.code, 'reason': fault.name},
    );
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
    if (pin != _config.pin) {
      // The attempted value is never logged — only that an attempt failed, and
      // how long it was, which is enough to tell a typo from someone probing.
      events.record(
        EventType.adminPinRejected,
        stationId: _config.stationId,
        detail: {'length': pin.length},
      );
      return false;
    }
    events.record(EventType.adminUnlock, stationId: _config.stationId);
    _mode = AppMode.admin;
    // Admin has text fields, so the IME is allowed to wake up here — and the
    // native keyboard block has to come off or the operator cannot Alt+Tab to
    // anything they might need.
    KioskLock.suspendKeyboardBlocking();
    notifyListeners();
    return true;
  }

  void returnToKiosk() {
    if (_mode == AppMode.admin) {
      events.record(EventType.adminExit, stationId: _config.stationId);
    }
    _mode = AppMode.kiosk;
    _state = KioskState.idle;
    _cardId = null;
    _fault = null;
    _decoder.cancel();
    KioskLock.resumeKeyboardBlocking();
    notifyListeners();
  }

  Future<void> updateConfig(StationConfig config) async {
    final before = _config.toJson();
    final after = config.toJson();
    final changed = <String, Object?>{
      for (final key in after.keys)
        if (before[key] != after[key]) key: after[key],
    };

    _config = config;
    await _configStore.save(config);

    if (changed.isNotEmpty) {
      // The station id is part of the event log's own path, so the targets move
      // with it — otherwise a renamed station would keep writing its diary into
      // the previous station's folder on the stick.
      events.targets = _eventTargets(_store, config.stationId);
      await events.record(
        EventType.configChange,
        stationId: config.stationId,
        detail: changed,
      );
    }
    notifyListeners();
  }

  /// Sets the extra backup folder and/or the export folder.
  ///
  /// Returns null on success, or a message for the operator. The folder is
  /// proved writable before anything changes, and the whole log is copied into
  /// a newly chosen extra folder so it holds the event rather than only the
  /// part of it that happens after the stick went in.
  Future<String?> changeStorage({String? extraDir, String? exportDir}) async {
    final next = _config.copyWith(extraDir: extraDir, exportDir: exportDir);

    for (final candidate in [next.extraDir, next.exportDir]) {
      if (candidate.trim().isEmpty) continue;
      final problem = await ScanStore.probeWritable(candidate);
      if (problem != null) return '無法寫入 $candidate — $problem';
    }

    final reopened = await ScanStore.open(
      extraDir: next.extraDir,
      exportOverride: next.exportDir,
    );
    final seedProblem = await reopened.seedExtraCopy();

    _store = reopened;
    _config = next;
    await _configStore.save(next);
    events.targets = _eventTargets(reopened, next.stationId);
    await events.record(
      EventType.storageChange,
      stationId: next.stationId,
      detail: {
        'extra_dir': next.extraDir.isEmpty ? '(未設定)' : next.extraDir,
        'export_dir': next.exportDir.isEmpty ? '(預設)' : next.exportDir,
        'seed_error': ?seedProblem,
      },
    );
    notifyListeners();

    return seedProblem == null
        ? null
        : '位置已更新,但既有紀錄複製失敗:$seedProblem';
  }

  List<ScanRecord> get recentScans => _store.recentFor(_config.stationId);

  Future<void> requestExit() async {
    // Awaited so the last line reaches disk before main() tears the process
    // down — an exit that leaves no trace is exactly the one worth tracing.
    await events.record(
      EventType.appExit,
      stationId: _config.stationId,
      detail: {'records': _store.totalLines},
    );
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
