import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/customer_provider.dart';
import '../../models/customer.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../core/theme.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId;

  const CustomerFormScreen({
    super.key,
    this.customerId,
  });

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Customer section controllers
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _vehicleNoController = TextEditingController();
  final _areaController = TextEditingController();
  final _pincodeController = TextEditingController();
  
  String _purchaseType = 'RETAIL';
  String _vehicleType = '4W'; // Default selection
  String _paymentMode = 'Cash'; // Default payment mode
  final List<String> _paymentModes = ['Cash', 'UPI', 'Net banking', 'Udhari'];
  bool _isPrefilled = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Scrap section (used in both creation and edit)
  bool _scrapBatteryPending = false;
  final _scrapExpectedValueController = TextEditingController();

  // Battery section controllers (only used for creation)
  final _batteryModelController = TextEditingController();
  final _batterySerialController = TextEditingController();
  final _batteryPriceController = TextEditingController();
  final _batteryNotesController = TextEditingController();
  
  int _warrantyMonths = 24; // Default warranty
  String _batteryType = '4W'; // Default battery type
  DateTime _saleDate = DateTime.now();
  int? _serviceReminderInterval = 12; // Default 12 Months
  int? _waterCheckInterval = 6; // Default Every 6 Months

  // Udhari section controllers (only used for creation)
  bool _hasUdhari = false;
  final _totalAmountController = TextEditingController();
  final _paidAmountController = TextEditingController();
  final _paymentMethodController = TextEditingController(text: 'CASH');
  final _paymentNotesController = TextEditingController();
  DateTime? _dueDate;
  double _calculatedPending = 0.0;

  final List<String> _vehicleTypes = ['2W', '4W', 'TRUCK', 'INVERTER', 'OTHER'];
  final List<String> _purchaseTypes = ['RETAIL', 'SHOP'];
  
  final List<int> _warrantyOptions = [0, 6, 12, 18, 24, 30, 36, 48, 60, 72];
  final List<String> _batteryTypes = ['2W', '4W', 'TRUCK', 'INVERTER'];
  final List<String> _paymentMethods = ['CASH', 'UPI', 'CARD', 'NET BANKING'];

  @override
  void initState() {
    super.initState();
    _totalAmountController.addListener(_onPaymentAmountsChanged);
    _paidAmountController.addListener(_onPaymentAmountsChanged);
    _batteryPriceController.addListener(_onBatteryPriceChanged);
  }

  @override
  void dispose() {
    _totalAmountController.removeListener(_onPaymentAmountsChanged);
    _paidAmountController.removeListener(_onPaymentAmountsChanged);
    _batteryPriceController.removeListener(_onBatteryPriceChanged);
    
    _nameController.dispose();
    _mobileController.dispose();
    _vehicleNoController.dispose();
    _areaController.dispose();
    _pincodeController.dispose();
    _scrapExpectedValueController.dispose();

    _batteryModelController.dispose();
    _batterySerialController.dispose();
    _batteryPriceController.dispose();
    _batteryNotesController.dispose();

    _totalAmountController.dispose();
    _paidAmountController.dispose();
    _paymentMethodController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  void _onBatteryPriceChanged() {
    if (_paymentMode != 'Udhari') {
      final priceText = _batteryPriceController.text.trim();
      _totalAmountController.text = priceText;
      _paidAmountController.text = priceText;
      _onPaymentAmountsChanged();
    }
  }

  void _onPaymentAmountsChanged() {
    final total = double.tryParse(_totalAmountController.text.trim()) ?? 0.0;
    final paid = double.tryParse(_paidAmountController.text.trim()) ?? 0.0;
    setState(() {
      _calculatedPending = total - paid;
    });
  }

  void _prefillForm(Customer customer) {
    if (_isPrefilled) return;
    _nameController.text = customer.name;
    _mobileController.text = customer.mobile;
    _vehicleNoController.text = customer.vehicleNo ?? '';
    _areaController.text = customer.area ?? '';
    _pincodeController.text = customer.pincode ?? '';
    _purchaseType = customer.purchaseType;
    _scrapBatteryPending = customer.scrapBatteryPending;
    _scrapExpectedValueController.text = customer.scrapExpectedValue > 0 ? customer.scrapExpectedValue.toStringAsFixed(0) : '';
    
    // Safety check for vehicleType selection
    final normalizedType = customer.vehicleType?.trim().toUpperCase() ?? '';
    if (_vehicleTypes.contains(normalizedType)) {
      _vehicleType = normalizedType;
    } else if (normalizedType.isNotEmpty) {
      _vehicleType = 'OTHER';
    }
    
    // Prefill payment mode
    final mode = customer.paymentMode?.trim() ?? 'Cash';
    final matchedMode = _paymentModes.firstWhere(
      (m) => m.toLowerCase() == mode.toLowerCase(),
      orElse: () => 'Cash',
    );
    _paymentMode = matchedMode;
    _hasUdhari = (_paymentMode == 'Udhari');
    
    _isPrefilled = true;
  }

  Future<void> _selectSaleDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _saleDate) {
      setState(() {
        _saleDate = picked;
      });
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final operations = ref.read(customerOperationsProvider);
      
      if (widget.customerId != null) {
        // Edit Customer Profile Mode
        final payload = {
          'name': _nameController.text.trim(),
          'mobile': _mobileController.text.trim(),
          'vehicle_no': _vehicleNoController.text.trim().isEmpty ? null : _vehicleNoController.text.trim(),
          'vehicle_type': _vehicleType,
          'area': _areaController.text.trim().isEmpty ? null : _areaController.text.trim(),
          'pincode': _pincodeController.text.trim().isEmpty ? null : _pincodeController.text.trim(),
          'purchase_type': _purchaseType,
          'payment_mode': _paymentMode,
          'scrap_battery_pending': _scrapBatteryPending,
          'scrap_expected_value': double.tryParse(_scrapExpectedValueController.text.trim()) ?? 0.0,
        };
        await operations.updateCustomer(widget.customerId!, payload);
      } else {
        // Combined Register Customer + Battery Mode
        final batteryPrice = double.tryParse(_batteryPriceController.text.trim()) ?? 0.0;
        final payload = {
          'name': _nameController.text.trim(),
          'mobile': _mobileController.text.trim(),
          'vehicle_no': _vehicleNoController.text.trim().isEmpty ? null : _vehicleNoController.text.trim(),
          'vehicle_type': _vehicleType,
          'area': _areaController.text.trim().isEmpty ? null : _areaController.text.trim(),
          'pincode': _pincodeController.text.trim().isEmpty ? null : _pincodeController.text.trim(),
          'purchase_type': _purchaseType,
          'payment_mode': _paymentMode,
          'scrap_battery_pending': _scrapBatteryPending,
          'scrap_expected_value': double.tryParse(_scrapExpectedValueController.text.trim()) ?? 0.0,

          // Battery details
          'battery_model': _batteryModelController.text.trim().toUpperCase(),
          'battery_serial_number': _batterySerialController.text.trim().toUpperCase(),
          'battery_warranty_months': _warrantyMonths,
          'battery_type': _batteryType,
          'battery_price': batteryPrice,
          'battery_notes': _batteryNotesController.text.trim().isEmpty ? null : _batteryNotesController.text.trim(),
          'battery_sale_date': _saleDate.toIso8601String().split('T')[0],
          'battery_service_reminder_interval_months': _serviceReminderInterval,
          'battery_water_check_interval_months': _batteryType == 'INVERTER' ? _waterCheckInterval : null,

          // Udhari / payments
          'has_udhari': true, // Always true to create a payment record
        };

        if (_paymentMode == 'Udhari') {
          final totalAmt = double.tryParse(_totalAmountController.text.trim()) ?? batteryPrice;
          final paidAmt = double.tryParse(_paidAmountController.text.trim()) ?? 0.0;
          payload['payment_total_amount'] = totalAmt;
          payload['payment_paid_amount'] = paidAmt;
          payload['payment_method'] = _paymentMethodController.text.trim();
          payload['payment_reminder_note'] = _paymentNotesController.text.trim().isEmpty ? null : _paymentNotesController.text.trim();
          if (_dueDate != null) {
            payload['payment_due_date'] = _dueDate!.toIso8601String().split('T')[0];
          }
        } else {
          payload['payment_total_amount'] = batteryPrice;
          payload['payment_paid_amount'] = batteryPrice;
          payload['payment_method'] = _paymentMode.toUpperCase();
          payload['payment_reminder_note'] = 'Fully paid via $_paymentMode';
        }

        await operations.createCombinedCustomer(payload);
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.customerId != null
                ? 'Customer updated successfully'
                : 'Customer and sale registered successfully',
          ),
        ),
      );
      
      context.go('/customers');
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.customerId != null;

    if (isEditMode) {
      final detailsAsync = ref.watch(customerDetailsProvider(widget.customerId!));
      return detailsAsync.when(
        data: (details) {
          _prefillForm(details.customer);
          return _buildScaffold(context, true);
        },
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryColor),
          ),
        ),
        error: (err, stack) => Scaffold(
          appBar: AppBar(title: const Text('Edit Customer')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error loading customer: $err'),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Go Back',
                  onPressed: () => context.go('/customers'),
                )
              ],
            ),
          ),
        ),
      );
    }

    return _buildScaffold(context, false);
  }

  Widget _buildScaffold(BuildContext context, bool isEditMode) {
    return AppScaffold(
      title: isEditMode ? 'Edit Customer' : 'Add Customer & Sale',
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isEditMode ? 'Modify Customer Profile' : 'Register Customer, Battery & Sale',
                        style: const TextStyle(
                          fontSize: 22,
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
                      
                      // ----------------------------------------------------
                      // CUSTOMER SECTION
                      // ----------------------------------------------------
                      _buildHeader('CUSTOMER DETAILS', Icons.person_outline),
                      const SizedBox(height: 16),
                      
                      AppInput(
                        controller: _nameController,
                        labelText: 'Customer Name *',
                        prefixIcon: Icons.person_outline,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Customer Name is required';
                          }
                          return null;
                        },
                        enabled: !_isSubmitting,
                      ),
                      const SizedBox(height: 16),

                      AppInput(
                        controller: _mobileController,
                        labelText: 'Mobile Number (10 digits) *',
                        prefixIcon: Icons.phone_android_outlined,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Mobile number is required';
                          }
                          final stripped = value.trim();
                          if (!RegExp(r'^\d+$').hasMatch(stripped) || stripped.length != 10) {
                            return 'Mobile number must be exactly 10 digits';
                          }
                          return null;
                        },
                        enabled: !_isSubmitting,
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _paymentMode,
                        decoration: const InputDecoration(
                          labelText: 'Payment Mode *',
                          prefixIcon: Icon(Icons.payment_outlined, size: 20),
                        ),
                        items: _paymentModes.map((mode) {
                          return DropdownMenuItem(
                            value: mode,
                            child: Text(mode),
                          );
                        }).toList(),
                        onChanged: _isSubmitting
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() {
                                    _paymentMode = val;
                                    _hasUdhari = (val == 'Udhari');
                                    
                                    // If we switch away from Udhari, set total and paid to battery price
                                    final priceText = _batteryPriceController.text.trim();
                                    if (val != 'Udhari') {
                                      _totalAmountController.text = priceText;
                                      _paidAmountController.text = priceText;
                                    } else {
                                      _totalAmountController.text = priceText;
                                      _paidAmountController.text = '0.0';
                                    }
                                    _onPaymentAmountsChanged();
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _vehicleType,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle Type',
                          prefixIcon: Icon(Icons.directions_car_outlined, size: 20),
                        ),
                        items: _vehicleTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: _isSubmitting
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() {
                                    _vehicleType = val;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 16),

                      AppInput(
                        controller: _vehicleNoController,
                        labelText: 'Vehicle Number',
                        prefixIcon: Icons.badge_outlined,
                        textCapitalization: TextCapitalization.characters,
                        enabled: !_isSubmitting,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: AppInput(
                              controller: _areaController,
                              labelText: 'Area / Village',
                              prefixIcon: Icons.location_city_outlined,
                              textCapitalization: TextCapitalization.words,
                              enabled: !_isSubmitting,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: AppInput(
                              controller: _pincodeController,
                              labelText: 'Pincode',
                              prefixIcon: Icons.pin_drop_outlined,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              enabled: !_isSubmitting,
                            ),
                          ),
                        ],
                      ),
                      
                      // ----------------------------------------------------
                      // SCRAP BATTERY SECTION
                      // ----------------------------------------------------
                      const SizedBox(height: 24),
                      _buildHeader('SCRAP BATTERY DETAILS', Icons.recycling_outlined),
                      const SizedBox(height: 16),
                      
                      DropdownButtonFormField<String>(
                        value: _scrapBatteryPending ? 'Yes' : 'No',
                        decoration: const InputDecoration(
                          labelText: 'Is Scrap Battery Pending?',
                          prefixIcon: Icon(Icons.help_outline, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'No', child: Text('No')),
                          DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                        ],
                        onChanged: _isSubmitting
                            ? null
                            : (val) {
                                setState(() {
                                  _scrapBatteryPending = (val == 'Yes');
                                });
                              },
                      ),
                      
                      if (_scrapBatteryPending) ...[
                        const SizedBox(height: 16),
                        AppInput(
                          controller: _scrapExpectedValueController,
                          labelText: 'Expected Scrap Value (₹) *',
                          prefixIcon: Icons.currency_rupee,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (_scrapBatteryPending && (value == null || value.trim().isEmpty)) {
                              return 'Expected scrap value is required when pending';
                            }
                            if (_scrapBatteryPending && double.tryParse(value!) == null) {
                              return 'Enter a valid number';
                            }
                            return null;
                          },
                          enabled: !_isSubmitting,
                        ),
                      ],
                      
                      // ----------------------------------------------------
                      // BATTERY SECTION (Skip if editing customer details)
                      // ----------------------------------------------------
                      if (!isEditMode) ...[
                        const SizedBox(height: 24),
                        _buildHeader('BATTERY & SALE DETAILS', Icons.battery_charging_full_outlined),
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              child: AppInput(
                                controller: _batteryModelController,
                                labelText: 'Battery Model *',
                                prefixIcon: Icons.model_training_outlined,
                                textCapitalization: TextCapitalization.characters,
                                validator: (value) {
                                  if (!isEditMode && (value == null || value.trim().isEmpty)) {
                                    return 'Battery Model is required';
                                  }
                                  return null;
                                },
                                enabled: !_isSubmitting,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: AppInput(
                                controller: _batterySerialController,
                                labelText: 'Battery Serial Number *',
                                prefixIcon: Icons.qr_code_outlined,
                                textCapitalization: TextCapitalization.characters,
                                validator: (value) {
                                  if (!isEditMode && (value == null || value.trim().isEmpty)) {
                                    return 'Battery Serial is required';
                                  }
                                  return null;
                                },
                                enabled: !_isSubmitting,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _warrantyMonths,
                                decoration: const InputDecoration(
                                  labelText: 'Warranty Duration *',
                                  prefixIcon: Icon(Icons.verified_outlined, size: 20),
                                ),
                                items: _warrantyOptions.map((months) {
                                  return DropdownMenuItem(
                                    value: months,
                                    child: Text(months == 0 ? 'No Warranty' : '$months Months'),
                                  );
                                }).toList(),
                                onChanged: _isSubmitting
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          setState(() {
                                            _warrantyMonths = val;
                                          });
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _batteryType,
                                decoration: const InputDecoration(
                                  labelText: 'Battery Type *',
                                  prefixIcon: Icon(Icons.flash_on_outlined, size: 20),
                                ),
                                items: _batteryTypes.map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  );
                                }).toList(),
                                onChanged: _isSubmitting
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          setState(() {
                                            _batteryType = val;
                                            if (val == 'INVERTER') {
                                              _waterCheckInterval = 6;
                                            } else {
                                              _waterCheckInterval = null;
                                            }
                                          });
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: AppInput(
                                controller: _batteryPriceController,
                                labelText: 'Battery Price (₹)',
                                prefixIcon: Icons.currency_rupee,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                enabled: !_isSubmitting,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: _isSubmitting ? null : () => _selectSaleDate(context),
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Sale Date *',
                                    prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                                  ),
                                  child: Text(
                                    DateFormat('dd MMM yyyy').format(_saleDate),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        AppInput(
                          controller: _batteryNotesController,
                          labelText: 'Battery / Sale Notes',
                          prefixIcon: Icons.notes_outlined,
                          enabled: !_isSubmitting,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                value: _serviceReminderInterval,
                                decoration: const InputDecoration(
                                  labelText: 'Service Reminder Schedule',
                                  prefixIcon: Icon(Icons.build_outlined, size: 20),
                                ),
                                items: const [
                                  DropdownMenuItem<int?>(value: null, child: Text('No Service Reminder')),
                                  DropdownMenuItem<int?>(value: 3, child: Text('3 Months')),
                                  DropdownMenuItem<int?>(value: 6, child: Text('6 Months')),
                                  DropdownMenuItem<int?>(value: 9, child: Text('9 Months')),
                                  DropdownMenuItem<int?>(value: 12, child: Text('12 Months')),
                                  DropdownMenuItem<int?>(value: 18, child: Text('18 Months')),
                                  DropdownMenuItem<int?>(value: 24, child: Text('24 Months')),
                                ],
                                onChanged: _isSubmitting
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _serviceReminderInterval = val;
                                        });
                                      },
                              ),
                            ),
                            if (_batteryType == 'INVERTER') ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<int?>(
                                  value: _waterCheckInterval,
                                  decoration: const InputDecoration(
                                    labelText: 'Water Check Schedule',
                                    prefixIcon: Icon(Icons.water_drop_outlined, size: 20),
                                  ),
                                  items: const [
                                    DropdownMenuItem<int?>(value: null, child: Text('Disabled')),
                                    DropdownMenuItem<int?>(value: 3, child: Text('Every 3 Months')),
                                    DropdownMenuItem<int?>(value: 6, child: Text('Every 6 Months')),
                                    DropdownMenuItem<int?>(value: 9, child: Text('Every 9 Months')),
                                    DropdownMenuItem<int?>(value: 12, child: Text('Every 12 Months')),
                                  ],
                                  onChanged: _isSubmitting
                                      ? null
                                      : (val) {
                                          setState(() {
                                            _waterCheckInterval = val;
                                          });
                                        },
                                ),
                              ),
                            ],
                          ],
                        ),
                        
                        // ----------------------------------------------------
                        // UDHARI / PAYMENT SECTION (Skip if editing customer details)
                        // ----------------------------------------------------
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'UDHARI / PAYMENT DETAILS',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                            const Spacer(),
                            Switch.adaptive(
                              value: _hasUdhari,
                              activeColor: AppTheme.primaryColor,
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _hasUdhari = value;
                                        if (value) {
                                          // Set default amounts if empty
                                          final priceText = _batteryPriceController.text.trim();
                                          if (priceText.isNotEmpty && _totalAmountController.text.isEmpty) {
                                            _totalAmountController.text = priceText;
                                            _paidAmountController.text = '0.0';
                                            _calculatedPending = double.tryParse(priceText) ?? 0.0;
                                          }
                                        }
                                      });
                                    },
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        
                        if (_hasUdhari) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppInput(
                                  controller: _totalAmountController,
                                  labelText: 'Total Amount *',
                                  prefixIcon: Icons.currency_rupee,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  validator: (value) {
                                    if (!isEditMode && _hasUdhari && (value == null || value.trim().isEmpty)) {
                                      return 'Total Amount is required';
                                    }
                                    final parsed = double.tryParse(value ?? '');
                                    if (_hasUdhari && (parsed == null || parsed <= 0)) {
                                      return 'Total must be greater than 0';
                                    }
                                    return null;
                                  },
                                  enabled: !_isSubmitting,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: AppInput(
                                  controller: _paidAmountController,
                                  labelText: 'Paid Amount *',
                                  prefixIcon: Icons.payments_outlined,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  validator: (value) {
                                    if (!isEditMode && _hasUdhari && (value == null || value.trim().isEmpty)) {
                                      return 'Paid Amount is required';
                                    }
                                    final totalVal = double.tryParse(_totalAmountController.text.trim()) ?? 0.0;
                                    final paidVal = double.tryParse(value ?? '0') ?? 0.0;
                                    if (paidVal < 0) {
                                      return 'Paid cannot be negative';
                                    }
                                    if (paidVal > totalVal) {
                                      return 'Paid cannot exceed Total';
                                    }
                                    return null;
                                  },
                                  enabled: !_isSubmitting,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              // Pending balance display
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.shade100),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Pending Balance (Auto)',
                                            style: TextStyle(fontSize: 12, color: Colors.red),
                                          ),
                                          Text(
                                            '₹${_calculatedPending.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _paymentMethodController.text,
                                  decoration: const InputDecoration(
                                    labelText: 'Payment Method',
                                    prefixIcon: Icon(Icons.credit_card_outlined, size: 20),
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
                                              _paymentMethodController.text = val;
                                            });
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _isSubmitting ? null : () => _selectDueDate(context),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Due Date',
                                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                                    ),
                                    child: Text(
                                      _dueDate != null
                                          ? DateFormat('dd MMM yyyy').format(_dueDate!)
                                          : 'Select Due Date',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: _dueDate != null ? Colors.black : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: AppInput(
                                  controller: _paymentNotesController,
                                  labelText: 'Reminder Note',
                                  prefixIcon: Icons.comment_bank_outlined,
                                  enabled: !_isSubmitting,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              'Sale is fully paid. Enable toggle above if this sale has pending payment (udhari).',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 32),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AppButton(
                            label: 'Cancel',
                            isSecondary: true,
                            onPressed: _isSubmitting ? null : () => context.go('/customers'),
                          ),
                          const SizedBox(width: 16),
                          AppButton(
                            label: isEditMode ? 'Update Profile' : 'Register Customer & Sale',
                            isLoading: _isSubmitting,
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

  Widget _buildHeader(String title, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: AppTheme.secondaryColor,
              ),
            ),
          ],
        ),
        const Divider(),
      ],
    );
  }
}
