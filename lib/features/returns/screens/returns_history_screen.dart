import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/sale_return.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/returns_provider.dart';
import 'refund_slip_screen.dart';

class ReturnsHistoryScreen extends ConsumerWidget {
  const ReturnsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returnsAsync = ref.watch(returnsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Returns & Refunds')),
      body: returnsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (returns) {
          if (returns.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_return_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No returns yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Open a bill in Bills and tap Return',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          final total = returns.fold<double>(0, (s, r) => s + r.refundAmount);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: returns.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  '${returns.length} return${returns.length == 1 ? '' : 's'} '
                  '• Rs. ${total.toStringAsFixed(0)} refunded in total',
                  style: const TextStyle(color: Colors.grey),
                );
              }
              return _ReturnCard(ret: returns[i - 1]);
            },
          );
        },
      ),
    );
  }
}

class _ReturnCard extends ConsumerWidget {
  final SaleReturn ret;
  const _ReturnCard({required this.ret});

  Future<void> _openSlip(BuildContext context, WidgetRef ref) async {
    final settings = await ref.read(shopSettingsProvider.future);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RefundSlipScreen(ret: ret, settings: settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('dd MMM yyyy, hh:mm a').format(ret.createdAt);
    final color = ret.isExchange ? Color(0xFFB07A1E) : Color(0xFFA8432F);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  ret.isExchange ? Icons.swap_horiz : Icons.undo,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ret.returnNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$date • from ${ret.billNumber}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '${ret.itemCount} item${ret.itemCount == 1 ? '' : 's'} • ${ret.reason}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '- Rs. ${ret.refundAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  Text(
                    ret.isExchange ? 'Exchange' : ret.refundMethod,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ret.returnNumber,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${DateFormat('dd MMM yyyy, hh:mm a').format(ret.createdAt)} '
                '• original bill ${ret.billNumber}'
                '${ret.billId == null ? ' (deleted)' : ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text('Reason: ${ret.reason}'),
              if (ret.note != null) Text('Note: ${ret.note}'),
              const Divider(height: 24),
              for (final i in ret.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.name),
                            Text(
                              [
                                ?i.size,
                                i.restocked ? 'restocked' : 'not restocked',
                              ].join(' • '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'x${i.quantity}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Rs. ${i.refund.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ret.isExchange ? 'CREDIT (EXCHANGE)' : 'REFUNDED',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs. ${ret.refundAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFFA8432F),
                    ),
                  ),
                ],
              ),
              if (!ret.isExchange)
                Text(
                  'by ${ret.refundMethod}',
                  style: const TextStyle(color: Colors.grey),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16171B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openSlip(context, ref);
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('Refund slip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
