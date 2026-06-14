import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/battery_provider.dart';
import '../../providers/customer_provider.dart';
import '../../models/stock.dart';
import '../../models/battery.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/toast_helper.dart';
import '../../core/api_client.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

// Independent provider to fetch active stock items for form selection
final activeStockDropdownProvider = FutureProvider<List<Stock>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get(
    '/stock',
    queryParameters: {
      'page': 1,
      'limit': 100,
      'archived': false,
    },
  );
  final data = response.data['data'] as List<dynamic>? ?? [];
  return data.map((s) => Stock.fromJson(s as Map<String, dynamic>)).toList();
});

class BatteryFormScreen extends ConsumerStatefulWidget {
  final String customerId;
  final String? batteryId;

  const BatteryFormScreen({
    super.key,
    required this.customerId,
    this.batteryId,
  });

  @override
  ConsumerState<BatteryFormScreen> createState() => _BatteryFormScreenState();
}

class _BatteryFormScreenState extends ConsumerState<BatteryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  final _saleDateController = TextEditingController();
  final _warrantyController = TextEditingController(text: '36'); // Default 3 years
  final _notesController = TextEditingController();
  
  String _batteryType = '4W'; // Default selection
  bool _autoReduceStock = true; // Auto reduce inventory stock on sale
  bool _isPrefilled = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  String? _selectedStockId;

  int? _serviceReminderInterval = 12; // Default 12 Months
  int? _waterCheckInterval = 6; // Default Every 6 Months

  final List<String> _batteryTypes = ['2W', '4W', 'TRUCK', 'INVERTER'];

  @override
  void initState() {
    super.initState();
    // Default sale date to today
    _saleDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // Auto-uppercase serial number while typing
    _serialController.addListener(() {
      final text = _serialController.text;
      final upper = text.toUpperCase();
      if (text != upper) {
        _serialController.value = _serialController.value.copyWith(
          text: upper,
          selection: TextSelection.collapsed(offset: upper.length),
        );
      }
    });

    _modelController.addListener(() {
      final text = _modelController.text;
      final upper = text.toUpperCase();
      if (text != upper) {
        _modelController.value = _modelController.value.copyWith(
          text: upper,
          selection: TextSelection.collapsed(offset: upper.length),
        );
      }
    });

    // Refresh preview when warranty or sale date changes
    _warrantyController.addListener(() {
      if (mounted) setState(() {});
    });
    _saleDateController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _modelController.dispose();
    _serialController.dispose();
    _saleDateController.dispose();
    _warrantyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _prefillForm(Battery battery) {
    if (_isPrefilled) return;
    _modelController.text = battery.modelNumber ?? '';
    _serialController.text = battery.serialNumber ?? '';
    _saleDateController.text = battery.saleDate;
    _warrantyController.text = battery.warrantyMonths.toString();
    _notesController.text = battery.notes ?? '';
    _batteryType = battery.batteryType;
    _serviceReminderInterval = battery.serviceReminderIntervalMonths;
    _waterCheckInterval = battery.waterCheckIntervalMonths;
    _autoReduceStock = false; // Disable auto-reduce by default when editing existing
    _isPrefilled = true;
  }

  Future<void> _selectSaleDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.secondaryColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _saleDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  DateTime _addMonths(DateTime date, int months) {
    int year = date.year;
    int month = date.month + months;
    int day = date.day;

    while (month > 12) {
      month -= 12;
      year += 1;
    }
    while (month < 1) {
      month += 12;
      year -= 1;
    }

    int lastDayOfMonth = DateTime(year, month + 1, 0).day;
    if (day > lastDayOfMonth) {
      day = lastDayOfMonth;
    }

    return DateTime(year, month, day);
  }

  List<Map<String, dynamic>> _calculatePreviewReminders() {
    final List<Map<String, dynamic>> preview = [];
    final warrantyText = _warrantyController.text.trim();
    if (warrantyText.isEmpty) return preview;
    final warrantyMonths = int.tryParse(warrantyText);
    if (warrantyMonths == null || warrantyMonths < 0) return preview;

    DateTime saleDate;
    try {
      saleDate = DateFormat('yyyy-MM-dd').parse(_saleDateController.text);
    } catch (_) {
      saleDate = DateTime.now();
    }

    final expiryDate = _addMonths(saleDate, warrantyMonths);

    // 1. Water Check Reminders (Inverter only)
    if (_batteryType == 'INVERTER') {
      if (_waterCheckInterval != null && _waterCheckInterval! > 0) {
        for (int m = _waterCheckInterval!; m <= warrantyMonths; m += _waterCheckInterval!) {
          final rDate = _addMonths(saleDate, m);
          preview.add({
            'type': 'WATER_CHECK',
            'date': DateFormat('dd-MMM-yyyy').format(rDate),
            'note': 'Distilled water check ($m-month interval)',
          });
        }
      }
    }

    // 2. Service Reminders (All batteries)
    if (_serviceReminderInterval != null && _serviceReminderInterval! > 0) {
      for (int m = _serviceReminderInterval!; m <= warrantyMonths; m += _serviceReminderInterval!) {
        final rDate = _addMonths(saleDate, m);
        preview.add({
          'type': 'SERVICE',
          'date': DateFormat('dd-MMM-yyyy').format(rDate),
          'note': 'Regular service check ($m-month interval)',
        });
      }
    }

    // 3. Warranty Expiry Reminder (5 days before expiry)
    final expiryRemDate = expiryDate.subtract(const Duration(days: 5));
    if (expiryRemDate.isAfter(saleDate)) {
      preview.add({
        'type': 'WARRANTY_EXPIRY',
        'date': DateFormat('dd-MMM-yyyy').format(expiryRemDate),
        'note': 'Guarantee expiry warning (5 days before expiration)',
      });
    }

    // Sort preview items by date
    preview.sort((a, b) {
      try {
        final dateA = DateFormat('dd-MMM-yyyy').parse(a['date'] as String);
        final dateB = DateFormat('dd-MMM-yyyy').parse(b['date'] as String);
        return dateA.compareTo(dateB);
      } catch (_) {
        return 0;
      }
    });

    return preview;
  }

  Widget _buildPreviewSection() {
    final previewItems = _calculatePreviewReminders();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview_outlined, color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Upcoming Scheduled Reminders Preview',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.primaryColor,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${previewItems.length} Reminders',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (previewItems.isEmpty)
            const Text(
              'No reminders will be scheduled for this configuration.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: previewItems.length,
              separatorBuilder: (context, index) => const Divider(height: 8, color: Color(0x1F000000)),
              itemBuilder: (context, index) {
                final item = previewItems[index];
                IconData icon = Icons.info_outline;
                Color color = Colors.grey;
                
                if (item['type'] == 'WATER_CHECK') {
                  icon = Icons.water_drop_outlined;
                  color = Colors.blue;
                } else if (item['type'] == 'SERVICE') {
                  icon = Icons.build_outlined;
                  color = Colors.purple;
                } else if (item['type'] == 'WARRANTY_EXPIRY') {
                  icon = Icons.gavel_outlined;
                  color = Colors.orange;
                }

                return Row(
                  children: [
                    Icon(icon, color: color, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['note'] as String,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item['date'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final payload = {
      'customer_id': widget.customerId,
      'battery_type': _batteryType,
      'model_number': _modelController.text.trim().isEmpty ? null : _modelController.text.trim().toUpperCase(),
      'serial_number': _serialController.text.trim().isEmpty ? null : _serialController.text.trim().toUpperCase(),
      'sale_date': _saleDateController.text.trim(),
      'warranty_months': int.parse(_warrantyController.text.trim()),
      'auto_reduce_stock': _autoReduceStock,
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'service_reminder_interval_months': _serviceReminderInterval,
      'water_check_interval_months': _batteryType == 'INVERTER' ? _waterCheckInterval : null,
    };

    try {
      final operations = ref.read(batteryOperationsProvider);
      if (widget.batteryId != null) {
        await operations.updateBattery(widget.batteryId!, widget.customerId, payload);
        if (mounted) {
          ToastHelper.show(context, 'Guarantee registry updated successfully');
        }
      } else {
        await operations.createBattery(payload);
        if (mounted) {
          ToastHelper.show(context, 'Guarantee registered successfully');
        }
      }
      
      if (!mounted) return;
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
    final stockDropdownAsync = ref.watch(activeStockDropdownProvider);
    final isEdit = widget.batteryId != null;

    return Scaffold(
      body: detailsAsync.when(
        data: (details) {
          final c = details.customer;

          if (isEdit) {
            final existingBatteryIndex = details.batteries.indexWhere((b) => b.id == widget.batteryId);
            if (existingBatteryIndex != -1) {
              _prefillForm(details.batteries[existingBatteryIndex]);
            }
          }

          return AppScaffold(
            title: isEdit ? 'Edit Guarantee' : 'Register Guarantee',
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
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
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              isEdit ? 'Modify Guarantee for ${c.name}' : 'New Battery Guarantee for ${c.name}',
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

                            // Linked Stock Model Dropdown (Only for creation)
                            if (!isEdit) ...[
                              stockDropdownAsync.when(
                                data: (stockItems) {
                                  if (stockItems.isEmpty) return const SizedBox.shrink();
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Link with Active Inventory (Optional)',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String?>(
                                        initialValue: _selectedStockId,
                                        decoration: const InputDecoration(
                                          prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                                          hintText: 'Select model to autofill',
                                        ),
                                        items: [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('Custom Model (No Link)'),
                                          ),
                                          ...stockItems.map((s) => DropdownMenuItem<String?>(
                                                value: s.id,
                                                child: Text('${s.modelName} [Type: ${s.batteryType}] (Stock: ${s.quantity})'),
                                              )),
                                        ],
                                        onChanged: _isSubmitting
                                            ? null
                                            : (val) {
                                                setState(() {
                                                  _selectedStockId = val;
                                                  if (val != null) {
                                                    final matched = stockItems.firstWhere((s) => s.id == val);
                                                    _modelController.text = matched.modelName;
                                                    _batteryType = matched.batteryType;
                                                    if (_batteryType == 'INVERTER') {
                                                      _waterCheckInterval = 6;
                                                    } else {
                                                      _waterCheckInterval = null;
                                                    }
                                                  }
                                                });
                                              },
                                      ),
                                      const SizedBox(height: 20),
                                    ],
                                  );
                                },
                                loading: () => const Padding(
                                  padding: EdgeInsets.only(bottom: 20.0),
                                  child: LinearProgressIndicator(color: AppTheme.primaryColor),
                                ),
                                error: (err, stack) => const SizedBox.shrink(),
                              ),
                            ],

                            // Battery Type Selection
                            DropdownButtonFormField<String>(
                              value: _batteryType,
                              decoration: const InputDecoration(
                                labelText: 'Battery Type *',
                                prefixIcon: Icon(Icons.battery_std_outlined, size: 20),
                              ),
                              items: _batteryTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text('$type Vehicle Battery'),
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
                            const SizedBox(height: 20),

                             // Model Number
                             Consumer(
                               builder: (context, ref, child) {
                                 final stockModelsAsync = ref.watch(activeStockDropdownProvider);
                                 return stockModelsAsync.when(
                                   data: (stockItems) {
                                     return Autocomplete<String>(
                                       optionsBuilder: (TextEditingValue textEditingValue) {
                                         final cleanText = textEditingValue.text.trim().toLowerCase();
                                         return stockItems
                                             .map((e) => e.modelName)
                                             .where((model) => model.toLowerCase().contains(cleanText));
                                       },
                                       onSelected: (String selection) {
                                         _modelController.text = selection;
                                         final matches = stockItems.where((item) => item.modelName.toUpperCase() == selection.toUpperCase()).toList();
                                         if (matches.isNotEmpty) {
                                           setState(() {
                                             _batteryType = matches.first.batteryType;
                                           });
                                         }
                                       },
                                       fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                         if (textEditingController.text != _modelController.text) {
                                           textEditingController.text = _modelController.text;
                                         }
                                         textEditingController.addListener(() {
                                           _modelController.text = textEditingController.text;
                                         });
                                         return TextFormField(
                                           controller: textEditingController,
                                           focusNode: focusNode,
                                           decoration: const InputDecoration(
                                             labelText: 'Battery Model *',
                                             prefixIcon: Icon(Icons.settings_outlined),
                                           ),
                                           textCapitalization: TextCapitalization.characters,
                                           enabled: !_isSubmitting,
                                           validator: (value) {
                                             if (value == null || value.trim().isEmpty) {
                                               return 'Battery model is required';
                                             }
                                             return null;
                                           },
                                         );
                                       },
                                     );
                                   },
                                   loading: () => const Center(
                                     child: Padding(
                                       padding: EdgeInsets.all(8.0),
                                       child: CircularProgressIndicator(strokeWidth: 2),
                                     ),
                                   ),
                                   error: (err, st) => Text(
                                     'Failed to load battery stock: $err',
                                     style: const TextStyle(color: Colors.red),
                                   ),
                                 );
                               },
                             ),
                             const SizedBox(height: 20),

                             // Serial Number
                             Consumer(
                               builder: (context, ref, child) {
                                 return Autocomplete<String>(
                                   optionsBuilder: (TextEditingValue textEditingValue) {
                                     final cleanText = textEditingValue.text.trim().toLowerCase();
                                     List<String> serialOptions = [];
                                     if (_modelController.text.isNotEmpty) {
                                       final stockItems = ref.read(activeStockDropdownProvider).value ?? [];
                                       final matchedList = stockItems.where((item) => item.modelName.toUpperCase() == _modelController.text.trim().toUpperCase()).toList();
                                       if (matchedList.isNotEmpty) {
                                         final matchedStockItem = matchedList.first;
                                         final unitsAsync = ref.watch(stockUnitsProvider(matchedStockItem.id));
                                         if (unitsAsync is AsyncData<List<BatteryUnit>>) {
                                           serialOptions = unitsAsync.value.map((u) => u.serialNumber).toList();
                                         }
                                       }
                                     }
                                     return serialOptions.where((s) => s.toLowerCase().contains(cleanText));
                                   },
                                   onSelected: (String selection) {
                                     _serialController.text = selection;
                                   },
                                   fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                     if (textEditingController.text != _serialController.text) {
                                       textEditingController.text = _serialController.text;
                                     }
                                     textEditingController.addListener(() {
                                       _serialController.text = textEditingController.text;
                                     });
                                     return TextFormField(
                                       controller: textEditingController,
                                       focusNode: focusNode,
                                       decoration: const InputDecoration(
                                         labelText: 'Serial Number',
                                         prefixIcon: Icon(Icons.qr_code_outlined),
                                         hintText: 'Enter unique battery serial code',
                                       ),
                                       textCapitalization: TextCapitalization.characters,
                                       enabled: !_isSubmitting,
                                       validator: (value) {
                                         if (value != null && value.trim().isNotEmpty) {
                                           if (value.trim().length < 4) {
                                             return 'Serial number should be at least 4 characters';
                                           }
                                         }
                                         return null;
                                       },
                                     );
                                   },
                                 );
                               },
                             ),
                             const SizedBox(height: 20),

                            // Sale Date
                            TextFormField(
                              controller: _saleDateController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Sale Date *',
                                prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.date_range, size: 20),
                                  onPressed: _isSubmitting ? null : () => _selectSaleDate(context),
                                ),
                              ),
                              onTap: _isSubmitting ? null : () => _selectSaleDate(context),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please pick a sale date';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Guarantee Months
                            AppInput(
                              controller: _warrantyController,
                              labelText: 'Guarantee Period (Months) *',
                              prefixIcon: Icons.timer_outlined,
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter guarantee period';
                                }
                                final months = int.tryParse(value.trim());
                                if (months == null || months < 0) {
                                  return 'Must be a non-negative whole number';
                                }
                                return null;
                              },
                              enabled: !_isSubmitting,
                            ),
                            const SizedBox(height: 20),

                            // Service Reminder Dropdown
                            Builder(
                              builder: (context) {
                                final intervals = [null, 3, 6, 9, 12, 18, 24];
                                if (_serviceReminderInterval != null && !intervals.contains(_serviceReminderInterval)) {
                                  intervals.add(_serviceReminderInterval);
                                  intervals.sort((a, b) => (a ?? 0).compareTo(b ?? 0));
                                }
                                return DropdownButtonFormField<int?>(
                                  value: _serviceReminderInterval,
                                  decoration: const InputDecoration(
                                    labelText: 'Service Reminder Schedule',
                                    prefixIcon: Icon(Icons.build_outlined, size: 20),
                                  ),
                                  items: intervals.map((val) {
                                    if (val == null) {
                                      return const DropdownMenuItem<int?>(value: null, child: Text('No Service Reminder'));
                                    }
                                    return DropdownMenuItem<int?>(value: val, child: Text('$val Months'));
                                  }).toList(),
                                  onChanged: _isSubmitting ? null : (val) {
                                    setState(() {
                                      _serviceReminderInterval = val;
                                    });
                                  },
                                );
                              }
                            ),
                            const SizedBox(height: 20),

                            // Water Check Dropdown (Only for Inverter batteries)
                            if (_batteryType == 'INVERTER') ...[
                              Builder(
                                builder: (context) {
                                  final intervals = [null, 3, 6, 9, 12];
                                  if (_waterCheckInterval != null && !intervals.contains(_waterCheckInterval)) {
                                    intervals.add(_waterCheckInterval);
                                    intervals.sort((a, b) => (a ?? 0).compareTo(b ?? 0));
                                  }
                                  return DropdownButtonFormField<int?>(
                                    value: _waterCheckInterval,
                                    decoration: const InputDecoration(
                                      labelText: 'Water Check Reminder Schedule',
                                      prefixIcon: Icon(Icons.water_drop_outlined, size: 20),
                                    ),
                                    items: intervals.map((val) {
                                      if (val == null) {
                                        return const DropdownMenuItem<int?>(value: null, child: Text('Disabled'));
                                      }
                                      return DropdownMenuItem<int?>(value: val, child: Text('Every $val Months'));
                                    }).toList(),
                                    onChanged: _isSubmitting ? null : (val) {
                                      setState(() {
                                        _waterCheckInterval = val;
                                      });
                                    },
                                  );
                                }
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Notes
                            AppInput(
                              controller: _notesController,
                              labelText: 'Notes (Optional)',
                              prefixIcon: Icons.note_alt_outlined,
                              hintText: 'e.g. Sold with custom clamp',
                              enabled: !_isSubmitting,
                            ),
                            const SizedBox(height: 24),

                            // Reminders Preview Section
                            _buildPreviewSection(),
                            const SizedBox(height: 24),

                            // Auto reduce stock switch (only shown on create)
                            if (!isEdit) ...[
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Auto-reduce inventory stock',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                subtitle: const Text(
                                  'Decrements stock by 1 if matching model and type exist',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                                value: _autoReduceStock,
                                activeThumbColor: AppTheme.primaryColor,
                                onChanged: _isSubmitting
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _autoReduceStock = val;
                                        });
                                      },
                              ),
                              const SizedBox(height: 32),
                            ] else
                              const SizedBox(height: 12),

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
                                  label: isEdit ? 'Update Guarantee' : 'Register Guarantee',
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
          appBar: AppBar(title: const Text('Register Guarantee')),
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
