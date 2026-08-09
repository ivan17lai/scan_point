#ifndef RUNNER_KIOSK_LOCK_H_
#define RUNNER_KIOSK_LOCK_H_

#include <flutter/plugin_registrar_windows.h>

// Native half of the kiosk lock on Windows.
//
// Fullscreen and always-on-top are done from Dart; what has to live here is the
// low-level keyboard hook, because Alt+Tab, the Windows key and Alt+F4 are
// handled by the shell before any application window ever sees them.
//
// Ctrl+Alt+Del is deliberately absent: it is the Secure Attention Sequence and
// no user-mode hook can intercept it. Blocking that one needs a machine policy
// (see docs/windows-kiosk.md).
namespace kiosk_lock {

// Registers the `scan_point/kiosk` method channel.
void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

// Installs / removes the keyboard hook. Safe to call repeatedly.
void Enable();
void Disable();

}  // namespace kiosk_lock

#endif  // RUNNER_KIOSK_LOCK_H_
