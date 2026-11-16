import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/database/database_helper.dart';
import 'backup_service.dart';

/// A backup file stored in Supabase.
class CloudBackup {
  final String path; // "<user id>/<file name>"
  final String name;
  final DateTime? createdAt;
  final int? sizeBytes;
  const CloudBackup(this.path, this.name, this.createdAt, this.sizeBytes);

  bool get isSafetyCopy => name.startsWith(CloudBackupService.safetyPrefix);
}

/// Emits whenever the user signs in or out.
final authUserProvider = StreamProvider<User?>((ref) {
  if (!SupabaseConfig.isConfigured) return Stream.value(null);
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange
      .map((e) => e.session?.user)
      .startWith(auth.currentUser);
});

/// Whether automatic daily backup is on (default: on).
final autoCloudBackupProvider = FutureProvider<bool>((ref) async {
  final s = await DatabaseHelper.instance.getSettings();
  return s[CloudBackupService.autoKey] != 'false';
});

class CloudBackupService {
  static const autoKey = 'auto_cloud_backup';
  static const lastCloudKey = 'last_cloud_backup_at';
  static const safetyPrefix = 'before-restore_';

  /// Backups kept per account; older ones are deleted after each upload.
  static const keep = 30;

  /// Minimum gap between automatic backups.
  static const autoInterval = Duration(hours: 24);

  static SupabaseClient get _client => Supabase.instance.client;
  static StorageFileApi get _bucket =>
      _client.storage.from(SupabaseConfig.bucket);

  static User? get user =>
      SupabaseConfig.isConfigured ? _client.auth.currentUser : null;

  // ─── Auth ───────────────────────────────────────────────

  static Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  /// Returns true if the account is ready, false if Supabase sent a
  /// confirmation email that must be opened first.
  static Future<bool> signUp(String email, String password) async {
    final res = await _client.auth.signUp(email: email, password: password);
    // Supabase answers "success" for an email that is already registered
    // (so strangers can't probe accounts) but sends no email and returns a
    // user with no identities. Say so instead of waiting for an email.
    if (res.session == null && (res.user?.identities?.isEmpty ?? false)) {
      throw const AuthException(
        'An account with this email already exists. Tap "Sign in" instead.',
      );
    }
    return res.session != null;
  }

  static Future<void> signOut() => _client.auth.signOut();

  // ─── Backup ─────────────────────────────────────────────

  static String _folder(User u) => u.id;

  /// Uploads all data. [prefix] marks special copies (e.g. pre-restore).
  static Future<void> backupNow({String prefix = ''}) async {
    final u = user;
    if (u == null) throw StateError('Sign in to back up to the cloud.');

    final data = await DatabaseHelper.instance.exportAll();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    await _bucket.uploadBinary(
      '${_folder(u)}/${prefix}pos_backup_$stamp.json',
      bytes,
      fileOptions: const FileOptions(
        contentType: 'application/json',
        upsert: true,
      ),
    );

    final now = DateTime.now().toIso8601String();
    await DatabaseHelper.instance.saveSettings({
      lastCloudKey: now,
      BackupService.lastBackupKey: now,
    });
    BackupService.changed.value++;
    await _prune(u);
  }

  /// Deletes all but the newest [keep] backups.
  static Future<void> _prune(User u) async {
    final all = await list();
    if (all.length <= keep) return;
    await _bucket.remove([for (final b in all.skip(keep)) b.path]);
  }

  /// This account's backups, newest first.
  static Future<List<CloudBackup>> list() async {
    final u = user;
    if (u == null) return const [];
    final files = await _bucket.list(
      path: _folder(u),
      searchOptions: const SearchOptions(
        limit: 1000,
        sortBy: SortBy(column: 'created_at', order: 'desc'),
      ),
    );
    return [
      for (final f in files)
        if (f.name.endsWith('.json'))
          CloudBackup(
            '${_folder(u)}/${f.name}',
            f.name,
            DateTime.tryParse(f.createdAt ?? '')?.toLocal(),
            (f.metadata?['size'] as num?)?.toInt(),
          ),
    ];
  }

  static Future<Map<String, dynamic>> download(CloudBackup b) async {
    final bytes = await _bucket.download(b.path);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != DatabaseHelper.backupFormat) {
      throw const FormatException('This is not a POS app backup file.');
    }
    return decoded;
  }

  /// Uploads a safety copy of the current data, then restores [b].
  static Future<void> restore(WidgetRef ref, CloudBackup b) async {
    final backup = await download(b);
    await backupNow(prefix: safetyPrefix);
    await BackupService.restore(ref, backup);
  }

  // ─── Automatic backup ──────────────────────────────────

  static Future<void>? _running;

  /// Backs up in the background if signed in, auto backup is on and the
  /// last cloud backup is older than [autoInterval] (or [force] is set).
  /// Never throws: failures are retried on the next call.
  static Future<void> autoBackupIfDue({bool force = false}) {
    return _running ??= _autoBackup(force).whenComplete(() => _running = null);
  }

  static Future<void> _autoBackup(bool force) async {
    try {
      if (user == null) return;
      final s = await DatabaseHelper.instance.getSettings();
      if (s[autoKey] == 'false') return;
      final last = DateTime.tryParse(s[lastCloudKey] ?? '');
      if (!force &&
          last != null &&
          DateTime.now().difference(last) < autoInterval) {
        return;
      }
      await backupNow();
    } catch (e) {
      debugPrint('Automatic cloud backup failed: $e');
    }
  }

  static Future<void> setAuto(WidgetRef ref, bool on) async {
    await DatabaseHelper.instance.saveSettings({
      autoKey: on ? 'true' : 'false',
    });
    ref.invalidate(autoCloudBackupProvider);
  }
}

extension<T> on Stream<T> {
  /// Emits [first] immediately, then this stream's events.
  Stream<T> startWith(T first) async* {
    yield first;
    yield* this;
  }
}
