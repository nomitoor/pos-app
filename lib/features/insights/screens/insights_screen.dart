import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../bills/providers/bills_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../insights_data.dart';
import '../insights_provider.dart';

const _blue = Color(0xFF16171B);
const _green = Color(0xFF4E7448);
const _red = Color(0xFFA8432F);
const _orange = Color(0xFFB07A1E);
const _purple = Color(0xFF7C6833);

final _money = NumberFormat('#,##0', 'en_US');
String rs(double v) => 'Rs. ${_money.format(v)}';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(insightsPeriodProvider);
    final insightsAsync = ref.watch(insightsProvider(period));

    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEC),
      appBar: AppBar(title: const Text('Insights')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<InsightPeriod>(
                showSelectedIcon: false,
                segments: [
                  for (final p in InsightPeriod.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {period},
                onSelectionChanged: (s) =>
                    ref.read(insightsPeriodProvider.notifier).state = s.first,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(billsProvider);
                ref.invalidate(inventoryProvider);
                await ref.read(insightsProvider(period).future);
              },
              child: insightsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (data) => _InsightsBody(data: data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsBody extends StatefulWidget {
  final Insights data;
  const _InsightsBody({required this.data});

  @override
  State<_InsightsBody> createState() => _InsightsBodyState();
}

class _InsightsBodyState extends State<_InsightsBody> {
  _Metric _metric = _Metric.qty;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final hasSales = d.billCount > 0;
    final metric = _metric == _Metric.profit && !d.hasProfit
        ? _Metric.qty
        : _metric;
    final top = switch (metric) {
      _Metric.qty => d.topByQty,
      _Metric.revenue => d.topByRevenue,
      _Metric.profit => d.topByProfit,
    }.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // ── KPIs ──
        _KpiGrid(data: d),
        const SizedBox(height: 12),
        if (hasSales) ...[_ProfitRow(data: d), const SizedBox(height: 16)],

        if (!hasSales)
          _EmptySales(period: d.period)
        else ...[
          // ── Highlights ──
          const _SectionTitle('Highlights'),
          _Highlights(data: d),
          const SizedBox(height: 16),

          // ── Trend ──
          _Card(
            title: d.trendTitle,
            child: _BarChart(points: d.trend, color: _blue),
          ),

          // ── Top items ──
          _Card(
            title: d.period == InsightPeriod.today
                ? 'Top selling today'
                : 'Top selling items',
            trailing: _Toggle<_Metric>(
              options: {
                _Metric.qty: 'Qty',
                _Metric.revenue: 'Rs',
                if (d.hasProfit) _Metric.profit: 'Profit',
              },
              selected: metric,
              onChanged: (v) => setState(() => _metric = v),
            ),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  _RankRow(
                    rank: i + 1,
                    stat: top[i],
                    metric: metric,
                    max: math.max(metric.of(top.first), 1),
                  ),
              ],
            ),
          ),

          // ── Sizes & types ──
          _Card(
            title: 'Sales by size',
            child: _ShareBars(stats: d.bySize, color: _purple),
          ),
          _Card(
            title: 'Sales by type',
            child: _ShareBars(stats: d.byType, color: _green),
          ),

          // ── Payment methods ──
          _Card(
            title: 'Payment methods',
            subtitle: 'Share of money received',
            child: _ShareBars(
              stats: d.byPayment,
              color: _blue,
              byRevenue: true,
            ),
          ),

          // ── When customers buy ──
          if (d.period != InsightPeriod.today)
            _Card(
              title: 'Busiest hours',
              subtitle: d.peakHour == null
                  ? null
                  : 'Peak: ${d.peakHour!.label}',
              child: _BarChart(points: _trimZeros(d.byHour), color: _orange),
            ),
          if (d.period == InsightPeriod.month || d.period == InsightPeriod.all)
            _Card(
              title: 'Sales by day of week',
              subtitle: d.bestWeekday == null
                  ? null
                  : 'Best day: ${d.bestWeekday!.label}',
              child: _BarChart(points: d.byWeekday, color: _purple),
            ),
        ],

        // ── Promotions ──
        if (d.byPromo.isNotEmpty)
          _Card(
            title: 'Promotions',
            subtitle: 'Customers saved ${rs(d.promoSavings)} through offers',
            child: Column(
              children: [
                for (final s in d.byPromo)
                  _ListRow(
                    title: s.label,
                    subtitle: '${s.qty} pcs sold • ${rs(s.revenue)} taken',
                    badge: '−${rs(s.profit)}',
                    badgeColor: const Color(0xFF7C6833),
                  ),
              ],
            ),
          ),

        // ── Expenses ──
        if (d.expensesByCategory.isNotEmpty)
          _Card(
            title: 'Expenses',
            subtitle: rs(d.expenses),
            child: Column(
              children: [
                for (final s in d.expensesByCategory)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(s.label)),
                            Text(
                              '${rs(s.revenue)} • ${_pct(s.revenue, d.expenses)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _Bar(
                          fraction: d.expenses == 0
                              ? 0
                              : s.revenue / d.expenses,
                          color: _red,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // ── Returns (shown even if nothing sold in the period) ──
        if (d.returnCount > 0) _ReturnsCard(data: d),

        // ── Inventory health (always shown) ──
        const _SectionTitle('Inventory health'),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'Stock value',
                value: rs(d.stockValue),
                icon: Icons.account_balance_wallet,
                color: _blue,
              ),
            ),
            if (d.stockCostValue != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Stock at cost',
                  value: rs(d.stockCostValue!),
                  icon: Icons.inventory,
                  color: _purple,
                ),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'Out of stock',
                value: '${d.outOfStock}',
                icon: Icons.remove_shopping_cart,
                color: d.outOfStock > 0 ? _red : _green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Restock soon',
          subtitle: 'Will run out within 14 days at the last 30 days\' pace',
          child: d.restock.isEmpty
              ? const _Muted('Nothing is running low. 👍')
              : Column(
                  children: [
                    for (final r in d.restock.take(8))
                      _ListRow(
                        title: r.product.name,
                        subtitle: [
                          if (r.product.type != null) r.product.type!,
                          if (r.product.size != null) r.product.size!,
                          '${r.product.quantity} left',
                          '~${r.perDay.toStringAsFixed(1)}/day',
                        ].join(' • '),
                        badge: r.daysLeft < 1
                            ? (r.product.quantity <= 0 ? 'Out' : '< 1 day')
                            : '${r.daysLeft.floor()} days',
                        badgeColor: r.daysLeft < 4 ? _red : _orange,
                      ),
                  ],
                ),
        ),
        _Card(
          title: 'Slow movers',
          subtitle: 'In stock but no sales in the last 30 days',
          child: d.slowMovers.isEmpty
              ? const _Muted('Every product sold recently.')
              : Column(
                  children: [
                    for (final p in d.slowMovers.take(8))
                      _ListRow(
                        title: p.name,
                        subtitle: [
                          if (p.type != null) p.type!,
                          if (p.size != null) p.size!,
                          '${p.quantity} in stock',
                        ].join(' • '),
                        badge: rs(p.price * p.quantity),
                        badgeColor: Colors.grey.shade700,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  // Keep only the span of hours that had sales.
  static List<ChartPoint> _trimZeros(List<ChartPoint> pts) {
    final first = pts.indexWhere((p) => p.value > 0);
    final last = pts.lastIndexWhere((p) => p.value > 0);
    if (first == -1) return pts;
    return pts.sublist(first, last + 1);
  }
}

// ═══════════════════════════════════════════════════════════
// Building blocks
// ═══════════════════════════════════════════════════════════

class _KpiGrid extends StatelessWidget {
  final Insights data;
  const _KpiGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final change = data.revenueChangePct;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF16171B), Color(0xFF16171B)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revenue • ${data.period.label}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                rs(data.revenue),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (data.refundTotal > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '− ${rs(data.refundTotal)} refunds  =  ${rs(data.netRevenue)} net',
                  style: const TextStyle(
                    color: Color(0xFFE3B5AB),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              if (data.previousRevenue != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (change != null) ...[
                      Icon(
                        change >= 0 ? Icons.trending_up : Icons.trending_down,
                        color: change >= 0
                            ? const Color(0xFFB9CDB4)
                            : const Color(0xFFE3B5AB),
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: change >= 0
                              ? const Color(0xFFB9CDB4)
                              : const Color(0xFFE3B5AB),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        'vs ${rs(data.previousRevenue!)} previous '
                        '${data.period == InsightPeriod.today ? 'day' : 'period'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'Bills',
                value: '${data.billCount}',
                icon: Icons.receipt_long,
                color: _purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'Items sold',
                value: '${data.itemsSold}',
                icon: Icons.shopping_bag,
                color: _green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'Avg bill',
                value: rs(data.avgBill),
                icon: Icons.calculate,
                color: _orange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Highlights extends StatelessWidget {
  final Insights data;
  const _Highlights({required this.data});

  @override
  Widget build(BuildContext context) {
    final best = data.bestSeller;
    final size = data.bestSize;
    final type = data.bestType;
    final peak = data.peakHour;
    final tiles = <Widget>[
      if (best != null)
        _HighlightTile(
          icon: Icons.emoji_events,
          color: const Color(0xFFB07A1E),
          label: 'Best seller',
          value: best.label,
          detail: '${best.qty} sold',
        ),
      if (size != null)
        _HighlightTile(
          icon: Icons.straighten,
          color: _purple,
          label: 'Top size',
          value: size.label,
          detail: '${_pct(size.qty, data.itemsSold)} of items',
        ),
      if (type != null)
        _HighlightTile(
          icon: Icons.checkroom,
          color: _green,
          label: 'Top type',
          value: type.label,
          detail: '${_pct(type.qty, data.itemsSold)} of items',
        ),
      if (peak != null)
        _HighlightTile(
          icon: Icons.schedule,
          color: _orange,
          label: 'Peak hour',
          value: peak.label,
          detail: rs(peak.value),
        ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: tiles,
    );
  }
}

String _pct(num part, num whole) =>
    whole == 0 ? '0%' : '${(part / whole * 100).round()}%';

class _HighlightTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;
  const _HighlightTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  const _Card({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Returns made in the period: totals, reasons and most-returned items.
class _ReturnsCard extends StatelessWidget {
  final Insights data;
  const _ReturnsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final rate = data.returnRatePct;
    final top = data.mostReturned.take(5).toList();
    return _Card(
      title: 'Returns & refunds',
      subtitle: rate == null
          ? null
          : '${rate.toStringAsFixed(1)}% of items sold in this period came back',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Returns',
                  value: '${data.returnCount}',
                  icon: Icons.assignment_return,
                  color: _red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Items back',
                  value: '${data.returnedQty}',
                  icon: Icons.inventory_2,
                  color: _orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Refunded',
                  value: rs(data.refundTotal),
                  icon: Icons.money_off,
                  color: _red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Why customers return',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _ShareBars(stats: data.returnsByReason, color: _red),
          const SizedBox(height: 4),
          const Text(
            'Most returned',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final s in top)
            _ListRow(
              title: s.label,
              subtitle: [?s.subtitle, 'refunded ${rs(s.revenue)}'].join(' • '),
              badge: '${s.qty} back',
              badgeColor: _red,
            ),
        ],
      ),
    );
  }
}

enum _Metric {
  qty,
  revenue,
  profit;

  double of(SalesStat s) => switch (this) {
    _Metric.qty => s.qty.toDouble(),
    _Metric.revenue => s.revenue,
    _Metric.profit => s.profit,
  };
}

/// Profit, margin and discounts for the period.
class _ProfitRow extends StatelessWidget {
  final Insights data;
  const _ProfitRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final margin = data.marginPct;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'Profit',
                value: data.hasProfit ? rs(data.profit) : '—',
                icon: Icons.savings,
                color: data.profit >= 0 ? _green : _red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'Margin',
                value: margin == null ? '—' : '${margin.toStringAsFixed(0)}%',
                icon: Icons.percent,
                color: _blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'Discounts + offers',
                value: rs(data.discountTotal + data.promoSavings),
                icon: Icons.local_offer,
                color: _red,
              ),
            ),
          ],
        ),
        if (data.expenses > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Expenses',
                  value: rs(data.expenses),
                  icon: Icons.money_off,
                  color: _red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _MiniStat(
                  label: data.hasProfit
                      ? 'Net profit (after expenses)'
                      : 'Net profit: add cost prices to see it',
                  value: data.hasProfit ? rs(data.netProfit) : '—',
                  icon: Icons.account_balance,
                  color: data.netProfit >= 0 ? _green : _red,
                ),
              ),
            ],
          ),
        ],
        if (data.uncostedQty > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${data.uncostedQty} item${data.uncostedQty == 1 ? '' : 's'} '
                    'sold without a cost price are not counted in profit. '
                    'Add cost prices in Inventory.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Toggle<T> extends StatelessWidget {
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const _Toggle({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            _chip(e.value, e.key == selected, () => onChanged(e.key)),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final SalesStat stat;
  final _Metric metric;
  final double max;
  const _RankRow({
    required this.rank,
    required this.stat,
    required this.metric,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final value = metric.of(stat);
    final headline = switch (metric) {
      _Metric.qty => '${stat.qty} sold',
      _Metric.revenue => rs(stat.revenue),
      _Metric.profit => rs(stat.profit),
    };
    final detail = [
      if (metric != _Metric.qty) '${stat.qty} sold',
      if (metric != _Metric.revenue) rs(stat.revenue),
      if (metric != _Metric.profit && stat.hasProfit)
        'profit ${rs(stat.profit)}',
    ].join(' • ');
    const medal = [Color(0xFFB07A1E), Color(0xFF9A9BA1), Color(0xFF8A5F17)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: rank <= 3
                ? medal[rank - 1]
                : const Color(0xFFDCDCD6),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: rank <= 3 ? Colors.white : Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stat.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      headline,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (stat.subtitle != null)
                  Text(
                    stat.subtitle!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                const SizedBox(height: 4),
                _Bar(fraction: max == 0 ? 0 : value / max, color: _blue),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareBars extends StatelessWidget {
  final List<SalesStat> stats;
  final Color color;

  /// Share by money instead of quantity (qty is then a bill count).
  final bool byRevenue;
  const _ShareBars({
    required this.stats,
    required this.color,
    this.byRevenue = false,
  });

  @override
  Widget build(BuildContext context) {
    if (byRevenue) {
      final total = stats.fold<double>(0, (s, e) => s + e.revenue);
      return Column(
        children: [
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${rs(s.revenue)} • ${_pct(s.revenue, total)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _Bar(
                    fraction: total == 0 ? 0 : s.revenue / total,
                    color: color,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.qty} bill${s.qty == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final total = stats.fold<int>(0, (s, e) => s + e.qty);
    return Column(
      children: [
        for (final s in stats)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${s.qty} • ${_pct(s.qty, total)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _Bar(fraction: total == 0 ? 0 : s.qty / total, color: color),
                const SizedBox(height: 2),
                Text(
                  [
                    rs(s.revenue),
                    if (s.hasProfit) 'profit ${rs(s.profit)}',
                    if (s.returnedQty > 0)
                      '${s.returnedQty} returned (${s.returnRatePct!.toStringAsFixed(0)}%)',
                  ].join(' • '),
                  style: TextStyle(
                    fontSize: 11,
                    color: (s.returnRatePct ?? 0) >= 15 ? _red : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _Bar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction.clamp(0, 1).toDouble(),
        minHeight: 8,
        color: color,
        backgroundColor: color.withValues(alpha: 0.12),
      ),
    );
  }
}

/// Simple vertical bar chart; long-press/hover a bar for its value.
class _BarChart extends StatelessWidget {
  final List<ChartPoint> points;
  final Color color;
  const _BarChart({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxV = points.fold<double>(0, (m, p) => math.max(m, p.value));
    // Show at most ~8 axis labels so they don't collide.
    final step = (points.length / 8).ceil().clamp(1, 1000);

    return SizedBox(
      height: 170,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in points)
                  Expanded(
                    child: Tooltip(
                      message: '${p.label}: ${rs(p.value)}',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: points.length > 20 ? 1 : 3,
                        ),
                        child: FractionallySizedBox(
                          heightFactor: maxV == 0
                              ? 0.02
                              : math.max(p.value / maxV, 0.02),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: p.value == maxV && maxV > 0
                                  ? color
                                  : color.withValues(alpha: 0.45),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < points.length; i++)
                Expanded(
                  child: Text(
                    i % step == 0 ? points[i].label : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  const _ListRow({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  final String text;
  const _Muted(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.grey));
}

class _EmptySales extends StatelessWidget {
  final InsightPeriod period;
  const _EmptySales({required this.period});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.insights, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            period == InsightPeriod.today
                ? 'No sales yet today'
                : 'No sales in this period',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sales insights will appear after checkout.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
