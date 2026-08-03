import 'package:flutter/services.dart';

/// Maps a *physical* key position to the character a US-QWERTY keyboard would
/// produce there.
///
/// The whole point of going through physical keys is that the result is
/// independent of the IME (注音 / 拼音 / 倉頡), of the OS keyboard layout, and of
/// CapsLock. A keyboard-wedge NFC reader emulates a US keyboard at the HID
/// level, so decoding the HID usage ourselves is the only way to be sure we see
/// what the reader actually sent rather than what the input method decided to
/// do with it.
class UsQwertyLayout {
  const UsQwertyLayout._();

  /// Physical key (USB HID usage) -> [unshifted, shifted].
  static const Map<int, List<String>> _map = <int, List<String>>{
    0x00070004: ['a', 'A'],
    0x00070005: ['b', 'B'],
    0x00070006: ['c', 'C'],
    0x00070007: ['d', 'D'],
    0x00070008: ['e', 'E'],
    0x00070009: ['f', 'F'],
    0x0007000A: ['g', 'G'],
    0x0007000B: ['h', 'H'],
    0x0007000C: ['i', 'I'],
    0x0007000D: ['j', 'J'],
    0x0007000E: ['k', 'K'],
    0x0007000F: ['l', 'L'],
    0x00070010: ['m', 'M'],
    0x00070011: ['n', 'N'],
    0x00070012: ['o', 'O'],
    0x00070013: ['p', 'P'],
    0x00070014: ['q', 'Q'],
    0x00070015: ['r', 'R'],
    0x00070016: ['s', 'S'],
    0x00070017: ['t', 'T'],
    0x00070018: ['u', 'U'],
    0x00070019: ['v', 'V'],
    0x0007001A: ['w', 'W'],
    0x0007001B: ['x', 'X'],
    0x0007001C: ['y', 'Y'],
    0x0007001D: ['z', 'Z'],
    0x0007001E: ['1', '!'],
    0x0007001F: ['2', '@'],
    0x00070020: ['3', '#'],
    0x00070021: ['4', r'$'],
    0x00070022: ['5', '%'],
    0x00070023: ['6', '^'],
    0x00070024: ['7', '&'],
    0x00070025: ['8', '*'],
    0x00070026: ['9', '('],
    0x00070027: ['0', ')'],
    0x0007002D: ['-', '_'],
    0x0007002E: ['=', '+'],
    0x0007002F: ['[', '{'],
    0x00070030: [']', '}'],
    0x00070031: [r'\', '|'],
    0x00070033: [';', ':'],
    0x00070034: ["'", '"'],
    0x00070035: ['`', '~'],
    0x00070036: [',', '<'],
    0x00070037: ['.', '>'],
    0x00070038: ['/', '?'],
    0x0007002C: [' ', ' '],
    // Numeric keypad. Some wedge readers are configured to emit the payload on
    // the keypad; those keys are unaffected by shift.
    0x00070054: ['/', '/'],
    0x00070055: ['*', '*'],
    0x00070056: ['-', '-'],
    0x00070057: ['+', '+'],
    0x00070059: ['1', '1'],
    0x0007005A: ['2', '2'],
    0x0007005B: ['3', '3'],
    0x0007005C: ['4', '4'],
    0x0007005D: ['5', '5'],
    0x0007005E: ['6', '6'],
    0x0007005F: ['7', '7'],
    0x00070060: ['8', '8'],
    0x00070061: ['9', '9'],
    0x00070062: ['0', '0'],
    0x00070063: ['.', '.'],
  };

  static const int enterUsage = 0x00070028;
  static const int numpadEnterUsage = 0x00070058;
  static const int tabUsage = 0x0007002B;
  static const int escapeUsage = 0x00070029;
  static const int backspaceUsage = 0x0007002A;

  /// The character [key] carries on a US layout, or null for keys that produce
  /// no character (modifiers, function keys, Enter, Tab...).
  static String? charFor(PhysicalKeyboardKey key, {required bool shift}) {
    final pair = _map[key.usbHidUsage];
    if (pair == null) return null;
    return shift ? pair[1] : pair[0];
  }

  static bool isEnter(PhysicalKeyboardKey key) =>
      key.usbHidUsage == enterUsage || key.usbHidUsage == numpadEnterUsage;

  /// Digit typed on either the number row or the keypad, ignoring shift so a
  /// stuck modifier cannot break PIN entry.
  static String? digitFor(PhysicalKeyboardKey key) {
    final pair = _map[key.usbHidUsage];
    if (pair == null) return null;
    final c = pair[0];
    return (c.length == 1 && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39)
        ? c
        : null;
  }
}
