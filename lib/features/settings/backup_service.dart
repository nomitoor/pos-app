import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/database_helper.dart';
import '../bills/providers/bills_provider.dart';
import '../inventory/providers/inventory_provider.dart';
import 'providers/settings_provider.dart';

/// When the last backup (cloud or file) was made; null if never.
final lastBackupProvider = FutureProvider<DateTime?>((ref) async {
  // Re-read whenever a backup completes, including background ones.
  void refresh() => ref.invalidateSelf();
  BackupService.changed.addListener(refresh);
  ref.onDispose(() => BackupService.changed.removeListener(refresh));

  final settings = await DatabaseHelper.instance.getSettings();
  final raw = settings[BackupService.lastBackupKey];
  return raw == null ? null : DateTime.tryParse(raw);
});

class BackupService {
  static const lastBackupKey = 'last_backup_at';

  /// Bumped after every backup so [lastBackupProvider] refreshes.
  static final changed = ValueNotifier<int>(0);

  /// Asks where to save a backup of all data. Returns false if cancelled.
  static Future<bool> export(WidgetRef ref) async {
    final data = await DatabaseHelper.instance.exportAll();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent(' ').convert(data)),
    );
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());

    final uri = await FilePicker.saveFile(
      fileName: 'pos_backup_$stamp.json',
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: 'Save backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (uri == null) return false;

    await DatabaseHelper.instance.saveSettings({
      lastBackupKey: DateTime.now().toIso8601String(),
    });
    changed.value++;
    return true;
  }

  /// Lets the user pick a backup file. Returns its parsed content, or null
  /// if cancelled. Throws [FormatException] if it isn't a backup file.
  static Future<Map<String, dynamic>?> pickBackup() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose backup file',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != DatabaseHelper.backupFormat) {
      throw const FormatException('This is not a POS app backup file.');
    }
    return decoded;
  }

  /// Replaces all data with [backup] and refreshes every screen.
  static Future<void> restore(
    WidgetRef ref,
    Map<String, dynamic> backup,
  ) async {
    await DatabaseHelper.instance.restoreAll(backup);
    ref.invalidate(inventoryProvider);
    ref.invalidate(designsProvider);
    ref.invalidate(billsProvider);
    ref.invalidate(shopSettingsProvider);
    ref.invalidate(lastBackupProvider);
  }

  /// Short summary ("12 products, 340 bills, saved 3 Nov 2026") for the
  /// restore confirmation.
  static String describe(Map<String, dynamic> backup) {
    final tables = (backup['tables'] as Map?) ?? const {};
    int count(String t) => (tables[t] as List?)?.length ?? 0;
    final at = DateTime.tryParse(backup['exported_at'] as String? ?? '');
    return '${count('products')} products, ${count('bills')} bills'
        '${at == null ? '' : ', saved ${DateFormat('d MMM yyyy, h:mm a').format(at)}'}';
  }
}
