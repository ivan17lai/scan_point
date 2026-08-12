import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';

/// First-run station identity setup shown before the scanner can be used.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _stationId;
  late final TextEditingController _stationName;
  late final TextEditingController _pin;
  late final TextEditingController _pinConfirmation;
  String? _error;
  bool _saving = false;
  bool _showPin = false;

  @override
  void initState() {
    super.initState();
    // Deliberately blank: CP1 is a useful hint and a valid value, but the
    // operator must actively confirm the station identity before scanning.
    _stationId = TextEditingController();
    _stationName = TextEditingController();
    _pin = TextEditingController();
    _pinConfirmation = TextEditingController();
  }

  @override
  void dispose() {
    _stationId.dispose();
    _stationName.dispose();
    _pin.dispose();
    _pinConfirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stationId = _stationId.text.trim();
    final stationName = _stationName.text.trim();
    final pin = _pin.text;
    final pinConfirmation = _pinConfirmation.text;
    if (stationId.isEmpty) {
      setState(() => _error = '請輸入站點編號');
      return;
    }
    if (stationName.isEmpty || stationName == '未命名站點') {
      setState(() => _error = '請輸入實際站點名稱');
      return;
    }
    if (pin.length < 4) {
      setState(() => _error = '管理 PIN 至少要 4 位數字');
      return;
    }
    if (pin != pinConfirmation) {
      setState(() => _error = '兩次輸入的管理 PIN 不一致');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.completeStationSetup(
        stationId: stationId,
        stationName: stationName,
        pin: pin,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '設定無法儲存：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Card(
                color: scheme.surfaceContainer,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.add_location_alt_rounded,
                        size: 52,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '設定這個掃描站',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '開始掃描前，請設定這台電腦代表的站點與管理 PIN。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 30),
                      TextField(
                        controller: _stationId,
                        autofocus: true,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '站點編號',
                          hintText: '例如 CP1',
                          prefixIcon: Icon(Icons.tag_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _stationName,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '站點名稱',
                          hintText: '例如 水源地',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _pin,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        obscureText: !_showPin,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '設定管理 PIN',
                          hintText: '至少 4 位數字',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _showPin ? '隱藏 PIN' : '顯示 PIN',
                            onPressed: _saving
                                ? null
                                : () => setState(() => _showPin = !_showPin),
                            icon: Icon(
                              _showPin
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _pinConfirmation,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        obscureText: !_showPin,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          labelText: '再次輸入管理 PIN',
                          hintText: '確認兩次輸入一致',
                          prefixIcon: Icon(Icons.lock_reset_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_saving ? '正在儲存…' : '儲存並開始掃描'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
