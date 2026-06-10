import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../providers/shop_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../core/theme.dart';

class ShopPurchaseFormScreen extends ConsumerStatefulWidget {
  final String shopId;

  const ShopPurchaseFormScreen({
    super.key,
    required this.shopId,
  });

  @override
  ConsumerState<ShopPurchaseFormScreen> createState() => _ShopPurchaseFormScreenState();
}

class _ShopPurchaseFormScreenState extends ConsumerState<ShopPurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedBatteryModel;
  final _serialNumberController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _amountController = TextEditingController();
  final _udhariAmountController = TextEditingController(text: '0');

  DateTime _purchaseDate = DateTime.now();
  String _paymentMode = 'Cash';
  final List<String> _paymentModes = ['Cash', 'UPI', 'Net banking', 'Udhari'];
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _serialNumberController.dispose();
    _invoiceNumberController.dispose();
    _quantityController.dispose();
    _amountController.dispose();
    _udhariAmountController.dispose();
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

    if (_selectedBatteryModel == null) {
      setState(() {
        _errorMessage = 'Please select a battery model';
      });
      return;
    }

    final totalAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final udhariAmount = _paymentMode == 'Udhari' ? (double.tryParse(_udhariAmountController.text.trim()) ?? 0.0) : 0.0;

    if (_paymentMode == 'Udhari' && udhariAmount > totalAmount) {
      setState(() {
        _errorMessage = 'Udhari amount cannot be greater than the total amount';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final payload = {
      'battery_model': _selectedBatteryModel,
      'serial_number': _serialNumberController.text.trim(),
      'invoice_number': _invoiceNumberController.text.trim(),
      'quantity': int.tryParse(_quantityController.text.trim()) ?? 1,
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'amount': totalAmount,
      'udhari_amount': udhariAmount,
      'payment_mode': _paymentMode,
    };

    try {
      await ref.read(shopOperationsProvider).logShopPurchase(widget.shopId, payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shop purchase recorded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/shops/${widget.shopId}');
      }
    } on DioException catch (e) {
      final responseData = e.response?.data;
      String detail = 'Failed to record purchase';
      if (responseData is Map && responseData.containsKey('detail')) {
        detail = responseData['detail'].toString();
      }
      setState(() {
        _errorMessage = detail;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
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
    final stockModelsAsync = ref.watch(activeStockModelsProvider);
    final shopDetailsAsync = ref.watch(shopDetailsProvider(widget.shopId));

    return shopDetailsAsync.when(
      data: (details) {
        final shop = details.shop;
        return AppScaffold(
          title: 'Log Shop Purchase',
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back navigation header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.go('/shops/${widget.shopId}'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Log Shop Purchase',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 48.0),
                  child: Text(
                    'Recording new inventory invoice for: ${shop.shopName} (Owner: ${shop.ownerName})',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: Colors.red.shade900),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              Text(
                                'Purchase Invoice Details',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                              ),
                              const SizedBox(height: 20),

                              // Stock list dropdown selector
                              stockModelsAsync.when(
                                data: (stockItems) {
                                  if (stockItems.isEmpty) {
                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'No active inventory items found in Stock. Please configure your Stock first!',
                                              style: TextStyle(color: Colors.amber.shade900),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  return DropdownButtonFormField<String>(
                                    value: _selectedBatteryModel,
                                    decoration: const InputDecoration(
                                      labelText: 'Select Battery Model *',
                                      prefixIcon: Icon(Icons.battery_saver_rounded),
                                    ),
                                    items: stockItems.map((item) {
                                      return DropdownMenuItem<String>(
                                        value: item.modelName,
                                        child: Text(
                                          '${item.modelName} (${item.batteryType}) — Stock Qty: ${item.quantity}',
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedBatteryModel = value;
                                      });
                                    },
                                    validator: (v) =>
                                        v == null ? 'Please select a battery model' : null,
                                  );
                                },
                                loading: () => const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                error: (err, st) => Text(
                                  'Failed to load battery stock: $err',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                              const SizedBox(height: 20),

                              AppInput(
                                controller: _serialNumberController,
                                labelText: 'Battery Serial Number *',
                                hintText: 'Enter mandatory unique serial code',
                                prefixIcon: Icons.qr_code_rounded,
                                textCapitalization: TextCapitalization.characters,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Battery serial number is required'
                                    : null,
                              ),
                              const SizedBox(height: 20),

                              AppInput(
                                controller: _invoiceNumberController,
                                labelText: 'Invoice / Bill Number *',
                                hintText: 'Enter purchase invoice number',
                                prefixIcon: Icons.receipt_long_rounded,
                                textCapitalization: TextCapitalization.characters,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Invoice number is required'
                                    : null,
                              ),
                              const SizedBox(height: 20),

                              DropdownButtonFormField<String>(
                                value: _paymentMode,
                                decoration: const InputDecoration(
                                  labelText: 'Payment Mode *',
                                  prefixIcon: Icon(Icons.payment_outlined),
                                ),
                                items: _paymentModes.map((mode) {
                                  return DropdownMenuItem(
                                    value: mode,
                                    child: Text(mode),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _paymentMode = val;
                                      if (val != 'Udhari') {
                                        _udhariAmountController.text = '0';
                                      }
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 20),

                              Row(
                                children: [
                                  Expanded(
                                    child: AppInput(
                                      controller: _quantityController,
                                      labelText: 'Quantity *',
                                      prefixIcon: Icons.production_quantity_limits_rounded,
                                      keyboardType: TextInputType.number,
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Required';
                                        final qty = int.tryParse(v.trim());
                                        if (qty == null || qty <= 0) return 'Must be > 0';
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _selectPurchaseDate(context),
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          labelText: 'Purchase Date',
                                          prefixIcon: Icon(Icons.calendar_month_rounded),
                                        ),
                                        child: Text(
                                          DateFormat('dd MMM yyyy').format(_purchaseDate),
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              Row(
                                children: [
                                  Expanded(
                                    child: AppInput(
                                      controller: _amountController,
                                      labelText: 'Total Bill Amount (₹) *',
                                      prefixIcon: Icons.currency_rupee_rounded,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Required';
                                        final val = double.tryParse(v.trim());
                                        if (val == null || val < 0) return 'Must be >= 0';
                                        return null;
                                      },
                                    ),
                                  ),
                                  if (_paymentMode == 'Udhari') ...[
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: AppInput(
                                        controller: _udhariAmountController,
                                        labelText: 'Udhari Amount (₹)',
                                        prefixIcon: Icons.credit_card_rounded,
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
                                ],
                              ),
                              const SizedBox(height: 32),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => context.go('/shops/${widget.shopId}'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 16),
                                  AppButton(
                                    label: 'Log Purchase',
                                    isLoading: _isSubmitting,
                                    icon: Icons.check_circle_rounded,
                                    onPressed: _submit,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const AppScaffold(
        title: 'Loading...',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, st) => AppScaffold(
        title: 'Error',
        child: Center(child: Text('Error loading shop: $err')),
      ),
    );
  }
}
