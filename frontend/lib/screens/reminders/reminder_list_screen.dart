import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/reminder_provider.dart';
import '../../providers/message_template_provider.dart';
import '../../models/reminder.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/toast_helper.dart';
import '../../core/url_helper.dart';
import '../../core/api_client.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

double getPendingAmount(Reminder r) {
  if (r.reminderType != 'UDHARI' && r.reminderCategory != 'UDHARI') return 0.0;
  final template = r.whatsappTemplate ?? '';
  final regExp = RegExp(r'₹([0-9.]+)');
  final match = regExp.firstMatch(template);
  if (match != null && match.groupCount >= 1) {
    return double.tryParse(match.group(1) ?? '') ?? 0.0;
  }
  return 0.0;
}

class GlowingPulseWrapper extends StatefulWidget {
  final Widget child;
  final bool isGlowEnabled;
  const GlowingPulseWrapper({super.key, required this.child, required this.isGlowEnabled});

  @override
  State<GlowingPulseWrapper> createState() => _GlowingPulseWrapperState();
}

class _GlowingPulseWrapperState extends State<GlowingPulseWrapper> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    if (widget.isGlowEnabled) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this,
      )..repeat(reverse: true);
      _animation = Tween<double>(begin: 2.0, end: 10.0).animate(_controller!);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isGlowEnabled || _animation == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _animation!,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.4),
                blurRadius: _animation!.value,
                spreadRadius: _animation!.value / 3,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class ReminderListScreen extends ConsumerStatefulWidget {
  const ReminderListScreen({super.key});

  @override
  ConsumerState<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends ConsumerState<ReminderListScreen> {
  bool _isProcessingBatch = false;

  void _showDeleteConfirmDialog(BuildContext context, WidgetRef ref, String id, String name) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Delete Reminder?', style: TextStyle(color: Colors.red)),
          content: Text('Are you sure you want to permanently delete the reminder for "$name"? This action cannot be undone.'),
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
                  await ref.read(reminderOperationsProvider).deleteReminder(id);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Reminder deleted successfully');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ToastHelper.show(context, 'Error: ${ErrorParser.parse(e)}', isError: true);
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

  void _showDeleteAllDialog(BuildContext context, WidgetRef ref) {

    String selectedType = 'ALL';
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                  SizedBox(width: 8),
                  Text('Delete All Reminders?', style: TextStyle(color: Colors.red)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select which reminder category/option you want to delete all data for:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Category / Option',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('ALL Reminders (Delete Everything)')),
                      DropdownMenuItem(value: 'WATER_CHECK', child: Text('Only Water Check Reminders')),
                      DropdownMenuItem(value: 'SERVICE', child: Text('Only Service Check Reminders')),
                      DropdownMenuItem(value: 'WARRANTY_EXPIRY', child: Text('Only Warranty Expiry Reminders')),
                      DropdownMenuItem(value: 'UDHARI', child: Text('Only Udhari Recovery Reminders')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedType = val ?? 'ALL';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'WARNING: This action is permanent and cannot be undone. All matching records will be permanently deleted from the database.',
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
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
                      final typeParam = selectedType == 'ALL' ? null : selectedType;
                      await ref.read(reminderOperationsProvider).deleteAllReminders(type: typeParam);
                      ref.invalidate(reminderListProvider);
                      ref.invalidate(reminderStatsProvider);
                      if (context.mounted) {
                        ToastHelper.show(context, 'Reminders deleted successfully');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ToastHelper.show(context, 'Error: ${ErrorParser.parse(e)}', isError: true);
                      }
                    }
                  },
                  child: const Text('Delete All'),
                ),
              ],
            );
          }
        );
      },
    );
  }



  Future<void> _sendWhatsAppFollowup(BuildContext context, WidgetRef ref, Reminder r) async {
    String template = r.whatsappTemplate ?? '';
    try {
      final renderRes = await ref.read(templateOperationsProvider).renderMessagePreview(r.id, channel: 'whatsapp');
      template = renderRes['message_body'] as String? ?? template;
    } catch (e) {
      // Fallback silently to in-memory template text
    }

    final mobile = r.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Add country code if missing (assuming 91 for India)
    final phone = mobile.length == 10 ? '91$mobile' : mobile;
    final encodedMsg = Uri.encodeComponent(template);
    final url = 'https://api.whatsapp.com/send?phone=$phone&text=$encodedMsg';

    try {
      // 1. Copy to clipboard for backup/safety
      await Clipboard.setData(ClipboardData(text: template));
      
      // 2. Open WhatsApp Web or App link
      launchUrlString(url);

      // 3. Mark as sent in DB
      await ref.read(reminderOperationsProvider).markAsSent(r.id, true);

      if (context.mounted) {
        ToastHelper.show(context, 'WhatsApp draft copied and opened!');
      }
    } catch (e) {
      if (context.mounted) {
        ToastHelper.show(context, 'Failed to launch WhatsApp: ${ErrorParser.parse(e)}', isError: true);
      }
    }
  }

  void _showFormModal(BuildContext context, WidgetRef ref, {Reminder? existing}) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return ReminderFormDialog(existing: existing);
      },
    );
  }

  void _showDetailsModal(BuildContext context, WidgetRef ref, Reminder r) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return ReminderDetailsDialog(reminder: r, onSend: () => _sendWhatsAppFollowup(context, ref, r));
      },
    );
  }

  Future<void> _triggerDailyCheck() async {
    setState(() {
      _isProcessingBatch = true;
    });
    try {
      await ref.read(reminderOperationsProvider).triggerDailyBatch();
      if (mounted) {
        ToastHelper.show(context, 'Daily reminder check completed successfully!');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.show(context, 'Batch run failed: ${ErrorParser.parse(e)}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingBatch = false;
        });
      }
    }
  }

  Widget _buildStatusChip(String status) {
    Color bgColor;
    Color textColor;
    Color borderColor;

    switch (status.toUpperCase()) {
      case 'COMPLETED':
        bgColor = const Color(0xFFF0FDF4);
        textColor = const Color(0xFF16A34A);
        borderColor = const Color(0xFFBBF7D0);
        break;
      case 'DUE':
        bgColor = const Color(0xFFFFFBEB);
        textColor = const Color(0xFFD97706);
        borderColor = const Color(0xFFFDE68A);
        break;
      case 'OVERDUE':
        bgColor = const Color(0xFFFEF2F2);
        textColor = const Color(0xFFDC2626);
        borderColor = const Color(0xFFFECACA);
        break;
      case 'EXPIRED':
        bgColor = const Color(0xFFF8FAFC);
        textColor = const Color(0xFF64748B);
        borderColor = const Color(0xFFE2E8F0);
        break;
      case 'UPCOMING':
      default:
        bgColor = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF2563EB);
        borderColor = const Color(0xFFBFDBFE);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    String label = type;
    IconData icon = Icons.info_outline;
    Color color = const Color(0xFF64748B);

    if (type == 'WATER_CHECK') {
      label = 'Water Check';
      icon = Icons.water_drop_outlined;
      color = Colors.blue;
    } else if (type == 'SERVICE') {
      label = 'Service Check';
      icon = Icons.build_outlined;
      color = Colors.purple;
    } else if (type == 'WARRANTY_EXPIRY') {
      label = 'Warranty Exp';
      icon = Icons.gavel_outlined;
      color = Colors.orange;
    } else if (type == 'UDHARI') {
      label = 'Udhari Recovery';
      icon = Icons.payment_outlined;
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, IconData icon, Color color, {bool isMobile = false}) {
    final cardContent = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isMobile) {
      return SizedBox(
        width: 160,
        child: cardContent,
      );
    }
    return Expanded(
      child: cardContent,
    );
  }

  void _showSettleConfirmDialog(BuildContext context, WidgetRef ref, String paymentId, String customerId, String name, double amount) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Settle Udhari?'),
          content: Text(
            'Mark this pending balance of ${FormatUtils.formatIndianCurrency(amount)} for $name as paid in full?',
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
                Navigator.of(ctx).pop();
                try {
                  final apiClient = ref.read(apiClientProvider);
                  await apiClient.dio.patch('/payments/$paymentId/settle');
                  
                  ref.invalidate(reminderListProvider);
                  ref.invalidate(reminderStatsProvider);
                  
                  if (context.mounted) {
                    ToastHelper.show(context, 'Payment settled successfully');
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
              child: const Text('Confirm Settle'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTypeFilterChips(WidgetRef ref, ReminderListFilter filter) {
    final types = ['ALL', 'SERVICE', 'WATER_CHECK', 'WARRANTY', 'UDHARI', 'DUE_TODAY', 'COMPLETED_CHIP'];
    final labels = {
      'ALL': 'All',
      'SERVICE': 'Service',
      'WATER_CHECK': 'Water Check',
      'WARRANTY': 'Warranty Expiry',
      'UDHARI': 'Udhari Recovery',
      'DUE_TODAY': 'Due Today',
      'COMPLETED_CHIP': 'Completed',
    };
    final icons = {
      'ALL': Icons.all_inbox_outlined,
      'SERVICE': Icons.build_outlined,
      'WATER_CHECK': Icons.water_drop_outlined,
      'WARRANTY': Icons.gavel_outlined,
      'UDHARI': Icons.payment_outlined,
      'DUE_TODAY': Icons.today,
      'COMPLETED_CHIP': Icons.check_circle_outline,
    };
    final colors = {
      'ALL': Colors.teal,
      'SERVICE': Colors.purple,
      'WATER_CHECK': Colors.blue,
      'WARRANTY': Colors.orange,
      'UDHARI': Colors.red,
      'DUE_TODAY': Colors.amber.shade700,
      'COMPLETED_CHIP': Colors.green,
    };
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: types.map((t) {
          final isSelected = (() {
            if (t == 'DUE_TODAY') return filter.status == 'DUE';
            if (t == 'COMPLETED_CHIP') return filter.status == 'COMPLETED';
            if (t == 'ALL') return filter.type == 'ALL' && filter.status != 'DUE' && filter.status != 'COMPLETED';
            return filter.type == t && filter.status != 'DUE' && filter.status != 'COMPLETED';
          })();
          
          final icon = icons[t]!;
          final color = colors[t]!;
          final label = labels[t]!;
          
          return Container(
            margin: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              avatar: Icon(icon, size: 14, color: isSelected ? Colors.white : color),
              label: Text(label),
              selected: isSelected,
              selectedColor: color,
              backgroundColor: Theme.of(context).brightness == Brightness.dark 
                  ? const Color(0xFF1E293B) 
                  : Colors.white,
              labelStyle: TextStyle(
                color: isSelected 
                    ? Colors.white 
                    : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade300 : AppTheme.secondaryColor),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                if (val) {
                  String newType = 'ALL';
                  String newStatus = '';
                  if (t == 'DUE_TODAY') {
                    newStatus = 'DUE';
                  } else if (t == 'COMPLETED_CHIP') {
                    newStatus = 'COMPLETED';
                  } else {
                    newType = t;
                  }
                  ref.read(reminderFilterProvider.notifier).update(
                        (state) => state.copyWith(type: newType, status: newStatus, page: 1),
                      );
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(reminderFilterProvider);
    final remindersAsync = ref.watch(reminderListProvider);
    final statsAsync = ref.watch(reminderStatsProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 900;
    final isMobile = width < 750;

    return AppScaffold(
      title: 'Service & Warranty Reminders',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Analytics Summary Bar
            statsAsync.when(
              data: (stats) {
                final cards = [
                  _buildStatCard('Today Due', stats.todayFollowups, Icons.alarm_on, Colors.orange, isMobile: isMobile),
                  const SizedBox(width: 16),
                  _buildStatCard('Water Checks', stats.waterChecksDue, Icons.water_drop, Colors.blue, isMobile: isMobile),
                  const SizedBox(width: 16),
                  _buildStatCard('Pending Service', stats.pendingService, Icons.handyman, Colors.purple, isMobile: isMobile),
                  const SizedBox(width: 16),
                  _buildStatCard('Upcoming Expiry', stats.upcomingExpiry, Icons.warning_amber_rounded, Colors.deepOrange, isMobile: isMobile),
                  const SizedBox(width: 16),
                  _buildStatCard('Completed', stats.completed, Icons.check_circle_outline, Colors.green, isMobile: isMobile),
                ];

                if (isMobile) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: cards),
                  );
                }
                return Row(children: cards);
              },
              loading: () => Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Type filter chips
            _buildTypeFilterChips(ref, filter),
            const SizedBox(height: 20),

            // Search Bar & Filter Toolbar
            isDesktop
                ? Row(
                    children: [
                      Expanded(
                        child: DebouncedSearchBar(
                          hintText: 'Search customer name, mobile, model, or serial...',
                          initialValue: filter.search,
                          onChanged: (val) {
                            ref.read(reminderFilterProvider.notifier).update(
                                  (state) => state.copyWith(search: val, page: 1),
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: filter.status.isEmpty ? 'ALL' : filter.status,
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                          DropdownMenuItem(value: 'UPCOMING', child: Text('Upcoming')),
                          DropdownMenuItem(value: 'DUE', child: Text('Due Today')),
                          DropdownMenuItem(value: 'OVERDUE', child: Text('Overdue')),
                          DropdownMenuItem(value: 'EXPIRED', child: Text('Expired')),
                          DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
                        ],
                        onChanged: (val) {
                          final statusVal = (val == 'ALL' || val == null) ? '' : val;
                          ref.read(reminderFilterProvider.notifier).update(
                                (state) => state.copyWith(status: statusVal, page: 1),
                              );
                        },
                      ),
                      const SizedBox(width: 16),
                      AppButton(
                        label: _isProcessingBatch ? 'Running Check...' : 'Trigger Daily Check',
                        icon: Icons.refresh,
                        isSecondary: true,
                        onPressed: _isProcessingBatch ? null : _triggerDailyCheck,
                      ),
                      const SizedBox(width: 16),
                      AppButton(
                        label: 'Add Reminder',
                        icon: Icons.add,
                        onPressed: () => _showFormModal(context, ref),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _showDeleteAllDialog(context, ref),
                        icon: const Icon(Icons.delete_sweep, size: 20),
                        label: const Text('Delete All Data'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DebouncedSearchBar(
                        hintText: 'Search customer name, mobile, model, or serial...',
                        initialValue: filter.search,
                        onChanged: (val) {
                          ref.read(reminderFilterProvider.notifier).update(
                                (state) => state.copyWith(search: val, page: 1),
                              );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(
                            value: filter.status.isEmpty ? 'ALL' : filter.status,
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                              DropdownMenuItem(value: 'UPCOMING', child: Text('Upcoming')),
                              DropdownMenuItem(value: 'DUE', child: Text('Due Today')),
                              DropdownMenuItem(value: 'OVERDUE', child: Text('Overdue')),
                              DropdownMenuItem(value: 'EXPIRED', child: Text('Expired')),
                              DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
                            ],
                            onChanged: (val) {
                              final statusVal = (val == 'ALL' || val == null) ? '' : val;
                              ref.read(reminderFilterProvider.notifier).update(
                                    (state) => state.copyWith(status: statusVal, page: 1),
                                  );
                            },
                          ),
                          AppButton(
                            label: _isProcessingBatch ? 'Running Check...' : 'Trigger Daily Check',
                            icon: Icons.refresh,
                            isSecondary: true,
                            onPressed: _isProcessingBatch ? null : _triggerDailyCheck,
                          ),
                          AppButton(
                            label: 'Add Reminder',
                            icon: Icons.add,
                            onPressed: () => _showFormModal(context, ref),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _showDeleteAllDialog(context, ref),
                            icon: const Icon(Icons.delete_sweep, size: 18),
                            label: const Text('Delete All Data', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),

            const SizedBox(height: 24),

            // Content Area
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(reminderListProvider);
                  ref.invalidate(reminderStatsProvider);
                },
                color: AppTheme.primaryColor,
                child: remindersAsync.when(
                  data: (paginated) {
                    if (paginated.data.isEmpty) {
                      return const EmptyState(
                        title: 'No Reminders Found',
                        message: 'Try modifying your filters or create a manual reminder to start tracking.',
                        icon: Icons.notification_important_outlined,
                      );
                    }

                    // Sort reminders using centralized business rules
                    final sortedReminders = List<Reminder>.from(paginated.data);
                    FormatUtils.sortReminders(sortedReminders);

                    if (isDesktop) {
                      // Desktop Data Table
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final tableWidth = constraints.maxWidth > 1200.0 ? constraints.maxWidth : 1200.0;
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SizedBox(
                                width: tableWidth,
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
                                  ),
                                  child: PaginatedDataTable(
                                    header: null,
                                    showCheckboxColumn: false,
                                    columns: const [
                                      DataColumn(label: Text('Customer')),
                                      DataColumn(label: Text('Battery Details')),
                                      DataColumn(label: Text('Reminder Type')),
                                      DataColumn(label: Text('Due Date')),
                                      DataColumn(label: Text('Status')),
                                      DataColumn(label: Text('Channel')),
                                      DataColumn(label: Text('Actions')),
                                    ],
                                    source: ReminderDataSource(
                                      context: context,
                                      ref: ref,
                                      reminders: sortedReminders,
                                      onView: (r) => _showDetailsModal(context, ref, r),
                                      onEdit: (r) => _showFormModal(context, ref, existing: r),
                                      onDelete: (r) => _showDeleteConfirmDialog(context, ref, r.id, r.customerName),
                                      onCompleteToggle: (r, val) => ref.read(reminderOperationsProvider).toggleCompletion(r.id, val),
                                      onSendWhatsApp: (r) => _sendWhatsAppFollowup(context, ref, r),
                                      onSettle: (r) {
                                        final amt = getPendingAmount(r);
                                        _showSettleConfirmDialog(context, ref, r.linkedPaymentId ?? '', r.customerId ?? '', r.customerName, amt);
                                      },
                                    ),
                                    rowsPerPage: paginated.limit,
                                    availableRowsPerPage: [paginated.limit],
                                    onRowsPerPageChanged: null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }

                    // Mobile Layout Cards
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: sortedReminders.length,
                      itemBuilder: (ctx, index) {
                        final r = sortedReminders[index];
                        final isOverdueUdhari = (r.reminderType == 'UDHARI' || r.reminderCategory == 'UDHARI') && r.reminderStatus == 'OVERDUE' && !r.isCompleted;

                        return GlowingPulseWrapper(
                          isGlowEnabled: isOverdueUdhari,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
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
                                          r.customerName,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      _buildStatusChip(r.reminderStatus),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone_iphone, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(r.mobileNumber, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  const Divider(height: 20),
                                  Row(
                                    children: [
                                      _buildTypeChip(r.reminderType),
                                      const Spacer(),
                                      Text(
                                        'Due: ${FormatUtils.formatDate(r.reminderDate)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  if (r.reminderType == 'UDHARI' || r.reminderCategory == 'UDHARI') ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Pending Udhari: ${FormatUtils.formatIndianCurrency(getPendingAmount(r))}',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red),
                                    ),
                                  ] else if (r.batteryModel != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Battery: ${r.batteryModel} ${r.batterySerial != null ? "(${r.batterySerial})" : ""}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                  if (r.notes != null && r.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Note: ${r.notes}',
                                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const Divider(height: 24),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.info_outline, color: Colors.blue),
                                        tooltip: 'Details',
                                        onPressed: () => _showDetailsModal(context, ref, r),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Colors.amber),
                                        tooltip: 'Edit',
                                        onPressed: () => _showFormModal(context, ref, existing: r),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        tooltip: 'Delete',
                                        onPressed: () => _showDeleteConfirmDialog(context, ref, r.id, r.customerName),
                                      ),
                                      if (!r.isCompleted && (r.reminderType == 'UDHARI' || r.reminderCategory == 'UDHARI'))
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          onPressed: () {
                                            final amt = getPendingAmount(r);
                                            _showSettleConfirmDialog(context, ref, r.linkedPaymentId ?? '', r.customerId ?? '', r.customerName, amt);
                                          },
                                          icon: const Icon(Icons.check_circle_outline, size: 14),
                                          label: const Text('Mark Paid', style: TextStyle(fontSize: 12)),
                                        ),
                                      if (!r.isCompleted)
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          onPressed: () => _sendWhatsAppFollowup(context, ref, r),
                                          icon: const Icon(Icons.send, size: 14),
                                          label: const Text('Send Now', style: TextStyle(fontSize: 12)),
                                        ),
                                      if (r.isCompleted)
                                        const Icon(Icons.check_circle, color: Colors.green),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => EmptyState(
                    title: 'Failed to load reminders',
                    message: ErrorParser.parse(err),
                    icon: Icons.error_outline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReminderDataSource extends DataTableSource {
  final BuildContext context;
  final WidgetRef ref;
  final List<Reminder> reminders;
  final Function(Reminder) onView;
  final Function(Reminder) onEdit;
  final Function(Reminder) onDelete;
  final Function(Reminder, bool) onCompleteToggle;
  final Function(Reminder) onSendWhatsApp;
  final Function(Reminder) onSettle;

  ReminderDataSource({
    required this.context,
    required this.ref,
    required this.reminders,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onCompleteToggle,
    required this.onSendWhatsApp,
    required this.onSettle,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= reminders.length) return null;
    final r = reminders[index];

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(r.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(r.mobileNumber, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        DataCell(
          Builder(
            builder: (context) {
              if (r.reminderType == 'UDHARI' || r.reminderCategory == 'UDHARI') {
                final amt = getPendingAmount(r);
                return Text(
                  'Pending: ${FormatUtils.formatIndianCurrency(amt)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                );
              }
              return Text(r.batteryModel != null ? '${r.batteryModel} ${r.batterySerial != null ? "(${r.batterySerial})" : ""}' : 'N/A');
            }
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getTypeColor(r.reminderType).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              r.reminderType.replaceAll('_', ' '),
              style: TextStyle(fontSize: 11, color: _getTypeColor(r.reminderType), fontWeight: FontWeight.bold),
            ),
          ),
        ),
        DataCell(Text(FormatUtils.formatDate(r.reminderDate))),
        DataCell(_buildStatusWidget(r.reminderStatus)),
        DataCell(
          Row(
            children: [
              Icon(
                r.messageSent ? Icons.check_circle : Icons.pending_actions,
                size: 16,
                color: r.messageSent ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                r.messageSent ? 'Sent' : 'Pending',
                style: TextStyle(fontSize: 12, color: r.messageSent ? Colors.green : Colors.grey),
              ),
            ],
          ),
        ),
        DataCell(
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                tooltip: 'View Details',
                onPressed: () => onView(r),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.amber, size: 20),
                tooltip: 'Edit',
                onPressed: () => onEdit(r),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: 'Delete',
                onPressed: () => onDelete(r),
              ),
              const SizedBox(width: 8),
              if (!r.isCompleted && (r.reminderType == 'UDHARI' || r.reminderCategory == 'UDHARI')) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => onSettle(r),
                  icon: const Icon(Icons.check_circle_outline, size: 12),
                  label: const Text('Mark Paid', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
              ],
              if (!r.isCompleted)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => onSendWhatsApp(r),
                  icon: const Icon(Icons.send, size: 12),
                  label: const Text('Send Reminder Now', style: TextStyle(fontSize: 11)),
                )
              else
                Checkbox(
                  value: r.isCompleted,
                  onChanged: (val) => onCompleteToggle(r, val ?? false),
                  activeColor: Colors.green,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    if (type == 'WATER_CHECK') return Colors.blue;
    if (type == 'SERVICE') return Colors.purple;
    if (type == 'UDHARI') return Colors.red;
    return Colors.orange;
  }

  Widget _buildStatusWidget(String status) {
    Color bgColor;
    Color textColor;
    Color borderColor;

    switch (status.toUpperCase()) {
      case 'COMPLETED':
        bgColor = const Color(0xFFF0FDF4);
        textColor = const Color(0xFF16A34A);
        borderColor = const Color(0xFFBBF7D0);
        break;
      case 'DUE':
        bgColor = const Color(0xFFFFFBEB);
        textColor = const Color(0xFFD97706);
        borderColor = const Color(0xFFFDE68A);
        break;
      case 'OVERDUE':
        bgColor = const Color(0xFFFEF2F2);
        textColor = const Color(0xFFDC2626);
        borderColor = const Color(0xFFFECACA);
        break;
      case 'EXPIRED':
        bgColor = const Color(0xFFF8FAFC);
        textColor = const Color(0xFF64748B);
        borderColor = const Color(0xFFE2E8F0);
        break;
      case 'UPCOMING':
      default:
        bgColor = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF2563EB);
        borderColor = const Color(0xFFBFDBFE);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        status,
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
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => reminders.length;

  @override
  int get selectedRowCount => 0;
}

// ---------------------------------------------------------------------------
// Reminder Dialog for Creation & Edit
// ---------------------------------------------------------------------------
class ReminderFormDialog extends ConsumerStatefulWidget {
  final Reminder? existing;
  const ReminderFormDialog({super.key, this.existing});

  @override
  ConsumerState<ReminderFormDialog> createState() => _ReminderFormDialogState();
}

class _ReminderFormDialogState extends ConsumerState<ReminderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _serialCtrl;
  late TextEditingController _notesCtrl;
  
  String _batteryType = 'INVERTER';
  String _reminderType = 'WATER_CHECK';
  DateTime _reminderDate = DateTime.now().add(const Duration(days: 1));
  DateTime? _warrantyExpiry;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.customerName ?? '');
    _mobileCtrl = TextEditingController(text: widget.existing?.mobileNumber ?? '');
    _modelCtrl = TextEditingController(text: widget.existing?.batteryModel ?? '');
    _serialCtrl = TextEditingController(text: widget.existing?.batterySerial ?? '');
    _notesCtrl = TextEditingController(text: widget.existing?.notes ?? '');

    if (widget.existing != null) {
      _batteryType = widget.existing!.batteryType ?? 'INVERTER';
      _reminderType = widget.existing!.reminderType;
      _reminderDate = DateTime.parse(widget.existing!.reminderDate);
      if (widget.existing!.warrantyExpiry != null) {
        _warrantyExpiry = DateTime.parse(widget.existing!.warrantyExpiry!);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _modelCtrl.dispose();
    _serialCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isExpiry) async {
    final initial = isExpiry ? (_warrantyExpiry ?? DateTime.now()) : _reminderDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      setState(() {
        if (isExpiry) {
          _warrantyExpiry = picked;
        } else {
          _reminderDate = picked;
        }
      });
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final payload = {
      'customer_name': _nameCtrl.text.trim(),
      'mobile_number': _mobileCtrl.text.trim(),
      'battery_model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim().toUpperCase(),
      'battery_serial': _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim().toUpperCase(),
      'battery_type': _batteryType,
      'reminder_type': _reminderType,
      'reminder_category': _reminderType == 'UDHARI' ? 'UDHARI' : 'BATTERY',
      'reminder_date': DateFormat('yyyy-MM-dd').format(_reminderDate),
      'warranty_expiry': _warrantyExpiry != null ? DateFormat('yyyy-MM-dd').format(_warrantyExpiry!) : null,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    };

    try {
      final operations = ref.read(reminderOperationsProvider);
      if (widget.existing != null) {
        await operations.updateReminder(widget.existing!.id, payload);
        if (mounted) ToastHelper.show(context, 'Reminder updated successfully');
      } else {
        await operations.createReminder(payload);
        if (mounted) ToastHelper.show(context, 'Reminder created successfully');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ToastHelper.show(context, 'Error: ${ErrorParser.parse(e)}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit Reminder' : 'New Manual Reminder'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Customer Name *'),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter customer name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mobileCtrl,
                  decoration: const InputDecoration(labelText: 'Mobile Number *'),
                  keyboardType: TextInputType.phone,
                  validator: (val) => (val == null || val.trim().length < 10) ? 'Enter a valid 10-digit mobile number' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _modelCtrl,
                        decoration: const InputDecoration(labelText: 'Battery Model'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _serialCtrl,
                        decoration: const InputDecoration(labelText: 'Serial Number'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _batteryType,
                        decoration: const InputDecoration(labelText: 'Battery Type'),
                        items: const [
                          DropdownMenuItem(value: 'INVERTER', child: Text('Inverter')),
                          DropdownMenuItem(value: '2W', child: Text('2 Wheeler')),
                          DropdownMenuItem(value: '4W', child: Text('4 Wheeler')),
                          DropdownMenuItem(value: 'TRUCK', child: Text('Truck')),
                        ],
                        onChanged: (val) => setState(() => _batteryType = val ?? 'INVERTER'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _reminderType,
                        decoration: const InputDecoration(labelText: 'Reminder Type'),
                        items: const [
                          DropdownMenuItem(value: 'WATER_CHECK', child: Text('Water Check')),
                          DropdownMenuItem(value: 'SERVICE', child: Text('Service Check')),
                          DropdownMenuItem(value: 'WARRANTY_EXPIRY', child: Text('Warranty Expiry')),
                          DropdownMenuItem(value: 'UDHARI', child: Text('Udhari Recovery')),
                        ],
                        onChanged: (val) => setState(() => _reminderType = val ?? 'WATER_CHECK'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectDate(context, false),
                        icon: const Icon(Icons.calendar_month),
                        label: Text('Due: ${DateFormat('dd-MMM-yyyy').format(_reminderDate)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectDate(context, true),
                        icon: const Icon(Icons.security),
                        label: Text(_warrantyExpiry == null ? 'Set Expiry' : 'Exp: ${DateFormat('dd-MMM').format(_warrantyExpiry!)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Internal Service Notes'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveForm,
          child: _isSaving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Details and WhatsApp Template Review Dialog
// ---------------------------------------------------------------------------
class ReminderDetailsDialog extends ConsumerWidget {
  final Reminder reminder;
  final VoidCallback onSend;

  const ReminderDetailsDialog({super.key, required this.reminder, required this.onSend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.message_outlined, color: Colors.green),
          SizedBox(width: 10),
          Text('WhatsApp Follow-up Draft'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To: ${reminder.customerName} (${reminder.mobileNumber})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 16),
            FutureBuilder<Map<String, dynamic>>(
              future: ref.read(templateOperationsProvider).renderMessagePreview(reminder.id, channel: 'whatsapp'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator(color: Colors.green)),
                  );
                }
                
                final text = snapshot.data?['message_body'] as String? ?? reminder.whatsappTemplate ?? 'No draft available.';
                
                return Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(fontSize: 14, color: AppTheme.secondaryColor, height: 1.4),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Clicking "Send WhatsApp" will copy this draft to your clipboard, mark the reminder as Sent, and open WhatsApp Web/App.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
            onSend();
          },
          icon: const Icon(Icons.send),
          label: const Text('Send WhatsApp'),
        ),
      ],
    );
  }
}
