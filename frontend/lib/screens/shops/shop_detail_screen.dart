import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../providers/shop_provider.dart';
import '../../models/shop.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/toast_helper.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/download_helper.dart';

class ShopDetailScreen extends ConsumerStatefulWidget {
  final String shopId;

  const ShopDetailScreen({
    super.key,
    required this.shopId,
  });

  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSettlePaymentDialog(BuildContext context, double pendingAmount) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(text: pendingAmount.toStringAsFixed(2));
    final notesController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Settle Udhari Payment'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Outstanding Balance: ₹${pendingAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Settlement Amount (₹) *',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Amount is required';
                    final val = double.tryParse(v.trim());
                    if (val == null || val <= 0) return 'Must be greater than 0';
                    if (val > pendingAmount) return 'Cannot exceed outstanding balance';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Remarks',
                    prefixIcon: Icon(Icons.note_alt_rounded),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSubmitting = true);
                      try {
                        final amt = double.parse(amountController.text.trim());
                        final notes = notesController.text.trim().isEmpty ? null : notesController.text.trim();
                        await ref.read(shopOperationsProvider).settleShopPayment(widget.shopId, amt, notes);
                        if (context.mounted) {
                          ToastHelper.show(context, 'Payment settled successfully');
                          Navigator.pop(dialogContext);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ToastHelper.show(context, 'Failed to log settlement: $e', isError: true);
                        }
                      } finally {
                        setDialogState(() => isSubmitting = false);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm Pay'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPurchaseDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String? selectedBatteryModel;
    final serialNumberController = TextEditingController();
    final invoiceNumberController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final amountController = TextEditingController();
    final udhariAmountController = TextEditingController(text: '0');
    DateTime purchaseDate = DateTime.now();
    bool isSubmitting = false;
    String? localError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Add Battery Purchase'),
            content: Consumer(
              builder: (consumerContext, ref, child) {
                final stockModelsAsync = ref.watch(activeStockModelsProvider);
                return Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (localError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              localError!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        stockModelsAsync.when(
                          data: (stockItems) {
                            if (stockItems.isEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Text(
                                      'No active stock items found! You can enter the model manually.',
                                      style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    decoration: const InputDecoration(
                                      labelText: 'Battery Model *',
                                      prefixIcon: Icon(Icons.battery_saver_rounded),
                                    ),
                                    textCapitalization: TextCapitalization.characters,
                                    onChanged: (v) {
                                      selectedBatteryModel = v.trim().isEmpty ? null : v.trim();
                                    },
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a battery model' : null,
                                  ),
                                ],
                              );
                            }
                            return DropdownButtonFormField<String>(
                              value: selectedBatteryModel,
                              decoration: const InputDecoration(
                                labelText: 'Select Battery Model *',
                                prefixIcon: Icon(Icons.battery_saver_rounded),
                              ),
                              items: stockItems.map((item) {
                                return DropdownMenuItem<String>(
                                  value: item.modelName,
                                  child: Text('${item.modelName} (Stock: ${item.quantity})'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedBatteryModel = value;
                                });
                              },
                              validator: (v) => v == null ? 'Please select a battery model' : null,
                            );
                          },
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (err, st) => Text(
                            'Error loading stock: $err',
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: serialNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Battery Serial Number *',
                            prefixIcon: Icon(Icons.qr_code_rounded),
                          ),
                          textCapitalization: TextCapitalization.characters,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Serial number is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: invoiceNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Invoice / Bill Number (Optional)',
                            prefixIcon: Icon(Icons.receipt_long_rounded),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: quantityController,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity *',
                                  prefixIcon: Icon(Icons.production_quantity_limits_rounded),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  final qty = int.tryParse(v.trim());
                                  if (qty == null || qty <= 0) return 'Must be > 0';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: purchaseDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      purchaseDate = picked;
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Purchase Date',
                                    prefixIcon: Icon(Icons.calendar_month_rounded),
                                  ),
                                  child: Text(
                                    DateFormat('dd MMM yyyy').format(purchaseDate),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: amountController,
                                decoration: const InputDecoration(
                                  labelText: 'Bill Amount (₹) *',
                                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  final val = double.tryParse(v.trim());
                                  if (val == null || val < 0) return 'Must be >= 0';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: udhariAmountController,
                                decoration: const InputDecoration(
                                  labelText: 'Udhari Amount (₹)',
                                  prefixIcon: Icon(Icons.credit_card_rounded),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  final val = double.tryParse(v.trim());
                                  if (val == null || val < 0) return 'Must be >= 0';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        if (selectedBatteryModel == null) {
                          setDialogState(() {
                            localError = 'Please select a battery model';
                          });
                          return;
                        }

                        final amt = double.parse(amountController.text.trim());
                        final udhari = double.tryParse(udhariAmountController.text.trim()) ?? 0.0;

                        if (udhari > amt) {
                          setDialogState(() {
                            localError = 'Udhari cannot be greater than bill amount';
                          });
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          localError = null;
                        });

                        final payload = {
                          'battery_model': selectedBatteryModel,
                          'serial_number': serialNumberController.text.trim(),
                          'invoice_number': invoiceNumberController.text.trim(),
                          'quantity': int.parse(quantityController.text.trim()),
                          'purchase_date': DateFormat('yyyy-MM-dd').format(purchaseDate),
                          'amount': amt,
                          'udhari_amount': udhari,
                        };

                        try {
                          await ref.read(shopOperationsProvider).logShopPurchase(widget.shopId, payload);
                          if (context.mounted) {
                            ToastHelper.show(context, 'Purchase logged successfully');
                            Navigator.pop(dialogContext);
                          }
                        } on DioException catch (e) {
                          final data = e.response?.data;
                          String msg = 'Failed to log purchase';
                          if (data is Map && data.containsKey('detail')) {
                            msg = data['detail'].toString();
                          }
                          setDialogState(() {
                            localError = msg;
                            isSubmitting = false;
                          });
                        } catch (e) {
                          setDialogState(() {
                            localError = 'An unexpected error occurred: $e';
                            isSubmitting = false;
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Purchase'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showArchiveConfirmDialog(BuildContext context, String name, bool archive) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(archive ? 'Archive Shop?' : 'Restore Shop?'),
          content: Text(
            archive
                ? 'Are you sure you want to archive "$name"? This will hide it from the active registry.'
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
                try {
                  if (archive) {
                    await ref.read(shopOperationsProvider).archiveShop(widget.shopId);
                    if (context.mounted) ToastHelper.show(context, 'Shop archived successfully');
                  } else {
                    await ref.read(shopOperationsProvider).restoreShop(widget.shopId);
                    if (context.mounted) ToastHelper.show(context, 'Shop restored successfully');
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

  void _showDeleteConfirmDialog(BuildContext context, String name) {
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
                  await ref.read(shopOperationsProvider).deleteShop(widget.shopId);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Shop permanently deleted');
                    context.go('/shops');
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

  Future<void> _downloadStatement(BuildContext context) async {
    final apiClient = ref.read(apiClientProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final filename = 'shop_statement_${widget.shopId}_$today.xlsx';

    try {
      final response = await apiClient.dio.get<List<int>>(
        '/exports/shop-statement/${widget.shopId}',
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        downloadFile(response.data!, filename);
        if (context.mounted) {
          ToastHelper.show(context, 'Statement downloaded successfully');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ToastHelper.show(context, 'Download failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(shopDetailsProvider(widget.shopId));

    return AppScaffold(
      title: 'Shop Ledger Details',
      child: detailsAsync.when(
        data: (details) {
          final shop = details.shop;
          final payment = details.payment;
          final purchases = details.purchases;
          final transactions = details.transactions;

          final totalPaid = payment?.paidAmount ?? 0.0;
          final pendingUdhari = payment?.pendingAmount ?? 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.go('/shops'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                shop.shopName,
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (shop.isArchived) ...[
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Text(
                                    'Archived',
                                    style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            'Owner: ${shop.ownerName} | Mobile: ${shop.mobile}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    _buildActionsMenu(context, shop, pendingUdhari),
                  ],
                ),
                const SizedBox(height: 24),

                // Shop Information Card (integrates contact info & requested KPI metrics)
                _buildShopInfoCard(context, shop, purchases, totalPaid, pendingUdhari),
                const SizedBox(height: 24),

                // Tab Bar Header
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.primaryColor,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: AppTheme.primaryColor,
                    tabs: const [
                      Tab(text: 'Battery Purchase History'),
                      Tab(text: 'Udhari Ledger History'),
                    ],
                  ),
                ),

                // Tab Content Panel
                SizedBox(
                  height: 600,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBatteryPurchaseHistoryTable(purchases),
                      _buildUdhariLedgerHistory(transactions),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Error loading shop: $err', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  Widget _buildShopInfoCard(BuildContext context, Shop shop, List<ShopPurchase> purchases, double totalPaid, double totalUdhari) {
    final totalPurchasesCount = purchases.length;
    final totalBatteriesPurchased = purchases.fold<int>(0, (sum, p) => sum + p.quantity);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shop Information Card',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Shop Name:', shop.shopName),
                      const SizedBox(height: 8),
                      _buildInfoRow('Owner Name:', shop.ownerName),
                      const SizedBox(height: 8),
                      _buildInfoRow('Mobile:', shop.mobile),
                      const SizedBox(height: 8),
                      _buildInfoRow('Address:', shop.address ?? 'N/A'),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 768;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 4 : 2,
                  childAspectRatio: isWide ? 2.0 : 1.3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildMetricCard('Total Purchases', '$totalPurchasesCount bills', Icons.receipt_long_rounded, Colors.blue),
                    _buildMetricCard('Total Batteries Purchased', '$totalBatteriesPurchased units', Icons.battery_charging_full_rounded, Colors.purple),
                    _buildMetricCard('Total Paid', '₹${totalPaid.toStringAsFixed(2)}', Icons.price_check_rounded, Colors.green),
                    _buildMetricCard('Total Udhari', '₹${totalUdhari.toStringAsFixed(2)}', Icons.pending_actions_rounded, totalUdhari > 0 ? Colors.red : Colors.green),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade800),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsMenu(BuildContext context, Shop shop, double pendingAmount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.download_rounded, color: Colors.blue),
          tooltip: 'Download Shop Statement',
          onPressed: () => _downloadStatement(context),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: pendingAmount <= 0 ? null : () => _showSettlePaymentDialog(context, pendingAmount),
          icon: const Icon(Icons.payment_rounded),
          label: const Text('Settle Payment'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: '+ Add Battery Purchase',
          icon: Icons.add_rounded,
          onPressed: () => _showAddPurchaseDialog(context),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (val) {
            if (val == 'edit') {
              context.go('/shops/${shop.id}/edit');
            } else if (val == 'archive') {
              _showArchiveConfirmDialog(context, shop.shopName, !shop.isArchived);
            } else if (val == 'delete') {
              _showDeleteConfirmDialog(context, shop.shopName);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Profile')])),
            PopupMenuItem(
              value: 'archive',
              child: Row(
                children: [
                  Icon(shop.isArchived ? Icons.unarchive_rounded : Icons.archive_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(shop.isArchived ? 'Restore Shop' : 'Archive Shop')
                ],
              ),
            ),
            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete Shop', style: TextStyle(color: Colors.red))])),
          ],
        ),
      ],
    );
  }

  Widget _buildBatteryPurchaseHistoryTable(List<ShopPurchase> purchases) {
    if (purchases.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(top: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: EmptyState(
          title: 'No Purchases Logged',
          message: 'Record battery stock transactions under this retailer to build purchase history.',
          icon: Icons.shopping_bag_outlined,
          actionLabel: '+ Add Battery Purchase',
          onAction: () => _showAddPurchaseDialog(context),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                columns: const [
                  DataColumn(label: Text('Purchase Date')),
                  DataColumn(label: Text('Battery Model')),
                  DataColumn(label: Text('Battery Serial Number')),
                  DataColumn(label: Text('Quantity', textAlign: TextAlign.center)),
                  DataColumn(label: Text('Amount (₹)', textAlign: TextAlign.right)),
                  DataColumn(label: Text('Udhari Amount (₹)', textAlign: TextAlign.right)),
                  DataColumn(label: Text('Status', textAlign: TextAlign.center)),
                ],
                rows: purchases.map((p) {
                  final isPaid = p.udhariAmount == 0;
                  return DataRow(
                    cells: [
                      DataCell(Text(DateFormat('dd MMM yyyy').format(DateTime.parse(p.purchaseDate)))),
                      DataCell(Text(p.batteryModel, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(p.serialNumber)),
                      DataCell(Center(child: Text('${p.quantity}'))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text('₹${p.amount.toStringAsFixed(2)}'))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text('₹${p.udhariAmount.toStringAsFixed(2)}'))),
                      DataCell(
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPaid ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isPaid ? Colors.green.shade200 : Colors.red.shade200),
                            ),
                            child: Text(
                              isPaid ? 'Paid' : 'Udhari',
                              style: TextStyle(
                                color: isPaid ? Colors.green.shade900 : Colors.red.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
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
    );
  }

  Widget _buildUdhariLedgerHistory(List<ShopPaymentTransaction> transactions) {
    if (transactions.isEmpty) {
      return const EmptyState(
        title: 'No Ledger Entries',
        message: 'All Udhari bills and payments will log entries here chronologically.',
        icon: Icons.history_rounded,
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListView.builder(
        itemCount: transactions.length,
        itemBuilder: (ctx, idx) {
          final tx = transactions[idx];
          final isAddition = tx.transactionType == 'ADDITION';
          
          return Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isAddition ? Colors.red.shade50 : Colors.green.shade50,
                child: Icon(
                  isAddition ? Icons.trending_up_rounded : Icons.price_check_rounded,
                  color: isAddition ? Colors.red : Colors.green,
                ),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isAddition ? 'Udhari Addition' : 'Payment Collection',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isAddition ? Colors.red.shade900 : Colors.green.shade900),
                  ),
                  Text(
                    '${isAddition ? "+" : "-"} ₹${tx.amount.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isAddition ? Colors.red : Colors.green),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.notes ?? (isAddition ? 'Stock bill purchase addition' : 'Retailer payoff settlement')),
                    const SizedBox(height: 2),
                    Text(
                      'Logged: ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.parse(tx.createdAt).toLocal())}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
