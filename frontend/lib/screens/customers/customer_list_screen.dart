import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/customer_provider.dart';
import '../../models/customer.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

class CustomerListScreen extends ConsumerWidget {
  const CustomerListScreen({super.key});

  void _showArchiveConfirmDialog(BuildContext context, WidgetRef ref, String id, String name, bool archive) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(archive ? 'Archive Customer?' : 'Restore Customer?'),
          content: Text(
            archive
                ? 'Are you sure you want to archive $name? This will hide them from the primary customer registry.'
                : 'Do you want to restore $name back to the active customer registry?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: archive ? Colors.orange : Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final operations = ref.read(customerOperationsProvider);
                try {
                  if (archive) {
                    await operations.archiveCustomer(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Customer archived successfully');
                    }
                  } else {
                    await operations.restoreCustomer(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Customer restored successfully');
                    }
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
              child: Text(archive ? 'Archive' : 'Restore'),
            ),
          ],
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
    final filter = ref.watch(customerFilterProvider);
    final customersAsync = ref.watch(customerListProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 768;

    return AppScaffold(
      title: filter.archived ? 'Archived Customers' : 'Customer Directory',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toolbar: Search and Buttons
            isDesktop
                ? Row(
                    children: [
                      Expanded(
                        child: DebouncedSearchBar(
                          hintText: 'Search by name, mobile, or vehicle number...',
                          initialValue: filter.search,
                          onChanged: (val) {
                            ref.read(customerFilterProvider.notifier).update(
                                  (state) => state.copyWith(search: val, page: 1),
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      ChoiceChip(
                        label: const Text('Archived Only'),
                        selected: filter.archived,
                        selectedColor: AppTheme.primaryColor.withAlpha(40),
                        onSelected: (val) {
                          ref.read(customerFilterProvider.notifier).update(
                                (state) => state.copyWith(archived: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(width: 16),
                      AppButton(
                        label: 'Add Customer',
                        icon: Icons.add,
                        onPressed: () {
                          context.go('/customers/new');
                        },
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DebouncedSearchBar(
                        hintText: 'Search by name, mobile, or vehicle number...',
                        initialValue: filter.search,
                        onChanged: (val) {
                          ref.read(customerFilterProvider.notifier).update(
                                (state) => state.copyWith(search: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Archived Only'),
                            selected: filter.archived,
                            selectedColor: AppTheme.primaryColor.withAlpha(40),
                            onSelected: (val) {
                              ref.read(customerFilterProvider.notifier).update(
                                    (state) => state.copyWith(archived: val, page: 1),
                                  );
                            },
                          ),
                          const Spacer(),
                          AppButton(
                            label: 'Add Customer',
                            icon: Icons.add,
                            onPressed: () {
                              context.go('/customers/new');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All Customers'),
                    selected: filter.filterType == 'ALL',
                    selectedColor: AppTheme.primaryColor.withAlpha(40),
                    onSelected: (selected) {
                      if (selected) {
                        ref.read(customerFilterProvider.notifier).update(
                              (state) => state.copyWith(filterType: 'ALL', page: 1),
                            );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Pending Scrap Batteries'),
                    selected: filter.filterType == 'SCRAP_PENDING',
                    selectedColor: AppTheme.primaryColor.withAlpha(40),
                    onSelected: (selected) {
                      if (selected) {
                        ref.read(customerFilterProvider.notifier).update(
                              (state) => state.copyWith(filterType: 'SCRAP_PENDING', page: 1),
                            );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Active Warranties'),
                    selected: filter.filterType == 'ACTIVE_WARRANTIES',
                    selectedColor: AppTheme.primaryColor.withAlpha(40),
                    onSelected: (selected) {
                      if (selected) {
                        ref.read(customerFilterProvider.notifier).update(
                              (state) => state.copyWith(filterType: 'ACTIVE_WARRANTIES', page: 1),
                            );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Pending Udhari'),
                    selected: filter.filterType == 'PENDING_UDHARI',
                    selectedColor: AppTheme.primaryColor.withAlpha(40),
                    onSelected: (selected) {
                      if (selected) {
                        ref.read(customerFilterProvider.notifier).update(
                              (state) => state.copyWith(filterType: 'PENDING_UDHARI', page: 1),
                            );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Customer List Content wrapped in RefreshIndicator
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(customerListProvider.future),
                color: AppTheme.primaryColor,
                child: customersAsync.when(
                  data: (paginated) {
                    if (paginated.data.isEmpty) {
                      // Wrapped in ListView to allow pull-to-refresh even when empty
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: EmptyState(
                              title: filter.archived ? 'No Archived Customers' : 'No Customers Found',
                              message: filter.search.isNotEmpty
                                  ? 'No matching results for "${filter.search}". Try refining your search.'
                                  : (filter.archived
                                      ? 'You have not archived any customers yet.'
                                      : 'Start by adding your first customer to the directory.'),
                              icon: filter.archived ? Icons.archive_outlined : Icons.people_outline,
                              actionLabel: filter.archived ? null : 'Add Customer',
                              onAction: filter.archived ? null : () => context.go('/customers/new'),
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
                                  ? _buildCustomerTable(context, ref, paginated.data, filter.archived)
                                  : _buildCustomerCardList(context, ref, paginated.data, filter.archived),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Paging Controls
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
                          'Failed to load customer list',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(ErrorParser.parse(err), style: const TextStyle(color: Color(0xFF64748B))),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Retry',
                          onPressed: () => ref.invalidate(customerListProvider),
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

  Widget _buildCustomerTable(BuildContext context, WidgetRef ref, List<Customer> customers, bool archived) {
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
              DataColumn(label: Text('Customer Name')),
              DataColumn(label: Text('Mobile Number')),
              DataColumn(label: Text('Vehicle No')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Area')),
              DataColumn(label: Text('Purchase Type')),
              DataColumn(label: Text('Actions')),
            ],
            rows: customers.map((c) {
              return DataRow(
                onSelectChanged: (_) {
                  context.go('/customers/${c.id}');
                },
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (c.scrapBatteryPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              'SCRAP PENDING',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(Text(c.mobile)),
                  DataCell(Text(c.vehicleNo ?? '-')),
                  DataCell(Text(c.vehicleType ?? '-')),
                  DataCell(Text(c.area ?? '-')),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.purchaseType == 'SHOP' ? Colors.purple.shade50 : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        c.purchaseType,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: c.purchaseType == 'SHOP' ? Colors.purple.shade700 : Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                          tooltip: 'Edit details',
                          onPressed: () {
                            context.go('/customers/${c.id}/edit');
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            archived ? Icons.settings_backup_restore : Icons.archive_outlined,
                            color: archived ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          tooltip: archived ? 'Restore customer' : 'Archive customer',
                          onPressed: () {
                            _showArchiveConfirmDialog(context, ref, c.id, c.name, !archived);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 20),
                          tooltip: 'Delete customer',
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
      ),
    );
  }

  Widget _buildCustomerCardList(BuildContext context, WidgetRef ref, List<Customer> customers, bool archived) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final c = customers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () {
              context.go('/customers/${c.id}');
            },
            title: Row(
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
                    color: c.purchaseType == 'SHOP' ? Colors.purple.shade50 : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    c.purchaseType,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: c.purchaseType == 'SHOP' ? Colors.purple.shade700 : Colors.teal.shade700,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.scrapBatteryPending) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      'SCRAP PENDING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(c.mobile),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.directions_car, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(c.vehicleNo != null ? '${c.vehicleNo} (${c.vehicleType ?? 'Other'})' : 'No Vehicle'),
                  ],
                ),
                if (c.area != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(c.area!),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                  onPressed: () {
                    context.go('/customers/${c.id}/edit');
                  },
                ),
                IconButton(
                  icon: Icon(
                    archived ? Icons.restore : Icons.archive_outlined,
                    color: archived ? Colors.green : Colors.orange,
                  ),
                  onPressed: () {
                    _showArchiveConfirmDialog(context, ref, c.id, c.name, !archived);
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
          ),
        );
      },
    );
  }

  Widget _buildPagination(BuildContext context, WidgetRef ref, PaginatedCustomers paginated) {
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
                  ref.read(customerFilterProvider.notifier).update(
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
                  ref.read(customerFilterProvider.notifier).update(
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
