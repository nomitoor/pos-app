import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/database/database_helper.dart';
import '../../models/design.dart';
import '../inventory/providers/inventory_provider.dart';
import '../settings/cloud_backup_service.dart';

/// Whether the signed-in account owns the online store (null = signed out
/// or not set up). Re-checked whenever the user signs in or out.
final shopOwnerProvider = FutureProvider<bool?>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null || !SupabaseConfig.isConfigured) return null;
  try {
    // First account to call this becomes the owner; later calls just
    // report whether we are.
    return await Supabase.instance.client.rpc('claim_shop') as bool;
  } catch (e) {
    debugPrint('claim_shop failed (store.sql not run yet?): $e');
    return null;
  }
});

enum SyncState { idle, syncing, done, error }

class SyncStatus {
  final SyncState state;
  final DateTime? lastSynced;
  final String? message;
  const SyncStatus(this.state, {this.lastSynced, this.message});
}

class OnlineStoreService {
  static const photosBucket = 'product-photos';

  static SupabaseClient get _client => Supabase.instance.client;

  // ─── Photos ───────────────────────────────────────────────

  /// Takes or picks a photo, shrinks it for the web and uploads it.
  /// Returns its public URL, or null if the user cancelled.
  static Future<String?> addPhoto(int designId, ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final path =
        'designs/$designId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage
        .from(photosBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '31536000',
          ),
        );
    return _client.storage.from(photosBucket).getPublicUrl(path);
  }

  /// Deletes an uploaded photo by its public URL (ignores failures).
  static Future<void> deletePhoto(String url) async {
    final marker = '/$photosBucket/';
    final i = url.indexOf(marker);
    if (i < 0) return;
    try {
      await _client.storage.from(photosBucket).remove([
        url.substring(i + marker.length),
      ]);
    } catch (e) {
      debugPrint('Photo delete failed: $e');
    }
  }

  // ─── Catalogue sync ───────────────────────────────────────

  /// Pushes every design and size (with current stock) to the online
  /// store, and removes ones deleted in the POS. The POS is the master.
  static Future<int> pushCatalog() async {
    final db = DatabaseHelper.instance;
    final designs = await db.getDesigns();
    final products = await db.getAllProducts();
    final now = DateTime.now().toUtc().toIso8601String();

    final designRows = [
      for (final d in designs)
        {
          'id': d.id,
          'name': d.name,
          'type': d.type,
          'description': d.description,
          'price': d.price,
          'photos': d.photos,
          'online': d.online,
          'updated_at': now,
        },
    ];
    final variantRows = [
      for (final p in products)
        if (p.designId != null)
          {
            'id': p.id,
            'design_id': p.designId,
            'size': p.size,
            'price': p.price,
            'stock': p.quantity,
            'updated_at': now,
          },
    ];

    if (designRows.isNotEmpty) {
      await _client.from('catalog_designs').upsert(designRows);
    }
    if (variantRows.isNotEmpty) {
      await _client.from('catalog_variants').upsert(variantRows);
    }

    // Remove what no longer exists locally.
    final designIds = designs.map((d) => d.id).toList();
    final variantIds = [for (final r in variantRows) r['id']];
    await _client
        .from('catalog_variants')
        .delete()
        .not('id', 'in', variantIds.isEmpty ? [-1] : variantIds);
    await _client
        .from('catalog_designs')
        .delete()
        .not('id', 'in', designIds.isEmpty ? [-1] : designIds);

    return designs.where((d) => d.online).length;
  }
}

/// Keeps the online store in step with the POS: pushes the catalogue a few
/// seconds after any product, size or stock change (and once at start),
/// while the owner is signed in. Watch it once (MainShell) to activate.
final catalogSyncProvider = NotifierProvider<CatalogSyncNotifier, SyncStatus>(
  CatalogSyncNotifier.new,
);

class CatalogSyncNotifier extends Notifier<SyncStatus> {
  Timer? _debounce;

  @override
  SyncStatus build() {
    ref.onDispose(() => _debounce?.cancel());
    ref.listen(inventoryProvider, (_, next) {
      if (next.hasValue) schedule();
    });
    ref.listen(designsProvider, (_, next) {
      if (next.hasValue) schedule();
    });
    ref.listen(shopOwnerProvider, (_, next) {
      if (next.value == true) schedule(delay: Duration.zero);
    });
    return const SyncStatus(SyncState.idle);
  }

  void schedule({Duration delay = const Duration(seconds: 4)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    if (!SupabaseConfig.isConfigured) return;
    final owner = ref.read(shopOwnerProvider).value;
    if (owner != true) return; // signed out, or not the shop owner
    if (state.state == SyncState.syncing) {
      schedule(); // try again after this run
      return;
    }
    state = SyncStatus(SyncState.syncing, lastSynced: state.lastSynced);
    try {
      final online = await OnlineStoreService.pushCatalog();
      state = SyncStatus(
        SyncState.done,
        lastSynced: DateTime.now(),
        message: '$online product${online == 1 ? '' : 's'} online',
      );
    } catch (e) {
      state = SyncStatus(
        SyncState.error,
        lastSynced: state.lastSynced,
        message: '$e',
      );
    }
  }
}

/// Convenience for screens: does this design have what the store needs?
String? onlineReadinessIssue(DesignGroup g) {
  if (g.design.photos.isEmpty) return 'Add at least one photo';
  if (g.totalStock <= 0) return 'All sizes are sold out';
  return null;
}
