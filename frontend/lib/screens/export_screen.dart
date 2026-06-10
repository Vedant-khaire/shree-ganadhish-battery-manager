// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../core/download_helper.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_button.dart';
import '../widgets/toast_helper.dart';
import '../core/utils.dart';
import '../core/theme.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String _exportType = 'all'; // Default: export everything
  final _fromDateController = TextEditingController();
  final _toDateController = TextEditingController();
  
  // Backup controls
  int _selectedBackupYear = DateTime.now().year;
  
  // Cleanup controls
  int _cleanupYear = DateTime.now().year - 1;
  String _cleanupAction = 'archive'; // 'archive' or 'delete'
  final _cleanupConfirmController = TextEditingController();

  bool _isDownloading = false;
  String? _errorMessage;

  // Email Backup metadata
  String? _lastBackupSentDate;
  String? _recommendedNextBackupDate;
  String? _lastBackupFilename;
  bool _isMonthlyBackup = false;
  int _selectedBackupMonth = DateTime.now().month;
  bool _showSuccessGlow = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchBackupStatus();
    });
  }

  Future<void> _fetchBackupStatus() async {
    final apiClient = ref.read(apiClientProvider);
    try {
      final response = await apiClient.dio.get('/exports/backup-status');
      if (mounted) {
        setState(() {
          _lastBackupSentDate = response.data['last_backup_sent_date'];
          _recommendedNextBackupDate = response.data['recommended_next_backup_date'];
          _lastBackupFilename = response.data['last_backup_filename'];

        });
      }
    } catch (_) {
      // Fail silently for status loading
    }
  }


  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    _cleanupConfirmController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller, {DateTime? firstDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: firstDate ?? DateTime(2020),
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
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _startExport() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    final apiClient = ref.read(apiClientProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    String filename;
    if (_exportType == 'customers') {
      filename = 'customers_$today.xlsx';
    } else if (_exportType == 'batteries') {
      filename = 'guarantees_$today.xlsx';
    } else if (_exportType == 'payments') {
      filename = 'udhari_$today.xlsx';
    } else if (_exportType == 'customer_payment_transactions') {
      filename = 'customer_payment_transactions_$today.xlsx';
    } else if (_exportType == 'scrap_payments') {
      filename = 'scrap_battery_payments_$today.xlsx';
    } else {
      filename = 'shree_ganadhish_export_$today.xlsx';
    }

    final queryParams = <String, dynamic>{
      'type': _exportType,
    };

    if (_fromDateController.text.trim().isNotEmpty) {
      queryParams['date_from'] = _fromDateController.text.trim();
    }
    if (_toDateController.text.trim().isNotEmpty) {
      queryParams['date_to'] = _toDateController.text.trim();
    }

    try {
      final response = await apiClient.dio.get<List<int>>(
        '/exports/excel',
        queryParameters: queryParams,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        downloadFile(response.data!, filename);
        if (mounted) {
          ToastHelper.show(context, 'Report downloaded successfully');
        }
      } else {
        throw Exception('Received empty data from export endpoint');
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorParser.parse(e);
      });
      if (mounted) {
        ToastHelper.show(context, 'Export failed: $_errorMessage', isError: true);
      }
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _downloadBackupZip() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    final apiClient = ref.read(apiClientProvider);
    final filename = _isMonthlyBackup
        ? 'shree_ganadhish_backup_${_selectedBackupYear}_${_selectedBackupMonth.toString().padLeft(2, '0')}.zip'
        : 'yearly_backup_$_selectedBackupYear.zip';

    try {
      final response = await apiClient.dio.get<List<int>>(
        '/exports/backup',
        queryParameters: {
          'period': _isMonthlyBackup ? 'monthly' : 'yearly',
          'year': _selectedBackupYear,
          if (_isMonthlyBackup) 'month': _selectedBackupMonth,
        },
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        downloadFile(response.data!, filename);
        if (mounted) {
          ToastHelper.show(context, 'Backup ZIP downloaded successfully');
        }
      } else {
        throw Exception('Empty backup ZIP data returned');
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorParser.parse(e);
      });
      if (mounted) {
        ToastHelper.show(context, 'Backup download failed: $_errorMessage', isError: true);
      }
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _triggerEmailBackup() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    final apiClient = ref.read(apiClientProvider);
    final filename = _isMonthlyBackup
        ? 'shree_ganadhish_backup_${_selectedBackupYear}_${_selectedBackupMonth.toString().padLeft(2, '0')}.zip'
        : 'yearly_backup_$_selectedBackupYear.zip';

    try {
      final response = await apiClient.dio.post(
        '/exports/email-backup',
        queryParameters: {
          'period': _isMonthlyBackup ? 'monthly' : 'yearly',
          'year': _selectedBackupYear,
          if (_isMonthlyBackup) 'month': _selectedBackupMonth,
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ToastHelper.show(context, 'Backup ZIP sent to email successfully!');
          setState(() {
            _showSuccessGlow = true;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _showSuccessGlow = false;
              });
            }
          });
        }
        await _fetchBackupStatus();
      } else {
        throw Exception('Received unexpected response format');
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorParser.parse(e);
      });
      if (mounted) {
        ToastHelper.show(context, 'Email Backup failed: $_errorMessage', isError: true);
      }
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }


  Future<void> _executeCleanup() async {
    final expectedConfirm = '${_cleanupAction.toUpperCase()} $_cleanupYear DATA';
    if (_cleanupConfirmController.text.trim() != expectedConfirm) {
      setState(() {
        _errorMessage = 'Invalid confirmation. Please type "$expectedConfirm" exactly.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    final apiClient = ref.read(apiClientProvider);
    try {
      final response = await apiClient.dio.post(
        '/exports/archive',
        data: {
          'action': _cleanupAction,
          'year': _cleanupYear,
          'confirm_text': _cleanupConfirmController.text.trim(),
        },
      );

      final resData = response.data['data'] as Map<String, dynamic>? ?? {};
      final pCount = resData['payments_count'] ?? 0;
      final bCount = resData['batteries_count'] ?? 0;
      final cCount = resData['customers_count'] ?? 0;

      if (mounted) {
        _cleanupConfirmController.clear();
        ToastHelper.show(
          context,
          'Cleanup Successful: Settled/Expired records processed ($cCount customers, $bCount batteries, $pCount payments).',
        );
        ref.invalidate(dashboardProvider);
      }
    } catch (e) {
      setState(() {
        _errorMessage = ErrorParser.parse(e);
      });
      if (mounted) {
        ToastHelper.show(context, 'Cleanup execution failed: $_errorMessage', isError: true);
      }
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 900;

    return AppScaffold(
      title: 'Data Export Center & Backups',
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Generate Business Reports',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Generate spreadsheet exports, download full yearly backup ZIP archives, and safely manage records retention.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
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

                    // Grid layout for selection
                    isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: _buildExportTypeSelector()),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: _buildFiltersCard()),
                            ],
                          )
                        : Column(
                            children: [
                              _buildExportTypeSelector(),
                              const SizedBox(height: 20),
                              _buildFiltersCard(),
                            ],
                          ),
                    
                    const SizedBox(height: 24),
                    
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: AppButton(
                          label: 'Generate & Download Excel',
                          icon: Icons.download_outlined,
                          isLoading: _isDownloading,
                          onPressed: _isDownloading ? null : _startExport,
                        ),
                      ),
                    ),

                    const Divider(height: 48),

                    // Yearly ZIP Backup Section
                    _buildYearlyBackupCard(isDesktop),

                    const SizedBox(height: 24),

                    // Archive & Cleanup protections Section
                    _buildArchivingCleanupSection(isDesktop),
                  ],
                ),
              ),
            ),
          ),
          if (_isDownloading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(color: AppTheme.primaryColor),
                          SizedBox(height: 16),
                          Text(
                            'Processing request...',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Please wait while the server packages your data.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
    );
  }

  Widget _buildExportTypeSelector() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Report Type',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            const SizedBox(height: 16),
            _buildRadioTile('all', 'Complete Database Export', 'Downloads all customers, guarantee registries, and payment history in separate sheets.', Icons.analytics_outlined),
            const Divider(),
            _buildRadioTile('customers', 'Customer Directory Only', 'List of all customer profiles, contact numbers, vehicle numbers, and addresses.', Icons.people_outline),
            const Divider(),
            _buildRadioTile('batteries', 'Guarantee Registry Only', 'All registered batteries, warranty durations, expiry dates, and serial numbers.', Icons.battery_charging_full_outlined),
            const Divider(),
            _buildRadioTile('payments', 'Udhari & Payments Ledger', 'List of outstanding debts, totals, paid amounts, and customer contact info.', Icons.receipt_long_outlined),
            const Divider(),
            _buildRadioTile('customer_payment_transactions', 'Customer Payments History', 'Detailed history of all customer payments and transactions.', Icons.history_outlined),
            const Divider(),
            _buildRadioTile('scrap_payments', 'Scrap Battery Payouts', 'List of scrap battery payouts, expected/received values, and payout dates.', Icons.recycling_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioTile(String value, String title, String subtitle, IconData icon) {
    final selected = _exportType == value;
    return InkWell(
      onTap: _isDownloading ? null : () => setState(() => _exportType = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor.withOpacity(0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<String>(
              value: value,
              groupValue: _exportType,
              activeColor: AppTheme.primaryColor,
              onChanged: _isDownloading ? null : (val) {
                if (val != null) {
                  setState(() => _exportType = val);
                }
              },
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 24, color: selected ? AppTheme.primaryColor : const Color(0xFF64748B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: selected ? AppTheme.primaryColor : AppTheme.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Date Range (Optional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            const SizedBox(height: 16),
            
            // From Date
            TextFormField(
              controller: _fromDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'From Date',
                prefixIcon: const Icon(Icons.date_range_outlined, size: 20),
                suffixIcon: _fromDateController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _fromDateController.clear()),
                      )
                    : null,
              ),
              onTap: _isDownloading ? null : () => _selectDate(context, _fromDateController),
            ),
            const SizedBox(height: 20),

            // To Date
            TextFormField(
              controller: _toDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'To Date',
                prefixIcon: const Icon(Icons.date_range_outlined, size: 20),
                suffixIcon: _toDateController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _toDateController.clear()),
                      )
                    : null,
              ),
              onTap: _isDownloading ? null : () => _selectDate(context, _toDateController),
            ),
            const SizedBox(height: 16),
            
            if (_fromDateController.text.isNotEmpty || _toDateController.text.isNotEmpty)
              TextButton.icon(
                onPressed: _isDownloading
                    ? null
                    : () {
                        setState(() {
                          _fromDateController.clear();
                          _toDateController.clear();
                        });
                      },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset Date Filters'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isBackupOverdue() {
    if (_recommendedNextBackupDate == null) return true;
    try {
      final nextDate = DateTime.parse(_recommendedNextBackupDate!);
      final today = DateTime.now();
      return nextDate.isBefore(today);
    } catch (_) {
      return true;
    }
  }

  Widget _buildPeriodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleItem(false, 'Yearly Backup'),
          _buildToggleItem(true, 'Monthly Backup'),
        ],
      ),
    );
  }

  Widget _buildToggleItem(bool value, String label) {
    final isSelected = _isMonthlyBackup == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _isDownloading
          ? null
          : () {
              setState(() {
                _isMonthlyBackup = value;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey.shade400 : const Color(0xFF64748B)),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildYearlyBackupCard(bool isDesktop) {
    final currentYear = DateTime.now().year;
    final years = List<int>.generate(7, (idx) => currentYear - idx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOverdue = _isBackupOverdue();

    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOverdue 
            ? Colors.amber.shade50.withOpacity(isDark ? 0.15 : 0.9) 
            : Colors.green.shade50.withOpacity(isDark ? 0.15 : 0.9),
        border: Border.all(
          color: isOverdue 
              ? (isDark ? Colors.amber.shade700 : Colors.amber.shade300)
              : (isDark ? Colors.green.shade700 : Colors.green.shade300),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: isOverdue 
                ? (isDark ? Colors.amber.shade400 : Colors.amber.shade900)
                : (isDark ? Colors.green.shade400 : Colors.green.shade900),
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            isOverdue ? 'ACTION REQUIRED' : 'UP TO DATE',
            style: TextStyle(
              color: isOverdue 
                  ? (isDark ? Colors.amber.shade400 : Colors.amber.shade900)
                  : (isDark ? Colors.green.shade400 : Colors.green.shade900),
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );

    final lastBackupText = _lastBackupSentDate != null
        ? FormatUtils.formatDate(_lastBackupSentDate!)
        : 'Never';
        
    final recommendedNextText = _recommendedNextBackupDate != null
        ? FormatUtils.formatDate(_recommendedNextBackupDate!)
        : FormatUtils.formatDate(DateTime.now().toIso8601String().substring(0, 10));

    Widget buildMetaItem(String title, String val, IconData icon, {bool highlight = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon, 
              color: highlight 
                  ? AppTheme.primaryColor 
                  : (isDark ? Colors.grey.shade400 : const Color(0xFF64748B)), 
              size: 20
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    val,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: highlight 
                          ? AppTheme.primaryColor 
                          : (isDark ? Colors.white : AppTheme.secondaryColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final item1 = buildMetaItem('LAST BACKUP SENT', lastBackupText, Icons.cloud_done_outlined);
    final item2 = buildMetaItem('RECOMMENDED NEXT BACKUP', recommendedNextText, Icons.calendar_month_outlined, highlight: isOverdue);
    final item3 = buildMetaItem('LAST BACKUP FILENAME', _lastBackupFilename ?? 'None', Icons.insert_drive_file_outlined);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _showSuccessGlow
              ? Colors.green
              : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200),
          width: _showSuccessGlow ? 2 : 1,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _showSuccessGlow
              ? [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 4,
                  )
                ]
              : null,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    const Color(0xFF1E293B).withOpacity(0.4),
                  ]
                : [
                    Colors.white,
                    const Color(0xFFF8FAFC),
                  ],
          ),
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cloud_sync_outlined,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Secure Backup Control Center',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Email a fully secured ZIP archive (containing Customers, Batteries, Payments, Stock, and Reminders) directly to your inbox, and simultaneously download it locally.',
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Warning Banner for Overdue Backup
            if (isOverdue) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50.withOpacity(isDark ? 0.15 : 0.9),
                  border: Border.all(
                    color: isDark ? Colors.amber.shade700 : Colors.amber.shade300,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'WARNING: Your backup is overdue! Please click "Send Backup to Email" or "Download ZIP Only" to update your backup history.',
                        style: TextStyle(
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Metadata panel
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : const Color(0xFFF1F5F9).withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'EMAIL BACKUP METADATA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      statusBadge,
                    ],
                  ),
                  const SizedBox(height: 12),
                  isDesktop
                      ? Row(
                          children: [
                            Expanded(child: item1),
                            const SizedBox(width: 12),
                            Expanded(child: item2),
                            const SizedBox(width: 12),
                            Expanded(child: item3),
                          ],
                        )
                      : Column(
                          children: [
                            item1,
                            const SizedBox(height: 12),
                            item2,
                            const SizedBox(height: 12),
                            item3,
                          ],
                        ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Period Selector & Dropdowns Wrap
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildPeriodToggle(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isMonthlyBackup) ...[
                      const Text(
                        'Month: ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 130,
                        child: DropdownButton<int>(
                          value: _selectedBackupMonth,
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.secondaryColor,
                          ),
                          underline: Container(
                            height: 1.5,
                            color: AppTheme.primaryColor,
                          ),
                          items: List.generate(12, (index) {
                            final monthVal = index + 1;
                            final date = DateTime(2026, monthVal, 1);
                            final monthName = DateFormat('MMMM').format(date);
                            return DropdownMenuItem(
                              value: monthVal,
                              child: Text(monthName),
                            );
                          }),
                          onChanged: _isDownloading
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() => _selectedBackupMonth = val);
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    const Text(
                      'Year: ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<int>(
                      value: _selectedBackupYear,
                      style: TextStyle(
                        fontSize: 13, 
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.secondaryColor,
                      ),
                      underline: Container(
                        height: 1.5,
                        color: AppTheme.primaryColor,
                      ),
                      items: years.map((y) {
                        return DropdownMenuItem(
                          value: y,
                          child: Text('$y'),
                        );
                      }).toList(),
                      onChanged: _isDownloading
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _selectedBackupYear = val);
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Actions row
            isDesktop
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: 'Download ZIP Only',
                        icon: Icons.archive_outlined,
                        isSecondary: true,
                        isLoading: _isDownloading,
                        onPressed: _isDownloading ? null : _downloadBackupZip,
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        label: 'Send Backup to Email',
                        icon: Icons.email_outlined,
                        isLoading: _isDownloading,
                        onPressed: _isDownloading ? null : _triggerEmailBackup,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppButton(
                        label: 'Send Backup to Email',
                        icon: Icons.email_outlined,
                        isLoading: _isDownloading,
                        onPressed: _isDownloading ? null : _triggerEmailBackup,
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'Download ZIP Only',
                        icon: Icons.archive_outlined,
                        isSecondary: true,
                        isLoading: _isDownloading,
                        onPressed: _isDownloading ? null : _downloadBackupZip,
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivingCleanupSection(bool isDesktop) {
    final currentYear = DateTime.now().year;
    final years = List<int>.generate(5, (idx) => currentYear - idx);
    final confirmString = '${_cleanupAction.toUpperCase()} $_cleanupYear DATA';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.red.shade100),
      ),
      color: Colors.red.shade50.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Archiving & Clean-up Workspace',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade900),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Delete or archive records that are old. Smart protection safeguards are applied automatically: we never delete active warranties, customers with pending balances, or active battery registries.',
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Choose Year & Action Dropdowns
            Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Target Year: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _cleanupYear,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                      items: years.map((y) {
                        return DropdownMenuItem(value: y, child: Text('$y'));
                      }).toList(),
                      onChanged: _isDownloading
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() {
                                  _cleanupYear = val;
                                  _cleanupConfirmController.clear();
                                });
                              }
                            },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Cleanup Mode: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _cleanupAction,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                      items: const [
                        DropdownMenuItem(value: 'archive', child: Text('Archive')),
                        DropdownMenuItem(value: 'delete', child: Text('Hard Delete')),
                      ],
                      onChanged: _isDownloading
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() {
                                  _cleanupAction = val;
                                  _cleanupConfirmController.clear();
                                });
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Warning Notice Cards
            if (_cleanupAction == 'delete') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'WARNING: Hard Delete is permanent and cannot be undone. Always verify that a ZIP backup has been downloaded first.',
                        style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Confirmation typing text field
            Text(
              'Type confirmation string to execute: "$confirmString"',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.secondaryColor),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _cleanupConfirmController,
              enabled: !_isDownloading,
              decoration: InputDecoration(
                hintText: 'Enter "$confirmString" exactly',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) {
                // Force UI rebuild to enable/disable button
                setState(() {});
              },
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cleanupAction == 'delete' ? Colors.red : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  icon: Icon(_cleanupAction == 'delete' ? Icons.delete_forever : Icons.archive),
                  label: Text(
                    _cleanupAction == 'delete' ? 'Permanently Delete records' : 'Archive records',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: (_isDownloading || _cleanupConfirmController.text.trim() != confirmString)
                      ? null
                      : _executeCleanup,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
