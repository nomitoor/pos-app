import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/config/supabase_config.dart';
import '../../core/theme/app_theme.dart';
import 'online_store_service.dart';

/// Settings card: are we the store owner, when did the catalogue last
/// sync, and a "Sync now" button.
class OnlineStoreStatus extends ConsumerWidget {
  const OnlineStoreStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!SupabaseConfig.isConfigured) return const SizedBox.shrink();
    final owner = ref.watch(shopOwnerProvider);
    final sync = ref.watch(catalogSyncProvider);

    final (
      IconData icon,
      Color color,
      String title,
      String detail,
    ) = switch (owner) {
      AsyncLoading() => (
        Icons.hourglass_empty,
        AppTheme.muted,
        'Checking…',
        '',
      ),
      AsyncData(value: true) => switch (sync.state) {
        SyncState.syncing => (Icons.sync, AppTheme.brand, 'Syncing…', ''),
        SyncState.error => (
          Icons.sync_problem,
          Color(0xFFA8432F),
          'Sync failed',
          sync.message ?? '',
        ),
        _ => (
          Icons.cloud_done,
          const Color(0xFF4E7448),
          'In sync',
          [
            if (sync.message != null) sync.message!,
            if (sync.lastSynced != null)
              'last ${DateFormat('h:mm a').format(sync.lastSynced!)}',
          ].join(' · '),
        ),
      },
      AsyncData(value: false) => (
        Icons.block,
        Color(0xFFB07A1E),
        'Not the store owner',
        'Another account owns this online store.',
      ),
      _ => (
        Icons.cloud_off,
        AppTheme.muted,
        'Not connected',
        'Sign in above. If you just set up Supabase, run supabase/store.sql.',
      ),
    };

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('Online store · $title'),
        subtitle: detail.isEmpty ? null : Text(detail),
        trailing: owner.value == true
            ? TextButton(
                onPressed: sync.state == SyncState.syncing
                    ? null
                    : () => ref.read(catalogSyncProvider.notifier).syncNow(),
                child: const Text('Sync now'),
              )
            : null,
      ),
    );
  }
}
