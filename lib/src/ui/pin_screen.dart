import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../scanner/keyboard_layout.dart';
import 'm3e/expressive_motion.dart';
import 'm3e/expressive_shape.dart';

/// PIN gate between the kiosk and the admin panel.
///
/// Digits are read from *physical* keys, same as the scanner, so a Chinese
/// input method left switched on cannot eat the operator's keystrokes at the
/// one moment they need the machine to respond. On-screen buttons are there too
/// because the machine is a convertible and may be folded with the keyboard
/// tucked away.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final FocusNode _focus = FocusNode();
  String _entry = '';
  bool _wrong = false;

  static const int _maxLength = 12;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _append(String digit) {
    if (_entry.length >= _maxLength) return;
    setState(() {
      _entry += digit;
      _wrong = false;
    });
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _submit() {
    if (widget.controller.submitPin(_entry)) return;
    setState(() {
      _wrong = true;
      _entry = '';
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final digit = UsQwertyLayout.digitFor(event.physicalKey);
    if (digit != null) {
      _append(digit);
      return KeyEventResult.handled;
    }
    if (UsQwertyLayout.isEnter(event.physicalKey)) {
      _submit();
      return KeyEventResult.handled;
    }
    if (event.physicalKey == PhysicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.physicalKey == PhysicalKeyboardKey.escape) {
      widget.controller.returnToKiosk();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: scheme.surface,
        child: Align(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The M3E shape language from the kiosk screen carries over, so
                // the operator surface is recognisably the same app.
                ExpressiveShape(
                  size: 96,
                  color: _wrong
                      ? scheme.errorContainer
                      : scheme.primaryContainer,
                  sides: _wrong ? 4 : 7,
                  rounding: _wrong ? 0.3 : 0.52,
                  child: Icon(
                    _wrong ? Icons.priority_high_rounded : Icons.lock_rounded,
                    size: 44,
                    color: _wrong
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '管理員驗證',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _wrong ? 'PIN 不正確,請重新輸入' : '輸入 PIN 後按 Enter,Esc 返回掃描畫面',
                  style: TextStyle(
                    color: _wrong ? scheme.error : scheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedSize(
                  duration: ExpressiveDurations.stateChange,
                  curve: SpringCurve.spatial,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      _entry.isEmpty ? 1 : _entry.length,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _entry.isEmpty
                              ? scheme.onSurface.withValues(alpha: 0.22)
                              : scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(width: 300, child: _keypad(scheme)),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: widget.controller.returnToKiosk,
                  child: const Text('返回掃描畫面'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad(ColorScheme scheme) {
    const labels = [
      '1', '2', '3', //
      '4', '5', '6',
      '7', '8', '9',
      '⌫', '0', '✓',
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: labels.map((label) {
        final isConfirm = label == '✓';
        final isDelete = label == '⌫';
        return FilledButton(
          onPressed: () {
            _focus.requestFocus();
            if (isDelete) {
              _backspace();
            } else if (isConfirm) {
              _submit();
            } else {
              _append(label);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: isConfirm
                ? scheme.primary
                : isDelete
                ? scheme.surfaceContainerHighest
                : scheme.secondaryContainer,
            foregroundColor: isConfirm
                ? scheme.onPrimary
                : isDelete
                ? scheme.onSurfaceVariant
                : scheme.onSecondaryContainer,
            // M3 Expressive uses much larger corner radii than baseline M3.
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        );
      }).toList(),
    );
  }
}
