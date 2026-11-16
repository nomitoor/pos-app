import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../models/shop_settings.dart';
import '../providers/settings_provider.dart';
import '../backup_service.dart';
import 'cloud_backup_section.dart';
import 'receipt_printer_section.dart';
import 'order_alerts_section.dart';
import '../../online/online_store_status.dart';
import 'package:intl/intl.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _shopNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _taxController = TextEditingController();
  final _termsController = TextEditingController();
  final _footerController = TextEditingController();

  bool _loaded = false;
  bool _isSaving = false;
  String? _logoBase64;

  void _fillFrom(ShopSettings settings) {
    _shopNameController.text = settings.shopName;
    _addressController.text = settings.address;
    _phoneController.text = settings.phone;
    _emailController.text = settings.email;
    _taxController.text = settings.taxNumber;
    _termsController.text = settings.terms;
    _footerController.text = settings.footerMessage;
    _logoBase64 = settings.logoBase64;
  }

  Future<void> _pickLogo() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _logoBase64 = base64Encode(bytes));
    }
  }

  void _removeLogo() => setState(() => _logoBase64 = null);

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxController.dispose();
    _termsController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await ref
        .read(shopSettingsProvider.notifier)
        .save(
          ShopSettings(
            shopName: _shopNameController.text.trim().isEmpty
                ? 'Urban Thread'
                : _shopNameController.text.trim(),
            address: _addressController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            taxNumber: _taxController.text.trim(),
            terms: _termsController.text.trim(),
            footerMessage: _footerController.text.trim().isEmpty
                ? 'Thank you for your purchase!'
                : _footerController.text.trim(),
            logoBase64: _logoBase64,
          ),
        );
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invoice details saved')));
    }
  }

  bool _busy = false;

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Color(0xFFA8432F) : null,
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final saved = await BackupService.export(ref);
      if (saved && mounted) _snack('Backup saved');
    } catch (e) {
      if (mounted) _snack('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    Map<String, dynamic>? backup;
    try {
      backup = await BackupService.pickBackup();
    } catch (e) {
      if (mounted) _snack('$e', error: true);
      return;
    }
    if (backup == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          'This backup has ${BackupService.describe(backup!)}.\n\n'
          'ALL current products, bills and settings on this device will be '
          'replaced. This cannot be undone. Consider saving a backup first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Replace everything',
              style: TextStyle(color: Color(0xFFA8432F)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupService.restore(ref, backup);
      _loaded = false; // refill the form from the restored settings
      if (mounted) _snack('Backup restored');
    } catch (e) {
      if (mounted) {
        _snack('Restore failed, nothing was changed: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _backupSection() {
    final last = ref.watch(lastBackupProvider).value;
    final stale = last == null || DateTime.now().difference(last).inDays >= 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 48),
        const Text(
          'Backup & Restore',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          last == null
              ? 'No backup saved yet.'
              : 'Last backup: ${DateFormat('d MMM yyyy, h:mm a').format(last)}',
          style: TextStyle(
            color: stale ? Color(0xFF8A5F17) : Colors.grey,
            fontWeight: stale ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 16),

        // ── Cloud (Supabase) ──
        const Row(
          children: [
            Icon(Icons.cloud, color: Color(0xFF16171B), size: 20),
            SizedBox(width: 6),
            Text(
              'Cloud backup',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CloudBackupSection(onRestored: () => setState(() => _loaded = false)),
        const SizedBox(height: 12),
        const OnlineStoreStatus(),

        // ── File (secondary) ──
        const SizedBox(height: 20),
        const Text(
          'Backup file',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Optional: save or load a backup as a file on this device.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _exportBackup,
                icon: const Icon(Icons.save_alt),
                label: const Text('Export file'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restoreBackup,
                icon: const Icon(Icons.file_open),
                label: const Text('Import file'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(shopSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          if (!_loaded) {
            _fillFrom(settings);
            _loaded = true;
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invoice Template',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'These details appear on every printed receipt.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Logo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _logoBase64 == null
                          ? const Icon(Icons.image_outlined, color: Colors.grey)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(_logoBase64!),
                                fit: BoxFit.contain,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _pickLogo,
                      child: Text(_logoBase64 == null ? 'Upload' : 'Replace'),
                    ),
                    if (_logoBase64 != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _removeLogo,
                        child: const Text(
                          'Remove',
                          style: TextStyle(color: Color(0xFFA8432F)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _field('Shop Name', _shopNameController, Icons.storefront),
                const SizedBox(height: 16),
                _field(
                  'Address',
                  _addressController,
                  Icons.location_on,
                  hint: 'Optional',
                ),
                const SizedBox(height: 16),
                _field(
                  'Phone',
                  _phoneController,
                  Icons.phone,
                  hint: 'Optional',
                ),
                const SizedBox(height: 16),
                _field(
                  'Email',
                  _emailController,
                  Icons.email,
                  hint: 'Optional',
                ),
                const SizedBox(height: 16),
                _field(
                  'Tax number (NTN / STRN)',
                  _taxController,
                  Icons.badge,
                  hint: 'Optional, e.g. NTN 1234567-8',
                ),
                const SizedBox(height: 16),
                _field(
                  'Terms & conditions',
                  _termsController,
                  Icons.gavel,
                  hint:
                      'Optional, e.g. Exchange within 7 days with '
                      'receipt. No cash refund on sale items.',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _field(
                  'Receipt Footer Message',
                  _footerController,
                  Icons.message,
                  maxLines: 2,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16171B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Save', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const ReceiptPrinterSection(),
                const OrderAlertsSection(),
                _backupSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: Icon(icon),
          ),
        ),
      ],
    );
  }
}
