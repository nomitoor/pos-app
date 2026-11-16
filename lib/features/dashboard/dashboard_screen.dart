import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/navigation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand.dart';
import '../../shared/widgets/thread.dart';
import '../billing/providers/held_bills_provider.dart';
import '../bills/providers/bills_provider.dart';
import '../customers/providers/customers_provider.dart';
import '../customers/screens/customers_screen.dart';
import '../day_close/screens/day_close_screen.dart';
import '../expenses/screens/expenses_screen.dart';
import '../insights/insights_data.dart';
import '../insights/insights_provider.dart';
import '../insights/screens/insights_screen.dart';
import '../inventory/providers/inventory_provider.dart';
import '../promotions/screens/promotions_screen.dart';
import '../online/online_orders.dart';
import '../online/screens/online_orders_screen.dart';
import '../settings/backup_service.dart';
import '../settings/providers/settings_provider.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _rs(double v) => 'Rs ${_money.format(v)}';

/// Content wider than this splits into two columns.
const _twoColumn = 760.0;

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopSettingsProvider).value?.shopName ?? '';
    final name = shop.isEmpty || shop == 'MY SHOP' ? Brand.name : shop;
    void tab(int i) => ref.read(navIndexProvider.notifier).state = i;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.ink,
          onRefresh: () async {
            ref.invalidate(billsProvider);
            ref.invalidate(inventoryProvider);
          },
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= _twoColumn;
              final pad = wide ? 40.0 : 16.0;

              final header = _Header(
                shopName: name,
                compact: !wide,
                onInsights: () => _push(context, const InsightsScreen()),
              );
              final todayTag = _TodayTag(
                onTap: () => _push(context, const InsightsScreen()),
              );
              const attention = _AttentionList();
              final shortcuts = _Shortcuts(onTab: tab);

              return ListView(
                padding: EdgeInsets.fromLTRB(pad, wide ? 32 : 16, pad, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: wide
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                header,
                                const SizedBox(height: 28),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 7,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          todayTag,
                                          const SizedBox(height: 32),
                                          attention,
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 32),
                                    Expanded(flex: 4, child: shortcuts),
                                  ],
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                header,
                                const SizedBox(height: 18),
                                todayTag,
                                const SizedBox(height: 28),
                                attention,
                                const SizedBox(height: 28),
                                shortcuts,
                              ],
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String shopName;
  final bool compact;
  final VoidCallback onInsights;
  const _Header({
    required this.shopName,
    required this.compact,
    required this.onInsights,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, d MMMM').format(DateTime.now());
    final t = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date,
                style: const TextStyle(color: AppTheme.muted, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: compact ? t.headlineSmall : t.headlineMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        compact
            ? IconButton.outlined(
                tooltip: 'Insights',
                onPressed: onInsights,
                style: IconButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  backgroundColor: AppTheme.surface,
                ),
                icon: const Icon(Icons.insights_rounded),
              )
            : OutlinedButton.icon(
                onPressed: onInsights,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                ),
                icon: const Icon(Icons.insights_rounded, size: 20),
                label: const Text('Insights'),
              ),
      ],
    );
  }
}

// ── Today, as a swing tag ──────────────────────────────────
class _TodayTag extends ConsumerWidget {
  final VoidCallback onTap;
  const _TodayTag({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(insightsProvider(InsightPeriod.today));

    return ClipPath(
      clipper: const _SwingTagClipper(),
      child: Material(
        color: AppTheme.ink,
        child: InkWell(
          onTap: onTap,
          focusColor: AppTheme.gold.withValues(alpha: 0.18),
          hoverColor: Colors.white.withValues(alpha: 0.03),
          splashColor: Colors.white.withValues(alpha: 0.06),
          child: LayoutBuilder(
            builder: (context, box) {
              // On narrow tags the threads stay above the figure so a long
              // total never runs into them.
              final narrow = box.maxWidth < 520;
              return Stack(
                children: [
                  // The logo's threads, running off the top-right corner.
                  Positioned(
                    right: -8,
                    top: narrow ? -14 : -18,
                    width: narrow ? 150 : 240,
                    height: narrow ? 56 : 120,
                    child: ExcludeSemantics(
                      child: ThreadStripes(
                        strokeWidth: narrow ? 4 : 6,
                        gap: narrow ? 3.5 : 5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _SwingTagClipper.bodyInset,
                      22,
                      22,
                      20,
                    ),
                    child: today.when(
                      loading: () => const SizedBox(
                        height: 168,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.gold,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      error: (e, _) => SizedBox(
                        height: 168,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Today's sales couldn't load: $e",
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      data: (d) => _body(d),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _body(Insights d) {
    final change = d.revenueChangePct;
    final best = d.bestSeller;
    const soft = Color(0xFFA9AAB0);

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTheme.figure(
                17,
                color: Colors.white,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: soft, fontSize: 13)),
        ],
      ),
    );

    Widget seam() => Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.only(right: 16),
      color: Colors.white.withValues(alpha: 0.12),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's sales",
          style: TextStyle(color: soft, fontSize: 14),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _rs(d.netRevenue),
            style: AppTheme.figure(42, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          change == null
              ? 'No sales yesterday to compare with'
              : '${change >= 0 ? 'Up' : 'Down'} ${change.abs().toStringAsFixed(0)}% on yesterday',
          style: TextStyle(
            color: change == null ? soft : AppTheme.gold,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            stat('Bills', '${d.billCount}'),
            seam(),
            stat('Items sold', '${d.itemsSold}'),
            seam(),
            d.hasProfit
                ? stat('Profit', _rs(d.profit))
                : stat('Average bill', _rs(d.avgBill)),
          ],
        ),
        const SizedBox(height: 18),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                best == null
                    ? 'No sales yet today'
                    : 'Best seller: ${best.label}, ${best.qty} sold',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'See insights',
              style: TextStyle(
                color: soft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: soft, size: 20),
          ],
        ),
      ],
    );
  }
}

/// A price-tag outline: chamfered left end with a punched string hole.
class _SwingTagClipper extends CustomClipper<Path> {
  const _SwingTagClipper();

  static const chamfer = 22.0;
  static const radius = 10.0;
  static const holeX = 22.0;
  static const holeR = 6.0;

  /// Left padding that keeps content clear of the hole.
  static const bodyInset = 48.0;

  @override
  Path getClip(Size s) {
    final tag = Path()
      ..moveTo(chamfer, 0)
      ..lineTo(s.width - radius, 0)
      ..arcToPoint(
        Offset(s.width, radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(s.width, s.height - radius)
      ..arcToPoint(
        Offset(s.width - radius, s.height),
        radius: const Radius.circular(radius),
      )
      ..lineTo(chamfer, s.height)
      ..lineTo(0, s.height - chamfer)
      ..lineTo(0, chamfer)
      ..close();
    // Even-odd fill turns the inner circle into a hole.
    return tag
      ..addOval(
        Rect.fromCircle(center: Offset(holeX, s.height / 2), radius: holeR),
      )
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

// ── Needs attention ────────────────────────────────────────
class _Alert {
  final IconData icon;
  final Color color;
  final String title;
  final String action;
  final VoidCallback onTap;
  const _Alert(this.icon, this.color, this.title, this.action, this.onTap);
}

class _AttentionList extends ConsumerWidget {
  const _AttentionList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void tab(int i) => ref.read(navIndexProvider.notifier).state = i;

    final products = ref.watch(inventoryProvider).value ?? const [];
    final lowStock = products
        .where((p) => p.quantity > 0 && p.quantity <= 5)
        .length;
    final outOfStock = products.where((p) => p.quantity <= 0).length;
    final held = ref.watch(heldBillsProvider).value?.length ?? 0;
    final accounts = ref.watch(customerAccountsProvider).value;
    final udhaar = accounts == null
        ? 0.0
        : accounts.values.fold<double>(
            0,
            (s, a) => s + (a.balance > 0 ? a.balance : 0),
          );
    final lastBackup = ref.watch(lastBackupProvider);
    final billCount = ref.watch(billsProvider).value ?? 0;
    final backupDue =
        lastBackup.hasValue &&
        billCount > 0 &&
        (lastBackup.value == null ||
            DateTime.now().difference(lastBackup.value!).inDays >= 7);
    final newOrders = ref.watch(newOnlineOrdersCountProvider);

    final alerts = <_Alert>[
      if (newOrders > 0)
        _Alert(
          Icons.shopping_bag_outlined,
          AppTheme.success,
          '$newOrders new online order${newOrders == 1 ? '' : 's'}',
          'Review and accept',
          () => DashboardScreen._push(context, const OnlineOrdersScreen()),
        ),
      if (outOfStock > 0)
        _Alert(
          Icons.remove_shopping_cart_outlined,
          AppTheme.danger,
          '$outOfStock item${outOfStock == 1 ? '' : 's'} out of stock',
          'Restock',
          () => tab(Tabs.inventory),
        ),
      if (udhaar > 0.5)
        _Alert(
          Icons.account_balance_wallet_outlined,
          AppTheme.danger,
          '${_rs(udhaar)} udhaar outstanding',
          'See customers',
          () => DashboardScreen._push(context, const CustomersScreen()),
        ),
      if (held > 0)
        _Alert(
          Icons.pause_circle_outline_rounded,
          AppTheme.warning,
          '$held held bill${held == 1 ? '' : 's'} waiting',
          'Open billing',
          () => tab(Tabs.billing),
        ),
      if (lowStock > 0)
        _Alert(
          Icons.inventory_outlined,
          AppTheme.warning,
          '$lowStock item${lowStock == 1 ? '' : 's'} with 5 or fewer left',
          'Check stock',
          () => tab(Tabs.inventory),
        ),
      if (backupDue)
        _Alert(
          Icons.cloud_off_outlined,
          AppTheme.warning,
          lastBackup.value == null
              ? 'Your data has never been backed up'
              : 'Last backup was ${DateTime.now().difference(lastBackup.value!).inDays} days ago',
          'Back up now',
          () => tab(Tabs.settings),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Needs attention', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: alerts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: AppTheme.success,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'All clear. Stock, backups and payments are up to date.',
                          style: TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < alerts.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _AlertRow(alerts[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  final _Alert a;
  const _AlertRow(this.a);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: a.onTap,
      focusColor: AppTheme.gold.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Row(
          children: [
            Icon(a.icon, color: a.color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                a.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              a.action,
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shortcuts ──────────────────────────────────────────────
class _Shortcuts extends ConsumerWidget {
  final ValueChanged<int> onTab;
  const _Shortcuts({required this.onTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget w) => DashboardScreen._push(context, w);
    final newOrders = ref.watch(newOnlineOrdersCountProvider);
    final t = Theme.of(context).textTheme;

    Widget group(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one thing the counter does most gets the one big button.
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: () => onTab(Tabs.billing),
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text(
              'Start a new sale',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 28),
        group('Today', [
          _ShortcutRow(
            Icons.receipt_long_outlined,
            'Bills',
            () => onTab(Tabs.bills),
          ),
          _ShortcutRow(
            Icons.shopping_bag_outlined,
            'Online orders',
            () => push(const OnlineOrdersScreen()),
            count: newOrders,
          ),
          _ShortcutRow(
            Icons.account_balance_wallet_outlined,
            'Expenses',
            () => push(const ExpensesScreen()),
          ),
          _ShortcutRow(
            Icons.lock_clock_outlined,
            'Close the day',
            () => push(const DayCloseScreen()),
          ),
        ]),
        const SizedBox(height: 28),
        group('Shop', [
          _ShortcutRow(
            Icons.inventory_2_outlined,
            'Stock',
            () => onTab(Tabs.inventory),
          ),
          _ShortcutRow(
            Icons.people_alt_outlined,
            'Customers',
            () => push(const CustomersScreen()),
          ),
          _ShortcutRow(
            Icons.local_offer_outlined,
            'Offers',
            () => push(const PromotionsScreen()),
          ),
          _ShortcutRow(
            Icons.insights_rounded,
            'Insights',
            () => push(const InsightsScreen()),
          ),
        ]),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;
  const _ShortcutRow(this.icon, this.label, this.onTap, {this.count = 0});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      focusColor: AppTheme.gold.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.ink, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppTheme.ink,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count new',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
