import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

/// Locks the machine down to this app.
///
/// Two halves. The cross-platform half (fullscreen, always on top, close
/// blocked, no sleep) is pure Dart. The half that actually stops someone
/// leaving the app — swallowing Alt+Tab / Win / Cmd+Tab — has to be native, and
/// lives in `windows/runner/kiosk_lock.cpp` and `macos/Runner/KioskLock.swift`
/// behind this channel.
class KioskLock {
  KioskLock._();

  static const MethodChannel _channel = MethodChannel('scan_point/kiosk');

  /// Locking a developer out of their own machine every time they press run is
  /// no way to work on this, so a debug build stays windowed and switchable
  /// unless it is started with `--dart-define=KIOSK=true`. Release builds — the
  /// ones that go to a control point — always lock.
  static const bool _forcedInDebug = bool.fromEnvironment('KIOSK');
  static bool get locksFully => kReleaseMode || kProfileMode || _forcedInDebug;

  static bool _engaged = false;
  static bool get isEngaged => _engaged;

  /// Non-fatal reason the native lock could not be installed, shown in admin.
  static String? nativeError;

  static Future<void> engage() async {
    nativeError = null;
    await _setWindowsImeEnabled(false);
    if (!locksFully) {
      nativeError ??= 'Debug 執行:未鎖定畫面(加 --dart-define=KIOSK=true 可測試鎖定)';
      _engaged = false;
      return;
    }
    await windowManager.setFullScreen(true);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setPreventClose(true);
    await windowManager.focus();
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // A machine that will not hold the wakelock still needs to scan.
    }
    await _invokeNative('enable');
    _engaged = true;
  }

  /// Drops the lock so the operator can reach the desktop after the PIN screen.
  static Future<void> release() async {
    nativeError = null;
    await _invokeNative('disable');
    await _setWindowsImeEnabled(true);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setPreventClose(false);
    await windowManager.setFullScreen(false);
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    _engaged = false;
  }

  /// Temporarily lets the window sit below others (admin panel is open) without
  /// giving up fullscreen — the runner-facing screen never shows the desktop.
  static Future<void> suspendKeyboardBlocking() async {
    nativeError = null;
    if (locksFully) {
      await _invokeNative('disable');
      // IME candidate and language-switcher windows belong to Windows, not this
      // process. Leaving the kiosk window topmost can hide them behind Flutter.
      await windowManager.setAlwaysOnTop(false);
    }
    await _setWindowsImeEnabled(true);
    if (!locksFully) {
      nativeError ??= 'Debug 執行:未鎖定畫面(加 --dart-define=KIOSK=true 可測試鎖定)';
    }
  }

  static Future<void> resumeKeyboardBlocking() async {
    nativeError = null;
    if (locksFully) {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await _invokeNative('enable');
    }
    await _setWindowsImeEnabled(false);
  }

  static Future<void> _setWindowsImeEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    await _invokeNative(enabled ? 'enableIme' : 'disableIme');
  }

  static Future<void> _invokeNative(String method) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      nativeError = '原生鎖定未載入(平台程式碼未編入)';
    } catch (e) {
      nativeError = '$e';
    }
  }
}
