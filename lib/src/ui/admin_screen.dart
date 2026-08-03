import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_controller.dart';
import '../audio/tone_player.dart';
import '../model/station_config.dart';
import '../platform/kiosk_lock.dart';
import '../storage/event_log.dart';

/// Operator surface behind the PIN: station identity, counts, export, upload,
/// and the only way out of the app.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final TextEditingController _stationId;
  late final TextEditingController _stationName;
  late final TextEditingController _pin;
  late final TextEditingController _uploadUrl;
  late final TextEditingController _uploadToken;

  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    _stationId = TextEditingController(text: config.stationId);
    _stationName = TextEditingController(text: config.stationName);
    _pin = TextEditingController(text: config.pin);
    _uploadUrl = TextEditingController(text: config.uploadUrl);
    _uploadToken = TextEditingController(text: config.uploadToken);
  }

  @override
  void dispose() {
    for (final c in [
      _stationId,
      _stationName,
      _pin,
      _uploadUrl,
      _uploadToken,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (pin.length < 4) {
      setState(() => _status = 'PIN 至少要 4 位數字');
      return;
    }
    await widget.controller.updateConfig(
      StationConfig(
        stationId: _stationId.text.trim().isEmpty
            ? 'CP1'
            : _stationId.text.trim(),
        stationName: _stationName.text.trim().isEmpty
            ? '未命名站點'
            : _stationName.text.trim(),
        pin: pin,
        uploadUrl: _uploadUrl.text.trim(),
        uploadToken: _uploadToken.text.trim(),
      ),
    );
    setState(() => _status = '設定已儲存');
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final dir = await widget.controller.store.exportAll();
      await widget.controller.events.record(
        EventType.exportRun,
        stationId: widget.controller.config.stationId,
        detail: {
          'target': dir.path,
          'records': widget.controller.store.totalLines,
        },
      );
      setState(() => _status = '已匯出到 ${dir.path}');
    } catch (e) {
      await widget.controller.events.record(
        EventType.exportRun,
        stationId: widget.controller.config.stationId,
        detail: {'error': '$e'},
      );
      setState(() => _status = '匯出失敗:$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final url = widget.controller.config.uploadUrl.trim();
    if (url.isEmpty) {
      setState(() => _status = '尚未設定上傳網址,請先填寫或改用匯出');
      return;
    }
    setState(() {
      _busy = true;
      _status = '上傳中…';
    });
    try {
      final token = widget.controller.config.uploadToken.trim();
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'station_id': widget.controller.config.stationId,
              'station_name': widget.controller.config.stationName,
              'uploaded_at': DateTime.now().toIso8601String(),
              'records': widget.controller.store.toJsonList(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      await widget.controller.events.record(
        EventType.uploadRun,
        stationId: widget.controller.config.stationId,
        detail: {
          // Host only: the full URL can carry a query-string secret.
          'host': Uri.parse(url).host,
          'status': response.statusCode,
          'records': widget.controller.store.totalLines,
        },
      );
      setState(
        () => _status = ok
            ? '上傳成功(${widget.controller.store.totalLines} 筆)'
            : '上傳失敗:HTTP ${response.statusCode}',
      );
    } catch (e) {
      await widget.controller.events.record(
        EventType.uploadRun,
        stationId: widget.controller.config.stationId,
        detail: {'host': Uri.tryParse(url)?.host, 'error': '$e'},
      );
      setState(() => _status = '上傳失敗:$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder({required bool extra}) async {
    final chosen = await getDirectoryPath(
      confirmButtonText: '選擇',
      initialDirectory: extra
          ? widget.controller.store.extraDir?.path
          : widget.controller.store.exportDir.path,
    );
    if (chosen == null) return;

    setState(() {
      _busy = true;
      _status = extra ? '正在複製既有紀錄到 $chosen…' : '正在切換到 $chosen…';
    });
    final problem = await widget.controller.changeStorage(
      extraDir: extra ? chosen : null,
      exportDir: extra ? null : chosen,
    );
    setState(() {
      _busy = false;
      _status =
          problem ??
          (extra ? '額外備份已設定,既有紀錄已複製到 $chosen' : '匯出目的地已改為 $chosen');
    });
  }

  Future<void> _resetFolder({required bool extra}) async {
    setState(() => _busy = true);
    final problem = await widget.controller.changeStorage(
      extraDir: extra ? '' : null,
      exportDir: extra ? null : '',
    );
    setState(() {
      _busy = false;
      _status = problem ?? (extra ? '已取消額外備份' : '匯出目的地已還原為預設');
    });
  }

  Widget _folderRow({
    required String label,
    required String path,
    required bool isCustom,
    required VoidCallback onPick,
    required VoidCallback onReset,
    String resetLabel = '還原預設',
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
              if (isCustom) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: scheme.secondaryContainer,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    '自訂',
                    style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(path, style: TextStyle(color: scheme.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : onPick,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('選擇資料夾'),
              ),
              if (isCustom)
                TextButton(
                  onPressed: _busy ? null : onReset,
                  child: Text(resetLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _backToKiosk() {
    // Drop the text input client before returning, otherwise the IME stays
    // attached and the next card scan would be routed through it.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.controller.returnToKiosk();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final store = c.store;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: scheme.onSurface,
        title: const Text('管理台'),
        actions: [
          TextButton.icon(
            onPressed: _backToKiosk,
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回掃描畫面'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_status != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: ShapeDecoration(
                color: scheme.secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _status!,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          if (c.config.isPinDefault)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: ShapeDecoration(
                color: scheme.errorContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_open_rounded,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '目前仍在使用預設 PIN。這組密碼寫在公開的原始碼裡,任何人都查得到 —— '
                      '部署到現場前請在下方改掉。',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          _section('本站統計', [
            _kv('本站已記錄', '${c.recordedCount} 筆'),
            _kv('紀錄檔總行數(含重複刷)', '${store.totalLines} 行'),
            _kv('設定來源', c.configSource),
            if (store.lastWriteError != null)
              _kv('寫入警告', store.lastWriteError!),
            if (KioskLock.nativeError != null)
              _kv('鎖定狀態', KioskLock.nativeError!),
            if (TonePlayer.unavailableReason != null)
              _kv('音效狀態', TonePlayer.unavailableReason!),
          ]),
          const SizedBox(height: 24),
          _section('儲存位置', [
            _kv('① 程式資料夾(固定)', store.primaryDir.path),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 10),
              child: Text(
                '含 scans.jsonl(掃描成功)、scans-<日期>.csv(同上,可直接開)、'
                'events.jsonl(完整操作紀錄:失敗讀取、管理員登入、設定變更)',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            _kv('② 鏡像備份(固定)', store.mirrorDir.path),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 10),
              child: Text(
                '與 ① 相同的三種檔案 —— 完整的一份副本,不是只有掃描紀錄。',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              child: Text(
                '這兩份的位置不開放更改 —— 它們必須永遠掛載、永遠可寫。'
                '若指向隨身碟而中途鬆脫,山上這台機器會靜默地停止記錄。',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            _folderRow(
              label: '③ 額外備份(例如隨身碟)',
              path:
                  store.extraDirFor(c.config.stationId)?.path ??
                  '未設定 — 只寫上面兩份',
              isCustom: c.config.extraDir.trim().isNotEmpty,
              onPick: () => _pickFolder(extra: true),
              onReset: () => _resetFolder(extra: true),
              resetLabel: '取消額外備份',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '這是「多寫一份」,不會取代上面兩份 —— 隨身碟拔掉,原本的備援完全不受影響。'
                '兩種 log 都會複製,設定後既有紀錄整份寫過去,不是只從現在開始記。\n'
                '檔案放在 <你選的資料夾>/scan_point/<站點編號>/,依站點分開,'
                '所以同一支隨身碟可以收多台機器而不會互相覆蓋。',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            _folderRow(
              label: '匯出目的地',
              path: store.exportDir.path,
              isCustom: c.config.exportDir.trim().isNotEmpty,
              onPick: () => _pickFolder(extra: false),
              onReset: () => _resetFolder(extra: false),
            ),
          ]),
          const SizedBox(height: 24),
          _section('站點設定', [
            _field('站點編號', _stationId, hint: 'CP3'),
            _field('站點名稱', _stationName, hint: '水源地'),
            _field('管理 PIN(僅數字)', _pin),
            _field('雲端上傳網址(可留空)', _uploadUrl, hint: 'https://…'),
            _field('上傳權杖(可留空)', _uploadToken),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('儲存設定'),
            ),
          ]),
          const SizedBox(height: 24),
          _section('資料', [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('匯出全部紀錄'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上傳到雲端'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '上傳不會刪除本機紀錄,可重複執行。',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ]),
          const SizedBox(height: 24),
          _section('最近刷卡', [
            if (c.recentScans.isEmpty)
              const Text('尚無紀錄', style: TextStyle(color: Colors.white54))
            else
              ...c.recentScans.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          '${r.at.hour.toString().padLeft(2, '0')}:'
                          '${r.at.minute.toString().padLeft(2, '0')}:'
                          '${r.at.second.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.cardId,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (r.isDuplicate)
                        Text('重複', style: TextStyle(color: scheme.tertiary)),
                    ],
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 24),
          _section('離開', [
            Text(
              '離開後畫面鎖定會解除,現場請務必重新啟動程式。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: c.requestExit,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              ),
              icon: const Icon(Icons.logout),
              label: const Text('解除鎖定並關閉程式'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        // M3 Expressive corner scale: containers are noticeably rounder than
        // baseline M3, which keeps the admin panel visually related to the
        // shape language on the kiosk screen.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}
