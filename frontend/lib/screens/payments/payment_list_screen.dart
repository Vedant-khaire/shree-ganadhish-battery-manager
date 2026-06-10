import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/payment_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../models/payment.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';
import '../../widgets/search_bar.dart';

class PaymentListScreen extends ConsumerWidget {
  const PaymentListScreen({super.key});

  void _showSettleConfirmDialog(BuildContext context, WidgetRef ref, String paymentId, String customerId, String name, double amount) {
    String selectedMode = 'CASH';
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Settle Udhari?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mark this pending balance of ${FormatUtils.formatIndianCurrency(amount)} for $name as paid in full?',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Payment Mode *',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedMode,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                      DropdownMenuItem(value: 'ONLINE', child: Text('Online')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedMode = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await ref.read(paymentOperationsProvider).settlePayment(paymentId, customerId, selectedMode);
                      if (context.mounted) {
                        ToastHelper.show(context, 'Payment settled successfully');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ToastHelper.show(
                          context,
                          'Error: ${ErrorParser.parse(e)}',
                          isError: true,
                        );
                      }
                    }
                  },
                  child: const Text('Confirm Settle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showArchiveConfirmDialog(BuildContext context, WidgetRef ref, String paymentId, String customerId, double totalAmount) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Archive Payment Record?'),
          content: Text(
            'Are you sure you want to archive this transaction of ${FormatUtils.formatIndianCurrency(totalAmount)}? This will hide it from the Udhari list.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await ref.read(paymentOperationsProvider).archivePayment(paymentId, customerId);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Payment record archived successfully');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ToastHelper.show(
                      context,
                      'Error: ${ErrorParser.parse(e)}',
                      isError: true,
                    );
                  }
                }
              },
              child: const Text('Confirm Archive'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(paymentFilterProvider);
    final paymentsAsync = ref.watch(paymentListProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 900;

    return AppScaffold(
      title: 'Udhari & Payments',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter Toolbar
            isDesktop
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          filter.isSettled == false
                              ? 'Pending Udharis'
                              : (filter.isSettled == true ? 'Settled Payments' : 'All Transactions'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Pending (Udhari)'),
                        selected: filter.isSettled == false,
                        selectedColor: AppTheme.primaryColor.withAlpha(40),
                        onSelected: (val) {
                          if (val) {
                            ref.read(paymentFilterProvider.notifier).update(
                                  (state) => state.copyWith(isSettled: false, page: 1),
                                );
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Settled (Paid)'),
                        selected: filter.isSettled == true,
                        selectedColor: AppTheme.primaryColor.withAlpha(40),
                        onSelected: (val) {
                          if (val) {
                            ref.read(paymentFilterProvider.notifier).update(
                                  (state) => state.copyWith(isSettled: true, page: 1),
                                );
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('All'),
                        selected: filter.isSettled == null,
                        selectedColor: AppTheme.primaryColor.withAlpha(40),
                        onSelected: (val) {
                          if (val) {
                            ref.read(paymentFilterProvider.notifier).update(
                                  (state) => state.copyWith(isSettled: null, page: 1),
                                );
                          }
                        },
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filter.isSettled == false
                            ? 'Pending Udharis'
                            : (filter.isSettled == true ? 'Settled Payments' : 'All Transactions'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Pending (Udhari)'),
                              selected: filter.isSettled == false,
                              selectedColor: AppTheme.primaryColor.withAlpha(40),
                              onSelected: (val) {
                                if (val) {
                                  ref.read(paymentFilterProvider.notifier).update(
                                        (state) => state.copyWith(isSettled: false, page: 1),
                                      );
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            ChoiceChip(
                              label: const Text('Settled (Paid)'),
                              selected: filter.isSettled == true,
                              selectedColor: AppTheme.primaryColor.withAlpha(40),
                              onSelected: (val) {
                                if (val) {
                                  ref.read(paymentFilterProvider.notifier).update(
                                        (state) => state.copyWith(isSettled: true, page: 1),
                                      );
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            ChoiceChip(
                              label: const Text('All'),
                              selected: filter.isSettled == null,
                              selectedColor: AppTheme.primaryColor.withAlpha(40),
                              onSelected: (val) {
                                if (val) {
                                  ref.read(paymentFilterProvider.notifier).update(
                                        (state) => state.copyWith(isSettled: null, page: 1),
                                      );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 16),
            DebouncedSearchBar(
              hintText: 'Search payments by customer name or mobile number...',
              initialValue: filter.search,
              onChanged: (val) {
                ref.read(paymentFilterProvider.notifier).update(
                      (state) => state.copyWith(search: val, page: 1),
                    );
              },
            ),
            const SizedBox(height: 16),

            // Main Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(paymentListProvider.future),
                color: AppTheme.primaryColor,
                child: paymentsAsync.when(
                  data: (paginated) {
                    if (paginated.data.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: EmptyState(
                              title: 'No Payments Found',
                              message: filter.isSettled == false
                                  ? 'Great! There are no pending udharis currently.'
                                  : 'No payment entries match this filter.',
                              icon: Icons.receipt_long_outlined,
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              isDesktop
                                  ? _buildPaymentTable(context, ref, paginated.data)
                                  : _buildPaymentCardList(context, ref, paginated.data),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPagination(context, ref, paginated),
                      ],
                    );
                  },
                  loading: () => isDesktop ? LoadingSkeleton.table(rows: 5) : LoadingSkeleton.list(count: 3),
                  error: (err, stack) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load payment registry',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(ErrorParser.parse(err), style: const TextStyle(color: Color(0xFF64748B))),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Retry',
                          onPressed: () => ref.invalidate(paymentListProvider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentTable(BuildContext context, WidgetRef ref, List<Payment> payments) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Customer')),
              DataColumn(label: Text('Mobile')),
              DataColumn(label: Text('Total Bill')),
              DataColumn(label: Text('Paid Amount')),
              DataColumn(label: Text('Udhari Balance')),
              DataColumn(label: Text('Date Registered')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: payments.map((p) {
              final cName = p.customerName ?? 'Unknown Customer';
              final cMobile = p.customerMobile ?? '-';

              return DataRow(
                onSelectChanged: (_) {
                  context.go('/customers/${p.customerId}');
                },
                cells: [
                  DataCell(
                    Text(
                      cName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  DataCell(Text(cMobile)),
                  DataCell(Text(FormatUtils.formatIndianCurrency(p.totalAmount))),
                  DataCell(Text(FormatUtils.formatIndianCurrency(p.paidAmount))),
                  DataCell(
                    Text(
                      FormatUtils.formatIndianCurrency(p.pendingAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: p.pendingAmount > 0 ? Colors.red : Colors.green.shade800,
                      ),
                    ),
                  ),
                  DataCell(Text(FormatUtils.formatDate(p.createdAt.split('T').first))),
                  DataCell(StatusChip(type: p.isSettled ? StatusType.paid : StatusType.pending)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!p.isSettled)
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                            tooltip: 'Mark as Paid',
                            onPressed: () {
                              _showSettleConfirmDialog(context, ref, p.id, p.customerId, cName, p.pendingAmount);
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.history, color: AppTheme.primaryColor, size: 20),
                          tooltip: 'View ledger history',
                          onPressed: () {
                            _showTransactionHistoryDialog(context, ref, p);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.archive_outlined, color: Colors.redAccent, size: 20),
                          tooltip: 'Archive record',
                          onPressed: () {
                            _showArchiveConfirmDialog(context, ref, p.id, p.customerId, p.totalAmount);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCardList(BuildContext context, WidgetRef ref, List<Payment> payments) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final p = payments[index];
        final cName = p.customerName ?? 'Unknown Customer';
        final cMobile = p.customerMobile ?? '-';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () {
              context.go('/customers/${p.customerId}');
            },
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    cName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.primaryColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                StatusChip(type: p.isSettled ? StatusType.paid : StatusType.pending),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(cMobile),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSubField('Total', FormatUtils.formatIndianCurrency(p.totalAmount)),
                    _buildSubField('Paid', FormatUtils.formatIndianCurrency(p.paidAmount)),
                    _buildSubField(
                      'Udhari',
                      FormatUtils.formatIndianCurrency(p.pendingAmount),
                      textColor: p.pendingAmount > 0 ? Colors.red : Colors.green.shade800,
                    ),
                  ],
                ),
                if (p.reminderNote != null && p.reminderNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Note: ${p.reminderNote}',
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'settle') {
                  _showSettleConfirmDialog(context, ref, p.id, p.customerId, cName, p.pendingAmount);
                } else if (val == 'archive') {
                  _showArchiveConfirmDialog(context, ref, p.id, p.customerId, p.totalAmount);
                } else if (val == 'history') {
                  _showTransactionHistoryDialog(context, ref, p);
                }
              },
              itemBuilder: (ctx) => [
                if (!p.isSettled)
                  const PopupMenuItem(
                    value: 'settle',
                    child: Row(
                      children: [
                        Icon(Icons.check, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Text('Mark as Paid'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'history',
                  child: Row(
                    children: [
                      Icon(Icons.history, color: AppTheme.primaryColor, size: 18),
                      SizedBox(width: 8),
                      Text('View Ledger History'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Archive Entry'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubField(String label, String val, {Color? textColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
        ),
        Text(
          val,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: textColor ?? AppTheme.secondaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(BuildContext context, WidgetRef ref, PaginatedPayments paginated) {
    final hasPrev = paginated.page > 1;
    final hasNext = (paginated.page * paginated.limit) < paginated.total;
    final totalPages = (paginated.total / paginated.limit).ceil();

    if (paginated.total == 0) return const SizedBox.shrink();

    final isMobile = MediaQuery.of(context).size.width < 600;

    final showingText = Text(
      'Showing ${(paginated.page - 1) * paginated.limit + 1} to '
      '${(paginated.page * paginated.limit) > paginated.total ? paginated.total : (paginated.page * paginated.limit)} '
      'of ${paginated.total} entries',
      style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      textAlign: TextAlign.center,
    );

    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: hasPrev
              ? () {
                  ref.read(paymentFilterProvider.notifier).update(
                        (state) => state.copyWith(page: state.page - 1),
                      );
                }
              : null,
          child: const Text('Previous'),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Page ${paginated.page} of $totalPages',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: hasNext
              ? () {
                  ref.read(paymentFilterProvider.notifier).update(
                        (state) => state.copyWith(page: state.page + 1),
                      );
                }
              : null,
          child: const Text('Next'),
        ),
      ],
    );

    if (isMobile) {
      return Column(
        children: [
          showingText,
          const SizedBox(height: 12),
          controls,
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        showingText,
        controls,
      ],
    );
  }
}

void _showTransactionHistoryDialog(BuildContext context, WidgetRef ref, Payment payment) {
  final cName = payment.customerName ?? 'Customer';
  showDialog(
    context: context,
    builder: (BuildContext ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final txAsync = ref.watch(paymentTransactionsProvider(payment.id));
          
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.history, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Expanded(child: Text('Udhari Ledger: $cName')),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 350,
              child: txAsync.when(
                data: (txList) {
                  if (txList.isEmpty) {
                    return const Center(child: Text('No transaction logs found'));
                  }
                  return ListView.separated(
                    itemCount: txList.length,
                    separatorBuilder: (c, idx) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final tx = txList[idx];
                      final isAdd = tx.transactionType == 'ADDITION';
                      
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isAdd ? Colors.red.shade50 : Colors.green.shade50,
                          child: Icon(
                            isAdd ? Icons.arrow_outward : Icons.arrow_downward,
                            color: isAdd ? Colors.red : Colors.green,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isAdd ? 'Balance Added' : 'Payment Received',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${isAdd ? "+" : "-"} ₹${tx.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isAdd ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tx.notes != null) Text(tx.notes!),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  FormatUtils.formatDate(tx.createdAt.split('T').first),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                if (!isAdd && tx.paymentMode != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      tx.paymentMode!,
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error loading history: $err')),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}
