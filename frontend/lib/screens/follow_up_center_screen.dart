import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/url_helper.dart';
import '../core/api_client.dart';
import '../models/reminder.dart';
import '../models/payment.dart';
import '../providers/reminder_provider.dart';
import '../providers/payment_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/toast_helper.dart';

// Parsing helper for Udhari pending amount
double getPendingAmount(Reminder r) {
  if (r.reminderType != 'UDHARI' && r.reminderType != 'UDHARI_RECOVERY' && r.reminderCategory != 'UDHARI') {
    return 0.0;
  }
  final template = r.whatsappTemplate ?? '';
  final regExp = RegExp(r'₹([0-9.]+)');
  final match = regExp.firstMatch(template);
  if (match != null && match.groupCount >= 1) {
    return double.tryParse(match.group(1) ?? '') ?? 0.0;
  }
  return 0.0;
}

class FollowUpCenterScreen extends ConsumerStatefulWidget {
  const FollowUpCenterScreen({super.key});

  @override
  ConsumerState<FollowUpCenterScreen> createState() => _FollowUpCenterScreenState();
}

class _FollowUpCenterScreenState extends ConsumerState<FollowUpCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _activeReminderFilter = 'ALL'; // ALL, TODAY, SERVICE, WATER_CHECK, WARRANTY
  bool _isActionExecuting = false;

  // Cached payments list to lookup payment metadata (e.g. last payment date)
  Map<String, Payment> _paymentsMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    
    // Fetch pending payments to cross-reference payment metadata
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPaymentsCache();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentsCache() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('/payments', queryParameters: {
        'is_settled': false,
        'limit': 100,
      });
      final paginated = PaginatedPayments.fromJson(response.data as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _paymentsMap = {for (var p in paginated.data) p.id: p};
        });
      }
    } catch (e) {
      // Settle silently - cache is fallback only
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Read route parameters once loaded
    try {
      final state = GoRouterState.of(context);
      final tabParam = state.uri.queryParameters['tab'];
      final filterParam = state.uri.queryParameters['filter'];

      if (tabParam != null) {
        if (tabParam == 'udhari' && _tabController.index != 1) {
          _tabController.index = 1;
        } else if (tabParam == 'reminders' && _tabController.index != 0) {
          _tabController.index = 0;
        }
      }

      if (filterParam != null) {
        setState(() {
          _activeReminderFilter = filterParam.toUpperCase();
        });
      }
    } catch (_) {}
  }

  // Trigger Dynamic WhatsApp manual dispatch
  Future<void> _triggerWhatsApp(Reminder r) async {
    setState(() {
      _isActionExecuting = true;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      // Requirement 6: Load the latest active template, render variables dynamically
      final response = await apiClient.dio.get('/reminders/${r.id}/render-message');
      final renderedText = response.data['rendered_message'] as String? ?? r.whatsappTemplate ?? '';

      final mobile = r.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final phone = mobile.length == 10 ? '91$mobile' : mobile;
      final encodedMsg = Uri.encodeComponent(renderedText);
      final url = 'https://api.whatsapp.com/send?phone=$phone&text=$encodedMsg';

      // Copy text to clipboard as safety buffer
      await Clipboard.setData(ClipboardData(text: renderedText));
      
      // Launch WhatsApp url
      launchUrlString(url);

      // Record dispatch sent in DB
      await ref.read(reminderOperationsProvider).markAsSent(r.id, true);
      
      if (mounted) {
        ToastHelper.show(context, 'WhatsApp draft opened. Message copied to clipboard.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.show(context, 'Error launching WhatsApp: ${ErrorParser.parse(e)}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionExecuting = false;
        });
      }
      ref.invalidate(reminderListProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  // Trigger Phone Call
  Future<void> _triggerCall(String mobile) async {
    final cleanPhone = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final url = 'tel:$cleanPhone';
    try {
      launchUrlString(url);
    } catch (e) {
      if (mounted) {
        ToastHelper.show(context, 'Could not initiate call: $e', isError: true);
      }
    }
  }

  // Settle Outstanding Payment
  void _settleUdhari(String paymentId, String customerId, String name, double amount) {
    String selectedMode = 'CASH';
    final TextEditingController amountController = TextEditingController(text: amount.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final inputVal = double.tryParse(amountController.text) ?? 0.0;
            final remainingAmount = (amount - inputVal).clamp(0.0, double.infinity);

            return AlertDialog(
              title: const Text('Settle Udhari Payment'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Outstanding balance for "$name": ${FormatUtils.formatIndianCurrency(amount)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Amount Paid (₹) *',
                          border: OutlineInputBorder(),
                          prefixText: '₹ ',
                        ),
                        onChanged: (val) {
                          dialogSetState(() {});
                        },
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter the amount paid';
                          }
                          final amt = double.tryParse(val.trim());
                          if (amt == null) {
                            return 'Please enter a valid number';
                          }
                          if (amt <= 0) {
                            return 'Amount must be greater than zero';
                          }
                          if (amt > amount + 0.01) {
                            return 'Amount cannot exceed pending balance';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        remainingAmount <= 0.01
                            ? 'This will settle the outstanding balance in full.'
                            : 'Remaining Balance: ${FormatUtils.formatIndianCurrency(remainingAmount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: remainingAmount <= 0.01 ? Colors.green.shade700 : Colors.orange.shade800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Payment Mode *',
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
                            dialogSetState(() {
                              selectedMode = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
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
                    if (formKey.currentState?.validate() ?? false) {
                      final enteredAmount = double.parse(amountController.text.trim());
                      Navigator.of(ctx).pop();
                      this.setState(() {
                        _isActionExecuting = true;
                      });
                      try {
                        await ref.read(paymentOperationsProvider).settlePayment(
                              paymentId,
                              customerId,
                              selectedMode,
                              amount: enteredAmount,
                            );
                        await _loadPaymentsCache();
                        if (mounted) {
                          ToastHelper.show(context, 'Payment updated successfully');
                        }
                      } catch (e) {
                        if (mounted) {
                          ToastHelper.show(context, 'Error: ${ErrorParser.parse(e)}', isError: true);
                        }
                      } finally {
                        if (mounted) {
                          this.setState(() {
                            _isActionExecuting = false;
                          });
                        }
                        ref.invalidate(reminderListProvider);
                        ref.invalidate(dashboardProvider);
                      }
                    }
                  },
                  child: const Text('Confirm Settle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Complete Standard Reminder
  void _completeReminder(Reminder r) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Mark Reminder Completed?'),
          content: Text('Mark the ${r.reminderType.replaceAll('_', ' ')} reminder for "${r.customerName}" as completed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                setState(() {
                  _isActionExecuting = true;
                });
                try {
                  await ref.read(reminderOperationsProvider).toggleCompletion(r.id, true);
                  if (mounted) {
                    ToastHelper.show(context, 'Reminder completed');
                  }
                } catch (e) {
                  if (mounted) {
                    ToastHelper.show(context, 'Error: ${ErrorParser.parse(e)}', isError: true);
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isActionExecuting = false;
                    });
                  }
                  ref.invalidate(reminderListProvider);
                  ref.invalidate(dashboardProvider);
                }
              },
              child: const Text('Complete'),
            ),
          ],
        );
      },
    );
  }

  // Build colorful profile initials avatar
  Widget _buildAvatar(String name) {
    final initials = name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase();
    final List<Color> colors = [
      Colors.blue.shade700,
      Colors.indigo.shade700,
      Colors.teal.shade700,
      Colors.purple.shade700,
      Colors.orange.shade700,
    ];
    final colorIndex = name.hashCode % colors.length;
    return CircleAvatar(
      radius: 26,
      backgroundColor: colors[colorIndex].withOpacity(0.15),
      child: Text(
        initials.isNotEmpty ? initials : 'C',
        style: TextStyle(
          color: colors[colorIndex],
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(reminderListProvider);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    return AppScaffold(
      title: 'Follow-up Center',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Tab controls
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryColor,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(
                  icon: Icon(Icons.alarm, size: 20),
                  text: 'Standard Reminders',
                ),
                Tab(
                  icon: Icon(Icons.account_balance_wallet, size: 20),
                  text: 'Udhari Recovery',
                ),
              ],
            ),
          ),
          
          // Search & Filters Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search customer, phone, battery serial or model...',
                            prefixIcon: Icon(Icons.search, size: 18),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim().toLowerCase();
                            });
                          },
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      ),
                    ]
                  ],
                ),
                
                // standard filter chips if on Tab 0
                if (_tabController.index == 0) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildFilterChip('All', 'ALL'),
                        _buildFilterChip('Due Today', 'TODAY'),
                        _buildFilterChip('Service Due', 'SERVICE'),
                        _buildFilterChip('Water Check Due', 'WATER_CHECK'),
                        _buildFilterChip('Warranty Expiries', 'WARRANTY_EXPIRY'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_isActionExecuting)
            const LinearProgressIndicator(color: AppTheme.primaryColor),

          // Main list container
          Expanded(
            child: remindersAsync.when(
              data: (paginated) {
                // Filter the list locally based on tabs, search and status filters
                List<Reminder> filtered = paginated.data.where((r) {
                  // Don't show completed reminders in Follow-up Center
                  if (r.isCompleted) return false;

                  final matchesSearch = r.customerName.toLowerCase().contains(_searchQuery) ||
                      r.mobileNumber.contains(_searchQuery) ||
                      (r.batteryModel ?? '').toLowerCase().contains(_searchQuery) ||
                      (r.batterySerial ?? '').toLowerCase().contains(_searchQuery);

                  if (!matchesSearch) return false;

                  if (_tabController.index == 0) {
                    // Standard Reminders Tab (Service, Water Check, Warranty Expiry, Due Today)
                    if (r.reminderType == 'UDHARI' || r.reminderType == 'UDHARI_RECOVERY' || r.reminderCategory == 'UDHARI') {
                      return false;
                    }

                    if (_activeReminderFilter == 'TODAY') {
                      return r.reminderStatus == 'DUE';
                    } else if (_activeReminderFilter != 'ALL') {
                      return r.reminderType == _activeReminderFilter;
                    }
                    return true;
                  } else {
                    // Udhari Tab
                    return r.reminderType == 'UDHARI' || r.reminderType == 'UDHARI_RECOVERY' || r.reminderCategory == 'UDHARI';
                  }
                }).toList();

                // Sort reminders using centralized business rules
                FormatUtils.sortReminders(filtered);

                if (filtered.isEmpty) {
                  return EmptyState(
                    title: _tabController.index == 0 ? 'No Reminders Found' : 'No Udhari Recovery Pending',
                    message: _searchQuery.isNotEmpty
                        ? 'Try modifying your search keywords.'
                        : (_tabController.index == 0
                            ? 'All standard service and water reminders are fully up to date.'
                            : 'All customer credit accounts are fully settled and cleared!'),
                    icon: _tabController.index == 0 ? Icons.alarm_off : Icons.check_circle_outline,
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final r = filtered[idx];
                    return _tabController.index == 0
                        ? _buildStandardReminderCard(r, isMobile)
                        : _buildUdhariCard(r, isMobile);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                    const SizedBox(height: 12),
                    Text('Error fetching data: ${ErrorParser.parse(err)}'),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Reload',
                      onPressed: () => ref.invalidate(reminderListProvider),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _activeReminderFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppTheme.primaryColor.withOpacity(0.15),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primaryColor : const Color(0xFF64748B),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? AppTheme.primaryColor : const Color(0xFFE2E8F0)),
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _activeReminderFilter = value;
            });
          }
        },
      ),
    );
  }

  // 5. Standard Reminder Card layout
  Widget _buildStandardReminderCard(Reminder r, bool isMobile) {
    final typeColors = {
      'SERVICE': Colors.amber.shade700,
      'WATER_CHECK': Colors.blue.shade700,
      'WARRANTY_EXPIRY': Colors.deepOrange.shade700,
    };
    final typeColor = typeColors[r.reminderType] ?? AppTheme.primaryColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(r.customerName),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              r.customerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.secondaryColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              r.reminderType.replaceAll('_', ' '),
                              style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.mobileNumber,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            
            // Battery details metadata
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Battery Model', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(r.batteryModel ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Serial Number', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(r.batterySerial ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reminder Date', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.event, color: AppTheme.primaryColor, size: 14),
                          const SizedBox(width: 4),
                          Text(FormatUtils.formatDate(r.reminderDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reason / Note', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(r.notes ?? 'Periodic check', style: const TextStyle(fontSize: 12, color: Color(0xFF475569)), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF475569),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _triggerCall(r.mobileNumber),
                  icon: const Icon(Icons.call, size: 16, color: Colors.blue),
                  label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF475569),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _triggerWhatsApp(r),
                  icon: const Icon(Icons.message, size: 16, color: Colors.green),
                  label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _completeReminder(r),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Complete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // 7. Dedicated Udhari Recovery section card layout
  Widget _buildUdhariCard(Reminder r, bool isMobile) {
    final pendingAmount = getPendingAmount(r);
    final linkedPaymentId = r.linkedPaymentId;
    final payment = linkedPaymentId != null ? _paymentsMap[linkedPaymentId] : null;
    
    // Determine last payment/activity date
    String billingDateLabel = 'N/A';
    if (payment != null) {
      billingDateLabel = FormatUtils.formatDate(payment.updatedAt ?? payment.createdAt);
    } else {
      billingDateLabel = FormatUtils.formatDate(r.reminderDate);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5), // Red glowing warning border
      ),
      color: const Color(0xFFFFFBEB), // Elegant soft yellow background
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(r.customerName),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              r.customerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.secondaryColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'UDHARI DEBT',
                              style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.mobileNumber,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            
            // Debt Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pending Debt Amount', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        FormatUtils.formatIndianCurrency(pendingAmount > 0 ? pendingAmount : getPendingAmount(r)),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Payment / Bill Date', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.date_range, color: Colors.deepOrangeAccent, size: 14),
                          const SizedBox(width: 4),
                          Text(billingDateLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Linked Battery Model', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(r.batteryModel ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Serial Number', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(r.batterySerial ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                    ],
                  ),
                ),
              ],
            ),
            
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF475569),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _triggerCall(r.mobileNumber),
                  icon: const Icon(Icons.call, size: 16, color: Colors.blue),
                  label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF475569),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _triggerWhatsApp(r),
                  icon: const Icon(Icons.message, size: 16, color: Colors.green),
                  label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                if (linkedPaymentId != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _settleUdhari(linkedPaymentId, r.customerId ?? '', r.customerName, pendingAmount > 0 ? pendingAmount : getPendingAmount(r)),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Mark Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            )
          ],
        ),
      ),
    );
  }
}
