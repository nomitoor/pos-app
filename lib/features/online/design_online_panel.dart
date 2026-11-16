import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import '../../core/theme/app_theme.dart';
import '../../models/design.dart';
import '../inventory/providers/inventory_provider.dart';
import 'online_store_service.dart';

/// Photos + "show on online store" switch for one design.
class DesignOnlinePanel extends ConsumerStatefulWidget {
  final DesignGroup group;
  const DesignOnlinePanel({super.key, required this.group});

  @override
  ConsumerState<DesignOnlinePanel> createState() => _DesignOnlinePanelState();
}

class _DesignOnlinePanelState extends ConsumerState<DesignOnlinePanel> {
  bool _uploading = false;

  Design get d => widget.group.design;

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? Color(0xFFA8432F) : null,
        ),
      );

  Future<void> _add(ImageSource source) async {
    setState(() => _uploading = true);
    try {
      final url = await OnlineStoreService.addPhoto(d.id!, source);
      if (url != null) {
        await ref
            .read(designsProvider.notifier)
            .updateDetails(d.copyWith(photos: [...d.photos, url]));
      }
    } catch (e) {
      if (mounted) _snack('Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != null) await _add(source);
  }

  Future<void> _remove(String url) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFFA8432F)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(designsProvider.notifier)
        .updateDetails(
          d.copyWith(photos: d.photos.where((p) => p != url).toList()),
        );
    await OnlineStoreService.deletePhoto(url);
  }

  /// Moves a photo to the front (the main photo on the website).
  Future<void> _makeMain(String url) => ref
      .read(designsProvider.notifier)
      .updateDetails(
        d.copyWith(photos: [url, ...d.photos.where((p) => p != url)]),
      );

  Future<void> _toggleOnline(bool v) async {
    final issue = onlineReadinessIssue(widget.group);
    if (v && issue != null) {
      _snack(issue, error: true);
      return;
    }
    await ref
        .read(designsProvider.notifier)
        .updateDetails(d.copyWith(online: v));
    if (mounted) {
      _snack(
        v
            ? '${d.name} will appear on the online store'
            : '${d.name} removed from the online store',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(shopOwnerProvider);
    final isOwner = owner.value == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined, color: AppTheme.brand),
                const SizedBox(width: 8),
                Text(
                  'Online store',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (isOwner) Switch(value: d.online, onChanged: _toggleOnline),
              ],
            ),
            if (!isOwner)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  owner.isLoading
                      ? 'Checking…'
                      : owner.value == false
                      ? 'Another account owns this online store. Sign in '
                            'with the owner account to add photos.'
                      : 'Sign in under Settings → Cloud backup to add '
                            'photos and sell online.',
                  style: const TextStyle(color: AppTheme.muted),
                ),
              )
            else ...[
              Text(
                d.online
                    ? 'Shown on the website'
                    : onlineReadinessIssue(widget.group) ??
                          'Hidden from the website',
                style: TextStyle(
                  color: d.online ? const Color(0xFF4E7448) : AppTheme.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, url) in d.photos.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _remove(url),
                          onLongPress: i == 0 ? null : () => _makeMain(url),
                          child: _Thumb(url: url, main: i == 0),
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _uploading ? null : _pickSource,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppTheme.border,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _uploading
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    color: AppTheme.brand,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Add photo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.brand,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (d.photos.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Tap a photo to remove · long-press to make it the main one',
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final bool main;
  const _Thumb({required this.url, required this.main});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (context, e, s) => Container(
              width: 96,
              height: 96,
              color: AppTheme.border,
              child: const Icon(Icons.cloud_off, color: AppTheme.muted),
            ),
          ),
        ),
        if (main)
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Main',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}
