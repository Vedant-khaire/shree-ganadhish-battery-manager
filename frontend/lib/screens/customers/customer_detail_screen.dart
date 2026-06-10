import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/customer_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/battery_provider.dart';
import '../../providers/reminder_provider.dart';
import '../../providers/message_template_provider.dart';
import '../../models/customer.dart';
import '../../models/battery.dart';
import '../../models/payment.dart';
import '../../models/reminder.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';
import '../../core/url_helper.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
  });

  String _getBatteryStatus(String expiryDateStr) {
    try {
      final expiry = DateTime.parse(expiryDateStr);
      final today = DateTime.now();
      final todayDateOnly = DateTime(today.year, today.month, today.day);
      if (expiry.isBefore(todayDateOnly)) {
        return 'EXPIRED';
      }
      final diff = expiry.difference(todayDateOnly).inDays;
      if (diff <= 30) {
        return 'EXPIRING SOON';
      }
      return 'ACTIVE';
    } catch (_) {
      return 'ACTIVE';
    }
  }

  String _parsePaymentMethod(String? note) {
    if (note == null) return 'N/A';
    final regExp = RegExp(r'\[Method:\s*([^\]]+)\]');
    final match = regExp.firstMatch(note);
    if (match != null) {
      return match.group(1)?.trim() ?? 'N/A';
    }
    return 'N/A';
  }

  String _parseDueDate(String? note) {
    if (note == null) return 'N/A';
    final regExp = RegExp(r'\[Due:\s*([^\]]+)\]');
    final match = regExp.firstMatch(note);
    if (match != null) {
      final dateStr = match.group(1)?.trim();
      if (dateStr != null) {
        return FormatUtils.formatDate(dateStr);
      }
    }
    return 'N/A';
  }

  String _parseReminderNote(String? note) {
    if (note == null) return '';
    var cleanNote = note;
    final methodRegExp = RegExp(r'\[Method:\s*([^\]]+)\]');
    cleanNote = cleanNote.replaceAll(methodRegExp, '').trim();
    final dueRegExp = RegExp(r'\[Due:\s*([^\]]+)\]');
    cleanNote = cleanNote.replaceAll(dueRegExp, '').trim();
    return cleanNote;
  }

  void _showArchiveCustomerDialog(BuildContext context, WidgetRef ref, String id, String name, bool archive) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(archive ? 'Archive Customer?' : 'Restore Customer?'),
          content: Text(
            archive
                ? 'Are you sure you want to archive $name? This will hide them from the active customer directory.'
                : 'Do you want to restore $name back to the active customer registry?',
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
                final operations = ref.read(customerOperationsProvider);
                try {
                  if (archive) {
                    await operations.archiveCustomer(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Customer archived successfully');
                      context.go('/customers');
                    }
                  } else {
                    await operations.restoreCustomer(id);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Customer restored successfully');
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

  void _showDeleteCustomerDialog(BuildContext context, WidgetRef ref, String id, String name) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Delete Customer permanently?', style: TextStyle(color: Colors.red)),
          content: Text(
            'Are you sure you want to delete customer "$name"?\n\n'
            'WARNING: This will permanently delete this customer and all their battery registrations and payment history. This action cannot be undone.',
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
                  await ref.read(customerOperationsProvider).deleteCustomer(id);
                  if (context.mounted) {
                    ToastHelper.show(context, 'Customer permanently deleted');
                    context.go('/customers');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ToastHelper.show(
                      context,
                      'Error deleting customer: ${ErrorParser.parse(e)}',
                      isError: true,
                    );
                  }
                }
              },
              child: const Text('Delete Customer'),
            ),
          ],
        );
      },
    );
  }

  void _settlePayment(BuildContext context, WidgetRef ref, String paymentId, double pendingAmount) {
    String selectedMode = 'CASH';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Settle Udhari?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mark this payment as settled? This will record that the pending balance of '
                  '${FormatUtils.formatIndianCurrency(pendingAmount)} has been paid in full.',
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
                      setState(() {
                        selectedMode = val;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ref.read(paymentOperationsProvider).settlePayment(paymentId, customerId, selectedMode);
                    if (context.mounted) {
                      ToastHelper.show(context, 'Payment settled successfully');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ToastHelper.show(
                        context,
                        'Error settling payment: ${ErrorParser.parse(e)}',
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
      ),
    );
  }

  void _archiveBattery(BuildContext context, WidgetRef ref, String batteryId, String serialNumber) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Guarantee?'),
        content: Text('Are you sure you want to archive the guarantee registry for serial number "$serialNumber"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(batteryOperationsProvider).archiveBattery(batteryId, customerId);
                if (context.mounted) {
                  ToastHelper.show(context, 'Guarantee archived successfully');
                }
              } catch (e) {
                if (context.mounted) {
                  ToastHelper.show(
                    context,
                    'Error archiving guarantee: ${ErrorParser.parse(e)}',
                    isError: true,
                  );
                }
              }
            },
            child: const Text('Confirm Archive'),
          ),
        ],
      ),
    );
  }

  void _showDeleteBatteryDialog(BuildContext context, WidgetRef ref, String batteryId, String serialNumber) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Guarantee permanently?', style: TextStyle(color: Colors.red)),
        content: Text(
          'Are you sure you want to permanently delete the guarantee registry for serial number "$serialNumber"?\n\n'
          'WARNING: This will delete the battery record and any payment logs linked to it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(batteryOperationsProvider).deleteBattery(batteryId, customerId);
                if (context.mounted) {
                  ToastHelper.show(context, 'Battery registry permanently deleted');
                }
              } catch (e) {
                if (context.mounted) {
                  ToastHelper.show(
                    context,
                    'Error deleting battery: ${ErrorParser.parse(e)}',
                    isError: true,
                  );
                }
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _archivePayment(BuildContext context, WidgetRef ref, String paymentId, double totalAmount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Payment Entry?'),
        content: Text(
          'Are you sure you want to archive this payment entry of '
          '${FormatUtils.formatIndianCurrency(totalAmount)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(paymentOperationsProvider).archivePayment(paymentId, customerId);
                if (context.mounted) {
                  ToastHelper.show(context, 'Payment record archived successfully');
                }
              } catch (e) {
                if (context.mounted) {
                  ToastHelper.show(
                    context,
                    'Error archiving payment: ${ErrorParser.parse(e)}',
                    isError: true,
                  );
                }
              }
            },
            child: const Text('Confirm Archive'),
          ),
        ],
      ),
    );
  }

  void _showDeletePaymentDialog(BuildContext context, WidgetRef ref, String paymentId, double totalAmount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment permanently?', style: TextStyle(color: Colors.red)),
        content: Text(
          'Are you sure you want to permanently delete this payment entry of '
          '${FormatUtils.formatIndianCurrency(totalAmount)}?\n\n'
          'WARNING: This will permanently remove this transaction from the records. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(paymentOperationsProvider).deletePayment(paymentId, customerId);
                if (context.mounted) {
                  ToastHelper.show(context, 'Payment entry permanently deleted');
                }
              } catch (e) {
                if (context.mounted) {
                  ToastHelper.show(
                    context,
                    'Error deleting payment: ${ErrorParser.parse(e)}',
                    isError: true,
                  );
                }
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStatusChip(String status) {
    Color bgColor;
    Color textColor;
    Color borderColor;

    switch (status) {
      case 'ACTIVE':
        bgColor = const Color(0xFFF0FDF4);
        textColor = const Color(0xFF16A34A);
        borderColor = const Color(0xFFBBF7D0);
        break;
      case 'EXPIRING SOON':
        bgColor = const Color(0xFFFFFBEB);
        textColor = const Color(0xFFD97706);
        borderColor = const Color(0xFFFDE68A);
        break;
      case 'EXPIRED':
        bgColor = const Color(0xFFFEF2F2);
        textColor = const Color(0xFFDC2626);
        borderColor = const Color(0xFFFECACA);
        break;
      default:
        bgColor = Colors.grey.shade50;
        textColor = Colors.grey.shade700;
        borderColor = Colors.grey.shade200;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(customerDetailsProvider(customerId));
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 900;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(customerDetailsProvider(customerId).future),
        color: AppTheme.primaryColor,
        child: detailsAsync.when(
          data: (details) {
            final c = details.customer;

            final sortedBatteries = List<Battery>.from(details.batteries)
              ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

            final sortedPayments = List<Payment>.from(details.payments)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            double pendingUdhari = 0.0;
            for (var p in details.payments) {
              if (!p.isArchived) {
                pendingUdhari += p.pendingAmount;
              }
            }

            return AppScaffold(
              title: 'Workspace: ${c.name}',
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Navigation Toolbar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => context.go('/customers'),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Back to Directory'),
                          ),
                          Row(
                            children: [
                              AppButton(
                                label: 'Edit Profile',
                                icon: Icons.edit_outlined,
                                isSecondary: true,
                                onPressed: () => context.go('/customers/${c.id}/edit'),
                              ),
                              const SizedBox(width: 12),
                              AppButton(
                                label: 'Delete Customer',
                                icon: Icons.delete_forever_outlined,
                                isSecondary: true,
                                onPressed: () => _showDeleteCustomerDialog(context, ref, c.id, c.name),
                              ),
                              const SizedBox(width: 12),
                              AppButton(
                                label: c.isArchived ? 'Restore' : 'Archive',
                                icon: c.isArchived ? Icons.settings_backup_restore : Icons.archive_outlined,
                                isSecondary: true,
                                onPressed: () => _showArchiveCustomerDialog(context, ref, c.id, c.name, !c.isArchived),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Customer Info Card
                      _buildProfileCard(context, c, sortedBatteries.length, pendingUdhari),
                      const SizedBox(height: 24),

                      // Quick Action Buttons Panel
                      _buildQuickActionButtonsPanel(context, ref, c),
                      const SizedBox(height: 28),

                      // Batteries List Section
                      _buildBatterySection(context, ref, sortedBatteries, isDesktop),
                      const SizedBox(height: 36),

                      // Payments List Section
                      _buildPaymentSection(context, ref, sortedPayments, isDesktop),
                      const SizedBox(height: 36),

                      // Service Reminders Section
                      _buildReminderSection(context, ref, details.reminders, isDesktop),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => AppScaffold(
            title: 'Loading profile...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LoadingSkeleton(width: double.infinity, height: 160),
                  const SizedBox(height: 32),
                  LoadingSkeleton.list(count: 2),
                  const SizedBox(height: 24),
                  LoadingSkeleton.list(count: 2),
                ],
              ),
            ),
          ),
          error: (err, stack) => AppScaffold(
            title: 'Error',
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('Failed to load customer profile details'),
                  Text(ErrorParser.parse(err), style: const TextStyle(color: Color(0xFF64748B))),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => context.go('/customers'),
                        child: const Text('Go Back'),
                      ),
                      const SizedBox(width: 16),
                      AppButton(
                        label: 'Try Again',
                        onPressed: () => ref.invalidate(customerDetailsProvider(customerId)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, Customer customer, int batteryCount, double pendingUdhari) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.primaryColor.withAlpha(20),
                  child: Text(
                    customer.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customer.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                          ),
                          if (customer.isArchived) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                'ARCHIVED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          _buildDetailItem(Icons.phone, 'Mobile', customer.mobile),
                          _buildDetailItem(
                            Icons.directions_car,
                            'Vehicle',
                            customer.vehicleNo != null
                                ? '${customer.vehicleNo} (${customer.vehicleType ?? 'Other'})'
                                : 'No Vehicle Registered',
                          ),
                          _buildDetailItem(Icons.location_on, 'Area/Village', customer.area ?? '-'),
                          _buildDetailItem(Icons.shopping_bag, 'Account Type', customer.purchaseType),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryStatCard('Batteries Sold', '$batteryCount', Colors.blue),
                _buildSummaryStatCard(
                  'Pending Udhari',
                  FormatUtils.formatIndianCurrency(pendingUdhari),
                  pendingUdhari > 0 ? Colors.red : Colors.green.shade800,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 13, color: AppTheme.secondaryColor, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionButtonsPanel(BuildContext context, WidgetRef ref, Customer customer) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OPERATIONAL CONTROLS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  label: 'Add Battery',
                  icon: Icons.battery_charging_full_outlined,
                  onPressed: () => context.go('/customers/${customer.id}/batteries/new'),
                ),
                AppButton(
                  label: 'Add Udhari',
                  icon: Icons.account_balance_wallet_outlined,
                  isSecondary: true,
                  onPressed: () => context.go('/customers/${customer.id}/payments/new'),
                ),
                AppButton(
                  label: 'Edit Customer',
                  icon: Icons.edit_outlined,
                  isSecondary: true,
                  onPressed: () => context.go('/customers/${customer.id}/edit'),
                ),
                AppButton(
                  label: 'Delete Customer',
                  icon: Icons.delete_forever_outlined,
                  isSecondary: true,
                  onPressed: () => _showDeleteCustomerDialog(context, ref, customer.id, customer.name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatterySection(BuildContext context, WidgetRef ref, List<Battery> batteries, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Battery History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
              onPressed: () => context.go('/customers/$customerId/batteries/new'),
              tooltip: 'Register Battery',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (batteries.isEmpty)
          EmptyState(
            title: 'No Batteries Registered',
            message: 'Track physical battery serial numbers and guarantee details for this customer.',
            icon: Icons.battery_alert_outlined,
            actionLabel: 'Register Battery',
            onAction: () => context.go('/customers/$customerId/batteries/new'),
          )
        else
          isDesktop
              ? _buildBatteryTable(context, ref, batteries)
              : _buildBatteryCards(context, ref, batteries),
      ],
    );
  }

  Widget _buildBatteryTable(BuildContext context, WidgetRef ref, List<Battery> batteries) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.5),
          4: FlexColumnWidth(1.5),
          5: FlexColumnWidth(1.5),
          6: IntrinsicColumnWidth(),
        },
        children: [
          // Table Header
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            ),
            children: const [
              Padding(padding: EdgeInsets.all(12.0), child: Text('Model', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Serial Number', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Warranty', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Sale Date', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Expiry Date', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          // Rows
          ...batteries.map((b) {
            final status = _getBatteryStatus(b.warrantyExpiry);
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.modelNumber ?? 'Custom Model', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (b.notes != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Note: ${b.notes!}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(b.serialNumber ?? '-', style: const TextStyle(fontFamily: 'monospace')),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text('${b.warrantyMonths} Mos'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(FormatUtils.formatDate(b.saleDate)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(FormatUtils.formatDate(b.warrantyExpiry)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: _buildBatteryStatusChip(status),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                        tooltip: 'Edit battery',
                        onPressed: () => context.go('/customers/$customerId/batteries/${b.id}/edit'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.archive_outlined, color: Colors.orange, size: 20),
                        tooltip: 'Archive battery',
                        onPressed: () => _archiveBattery(context, ref, b.id, b.serialNumber ?? 'No Serial'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 20),
                        tooltip: 'Delete permanently',
                        onPressed: () => _showDeleteBatteryDialog(context, ref, b.id, b.serialNumber ?? 'No Serial'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBatteryCards(BuildContext context, WidgetRef ref, List<Battery> batteries) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: batteries.length,
      itemBuilder: (ctx, index) {
        final b = batteries[index];
        final status = _getBatteryStatus(b.warrantyExpiry);
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      b.modelNumber ?? 'Custom Model',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    _buildBatteryStatusChip(status),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(child: _buildRecordField('Serial No', b.serialNumber ?? '-')),
                    Expanded(child: _buildRecordField('Warranty', '${b.warrantyMonths} Months')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildRecordField('Sale Date', FormatUtils.formatDate(b.saleDate))),
                    Expanded(child: _buildRecordField('Expiry Date', FormatUtils.formatDate(b.warrantyExpiry))),
                  ],
                ),
                if (b.notes != null) ...[
                  const SizedBox(height: 12),
                  _buildRecordField('Notes', b.notes!),
                ],
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      onPressed: () => context.go('/customers/$customerId/batteries/${b.id}/edit'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.archive_outlined, size: 16, color: Colors.orange),
                      label: const Text('Archive', style: TextStyle(color: Colors.orange)),
                      onPressed: () => _archiveBattery(context, ref, b.id, b.serialNumber ?? 'No Serial'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_forever_outlined, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      onPressed: () => _showDeleteBatteryDialog(context, ref, b.id, b.serialNumber ?? 'No Serial'),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentSection(BuildContext context, WidgetRef ref, List<Payment> payments, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Udhari Ledger',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
              onPressed: () => context.go('/customers/$customerId/payments/new'),
              tooltip: 'New Transaction',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          EmptyState(
            title: 'No Payments Recorded',
            message: 'All transaction logs and udhari credits will be displayed here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add Udhari',
            onAction: () => context.go('/customers/$customerId/payments/new'),
          )
        else
          isDesktop
              ? _buildPaymentTable(context, ref, payments)
              : _buildPaymentCards(context, ref, payments),
      ],
    );
  }

  Widget _buildPaymentTable(BuildContext context, WidgetRef ref, List<Payment> payments) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1.5),
          5: FlexColumnWidth(1.8),
          6: IntrinsicColumnWidth(),
        },
        children: [
          // Header Row
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            ),
            children: const [
              Padding(padding: EdgeInsets.all(12.0), child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Paid', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Pending', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Method', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Status & Comments', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12.0), child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          // Rows
          ...payments.map((p) {
            final method = _parsePaymentMethod(p.reminderNote);
            final note = _parseReminderNote(p.reminderNote);
            final dueDate = _parseDueDate(p.reminderNote);
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(FormatUtils.formatIndianCurrency(p.totalAmount)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(FormatUtils.formatIndianCurrency(p.paidAmount)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(
                    FormatUtils.formatIndianCurrency(p.pendingAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: p.pendingAmount > 0 ? Colors.red : Colors.green.shade800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.isSettled ? (p.paymentMode ?? 'N/A') : method,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Text(dueDate),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.isSettled ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          p.isSettled ? 'SETTLED' : 'PENDING',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: p.isSettled ? Colors.green.shade800 : Colors.orange.shade900,
                          ),
                        ),
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(note, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!p.isSettled)
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                          tooltip: 'Mark as Paid',
                          onPressed: () => _settlePayment(context, ref, p.id, p.pendingAmount),
                        ),
                      IconButton(
                        icon: const Icon(Icons.archive_outlined, color: Colors.orange, size: 20),
                        tooltip: 'Archive payment',
                        onPressed: () => _archivePayment(context, ref, p.id, p.totalAmount),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 20),
                        tooltip: 'Delete permanently',
                        onPressed: () => _showDeletePaymentDialog(context, ref, p.id, p.totalAmount),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPaymentCards(BuildContext context, WidgetRef ref, List<Payment> payments) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: payments.length,
      itemBuilder: (ctx, index) {
        final p = payments[index];
        final method = _parsePaymentMethod(p.reminderNote);
        final note = _parseReminderNote(p.reminderNote);
        final dueDate = _parseDueDate(p.reminderNote);
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      p.isSettled ? 'Paid Entry' : 'Outstanding Balance',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: p.isSettled ? Colors.green.shade800 : Colors.orange.shade900,
                      ),
                    ),
                    Text(
                      p.isSettled ? 'Settlement Mode: ${p.paymentMode ?? 'N/A'}' : 'Method: $method',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(child: _buildRecordField('Total', FormatUtils.formatIndianCurrency(p.totalAmount))),
                    Expanded(child: _buildRecordField('Paid', FormatUtils.formatIndianCurrency(p.paidAmount))),
                    Expanded(
                      child: _buildRecordField(
                        'Pending',
                        FormatUtils.formatIndianCurrency(p.pendingAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: p.pendingAmount > 0 ? Colors.red : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildRecordField('Due Date', dueDate)),
                    Expanded(child: _buildRecordField('Notes', note.isNotEmpty ? note : '-')),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!p.isSettled) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text('Mark Paid', style: TextStyle(fontSize: 12)),
                        onPressed: () => _settlePayment(context, ref, p.id, p.pendingAmount),
                      ),
                      const SizedBox(width: 8),
                    ],
                    TextButton.icon(
                      icon: const Icon(Icons.archive_outlined, size: 16, color: Colors.orange),
                      label: const Text('Archive', style: TextStyle(color: Colors.orange)),
                      onPressed: () => _archivePayment(context, ref, p.id, p.totalAmount),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_forever_outlined, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      onPressed: () => _showDeletePaymentDialog(context, ref, p.id, p.totalAmount),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordField(String label, String value, {TextStyle? style}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: style ?? const TextStyle(fontSize: 13, color: AppTheme.secondaryColor, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildReminderSection(BuildContext context, WidgetRef ref, List<Reminder> reminders, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Scheduled Reminders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
              onPressed: () {
                final state = ref.read(customerDetailsProvider(customerId));
                state.whenData((details) {
                  _showAddReminderDialog(context, ref, details);
                });
              },
              tooltip: 'Add Custom Reminder',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reminders.isEmpty)
          EmptyState(
            title: 'No Reminders Scheduled',
            message: 'Distilled water checks, service maintenance, and warranty warnings will appear here.',
            icon: Icons.notifications_none_outlined,
            actionLabel: 'Schedule Reminder',
            onAction: () {
              final state = ref.read(customerDetailsProvider(customerId));
              state.whenData((details) {
                _showAddReminderDialog(context, ref, details);
              });
            },
          )
        else
          isDesktop
              ? _buildReminderTable(context, ref, reminders)
              : _buildReminderCards(context, ref, reminders),
      ],
    );
  }

  Widget _buildReminderTable(BuildContext context, WidgetRef ref, List<Reminder> reminders) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            columns: const [
              DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Battery / Serial', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Notes', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: reminders.map((r) {
              return DataRow(
                cells: [
                  DataCell(Text(FormatUtils.formatDate(r.reminderDate))),
                  DataCell(Text(r.reminderType.replaceAll('_', ' '))),
                  DataCell(Text('${r.batteryModel ?? 'N/A'}\n${r.batterySerial ?? 'N/A'}', style: const TextStyle(fontSize: 12))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: r.isCompleted
                            ? const Color(0xFFF0FDF4)
                            : (r.reminderStatus == 'DUE' || r.reminderStatus == 'OVERDUE'
                                ? const Color(0xFFFEF2F2)
                                : const Color(0xFFFFFBEB)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r.isCompleted ? 'COMPLETED' : r.reminderStatus,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: r.isCompleted
                              ? const Color(0xFF16A34A)
                              : (r.reminderStatus == 'DUE' || r.reminderStatus == 'OVERDUE'
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFD97706)),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 200,
                      child: Text(
                        r.notes ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            r.isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
                            color: r.isCompleted ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          onPressed: () => _toggleReminderCompletion(context, ref, r),
                          tooltip: r.isCompleted ? 'Mark Pending' : 'Mark Completed',
                        ),
                        if (!r.isCompleted)
                          IconButton(
                            icon: const Icon(Icons.share, color: Colors.green, size: 20),
                            onPressed: () => _sendWhatsAppReminder(context, ref, r),
                            tooltip: 'Send WhatsApp Follow-up',
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _deleteReminder(context, ref, r),
                          tooltip: 'Delete Reminder',
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

  Widget _buildReminderCards(BuildContext context, WidgetRef ref, List<Reminder> reminders) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reminders.length,
      itemBuilder: (context, index) {
        final r = reminders[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      FormatUtils.formatDate(r.reminderDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: r.isCompleted
                            ? const Color(0xFFF0FDF4)
                            : (r.reminderStatus == 'DUE' || r.reminderStatus == 'OVERDUE'
                                ? const Color(0xFFFEF2F2)
                                : const Color(0xFFFFFBEB)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r.isCompleted ? 'COMPLETED' : r.reminderStatus,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: r.isCompleted
                              ? const Color(0xFF16A34A)
                              : (r.reminderStatus == 'DUE' || r.reminderStatus == 'OVERDUE'
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFD97706)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Type: ${r.reminderType.replaceAll('_', ' ')}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (r.batteryModel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Battery: ${r.batteryModel} (S/N: ${r.batterySerial ?? "N/A"})',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
                if (r.notes != null && r.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notes: ${r.notes}',
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(
                        r.isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
                        color: r.isCompleted ? Colors.green : Colors.grey,
                        size: 18,
                      ),
                      label: Text(r.isCompleted ? 'Completed' : 'Complete', style: TextStyle(color: r.isCompleted ? Colors.green : Colors.grey)),
                      onPressed: () => _toggleReminderCompletion(context, ref, r),
                    ),
                    if (!r.isCompleted) ...[
                      const SizedBox(width: 12),
                      TextButton.icon(
                        icon: const Icon(Icons.share, color: Colors.green, size: 18),
                        label: const Text('WhatsApp', style: TextStyle(color: Colors.green)),
                        onPressed: () => _sendWhatsAppReminder(context, ref, r),
                      ),
                    ],
                    const SizedBox(width: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      onPressed: () => _deleteReminder(context, ref, r),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendWhatsAppReminder(BuildContext context, WidgetRef ref, Reminder r) async {
    String template = r.whatsappTemplate ?? '';
    try {
      final renderRes = await ref.read(templateOperationsProvider).renderMessagePreview(r.id, channel: 'whatsapp');
      template = renderRes['message_body'] as String? ?? template;
    } catch (e) {
      // Fallback silently to in-memory template text
    }

    final phone = r.mobileNumber;
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final encodedMsg = Uri.encodeComponent(template);
    final url = 'https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedMsg';

    try {
      await ref.read(reminderOperationsProvider).markAsSent(r.id, true);
      if (context.mounted) {
        ToastHelper.show(context, 'WhatsApp reminder template opened and marked Sent!');
      }
    } catch (e) {
      if (context.mounted) {
        ToastHelper.show(context, 'Error updating delivery state: ${ErrorParser.parse(e)}', isError: true);
      }
    }
    launchUrlString(url);
  }

  Future<void> _toggleReminderCompletion(BuildContext context, WidgetRef ref, Reminder r) async {
    try {
      await ref.read(reminderOperationsProvider).toggleCompletion(r.id, !r.isCompleted);
      ref.invalidate(customerDetailsProvider(customerId));
      if (context.mounted) {
        ToastHelper.show(context, r.isCompleted ? 'Reminder marked pending' : 'Reminder marked completed');
      }
    } catch (e) {
      if (context.mounted) {
        ToastHelper.show(context, 'Error: ${ErrorParser.parse(e)}', isError: true);
      }
    }
  }

  Future<void> _deleteReminder(BuildContext context, WidgetRef ref, Reminder r) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reminder?', style: TextStyle(color: Colors.red)),
        content: const Text('Are you sure you want to permanently delete this reminder? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(reminderOperationsProvider).deleteReminder(r.id);
                ref.invalidate(customerDetailsProvider(customerId));
                if (context.mounted) {
                  ToastHelper.show(context, 'Reminder deleted successfully');
                }
              } catch (e) {
                if (context.mounted) {
                  ToastHelper.show(context, 'Error deleting reminder: ${ErrorParser.parse(e)}', isError: true);
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddReminderDialog(BuildContext context, WidgetRef ref, CustomerWithDetails details) {
    String selectedType = 'SERVICE';
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    Battery? selectedBattery = details.batteries.isNotEmpty ? details.batteries.first : null;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Schedule Custom Reminder'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'Reminder Type'),
                      items: const [
                        DropdownMenuItem(value: 'WATER_CHECK', child: Text('Distilled Water Check')),
                        DropdownMenuItem(value: 'SERVICE', child: Text('Maintenance Service')),
                        DropdownMenuItem(value: 'WARRANTY_EXPIRY', child: Text('Guarantee Expiry Warning')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedType = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (details.batteries.isNotEmpty) ...[
                      DropdownButtonFormField<Battery?>(
                        value: selectedBattery,
                        decoration: const InputDecoration(labelText: 'Link to Battery'),
                        items: details.batteries.map((b) {
                          return DropdownMenuItem<Battery?>(
                            value: b,
                            child: Text('${b.modelNumber} (${b.serialNumber})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedBattery = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Reminder Date: ${DateFormat('dd-MMM-yyyy').format(selectedDate)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 30)),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                            );
                            if (picked != null) {
                              setState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                          child: const Text('Select Date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'Custom Notes (Optional)'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    
                    // Create default template draft
                    final cName = details.customer.name;
                    final model = selectedBattery?.modelNumber ?? '';
                    final serial = selectedBattery?.serialNumber ?? '';
                    String templateText = '';
                    if (selectedType == 'WATER_CHECK') {
                      templateText = "Hello $cName, this is a friendly reminder from Shree Ganadhish Auto Ele to check the distilled water levels of your Inverter battery $model.";
                    } else if (selectedType == 'SERVICE') {
                      templateText = "Hello $cName, your battery $model (Serial: $serial) is due for its scheduled maintenance checkup. Please visit Shree Ganadhish Auto Ele.";
                    } else {
                      templateText = "Hello $cName, please note that the guarantee period of your battery $model (Serial: $serial) will expire soon. Contact Shree Ganadhish Auto Ele.";
                    }

                    final payload = {
                      'customer_id': details.customer.id,
                      'battery_id': selectedBattery?.id,
                      'customer_name': details.customer.name,
                      'mobile_number': details.customer.mobile,
                      'battery_model': selectedBattery?.modelNumber,
                      'battery_serial': selectedBattery?.serialNumber,
                      'battery_type': selectedBattery?.batteryType,
                      'reminder_type': selectedType,
                      'reminder_date': DateFormat('yyyy-MM-dd').format(selectedDate),
                      'warranty_expiry': selectedBattery != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(selectedBattery!.warrantyExpiry)) : null,
                      'notes': notesController.text.trim(),
                      'whatsapp_template': templateText,
                    };

                    try {
                      await ref.read(reminderOperationsProvider).createReminder(payload);
                      ref.invalidate(customerDetailsProvider(customerId));
                      if (context.mounted) {
                        ToastHelper.show(context, 'Reminder scheduled successfully');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ToastHelper.show(context, 'Error creating reminder: ${ErrorParser.parse(e)}', isError: true);
                      }
                    }
                  },
                  child: const Text('Schedule'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
