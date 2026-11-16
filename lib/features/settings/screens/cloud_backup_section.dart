import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../../../core/config/supabase_config.dart';
import '../cloud_backup_service.dart';

const _green = Color(0xFF4E7448);

/// Sign-in, "Back up now", restore list and auto-backup toggle.
class CloudBackupSection extends ConsumerStatefulWidget {
  /// Called after a successful restore so the parent can reload its form.
  final VoidCallback onRestored;
  const CloudBackupSection({super.key, required this.onRestored});

  @override
  ConsumerState<CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<CloudBackupSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Color(0xFFA8432F) : null,
      ),
    );
  }

  String _message(Object e) => e is AuthException ? e.message : '$e';

  /// Runs [action] with a spinner and error snackbar.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(_message(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validCredentials() {
    if (!_email.text.contains('@') || _password.text.length < 6) {
      _snack(
        'Enter an email and a password of at least 6 characters',
        error: true,
      );
      return false;
    }
    return true;
  }

  Future<void> _signIn() async {
    if (!_validCredentials()) return;
    await _run(() async {
      await CloudBackupService.signIn(_email.text.trim(), _password.text);
      _password.clear();
      _snack('Signed in. Backing up now…');
      await CloudBackupService.autoBackupIfDue(force: true);
    });
  }

  Future<void> _signUp() async {
    if (!_validCredentials()) return;
    await _run(() async {
      final ready = await CloudBackupService.signUp(
        _email.text.trim(),
        _password.text,
      );
      if (ready) {
        _password.clear();
        _snack('Account created. Backing up now…');
        await CloudBackupService.autoBackupIfDue(force: true);
      } else {
        _snack(
          'Check your email and open the confirmation link, '
          'then sign in here.',
        );
      }
    });
  }

  Future<void> _backupNow() => _run(() async {
    await CloudBackupService.backupNow();
    _snack('Backed up to the cloud');
  });

  Future<void> _restore() async {
    List<CloudBackup> backups = const [];
    await _run(() async => backups = await CloudBackupService.list());
    if (!mounted) return;
    if (backups.isEmpty) {
      _snack('No cloud backups yet');
      return;
    }

    final picked = await showModalBottomSheet<CloudBackup>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BackupPicker(backups: backups),
    );
    if (picked == null || !mounted) return;

    final when = picked.createdAt == null
        ? picked.name
        : DateFormat('d MMM yyyy, h:mm a').format(picked.createdAt!);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'Backup from $when.\n\n'
          'All products, bills and settings on this device will be replaced. '
          'A copy of your current data is uploaded first, so you can undo '
          'this by restoring the "Before restore" backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Restore',
              style: TextStyle(color: Color(0xFFA8432F)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _run(() async {
      await CloudBackupService.restore(ref, picked);
      widget.onRestored();
      _snack('Backup restored');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return const _InfoBox(
        icon: Icons.cloud_off,
        text:
            'Cloud backup is not set up. Add your Supabase URL and key to '
            '.env.prod (or .env.dev for the test app), then build with '
            '--dart-define-from-file pointing at that file.',
      );
    }

    final user = ref.watch(authUserProvider).value;
    return user == null ? _signedOut() : _signedIn(user.email ?? '');
  }

  Widget _signedOut() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sign in to back up automatically to the cloud. Use the same '
          'account on a new phone to get all your data back.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16171B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _signIn,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Sign in'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _signUp,
                child: const Text('Create account'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _signedIn(String email) {
    final auto = ref.watch(autoCloudBackupProvider).value ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_done, color: _green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                email,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(CloudBackupService.signOut),
              child: const Text('Sign out'),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatic daily backup'),
          subtitle: const Text(
            'Backs up once a day when the app opens or after a sale',
          ),
          value: auto,
          onChanged: _busy ? null : (v) => CloudBackupService.setAuto(ref, v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _backupNow,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload),
                label: const Text('Back up now'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Restore'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BackupPicker extends StatelessWidget {
  final List<CloudBackup> backups;
  const _BackupPicker({required this.backups});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE d MMM yyyy, h:mm a');
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choose a backup',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: backups.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final b = backups[i];
                  final size = b.sizeBytes == null
                      ? ''
                      : ' • ${(b.sizeBytes! / 1024).toStringAsFixed(0)} KB';
                  return ListTile(
                    leading: Icon(
                      b.isSafetyCopy ? Icons.history : Icons.cloud,
                      color: b.isSafetyCopy
                          ? Color(0xFFB07A1E)
                          : Color(0xFF16171B),
                    ),
                    title: Text(
                      b.createdAt == null ? b.name : fmt.format(b.createdAt!),
                    ),
                    subtitle: Text(
                      '${b.isSafetyCopy
                          ? 'Before restore'
                          : i == 0
                          ? 'Latest'
                          : 'Backup'}$size',
                    ),
                    onTap: () => Navigator.pop(context, b),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}
