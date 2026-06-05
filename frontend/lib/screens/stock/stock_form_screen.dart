import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/stock_provider.dart';
import '../../models/stock.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/toast_helper.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

class StockFormScreen extends ConsumerStatefulWidget {
  final String? stockId;

  const StockFormScreen({
    super.key,
    this.stockId,
  });

  @override
  ConsumerState<StockFormScreen> createState() => _StockFormScreenState();
}

class _StockFormScreenState extends ConsumerState<StockFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _modelNameController = TextEditingController();
  final _quantityController = TextEditingController(text: '0');
  final _lowStockThresholdController = TextEditingController(text: '2');

  String _batteryType = '4W'; // Default type selection
  bool _isPrefilled = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _batteryTypes = ['2W', '4W', 'TRUCK', 'INVERTER'];

  @override
  void dispose() {
    _modelNameController.dispose();
    _quantityController.dispose();
    _lowStockThresholdController.dispose();
    super.dispose();
  }

  void _prefillForm(Stock stock) {
    if (_isPrefilled) return;
    _modelNameController.text = stock.modelName;
    _quantityController.text = stock.quantity.toString();
    _lowStockThresholdController.text = stock.lowStockThreshold.toString();
    
    // Safety check for batteryType selection
    final normalizedType = stock.batteryType.trim().toUpperCase();
    if (_batteryTypes.contains(normalizedType)) {
      _batteryType = normalizedType;
    }
    
    _isPrefilled = true;
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final modelName = _modelNameController.text.trim().toUpperCase();
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    final threshold = int.tryParse(_lowStockThresholdController.text.trim()) ?? 2;

    final payload = {
      'model_name': modelName,
      'battery_type': _batteryType,
      'quantity': quantity,
      'low_stock_threshold': threshold,
    };

    try {
      final operations = ref.read(stockOperationsProvider);
      if (widget.stockId != null) {
        await operations.updateStock(widget.stockId!, payload);
      } else {
        await operations.createStock(payload);
      }

      if (!mounted) return;
      ToastHelper.show(
        context,
        widget.stockId != null 
            ? 'Stock item updated successfully' 
            : 'Stock item added successfully',
      );
      context.go('/stock');
    } catch (e) {
      setState(() {
        _errorMessage = ErrorParser.parse(e);
        _isSubmitting = false;
      });
      if (mounted) {
        ToastHelper.show(
          context,
          'Operation failed: $_errorMessage',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.stockId != null;

    if (isEdit) {
      final stockDetailsAsync = ref.watch(stockDetailsProvider(widget.stockId!));
      return stockDetailsAsync.when(
        data: (stock) {
          _prefillForm(stock);
          return _buildFormScaffold(context, 'Edit Stock Configuration');
        },
        loading: () => const AppScaffold(
          title: 'Edit Stock Configuration',
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryColor),
          ),
        ),
        error: (err, stack) => AppScaffold(
          title: 'Edit Stock Configuration',
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load stock details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(ErrorParser.parse(err), style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Back to Stock',
                  onPressed: () => context.go('/stock'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildFormScaffold(context, 'Add Stock Item');
  }

  Widget _buildFormScaffold(BuildContext context, String title) {
    return AppScaffold(
      title: title,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.stockId != null
                            ? 'Modify the stock metadata parameters.'
                            : 'Enter model, battery type, current quantity, and threshold alerts.',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      // Model Name Field
                      AppInput(
                        labelText: 'Model Name *',
                        controller: _modelNameController,
                        hintText: 'e.g. SF SONIC, EXIDE MILEAGE',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Model name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Battery Type dropdown
                      const Text(
                        'Battery Type *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _batteryType,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                          ),
                        ),
                        items: _batteryTypes.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _batteryType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 20),

                      // Quantity field
                      AppInput(
                        labelText: 'Quantity *',
                        controller: _quantityController,
                        hintText: 'e.g. 10',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Quantity is required';
                          }
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null || parsed < 0) {
                            return 'Quantity must be 0 or greater';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Low Stock Threshold field
                      AppInput(
                        labelText: 'Low Stock Threshold *',
                        controller: _lowStockThresholdController,
                        hintText: 'e.g. 2',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Threshold is required';
                          }
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null || parsed < 0) {
                            return 'Threshold must be 0 or greater';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            onPressed: _isSubmitting ? null : () => context.go('/stock'),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 16),
                          AppButton(
                            label: _isSubmitting ? 'Saving...' : 'Save Stock Item',
                            onPressed: _isSubmitting ? null : _saveForm,
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
      ),
    );
  }
}
