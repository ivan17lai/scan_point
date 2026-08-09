#include "kiosk_lock.h"

#include <windows.h>
#include <imm.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace kiosk_lock {

namespace {

constexpr char kChannelName[] = "scan_point/kiosk";

HHOOK g_hook = nullptr;
HWND g_flutter_window = nullptr;

bool IsDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

bool SetImeEnabled(bool enabled) {
  if (g_flutter_window == nullptr) {
    return false;
  }
  // Removing the input context prevents an active Chinese IME from consuming
  // scanner keystrokes as VK_PROCESSKEY. IACE_DEFAULT restores the window's
  // normal context when the operator reaches text fields in the admin panel.
  return ImmAssociateContextEx(
             g_flutter_window, nullptr, enabled ? IACE_DEFAULT : 0) != FALSE;
}

// Runs on the runner's message loop for every keystroke on the machine while
// the lock is engaged. Returning 1 swallows the key.
LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION) {
    const KBDLLHOOKSTRUCT* info = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    const DWORD vk = info->vkCode;
    const bool alt = (info->flags & LLKHF_ALTDOWN) != 0 ||
                     IsDown(VK_MENU);
    const bool ctrl = IsDown(VK_CONTROL);
    const bool shift = IsDown(VK_SHIFT);

    // The admin hotkey has to survive, or there is no way into the PIN screen.
    const bool is_admin_hotkey = (vk == 'X') && ctrl && shift && alt;

    bool block = false;
    if (!is_admin_hotkey) {
      if (vk == VK_LWIN || vk == VK_RWIN || vk == VK_APPS) {
        block = true;  // Start menu, context menu key.
      } else if (alt && (vk == VK_TAB || vk == VK_ESCAPE || vk == VK_F4)) {
        block = true;  // App switch, app cycle, close window.
      } else if (ctrl && vk == VK_ESCAPE) {
        block = true;  // Start menu, and Ctrl+Shift+Esc task manager.
      }
    }

    if (block) {
      return 1;
    }
  }
  return CallNextHookEx(g_hook, code, wparam, lparam);
}

}  // namespace

void Enable() {
  if (g_hook != nullptr) {
    return;
  }
  g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                             GetModuleHandle(nullptr), 0);
}

void Disable() {
  if (g_hook == nullptr) {
    return;
  }
  UnhookWindowsHookEx(g_hook);
  g_hook = nullptr;
}

void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  g_flutter_window = registrar->GetView()->GetNativeWindow();

  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "enable") {
          Enable();
          result->Success();
        } else if (call.method_name() == "disable") {
          Disable();
          result->Success();
        } else if (call.method_name() == "enableIme") {
          if (SetImeEnabled(true)) {
            result->Success();
          } else {
            result->Error("ime_context", "Unable to restore the IME context");
          }
        } else if (call.method_name() == "disableIme") {
          if (SetImeEnabled(false)) {
            result->Success();
          } else {
            result->Error("ime_context", "Unable to detach the IME context");
          }
        } else {
          result->NotImplemented();
        }
      });

  // Keep the channel alive for the process lifetime.
  static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      retained;
  retained = channel;
}

}  // namespace kiosk_lock
