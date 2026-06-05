import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/payment_provider.dart';
import '../../providers/customer_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/toast_helper.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

class PaymentFormScreen extends ConsumerStatefulWidget {
  final String customerId;

  const PaymentFormScreen({
    super.key,
    required this.customerId,
  });

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _totalController = TextEditingController();
  final _paidController = TextEditingController(text: '0');
  final _noteController = TextEditingController();
  
  String? _selectedBatteryId;
  double _pendingAmount = 0.0;
  bool _isSubmitting = false;
  String? _errorMessage;
  String _paymentMethod = 'CASH';
  final List<String> _paymentMethods = ['CASH', 'UPI', 'CARD', 'OTHER'];

  @override
  void initState() {
    super.initState();
    // Live update of pending balance as the user types
    _totalController.addListener(_calculatePending);
    _paidController.addListener(_calculatePending);
  }

  @override
  void dispose() {
    _totalController.dispose();
    _paidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _calculatePending() {
    final total = double.tryParse(_totalController.text.trim()) ?? 0.0;
    final paid = double.tryParse(_paidController.text.trim()) ?? 0.0;
    final diff = total - paid;
    setState(() {
      _pendingAmount = diff < 0 ? 0.0 : diff;
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final total = double.parse(_totalController.text.trim());
    final paid = double.parse(_paidController.text.trim());

    final notes = _noteController.text.trim();
    final reminderNote = notes.isEmpty ? '[Method: $_paymentMethod]' : '[Method: $_paymentMethod] $notes';

    final payload = {
      'customer_id': widget.customerId,
      'battery_id': _selectedBatteryId, // Can be null
      'total_amount': total,
      'paid_amount': paid,
      'reminder_note': reminderNote,
    };

    try {
      await ref.read(paymentOperationsProvider).createPayment(payload);
      
      if (!mounted) return;
      ToastHelper.show(context, 'Payment record saved successfully');
      context.go('/customers/${widget.customerId}');
    } catch (e) {
      setState(() {
        _errorMessage = ErrorParser.parse(e);
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(customerDetailsProvider(widget.customerId));

    return Scaffold(
      body: detailsAsync.when(
        data: (details) {
          final c = details.customer;
          final batteries = details.batteries;

          return AppScaffold(
            title: 'New Payment Record',
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Add Transaction for ${c.name}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  border: Border.all(color: Colors.red.shade200),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade900, fontSize: 14),
                                ),
                              ),

                            // Linked Battery Dropdown
                            if (batteries.isNotEmpty) ...[
                              DropdownButtonFormField<String?>(
                                initialValue: _selectedBatteryId,
                                decoration: const InputDecoration(
                                  labelText: 'Link Battery Guarantee (Optional)',
                                  prefixIcon: Icon(Icons.link_outlined, size: 20),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('General Store Purchase (No Link)'),
                                  ),
                                  ...batteries.map((b) {
                                    final label = '${b.batteryType} Battery (${b.serialNumber ?? 'No Serial'})';
                                    return DropdownMenuItem<String?>(
                                      value: b.id,
                                      child: Text(label),
                                    );
                                  }),
                                ],
                                onChanged: _isSubmitting
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _selectedBatteryId = val;
                                        });
                                      },
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Total Bill Amount
                            AppInput(
                              controller: _totalController,
                              labelText: 'Total Bill Amount (₹) *',
                              prefixIcon: Icons.currency_rupee,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the total bill amount';
                                }
                                final num = double.tryParse(value.trim());
                                if (num == null || num <= 0) {
                                  return 'Must be a positive number greater than 0';
                                }
                                return null;
                              },
                              enabled: !_isSubmitting,
                            ),
                            const SizedBox(height: 20),

                            // Paid Amount
                            AppInput(
                              controller: _paidController,
                              labelText: 'Amount Paid Now (₹) *',
                              prefixIcon: Icons.payments_outlined,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the amount paid';
                                }
                                final num = double.tryParse(value.trim());
                                if (num == null || num < 0) {
                                  return 'Paid amount cannot be negative';
                                }
                                return null;
                              },
                              enabled: !_isSubmitting,
                            ),
                            const SizedBox(height: 24),

                            // Balance indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _pendingAmount > 0
                                    ? Colors.orange.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _pendingAmount > 0
                                      ? Colors.orange.shade200
                                      : Colors.green.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _pendingAmount > 0 ? 'Pending Udhari Balance:' : 'Status: Fully Settled',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _pendingAmount > 0
                                          ? Colors.orange.shade900
                                          : Colors.green.shade900,
                                    ),
                                  ),
                                  Text(
                                    FormatUtils.formatIndianCurrency(_pendingAmount),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _pendingAmount > 0
                                          ? Colors.orange.shade900
                                          : Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                             // Payment Method Selection
                             const Text(
                               'Payment Method *',
                               style: TextStyle(
                                 fontSize: 14,
                                 fontWeight: FontWeight.bold,
                                 color: AppTheme.secondaryColor,
                               ),
                             ),
                             const SizedBox(height: 8),
                             DropdownButtonFormField<String>(
                               initialValue: _paymentMethod,
                               decoration: const InputDecoration(
                                 prefixIcon: Icon(Icons.payment_outlined, size: 20),
                               ),
                               items: _paymentMethods.map((method) {
                                 return DropdownMenuItem(
                                   value: method,
                                   child: Text(method),
                                 );
                               }).toList(),
                               onChanged: _isSubmitting
                                   ? null
                                   : (val) {
                                       if (val != null) {
                                         setState(() {
                                           _paymentMethod = val;
                                         });
                                       }
                                     },
                             ),
                             const SizedBox(height: 20),

                             // Reminder Note
                             AppInput(
                               controller: _noteController,
                               labelText: 'Udhari Reminder Note / Comment',
                               prefixIcon: Icons.note_alt_outlined,
                               hintText: 'e.g. Will pay balance next Tuesday',
                               maxLines: 2,
                               enabled: !_isSubmitting,
                             ),
                             const SizedBox(height: 32),

                            // Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                AppButton(
                                  label: 'Cancel',
                                  isSecondary: true,
                                  onPressed: _isSubmitting ? null : () => context.go('/customers/${widget.customerId}'),
                                ),
                                const SizedBox(width: 16),
                                AppButton(
                                  label: 'Save Record',
                                  isLoading: _isSubmitting,
                                  onPressed: _isSubmitting ? null : _submitForm,
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
        },
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryColor),
          ),
        ),
        error: (err, stack) => Scaffold(
          appBar: AppBar(title: const Text('New Payment Record')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: ${ErrorParser.parse(err)}'),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Go Back',
                  onPressed: () => context.go('/customers/${widget.customerId}'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
