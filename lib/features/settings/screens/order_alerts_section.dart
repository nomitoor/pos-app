import 'package:material_ui/material_ui.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../online/order_alerts.dart';

/// Settings → Online order alerts: allow notifications and send a test.
class OrderAlertsSection extends StatefulWidget {
  const OrderAlertsSection({super.key});

  @override
  State<OrderAlertsSection> createState() => _OrderAlertsSectionState();
}

class _OrderAlertsSectionState extends State<OrderAlertsSection> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = await OrderNotifications.allowed();
    if (mounted) setState(() => _allowed = a);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.danger : null,
      ),
    );
  }

  Future<void> _allow() async {
    final ok = await OrderNotifications.requestPermission();
    await _check();
    if (!mounted) return;
    if (!ok) {
      _snack(
        'Notifications are blocked. Turn them on for Urban Thread in your '
        'phone or browser settings.',
        error: true,
      );
    }
  }

  Future<void> _test() async {
    final ok = await OrderNotifications.test();
    if (!ok && mounted) _snack('Allow notifications first.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final supported = OrderNotifications.supported;
    final on = _allowed == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Text(
          'Online order alerts',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'A notification with sound when a customer orders online, while '
          'this app is open or recently used.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 12),
        Card(
          child: !SupabaseConfig.isConfigured || !supported
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    !SupabaseConfig.isConfigured
                        ? 'Set up the online store (Supabase) to get order alerts.'
                        : 'Order alerts work in the Android app and the browser.',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: Icon(
                        on
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        color: on ? AppTheme.success : AppTheme.muted,
                      ),
                      title: Text(
                        on ? 'Notifications are on' : 'Notifications are off',
                      ),
                      subtitle: Text(
                        on
                            ? "You'll be alerted about each new order."
                            : 'New orders will only show on the dashboard.',
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (!on)
                            FilledButton.icon(
                              onPressed: _allow,
                              icon: const Icon(Icons.notifications_outlined),
                              label: const Text('Allow notifications'),
                            ),
                          OutlinedButton.icon(
                            onPressed: on ? _test : null,
                            icon: const Icon(Icons.campaign_outlined),
                            label: const Text('Send test alert'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
