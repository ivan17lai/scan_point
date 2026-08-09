import Cocoa
import FlutterMacOS

/// Native half of the kiosk lock on macOS.
///
/// `NSApplication.presentationOptions` is what actually takes Cmd+Tab, Cmd+Q,
/// the Dock and the menu bar away — window-level fullscreen alone leaves all of
/// them reachable, which is not good enough for a control point with nobody
/// standing next to it.
enum KioskLock {
  static let channelName = "scan_point/kiosk"

  private static var engaged = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "enable":
        enable()
        result(nil)
      case "disable":
        disable()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func enable() {
    guard !engaged else { return }
    engaged = true
    NSApp.presentationOptions = [
      .hideDock,
      .hideMenuBar,
      .disableProcessSwitching,     // Cmd+Tab
      .disableForceQuit,            // Cmd+Opt+Esc
      .disableSessionTermination,   // shutdown / restart / log out
      .disableHideApplication,      // Cmd+H
      .disableAppleMenu,
      .disableMenuBarTransparency,
    ]
    // Cmd+Q is not covered by presentationOptions; the app delegate refuses it
    // separately (see AppDelegate.applicationShouldTerminate).
  }

  static func disable() {
    guard engaged else { return }
    engaged = false
    NSApp.presentationOptions = []
  }

  static var isEngaged: Bool { engaged }
}
