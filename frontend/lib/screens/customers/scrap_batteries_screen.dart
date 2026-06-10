import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/customer_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../models/customer.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

class ScrapBatteriesScreen extends ConsumerWidget {
  const ScrapBatteriesScreen({super.key});

  void _showMarkReceivedDialog(BuildContext context, WidgetRef ref, Customer customer) {
    final controller = TextEditingController(text: customer.scrapExpectedValue.toStringAsFixed(0));
    final formKey = GlobalKey<FormState>();
    String selectedMode = 'CASH';

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Mark Scrap Received: ${customer.name}'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expected Value: ₹${customer.scrapExpectedValue.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    AppInput(
                      controller: controller,
                      labelText: 'Received Scrap Value (₹) *',
                      prefixIcon: Icons.currency_rupee,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Received value is required';
                        }
                        if (double.tryParse(value) == null || double.tryParse(value)! < 0) {
                          return 'Enter a valid positive number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Payout Mode *',
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
                    if (!formKey.currentState!.validate()) return;
                    Navigator.of(ctx).pop();
                    
                    final val = double.parse(controller.text.trim());
                    try {
                      final operations = ref.read(customerOperationsProvider);
                      final payload = {
                        'scrap_battery_pending': false,
                        'scrap_received_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                        'scrap_received_value': val,
                        'scrap_payment_mode': selectedMode,
                      };
                      
                      await operations.updateCustomer(customer.id, payload);
                      
                      if (context.mounted) {
                        ToastHelper.show(context, 'Scrap battery received successfully');
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
                  child: const Text('Mark Received'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, WidgetRef ref, String id, String name) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Delete Customer permanently?', style: TextStyle(color: Colors.red)),
          content: Text(
            'Are you sure you want to permanently delete customer "$name"?\n\n'
            'WARNING: This will delete this customer and all their battery registrations and payment history. This action cannot be undone.',
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
                  await ref.read(customerOperationsProvider).deleteCustomer(id);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Customer permanently deleted');
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
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(scrapFilterProvider);
    final scrapAsync = ref.watch(scrapBatteriesProvider);
    final dashboardAsync = ref.watch(dashboardProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 768;

    return AppScaffold(
      title: 'Scrap Batteries Tracking',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Widgets Row
            dashboardAsync.when(
              data: (stats) {
                final summary = stats.scrapSummary;
                return GridView.count(
                  crossAxisCount: isDesktop ? 3 : 1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: isDesktop ? 2.8 : 4.0,
                  children: [
                    _buildKpiCard(
                      context,
                      'Pending Scrap Batteries',
                      '${summary.pendingCount}',
                      Icons.recycling_outlined,
                      Colors.orange,
                    ),
                    _buildKpiCard(
                      context,
                      'Pending Scrap Value',
                      '₹${NumberFormat('#,##,###').format(summary.pendingValue)}',
                      Icons.currency_rupee,
                      Colors.red,
                    ),
                    _buildKpiCard(
                      context,
                      'Collected Scrap Value',
                      '₹${NumberFormat('#,##,###').format(summary.collectedValue)}',
                      Icons.check_circle_outline,
                      Colors.green,
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Search Bar Row
            DebouncedSearchBar(
              hintText: 'Search scrap by customer name or mobile...',
              initialValue: filter.search,
              onChanged: (val) {
                ref.read(scrapFilterProvider.notifier).update(
                      (state) => state.copyWith(search: val, page: 1),
                    );
              },
            ),
            const SizedBox(height: 16),

            // Main List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.refresh(scrapBatteriesProvider);
                  ref.refresh(dashboardProvider);
                },
                color: AppTheme.primaryColor,
                child: scrapAsync.when(
                  data: (paginated) {
                    if (paginated.data.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: EmptyState(
                              title: 'No Pending Scrap Batteries',
                              message: filter.search.isNotEmpty
                                  ? 'No matching results for "${filter.search}".'
                                  : 'All scrap batteries are collected and accounted for.',
                              icon: Icons.recycling_outlined,
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
                                  ? _buildScrapTable(context, ref, paginated.data)
                                  : _buildScrapCardList(context, ref, paginated.data),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPagination(context, ref, paginated),
                      ],
                    );
                  },
                  loading: () => isDesktop ? LoadingSkeleton.table(rows: 4) : LoadingSkeleton.list(count: 3),
                  error: (err, stack) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Failed to load scrap list: ${ErrorParser.parse(err)}'),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Retry',
                          onPressed: () => ref.invalidate(scrapBatteriesProvider),
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

  Widget _buildKpiCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrapTable(BuildContext context, WidgetRef ref, List<Customer> customers) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Customer Name')),
            DataColumn(label: Text('Mobile Number')),
            DataColumn(label: Text('Expected Scrap Value')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: customers.map((c) {
            return DataRow(
              onSelectChanged: (_) {
                context.go('/customers/${c.id}');
              },
              cells: [
                DataCell(Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(c.mobile)),
                DataCell(Text(
                  '₹${NumberFormat('#,##,###.00').format(c.scrapExpectedValue)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
                )),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      'PENDING SCRAP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Received', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          _showMarkReceivedDialog(context, ref, c);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                        tooltip: 'Edit Customer',
                        onPressed: () {
                          context.go('/customers/${c.id}/edit');
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 20),
                        tooltip: 'Delete Customer',
                        onPressed: () {
                          _showDeleteConfirmDialog(context, ref, c.id, c.name);
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
    );
  }

  Widget _buildScrapCardList(BuildContext context, WidgetRef ref, List<Customer> customers) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final c = customers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        'PENDING SCRAP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(c.mobile),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.currency_rupee, size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Text(
                      'Expected Value: ₹${c.scrapExpectedValue.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        foregroundColor: Colors.green,
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Mark Received'),
                      onPressed: () {
                        _showMarkReceivedDialog(context, ref, c);
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      onPressed: () {
                        context.go('/customers/${c.id}/edit');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                      onPressed: () {
                        _showDeleteConfirmDialog(context, ref, c.id, c.name);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagination(BuildContext context, WidgetRef ref, PaginatedCustomers paginated) {
    final hasPrev = paginated.page > 1;
    final hasNext = (paginated.page * paginated.limit) < paginated.total;

    if (paginated.total == 0) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Showing ${(paginated.page - 1) * paginated.limit + 1} to '
          '${(paginated.page * paginated.limit) > paginated.total ? paginated.total : (paginated.page * paginated.limit)} '
          'of ${paginated.total} entries',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: hasPrev
                  ? () {
                      ref.read(scrapFilterProvider.notifier).update(
                            (state) => state.copyWith(page: state.page - 1),
                          );
                    }
                  : null,
            ),
            Text(
              'Page ${paginated.page}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: hasNext
                  ? () {
                      ref.read(scrapFilterProvider.notifier).update(
                            (state) => state.copyWith(page: state.page + 1),
                          );
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
