import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_controller.dart';
import 'src/platform/kiosk_lock.dart';
import 'src/ui/admin_screen.dart';
import 'src/ui/kiosk_screen.dart';
import 'src/ui/pin_screen.dart';
import 'src/ui/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      title: '定向越野 掃描站',
      size: const Size(1280, 800),
      fullScreen: KioskLock.locksFully,
      skipTaskbar: KioskLock.locksFully,
      titleBarStyle: KioskLock.locksFully
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // Nothing during startup is allowed to leave a control point with a dead
  // screen and no explanation. If the app cannot come up, it says so in a way a
  // marshal can photograph and send to whoever is running the event.
  final AppController controller;
  try {
    controller = await AppController.create();
  } catch (error, stack) {
    runApp(StartupFailureApp(error: error, stack: stack));
    return;
  }

  await KioskLock.engage();
  await controller.prepareInitialMode();
  runApp(StationApp(controller: controller));
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.stack,
  });

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Container(
        color: const Color(0xFF9B2222),
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '系統無法啟動',
              style: TextStyle(
                color: Color(0xFFFCEBEB),
                fontSize: 44,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '請通知工作人員,並改用紙本記錄',
              style: TextStyle(color: Color(0xFFF7C1C1), fontSize: 20),
            ),
            const SizedBox(height: 28),
            SelectableText(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFF7C1C1),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StationApp extends StatefulWidget {
  const StationApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<StationApp> createState() => _StationAppState();
}

class _StationAppState extends State<StationApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.exitRequested) _shutdown();
  }

  /// The only sanctioned way out: reached through the PIN screen.
  Future<void> _shutdown() async {
    await KioskLock.release();
    widget.controller.dispose();
    await windowManager.destroy();
    exit(0);
  }

  /// Alt+F4, the window close button, and anything else that asks the window to
  /// go away are refused — the station is unattended and must not be closable
  /// by a runner leaning on the keyboard.
  @override
  void onWindowClose() {}

  /// Something managed to push the window behind another; pull it back.
  @override
  void onWindowBlur() {
    if (widget.controller.mode == AppMode.kiosk && KioskLock.isEngaged) {
      windowManager.focus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '定向越野 掃描站',
      debugShowCheckedModeBanner: false,
      // Fixed palette, same as the kiosk states — nothing here is generated
      // from a seed, so what is written is what ships.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9EC4FF),
          onPrimary: Color(0xFF04305F),
          primaryContainer: Color(0xFF0E4BA8),
          onPrimaryContainer: Color(0xFFD8E6FF),
          secondaryContainer: Color(0xFF2C3A54),
          onSecondaryContainer: Color(0xFFD8E6FF),
          tertiary: Color(0xFFCFC6FF),
          error: Color(0xFFFFB4AB),
          errorContainer: Color(0xFF7A1A1A),
          onErrorContainer: Color(0xFFFFDAD5),
          surface: Color(0xFF14161A),
          onSurface: Color(0xFFE4E6EB),
          onSurfaceVariant: Color(0xFF9FA5B0),
          surfaceContainer: Color(0xFF1D2026),
          surfaceContainerHigh: Color(0xFF23262D),
          surfaceContainerHighest: Color(0xFF2A2E36),
        ),
        fontFamily: Platform.isWindows ? 'Microsoft JhengHei' : null,
      ),
      home: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return switch (widget.controller.mode) {
            AppMode.setup => SetupScreen(controller: widget.controller),
            AppMode.kiosk => KioskScreen(controller: widget.controller),
            AppMode.pinEntry => PinScreen(controller: widget.controller),
            AppMode.admin => AdminScreen(controller: widget.controller),
          };
        },
      ),
    );
  }
}
