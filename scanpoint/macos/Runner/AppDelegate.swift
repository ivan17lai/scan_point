import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Cmd+Q is the one exit route `presentationOptions` cannot take away, so it
  /// is refused for as long as the kiosk lock is engaged. Leaving the app goes
  /// through the PIN screen, which releases the lock first.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return KioskLock.isEngaged ? .terminateCancel : .terminateNow
  }
}
