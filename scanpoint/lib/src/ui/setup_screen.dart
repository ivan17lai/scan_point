import 'package:flutter/material.dart';

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
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Deliberately blank: CP1 is a useful hint and a valid value, but the
    // operator must actively confirm the station identity before scanning.
    _stationId = TextEditingController();
    _stationName = TextEditingController();
  }

  @override
  void dispose() {
    _stationId.dispose();
    _stationName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stationId = _stationId.text.trim();
    final stationName = _stationName.text.trim();
    if (stationId.isEmpty) {
      setState(() => _error = '請輸入站點編號');
      return;
    }
    if (stationName.isEmpty || stationName == '未命名站點') {
      setState(() => _error = '請輸入實際站點名稱');
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
                        '完整軟體包使用預設站點。開始掃描前，請先填寫這台電腦代表的站點。',
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
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          labelText: '站點名稱',
                          hintText: '例如 水源地',
                          prefixIcon: Icon(Icons.location_on_outlined),
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
