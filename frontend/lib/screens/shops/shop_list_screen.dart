import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../providers/shop_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/download_helper.dart';
import '../../core/utils.dart';

class ShopListScreen extends ConsumerWidget {
  const ShopListScreen({super.key});

  void _showArchiveConfirmDialog(BuildContext context, WidgetRef ref, String id, String name, bool archive) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(archive ? 'Archive Shop?' : 'Restore Shop?'),
          content: Text(
            archive
                ? 'Are you sure you want to archive "$name"? This will hide it from the active shop lists.'
                : 'Do you want to restore "$name" back to the active shop registry?',
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
                final ops = ref.read(shopOperationsProvider);
                try {
                  if (archive) {
                    await ops.archiveShop(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Shop archived successfully');
                    }
                  } else {
                    await ops.restoreShop(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Shop restored successfully');
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ToastHelper.show(
                      context,
                      e.toString().contains('Outstanding Udhari') 
                          ? 'Cannot archive shop. Outstanding Udhari balance exists.'
                          : 'Error updating shop status',
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
          title: const Text('Delete Shop permanently?', style: TextStyle(color: Colors.red)),
          content: Text(
            'Are you sure you want to permanently delete shop "$name"?\n\n'
            'WARNING: This will delete this shop, its purchase logs, and payments ledger. This action cannot be undone.',
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
                  await ref.read(shopOperationsProvider).deleteShop(id);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Shop permanently deleted');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ToastHelper.show(
                      context,
                      e.toString().contains('Outstanding Udhari') 
                          ? 'Cannot delete shop. Outstanding Udhari balance exists.'
                          : 'Failed to delete shop profile.',
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

  Future<void> _exportExcel(BuildContext context, WidgetRef ref, String type) async {
    final apiClient = ref.read(apiClientProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final filename = type == 'shops' ? 'shops_$today.xlsx' : 'shop_purchases_$today.xlsx';

    try {
      final response = await apiClient.dio.get<List<int>>(
        '/exports/excel',
        queryParameters: {'type': type},
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        downloadFile(response.data!, filename);
        if (context.mounted) {
          ToastHelper.show(context, 'Report downloaded successfully');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ToastHelper.show(context, 'Export failed: ${ErrorParser.parse(e)}', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(shopFilterProvider);
    final shopsAsync = ref.watch(shopListProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 992;

    return AppScaffold(
      title: filter.filterType == 'ARCHIVED' ? 'Archived Shops' : 'Shops & Retailers',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toolbar row
            isDesktop
                ? Row(
                    children: [
                      Expanded(
                        child: DebouncedSearchBar(
                          hintText: 'Search by shop name, owner, or mobile number...',
                          initialValue: filter.search,
                          onChanged: (val) {
                            ref.read(shopFilterProvider.notifier).update(
                                  (state) => state.copyWith(search: val, page: 1),
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildFilterTypeDropdown(context, ref, filter),
                      const SizedBox(width: 16),
                      _buildExportButtons(context, ref),
                      const SizedBox(width: 16),
                      AppButton(
                        label: 'Register Shop',
                        icon: Icons.add_business_rounded,
                        onPressed: () => context.go('/shops/new'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DebouncedSearchBar(
                        hintText: 'Search by shop name, owner, or mobile number...',
                        initialValue: filter.search,
                        onChanged: (val) {
                          ref.read(shopFilterProvider.notifier).update(
                                (state) => state.copyWith(search: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildFilterTypeDropdown(context, ref, filter)),
                          const SizedBox(width: 8),
                          AppButton(
                            label: 'New Shop',
                            icon: Icons.add_business_rounded,
                            onPressed: () => context.go('/shops/new'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildExportButtons(context, ref),
                    ],
                  ),
            const SizedBox(height: 24),

            // Content Panel
            Expanded(
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: shopsAsync.when(
                  data: (paginated) {
                    if (paginated.data.isEmpty) {
                      return const EmptyState(
                        title: 'No Shops Found',
                        message: 'Try modifying your search queries or register a new shop profile to get started.',
                        icon: Icons.storefront_rounded,
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: isDesktop ? width - 280 : 800),
                                child: DataTable(
                                  headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                                  columns: const [
                                    DataColumn(label: Text('Shop Name')),
                                    DataColumn(label: Text('Owner Name')),
                                    DataColumn(label: Text('Mobile Number')),
                                    DataColumn(label: Text('Total Purchases', textAlign: TextAlign.center)),
                                    DataColumn(label: Text('Consolidated Udhari', textAlign: TextAlign.right)),
                                    DataColumn(label: Text('Actions', textAlign: TextAlign.center)),
                                  ],
                                  rows: paginated.data.map((shop) {
                                    final pendingUdhari = shop.pendingUdhari;
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                            shop.shopName,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        DataCell(Text(shop.ownerName)),
                                        DataCell(Text(shop.mobile)),
                                        DataCell(
                                          Center(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${shop.totalPurchases} items',
                                                style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              pendingUdhari > 0 
                                                  ? '₹${pendingUdhari.toStringAsFixed(2)}' 
                                                  : 'Clear',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: pendingUdhari > 0 ? Colors.red : Colors.green,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.remove_red_eye_rounded, color: AppTheme.primaryColor),
                                                tooltip: 'View Ledger Profile',
                                                onPressed: () => context.go('/shops/${shop.id}'),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit_rounded, color: Colors.blue),
                                                tooltip: 'Edit Profile',
                                                onPressed: () => context.go('/shops/${shop.id}/edit'),
                                              ),
                                              if (shop.isArchived)
                                                IconButton(
                                                  icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.green),
                                                  tooltip: 'Restore Shop',
                                                  onPressed: () => _showArchiveConfirmDialog(context, ref, shop.id, shop.shopName, false),
                                                )
                                              else
                                                IconButton(
                                                  icon: const Icon(Icons.archive_outlined, color: Colors.orange),
                                                  tooltip: 'Archive Shop',
                                                  onPressed: () => _showArchiveConfirmDialog(context, ref, shop.id, shop.shopName, true),
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                                                tooltip: 'Delete permanently',
                                                onPressed: () => _showDeleteConfirmDialog(context, ref, shop.id, shop.shopName),
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
                          ),
                        ),
                        _buildPaginationFooter(context, ref, paginated),
                      ],
                    );
                  },
                  loading: () => LoadingSkeleton.table(rows: 8),
                  error: (err, st) => Center(child: Text('Error loading shops list: $err', style: const TextStyle(color: Colors.red))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTypeDropdown(BuildContext context, WidgetRef ref, ShopListFilter filter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: filter.filterType,
          onChanged: (val) {
            if (val != null) {
              ref.read(shopFilterProvider.notifier).update(
                    (state) => state.copyWith(filterType: val, page: 1),
                  );
            }
          },
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('Active Shops')),
            DropdownMenuItem(value: 'PENDING_UDHARI', child: Text('Pending Udhari')),
            DropdownMenuItem(value: 'NO_PENDING_UDHARI', child: Text('Clear Udhari')),
            DropdownMenuItem(value: 'ARCHIVED', child: Text('Archived Shops')),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButtons(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export Shops'),
          onPressed: () => _exportExcel(context, ref, 'shops'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt_rounded, size: 18),
          label: const Text('Export Purchases'),
          onPressed: () => _exportExcel(context, ref, 'shop_purchases'),
        ),
      ],
    );
  }

  Widget _buildPaginationFooter(BuildContext context, WidgetRef ref, PaginatedShops paginated) {
    final filter = ref.watch(shopFilterProvider);
    final totalPages = (paginated.total / filter.limit).ceil();
    final currentPage = filter.page;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(currentPage - 1) * filter.limit + 1} to '
            '${(currentPage * filter.limit).clamp(0, paginated.total)} of '
            '${paginated.total} shops',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentPage > 1
                    ? () {
                        ref.read(shopFilterProvider.notifier).update(
                              (state) => state.copyWith(page: currentPage - 1),
                            );
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              Text('Page $currentPage of ${totalPages > 0 ? totalPages : 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentPage < totalPages
                    ? () {
                        ref.read(shopFilterProvider.notifier).update(
                              (state) => state.copyWith(page: currentPage + 1),
                            );
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
