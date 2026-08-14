import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_controller.dart';
import '../audio/tone_player.dart';
import '../model/scan_record.dart';
import '../model/station_setup_validator.dart';
import '../platform/kiosk_lock.dart';
import '../storage/event_log.dart';
import '../upload/apps_script_uploader.dart';
import '../upload/batch_upload.dart';
import 'm3e/expressive_shape.dart';

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
  late final TextEditingController _spreadsheetId;
  late final TextEditingController _uploadUrl;
  late final TextEditingController _uploadToken;

  String? _status;
  bool _busy = false;
  bool _showPin = false;
  bool _showToken = false;
  bool _showHistory = false;
  Future<List<EventRecord>>? _operationHistory;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    _stationId = TextEditingController(text: config.stationId);
    _stationName = TextEditingController(text: config.stationName);
    _pin = TextEditingController(text: config.pin);
    _spreadsheetId = TextEditingController(text: config.spreadsheetId);
    _uploadUrl = TextEditingController(text: config.uploadUrl);
    _uploadToken = TextEditingController(text: config.uploadToken);
  }

  @override
  void dispose() {
    for (final c in [
      _stationId,
      _stationName,
      _pin,
      _spreadsheetId,
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
    // Only the character set is checked here. An empty field still falls back
    // to the placeholder id below, as it always has.
    final stationId = _stationId.text.trim();
    if (stationId.isNotEmpty) {
      final stationIdError = StationSetupValidator.validateStationId(stationId);
      if (stationIdError != null) {
        setState(() => _status = stationIdError);
        return;
      }
    }
    final spreadsheetId = _spreadsheetId.text.trim();
    final uploadUrl = _uploadUrl.text.trim();
    final uploadToken = _uploadToken.text.trim();
    final hasAnyCloudValue =
        spreadsheetId.isNotEmpty ||
        uploadUrl.isNotEmpty ||
        uploadToken.isNotEmpty;
    if (hasAnyCloudValue &&
        (spreadsheetId.isEmpty || uploadUrl.isEmpty || uploadToken.isEmpty)) {
      setState(() => _status = '雲端設定必須同時填寫試算表 ID、正式網址與上傳金鑰');
      return;
    }
    if (spreadsheetId.isNotEmpty &&
        !RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(spreadsheetId)) {
      setState(() => _status = 'Google 試算表 ID 格式不正確');
      return;
    }
    if (uploadUrl.isNotEmpty &&
        !RegExp(
          r'^https://script\.google\.com/macros/s/[^/]+/exec$',
        ).hasMatch(uploadUrl)) {
      setState(() => _status = '請填入以 /exec 結尾的 Apps Script 正式網址');
      return;
    }
    final current = widget.controller.config;
    await widget.controller.updateConfig(
      current.copyWith(
        stationId: stationId.isEmpty ? 'CP1' : stationId,
        stationName: _stationName.text.trim().isEmpty
            ? '未命名站點'
            : _stationName.text.trim(),
        pin: pin,
        spreadsheetId: spreadsheetId,
        uploadUrl: uploadUrl,
        uploadToken: uploadToken,
      ),
    );
    setState(() => _status = '設定已儲存');
  }

  Future<void> _export() async {
    final chosen = await getDirectoryPath(confirmButtonText: '選擇並匯出');
    if (chosen == null) return;

    setState(() {
      _busy = true;
      _status = '正在匯出到 $chosen…';
    });
    try {
      final dir = await widget.controller.store.exportAll(Directory(chosen));
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
        detail: {'target': chosen, 'error': '$e'},
      );
      setState(() => _status = '匯出失敗:$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final cloudConfig = widget.controller.config;
    if (!cloudConfig.hasCompleteCloudConfig) {
      setState(() => _status = 'cloud.config 不完整，請確認試算表 ID、正式網址與上傳金鑰');
      return;
    }
    final url = cloudConfig.uploadUrl.trim();
    setState(() {
      _busy = true;
      _status = '上傳中…';
    });
    try {
      final operationHistory = await widget.controller.events.history();
      final client = http.Client();
      late final BatchUploadResult result;
      try {
        result = await BatchUpload(
          uploader: AppsScriptUploader(client),
          cursors: widget.controller.uploadCursors,
        ).run(
          endpoint: Uri.parse(url),
          apiKey: cloudConfig.uploadToken.trim(),
          spreadsheetId: cloudConfig.spreadsheetId.trim(),
          stationId: cloudConfig.stationId,
          stationName: cloudConfig.stationName,
          scans: widget.controller.store.toJsonList(),
          // `history` is newest first; the cursor counts in written order.
          operations: operationHistory.reversed
              .map((event) => event.toJson())
              .toList(),
          onProgress: (progress) {
            if (!mounted) return;
            setState(
              () => _status =
                  '上傳中… ${progress.sentScans}/${progress.scansToSend} 筆紀錄'
                  '(第 ${progress.batches} 批)',
            );
          },
        );
      } finally {
        client.close();
      }
      await widget.controller.events.record(
        EventType.uploadRun,
        stationId: widget.controller.config.stationId,
        detail: {
          // Host only: the full URL can carry a query-string secret.
          'host': Uri.parse(url).host,
          'status': result.statusCode,
          'records': widget.controller.store.totalLines,
          'sent_scans': result.sentScans,
          'sent_operations': result.sentOperations,
          'batches': result.batches,
          'accepted': result.accepted,
          'duplicates': result.duplicates,
          'error': ?result.error,
        },
      );
      setState(() => _status = _uploadStatus(result));
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

  /// A partial run is deliberately not reported as a failure. Its batches did
  /// reach the sheet and were recorded, so the operator needs to know pressing
  /// upload again continues rather than starts over.
  static String _uploadStatus(BatchUploadResult result) {
    if (result.ok) {
      if (result.nothingToSend) return '雲端已是最新,沒有新紀錄需要上傳';
      return '上傳成功:${result.accepted} 筆新增、${result.duplicates} 筆略過'
          '(送出 ${result.sentScans} 筆紀錄,分 ${result.batches} 批)';
    }
    final reason = result.error ?? 'HTTP ${result.statusCode}';
    if (!result.isPartial) return '上傳失敗:$reason';
    return '上傳中斷:$reason。已完成 ${result.sentScans}/${result.scansToSend} '
        '筆紀錄並記住進度,再按一次可從中斷處繼續';
  }

  Future<void> _pickFolder() async {
    final chosen = await getDirectoryPath(
      confirmButtonText: '選擇',
      initialDirectory: widget.controller.store.extraDir?.path,
    );
    if (chosen == null) return;

    setState(() {
      _busy = true;
      _status = '正在複製既有紀錄到 $chosen…';
    });
    final problem = await widget.controller.changeStorage(extraDir: chosen);
    setState(() {
      _busy = false;
      _status = problem ?? '額外備份已設定,既有紀錄已複製到 $chosen';
    });
  }

  Future<void> _resetFolder() async {
    setState(() => _busy = true);
    final problem = await widget.controller.changeStorage(extraDir: '');
    setState(() {
      _busy = false;
      _status = problem ?? '已取消額外備份';
    });
  }

  Future<void> _importIdMapping() async {
    final chosen = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ID 對照表', extensions: ['csv', 'tsv', 'json']),
      ],
    );
    if (chosen == null) return;

    setState(() => _busy = true);
    try {
      final count = await widget.controller.importIdMapping(File(chosen.path));
      if (!mounted) return;
      setState(() => _status = 'ID 對照表已匯入，共 $count 筆');
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _status = '對照表格式不正確：${error.message}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '無法匯入對照表：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearIdMapping() async {
    setState(() => _busy = true);
    try {
      await widget.controller.clearIdMapping();
      if (!mounted) return;
      setState(() => _status = '已移除 ID 對照表，刷卡時會顯示原始 ID');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '無法移除對照表：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.12),
          ),
        ),
      ),
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
          const SizedBox(height: 10),
          _pathBox(path),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
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

  void _openHistory() {
    setState(() {
      _showHistory = true;
      _operationHistory = widget.controller.events.history();
    });
  }

  void _closeHistory() {
    setState(() => _showHistory = false);
  }

  Widget _buildHistory(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scans = widget.controller.scanHistory;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          toolbarHeight: 72,
          backgroundColor: scheme.surface.withValues(alpha: 0.96),
          foregroundColor: scheme.onSurface,
          title: Row(
            children: [
              ExpressiveShape(
                size: 42,
                color: scheme.primary,
                sides: 7,
                rounding: 0.55,
                child: Icon(
                  Icons.history_rounded,
                  size: 21,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '歷史紀錄',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '掃描紀錄與系統操作',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            FilledButton.tonalIcon(
              onPressed: _closeHistory,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('返回設定'),
            ),
            const SizedBox(width: 20),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: '掃描紀錄（${scans.length}）'),
              const Tab(text: '操作紀錄'),
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: const Alignment(0, -0.3),
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.25),
                scheme.surface,
              ],
            ),
          ),
          child: TabBarView(
            children: [
              _scanHistoryList(scans),
              FutureBuilder<List<EventRecord>>(
                future: _operationHistory,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _historyEmpty(
                      Icons.error_outline_rounded,
                      '無法讀取操作紀錄',
                    );
                  }
                  final records = snapshot.data ?? const <EventRecord>[];
                  return _operationHistoryList(records);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanHistoryList(List<ScanRecord> records) {
    if (records.isEmpty) {
      return _historyEmpty(Icons.nfc_rounded, '尚無掃描紀錄');
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final record = records[index];
            final label = widget.controller.labelForCard(record.cardId);
            return _historyCard(
              icon: record.isDuplicate
                  ? Icons.history_rounded
                  : Icons.check_rounded,
              title: label ?? record.cardId,
              subtitle:
                  '${_formatDateTime(record.at)} · ${record.stationId} ${record.stationName}',
              detail: label == null
                  ? '第 ${record.sequence} 筆'
                  : '原始 ID：${record.cardId} · 第 ${record.sequence} 筆',
              badge: record.isDuplicate ? '重複' : '有效',
              isWarning: record.isDuplicate,
              monospaceTitle: label == null,
            );
          },
        ),
      ),
    );
  }

  Widget _operationHistoryList(List<EventRecord> records) {
    if (records.isEmpty) {
      return _historyEmpty(Icons.receipt_long_rounded, '尚無操作紀錄');
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final record = records[index];
            final detail = record.detail.isEmpty
                ? null
                : jsonEncode(record.detail);
            return _historyCard(
              icon: _eventIcon(record.type),
              title: _eventLabel(record.type),
              subtitle:
                  '${_formatDateTime(record.at)}'
                  '${record.stationId == null ? '' : ' · ${record.stationId}'}',
              detail: detail,
              isWarning:
                  record.type == 'scan_fail' ||
                  record.type == 'admin_pin_rejected' ||
                  record.type == 'write_error',
            );
          },
        ),
      ),
    );
  }

  Widget _historyCard({
    required IconData icon,
    required String title,
    required String subtitle,
    String? detail,
    String? badge,
    bool isWarning = false,
    bool monospaceTitle = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isWarning ? scheme.tertiary : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.16),
            foregroundColor: accent,
            child: Icon(icon, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        title,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: monospaceTitle ? 'monospace' : null,
                        ),
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: ShapeDecoration(
                          color: accent.withValues(alpha: 0.14),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 9),
                  SelectableText(
                    detail,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyEmpty(IconData icon, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            message,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _eventLabel(String type) => switch (type) {
    'app_start' => '程式啟動',
    'app_exit' => '程式離開',
    'scan_ok' => '掃描成功',
    'scan_duplicate' => '重複刷卡',
    'scan_fail' => '掃描失敗',
    'admin_unlock' => '管理員解鎖',
    'admin_pin_rejected' => 'PIN 驗證失敗',
    'admin_exit' => '返回掃描畫面',
    'config_change' => '設定變更',
    'storage_change' => '儲存位置變更',
    'export' => '匯出紀錄',
    'upload' => '雲端上傳',
    'id_mapping_change' => 'ID 對照表變更',
    'write_error' => '寫入錯誤',
    _ => type,
  };

  IconData _eventIcon(String type) => switch (type) {
    'app_start' => Icons.play_arrow_rounded,
    'app_exit' => Icons.stop_rounded,
    'scan_ok' => Icons.check_rounded,
    'scan_duplicate' => Icons.history_rounded,
    'scan_fail' => Icons.error_outline_rounded,
    'admin_unlock' => Icons.lock_open_rounded,
    'admin_pin_rejected' => Icons.gpp_bad_rounded,
    'admin_exit' => Icons.arrow_back_rounded,
    'config_change' => Icons.tune_rounded,
    'storage_change' => Icons.storage_rounded,
    'export' => Icons.folder_zip_rounded,
    'upload' => Icons.cloud_upload_rounded,
    'id_mapping_change' => Icons.badge_outlined,
    'write_error' => Icons.warning_amber_rounded,
    _ => Icons.info_outline_rounded,
  };
  Future<void> _backToKiosk() async {
    // Drop the text input client before returning, otherwise the IME stays
    // attached and the next card scan would be routed through it.
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.controller.returnToKiosk();
  }

  @override
  Widget build(BuildContext context) {
    if (_showHistory) return _buildHistory(context);

    final c = widget.controller;
    final store = c.store;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: scheme.surface.withValues(alpha: 0.96),
        foregroundColor: scheme.onSurface,
        title: Row(
          children: [
            ExpressiveShape(
              size: 42,
              color: scheme.primary,
              sides: 7,
              rounding: 0.55,
              child: Icon(
                Icons.tune_rounded,
                size: 21,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '掃描站管理台',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  '站點設定與資料管理',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _backToKiosk,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('返回掃描畫面'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, -0.3),
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.25),
              scheme.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
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
                _section(
                  '本站概況',
                  [
                    _metricGrid(c),
                    const SizedBox(height: 16),
                    _kv('設定來源', c.configSource),
                    if (store.lastWriteError != null)
                      _kv('寫入警告', store.lastWriteError!),
                    if (KioskLock.nativeError != null)
                      _kv('鎖定狀態', KioskLock.nativeError!),
                    if (TonePlayer.unavailableReason != null)
                      _kv('音效狀態', TonePlayer.unavailableReason!),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _openHistory,
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('顯示歷史紀錄'),
                    ),
                  ],
                  headerActions: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.folder_zip_rounded),
                      label: const Text('匯出站點紀錄'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _upload,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('上傳到雲端'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _section('站點設定', [
                  _field('站點編號', _stationId, hint: 'CP3'),
                  _field('站點名稱', _stationName, hint: '水源地'),
                  _field('管理 PIN(僅數字)', _pin),
                  _field('Google 試算表 ID', _spreadsheetId),
                  _field(
                    'Apps Script 正式網址',
                    _uploadUrl,
                    hint: 'https://…/exec',
                  ),
                  _field('雲端上傳金鑰', _uploadToken),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('儲存設定'),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _section('ID 對照表', [
                  Text(
                    '匯入後，刷卡成功畫面會以自訂文字取代原始 ID；掃描紀錄、匯出、上傳與計分仍保留原始 ID。支援含 id、text 標題的 UTF-8 CSV／TSV，或 JSON。',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _kv(
                    '已載入',
                    c.idMappingCount == 0 ? '未設定' : '${c.idMappingCount} 筆',
                  ),
                  _kv('檔案位置', c.idMappingPath),
                  if (c.idMappingWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        c.idMappingWarning!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _importIdMapping,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('匯入對照表'),
                      ),
                      if (c.idMappingCount > 0)
                        TextButton.icon(
                          onPressed: _busy ? null : _clearIdMapping,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('移除對照表'),
                        ),
                    ],
                  ),
                ]),
                const SizedBox(height: 24),
                _section('儲存位置', [
                  _kv('① EXE 主記錄（固定）', store.primaryDir.path),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 10),
                    child: Text(
                      '位於 scan_point.exe 同層的 data 資料夾，作為日常讀取與匯出的主記錄。',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                  _kv('② AppData 常駐紀錄（固定）', store.archiveDir.path),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 16),
                    child: Text(
                      '持續同步追加完整紀錄且不會自動清空；正常啟動不讀取，也不會自動還原到主記錄。',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                  _folderRow(
                    label: '③ 額外備份（例如隨身碟）',
                    path:
                        store.extraDirFor(c.config.stationId)?.path ??
                        '未設定 — 只寫上面兩份',
                    isCustom: c.config.extraDir.trim().isNotEmpty,
                    onPick: _pickFolder,
                    onReset: _resetFolder,
                    resetLabel: '取消額外備份',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 16),
                    child: Text(
                      '額外備份不會取代前兩份；設定時會複製既有紀錄，之後持續即時寫入。'
                      '每個站點使用獨立子資料夾，因此可共用同一支隨身碟。',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _section('離開', [
                  Text(
                    '離開後畫面鎖定會解除,現場請務必重新啟動程式。',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
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
          ),
        ),
      ),
    );
  }

  Widget _metricGrid(AppController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _metric(
                Icons.flag_rounded,
                '有效紀錄',
                '${controller.recordedCount}',
                '不含重複刷卡',
              ),
            ),
            SizedBox(
              width: width,
              child: _metric(
                Icons.receipt_long_rounded,
                '總紀錄行數',
                '${controller.store.totalLines}',
                '包含重複刷卡',
              ),
            ),
            SizedBox(
              width: width,
              child: _metric(
                Icons.shield_rounded,
                '即時副本',
                controller.config.extraDir.trim().isEmpty ? '2' : '3',
                controller.config.extraDir.trim().isEmpty
                    ? 'EXE 主檔與 AppData 常駐紀錄'
                    : '包含額外備份',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _metric(IconData icon, String label, String value, String caption) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Row(
        children: [
          ExpressiveShape(
            size: 52,
            color: scheme.secondaryContainer,
            sides: 6,
            rounding: 0.58,
            child: Icon(icon, color: scheme.onSecondaryContainer, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 25,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  caption,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pathBox(String path) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: SelectableText(
        path,
        style: TextStyle(
          color: scheme.onSurface,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<Widget> children, {
    List<Widget> headerActions = const [],
  }) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, subtitle) = switch (title) {
      '本站概況' => (Icons.monitor_heart_rounded, '即時紀錄、匯出與雲端上傳'),
      '站點設定' => (Icons.tune_rounded, '站點識別、管理密碼與雲端上傳'),
      'ID 對照表' => (Icons.badge_outlined, '將原始卡號換成現場可辨識的文字'),
      '儲存位置' => (Icons.storage_rounded, '固定副本與額外備份位置'),
      '離開' => (Icons.power_settings_new_rounded, '解除現場保護並關閉程式'),
      _ => (Icons.settings_rounded, ''),
    };
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveShape(
                size: 48,
                color: scheme.secondaryContainer,
                sides: 7,
                rounding: 0.58,
                rotation: 0.01,
                child: Icon(icon, color: scheme.onSecondaryContainer, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (headerActions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: headerActions,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
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
  }) {
    final isPin = identical(controller, _pin);
    final isToken = identical(controller, _uploadToken);
    final obscure = (isPin && !_showPin) || (isToken && !_showToken);
    final icon = switch (label) {
      '站點編號' => Icons.tag_rounded,
      '站點名稱' => Icons.place_rounded,
      '管理 PIN(僅數字)' => Icons.lock_rounded,
      'Google 試算表 ID' => Icons.table_chart_rounded,
      'Apps Script 正式網址' => Icons.link_rounded,
      '雲端上傳金鑰' => Icons.key_rounded,
      _ => Icons.edit_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: isPin ? TextInputType.number : TextInputType.text,
        enableSuggestions: !isPin && !isToken,
        autocorrect: !isPin && !isToken,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: isPin ? '至少 4 位數字' : null,
          prefixIcon: Icon(icon),
          suffixIcon: !isPin && !isToken
              ? null
              : IconButton(
                  onPressed: () => setState(() {
                    if (isPin) {
                      _showPin = !_showPin;
                    } else {
                      _showToken = !_showToken;
                    }
                  }),
                  tooltip: obscure ? '顯示' : '隱藏',
                  icon: Icon(
                    obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
