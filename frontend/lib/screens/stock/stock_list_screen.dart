import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../providers/stock_provider.dart';
import '../../models/stock.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../core/api_client.dart';
import '../../core/download_helper.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

class StockListScreen extends ConsumerStatefulWidget {
  const StockListScreen({super.key});

  @override
  ConsumerState<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends ConsumerState<StockListScreen> {
  bool _isDownloading = false;

  void _showArchiveConfirmDialog(BuildContext context, WidgetRef ref, String id, String model, String type, bool archive) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(archive ? 'Archive Stock Item?' : 'Restore Stock Item?'),
          content: Text(
            archive
                ? 'Are you sure you want to archive "$model" ($type)? This will hide it from the active inventory directory.'
                : 'Do you want to restore "$model" ($type) back to the active inventory directory?',
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
                final operations = ref.read(stockOperationsProvider);
                try {
                  if (archive) {
                    await operations.archiveStock(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Stock item archived successfully');
                    }
                  } else {
                    await operations.restoreStock(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Stock item restored successfully');
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

  void _showDeleteConfirmDialog(BuildContext context, WidgetRef ref, String id, String model, String type) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Delete Stock Item permanently?', style: TextStyle(color: Colors.red)),
          content: Text(
            'Are you sure you want to permanently delete "$model" ($type) from inventory?\n\n'
            'WARNING: This will permanently delete the stock configuration and history. This action cannot be undone.',
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
                  await ref.read(stockOperationsProvider).deleteStock(id);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Stock item permanently deleted');
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

  Future<void> _adjustQty(BuildContext context, WidgetRef ref, Stock s, int amount, bool increase) async {
    try {
      await ref.read(stockOperationsProvider).adjustQuantity(s.id, amount, increase);
    } catch (e) {
      if (context.mounted) {
        ToastHelper.show(
          context,
          'Adjustment failed: ${ErrorParser.parse(e)}',
          isError: true,
        );
      }
    }
  }

  Future<void> _exportStock() async {
    setState(() {
      _isDownloading = true;
    });

    final apiClient = ref.read(apiClientProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final filename = 'stock_$today.xlsx';

    try {
      final response = await apiClient.dio.get<List<int>>(
        '/exports/excel',
        queryParameters: {'type': 'stock'},
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        downloadFile(response.data!, filename);
        if (mounted) {
          ToastHelper.show(context, 'Stock exported successfully: $filename');
        }
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.show(
          context,
          'Export failed: ${ErrorParser.parse(e)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Widget _buildStockChip(Stock s) {
    Color bgColor;
    Color textColor;
    Color borderColor;
    String label;

    if (s.quantity == 0) {
      bgColor = const Color(0xFFFEF2F2);
      textColor = const Color(0xFFDC2626);
      borderColor = const Color(0xFFFECACA);
      label = 'OUT OF STOCK';
    } else if (s.quantity <= s.lowStockThreshold) {
      bgColor = const Color(0xFFFFFBEB);
      textColor = const Color(0xFFD97706);
      borderColor = const Color(0xFFFDE68A);
      label = 'LOW STOCK';
    } else {
      bgColor = const Color(0xFFF0FDF4);
      textColor = const Color(0xFF16A34A);
      borderColor = const Color(0xFFBBF7D0);
      label = 'IN STOCK';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(stockFilterProvider);
    final stockAsync = ref.watch(stockListProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 768;

    return AppScaffold(
      title: filter.archived ? 'Archived Inventory' : 'Stock Management',
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
                          hintText: 'Search by battery model name...',
                          initialValue: filter.search,
                          onChanged: (val) {
                            ref.read(stockFilterProvider.notifier).update(
                                  (state) => state.copyWith(search: val, page: 1),
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Toggle Low Stock
                      ChoiceChip(
                        label: const Text('Low Stock Only'),
                        selected: filter.lowStock,
                        selectedColor: AppTheme.primaryColor.withAlpha(40),
                        onSelected: (val) {
                          ref.read(stockFilterProvider.notifier).update(
                                (state) => state.copyWith(lowStock: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(width: 16),
                      // Toggle Archived
                      ChoiceChip(
                        label: const Text('Archived Only'),
                        selected: filter.archived,
                        selectedColor: AppTheme.primaryColor.withAlpha(40),
                        onSelected: (val) {
                          ref.read(stockFilterProvider.notifier).update(
                                (state) => state.copyWith(archived: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(width: 16),
                      // Export Stock Button
                      AppButton(
                        label: _isDownloading ? 'Exporting...' : 'Export Excel',
                        icon: Icons.download_outlined,
                        isSecondary: true,
                        onPressed: _isDownloading ? null : _exportStock,
                      ),
                      const SizedBox(width: 16),
                      AppButton(
                        label: 'Add Stock Item',
                        icon: Icons.add,
                        onPressed: () {
                          context.go('/stock/new');
                        },
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DebouncedSearchBar(
                        hintText: 'Search by battery model name...',
                        initialValue: filter.search,
                        onChanged: (val) {
                          ref.read(stockFilterProvider.notifier).update(
                                (state) => state.copyWith(search: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('Low Stock Only'),
                            selected: filter.lowStock,
                            selectedColor: AppTheme.primaryColor.withAlpha(40),
                            onSelected: (val) {
                              ref.read(stockFilterProvider.notifier).update(
                                    (state) => state.copyWith(lowStock: val, page: 1),
                                  );
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Archived Only'),
                            selected: filter.archived,
                            selectedColor: AppTheme.primaryColor.withAlpha(40),
                            onSelected: (val) {
                              ref.read(stockFilterProvider.notifier).update(
                                    (state) => state.copyWith(archived: val, page: 1),
                                  );
                            },
                          ),
                          AppButton(
                            label: _isDownloading ? 'Exporting...' : 'Export Excel',
                            icon: Icons.download_outlined,
                            isSecondary: true,
                            onPressed: _isDownloading ? null : _exportStock,
                          ),
                          AppButton(
                            label: 'Add Stock Item',
                            icon: Icons.add,
                            onPressed: () {
                              context.go('/stock/new');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 24),

            // Stock List Content wrapped in RefreshIndicator
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(stockListProvider.future),
                color: AppTheme.primaryColor,
                child: stockAsync.when(
                  data: (paginated) {
                    if (paginated.data.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: EmptyState(
                              title: filter.archived 
                                  ? 'No Archived Stock' 
                                  : (filter.lowStock ? 'No Low Stock Items' : 'Inventory Empty'),
                              message: filter.search.isNotEmpty
                                  ? 'No matching results for "${filter.search}".'
                                  : (filter.archived
                                      ? 'You have not archived any stock items.'
                                      : 'Add your battery stock items to manage quantities.'),
                              icon: filter.archived ? Icons.archive_outlined : Icons.inventory_2_outlined,
                              actionLabel: (filter.archived || filter.lowStock) ? null : 'Add Stock Item',
                              onAction: (filter.archived || filter.lowStock) ? null : () => context.go('/stock/new'),
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
                                  ? _buildStockTable(context, paginated.data, filter.archived)
                                  : _buildStockCardList(context, paginated.data, filter.archived),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Paging Controls
                        _buildPagination(context, paginated),
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
                          'Failed to load stock list',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(ErrorParser.parse(err), style: const TextStyle(color: Color(0xFF64748B))),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Retry',
                          onPressed: () => ref.invalidate(stockListProvider),
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

  Widget _buildStockTable(BuildContext context, List<Stock> stockList, bool archived) {
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
              DataColumn(label: Text('Model Name')),
              DataColumn(label: Text('Battery Type')),
              DataColumn(label: Text('Quantity')),
              DataColumn(label: Text('Low Threshold')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: stockList.map((s) {
              return DataRow(
                cells: [
                  DataCell(Text(s.modelName, style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(s.batteryType)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF64748B), size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: s.quantity > 0
                              ? () => _adjustQty(context, ref, s, 1, false)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            '${s.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF64748B), size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _adjustQty(context, ref, s, 1, true),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text('${s.lowStockThreshold}')),
                  DataCell(_buildStockChip(s)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                          tooltip: 'Edit configuration',
                          onPressed: () {
                            context.go('/stock/${s.id}/edit');
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            archived ? Icons.settings_backup_restore : Icons.archive_outlined,
                            color: archived ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          tooltip: archived ? 'Restore item' : 'Archive item',
                          onPressed: () {
                            _showArchiveConfirmDialog(context, ref, s.id, s.modelName, s.batteryType, !archived);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 20),
                          tooltip: 'Delete permanently',
                          onPressed: () {
                            _showDeleteConfirmDialog(context, ref, s.id, s.modelName, s.batteryType);
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

  Widget _buildStockCardList(BuildContext context, List<Stock> stockList, bool archived) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stockList.length,
      itemBuilder: (context, index) {
        final s = stockList[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _showStockDetailsPanel(context, s),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          s.modelName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      _buildStockChip(s),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Type: ${s.batteryType}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                      Text(
                        'Threshold: ${s.lowStockThreshold}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Stock: ',
                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF64748B), size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: s.quantity > 0
                                ? () => _adjustQty(context, ref, s, 1, false)
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Text(
                              '${s.quantity}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF64748B), size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _adjustQty(context, ref, s, 1, true),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                            onPressed: () {
                              context.go('/stock/${s.id}/edit');
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              archived ? Icons.restore : Icons.archive_outlined,
                              color: archived ? Colors.green : Colors.orange,
                            ),
                            onPressed: () {
                              _showArchiveConfirmDialog(context, ref, s.id, s.modelName, s.batteryType, !archived);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                            onPressed: () {
                              _showDeleteConfirmDialog(context, ref, s.id, s.modelName, s.batteryType);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagination(BuildContext context, PaginatedStock paginated) {
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
                  ref.read(stockFilterProvider.notifier).update(
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
                  ref.read(stockFilterProvider.notifier).update(
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

  void _showStockDetailsPanel(BuildContext context, Stock stock) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StockDetailsSheet(stock: stock),
    );
  }
}

class _StockDetailsSheet extends ConsumerStatefulWidget {
  final Stock stock;

  const _StockDetailsSheet({super.key, required this.stock});

  @override
  ConsumerState<_StockDetailsSheet> createState() => _StockDetailsSheetState();
}

class _StockDetailsSheetState extends ConsumerState<_StockDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _serialsController = TextEditingController();
  final _shopSourceController = TextEditingController();
  DateTime _purchaseDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _serialsController.dispose();
    _shopSourceController.dispose();
    super.dispose();
  }

  Future<void> _selectPurchaseDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _purchaseDate) {
      setState(() {
        _purchaseDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final serialsText = _serialsController.text.trim();
    if (serialsText.isEmpty) {
      ToastHelper.show(context, 'Please enter at least one serial number', isError: true);
      return;
    }

    // Split by comma or newline
    final serials = serialsText
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();

    if (serials.isEmpty) {
      ToastHelper.show(context, 'Please enter at least one valid serial number', isError: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(_purchaseDate);
      final shopSource = _shopSourceController.text.trim().isEmpty 
          ? null 
          : _shopSourceController.text.trim();

      await ref.read(stockOperationsProvider).replenishStockUnits(
        widget.stock.id,
        serials,
        formattedDate,
        shopSource,
      );

      if (mounted) {
        ToastHelper.show(context, 'Stock replenished successfully');
        _serialsController.clear();
        _shopSourceController.clear();
        setState(() {
          _purchaseDate = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.show(
          context,
          'Error: ${ErrorParser.parse(e)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unitsAsync = ref.watch(stockUnitsProvider(widget.stock.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 8,
        left: 20,
        right: 20,
        bottom: 20 + bottomInset,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.stock.modelName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Type: ${widget.stock.batteryType}',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.stock.quantity <= widget.stock.lowStockThreshold
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.stock.quantity <= widget.stock.lowStockThreshold
                      ? 'LOW STOCK (${widget.stock.quantity})'
                      : 'IN STOCK (${widget.stock.quantity})',
                  style: TextStyle(
                    color: widget.stock.quantity <= widget.stock.lowStockThreshold
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          // Content Scroll View
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Available Serials Title
                  const Text(
                    'Available Serial Numbers',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  unitsAsync.when(
                    data: (units) {
                      if (units.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(
                            'No available serial numbers found. This item is currently managed as bulk stock.',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: units.map((u) {
                          return Tooltip(
                            message: 'Purchased: ${u.purchaseDate ?? "N/A"}\nSource: ${u.shopSource ?? "N/A"}',
                            child: Chip(
                              label: Text(u.serialNumber),
                              avatar: const Icon(Icons.qr_code, size: 16),
                              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              labelStyle: const TextStyle(fontSize: 13),
                              side: BorderSide(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, stack) => Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                        child: Text(
                          'Error loading serial numbers: ${err.toString()}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  // Add Serials Form
                  const Text(
                    'Replenish Stock (Add Serials)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _serialsController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Serial Numbers',
                            alignLabelWithHint: true,
                            hintText: 'Enter serial numbers separated by commas or newlines\ne.g. EXIDE123, EXIDE456',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.grey[500] : Colors.grey[400],
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Serial numbers are required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _shopSourceController,
                          decoration: const InputDecoration(
                            labelText: 'Supplier Shop / Source (Optional)',
                            hintText: 'e.g. Ramesh Battery House',
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => _selectPurchaseDate(context),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Purchase Date',
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  DateFormat('yyyy-MM-dd').format(_purchaseDate),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Icon(Icons.calendar_today, size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            label: 'Add Serials & Replenish Stock',
                            isLoading: _isSubmitting,
                            onPressed: _submit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
