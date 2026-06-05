import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/url_helper.dart';
import '../providers/message_template_provider.dart';
import '../models/message_template.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/toast_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/empty_state.dart';
import '../core/theme.dart';
import '../core/utils.dart';

class MessageTemplatesScreen extends ConsumerStatefulWidget {
  const MessageTemplatesScreen({super.key});

  @override
  ConsumerState<MessageTemplatesScreen> createState() => _MessageTemplatesScreenState();
}

class _MessageTemplatesScreenState extends ConsumerState<MessageTemplatesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MessageTemplate? _selectedTemplate;

  final _bodyController = TextEditingController();
  final _subjectController = TextEditingController();
  final _testMobileController = TextEditingController();
  bool _isActive = true;
  bool _isSaving = false;
  bool _isTesting = false;

  int _logsPage = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bodyController.dispose();
    _subjectController.dispose();
    _testMobileController.dispose();
    super.dispose();
  }

  void _selectTemplate(MessageTemplate t) {
    setState(() {
      _selectedTemplate = t;
      _bodyController.text = t.messageBody;
      _subjectController.text = t.messageSubject ?? '';
      _isActive = t.isActive;
    });
  }

  void _insertVariable(String variable) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, '{$variable}');
      _bodyController.text = newText;
      _bodyController.selection = TextSelection.collapsed(
        offset: selection.start + variable.length + 2,
      );
    } else {
      _bodyController.text = '$text {$variable}';
    }
    setState(() {}); // Update preview
  }

  Future<void> _updateTemplate() async {
    if (_selectedTemplate == null) return;

    setState(() {
      _isSaving = true;
    });

    final payload = {
      'message_body': _bodyController.text.trim(),
      'message_subject': _subjectController.text.trim().isEmpty ? null : _subjectController.text.trim(),
      'is_active': _isActive,
    };

    try {
      await ref.read(messageTemplatesProvider.notifier).updateTemplate(_selectedTemplate!.id, payload);
      ref.invalidate(templateVersionsProvider(_selectedTemplate!.id));
      ToastHelper.show(context, 'Template updated and versioned successfully!');
      
      // Refresh local template reference
      final list = ref.read(messageTemplatesProvider).value ?? [];
      final index = list.indexWhere((item) => item.id == _selectedTemplate!.id);
      if (index != -1) {
        setState(() {
          _selectedTemplate = list[index];
        });
      }
    } catch (e) {
      ToastHelper.show(context, 'Failed to update template: ${ErrorParser.parse(e)}', isError: true);
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _restoreVersion(int? versionNo) async {
    if (_selectedTemplate == null) return;
    
    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(messageTemplatesProvider.notifier).restoreTemplate(_selectedTemplate!.id, versionNo);
      ref.invalidate(templateVersionsProvider(_selectedTemplate!.id));
      
      // Reload template settings in inputs
      final list = ref.read(messageTemplatesProvider).value ?? [];
      final index = list.indexWhere((item) => item.id == _selectedTemplate!.id);
      if (index != -1) {
        _selectTemplate(list[index]);
      }
      
      ToastHelper.show(context, versionNo == null ? 'Restored factory default!' : 'Restored version $versionNo!');
    } catch (e) {
      ToastHelper.show(context, 'Failed to restore version: ${ErrorParser.parse(e)}', isError: true);
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _triggerTestMessage(String channel) async {
    if (_selectedTemplate == null) return;
    final mobile = _testMobileController.text.trim();
    if (mobile.isEmpty) {
      ToastHelper.show(context, 'Please enter a mobile number for testing', isError: true);
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final res = await ref.read(templateOperationsProvider).sendTestMessage(_selectedTemplate!.id, channel, mobile);
      
      if (channel.toUpperCase() == 'WHATSAPP' && res.containsKey('whatsapp_url')) {
        final url = res['whatsapp_url'] as String;
        launchUrlString(url);
        ToastHelper.show(context, 'WhatsApp sandbox link opened!');
      } else {
        ToastHelper.show(context, 'Test SMS successfully sent via MSG91!');
      }
    } catch (e) {
      ToastHelper.show(context, 'Test dispatch failed: ${ErrorParser.parse(e)}', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  String _renderMockPreview() {
    if (_selectedTemplate == null) return '';
    final shopSettings = ref.read(shopSettingsProvider).value;
    final shopName = shopSettings?.shopName ?? 'Shree Ganadhish Battery Services';
    final shopMobile = shopSettings?.shopMobile ?? '9730911213';

    var text = _bodyController.text;
    final mockContext = {
      'customer_name': 'Vedant Khaire',
      'mobile_number': '9730911213',
      'battery_model': 'AMARON-AAM-PR-00050',
      'battery_serial': 'AM20260601T',
      'battery_type': 'INVERTER',
      'expiry_date': '2028-06-01',
      'pending_amount': '1500',
      'period_label': '2026-06',
      'timestamp': '2026-06-01 12:00:00',
      'shop_name': shopName,
      'shop_mobile': shopMobile,
    };

    for (final entry in mockContext.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  Widget _buildTemplatesList(List<MessageTemplate> templates, bool isDark) {
    return ListView.builder(
      itemCount: templates.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final t = templates[index];
        final isSelected = _selectedTemplate?.id == t.id;
        
        IconData typeIcon = Icons.chat_bubble_outline;
        Color iconColor = Colors.blue;
        if (t.templateType.startsWith('SMS_')) {
          typeIcon = Icons.sms_outlined;
          iconColor = Colors.blue;
        } else if (t.templateType == 'EMAIL_BACKUP') {
          typeIcon = Icons.mail_outline;
          iconColor = Colors.orange;
        } else {
          typeIcon = Icons.chat_bubble_outlined;
          iconColor = Colors.green;
        }

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.08)
              : (isDark ? const Color(0xFF0F172A) : Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected
                  ? AppTheme.primaryColor
                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            leading: Icon(typeIcon, color: iconColor),
            title: Text(
              t.templateName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppTheme.primaryColor : (isDark ? Colors.white : AppTheme.secondaryColor),
              ),
            ),
            subtitle: Text(
              t.templateType,
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: t.isActive
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                t.isActive ? 'ACTIVE' : 'INACTIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: t.isActive ? Colors.green : Colors.red,
                ),
              ),
            ),
            onTap: () => _selectTemplate(t),
          ),
        );
      },
    );
  }

  Widget _buildEditorPanel(bool isDark) {
    if (_selectedTemplate == null) {
      return const Center(
        child: EmptyState(
          title: 'No Template Selected',
          message: 'Select a template from the left panel to edit, preview, restore history, or execute test dispatches.',
          icon: Icons.edit_note_outlined,
        ),
      );
    }

    final t = _selectedTemplate!;
    final variables = [
      'customer_name',
      'mobile_number',
      'battery_model',
      'battery_serial',
      'battery_type',
      'expiry_date',
      'pending_amount',
      'shop_name',
      'shop_mobile',
      if (t.templateType == 'EMAIL_BACKUP') ...['period_label', 'timestamp']
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section 1: Template Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.templateName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Type: ${t.templateType} • Version: ${t.versionNo}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              Switch(
                value: _isActive,
                activeColor: AppTheme.primaryColor,
                onChanged: _isSaving
                    ? null
                    : (val) {
                        setState(() {
                          _isActive = val;
                        });
                      },
              ),
            ],
          ),
          const Divider(height: 32),

          // Subject input (Only for subject-supporting templates)
          if (t.templateType == 'EMAIL_BACKUP') ...[
            AppInput(
              controller: _subjectController,
              labelText: 'Email Subject Template',
              prefixIcon: Icons.subject,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 20),
          ],

          // Body text field
          TextField(
            controller: _bodyController,
            maxLines: 6,
            enabled: !_isSaving,
            decoration: const InputDecoration(
              labelText: 'Message Body Template *',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Insert variable badges helper
          const Text(
            'Click variables to insert in template:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: variables.map((v) {
              return ActionChip(
                label: Text('{$v}'),
                padding: EdgeInsets.zero,
                labelStyle: const TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                backgroundColor: AppTheme.primaryColor.withOpacity(0.05),
                side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.15)),
                onPressed: _isSaving ? null : () => _insertVariable(v),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Split panel: Left: Mock Preview, Right: Test message panel
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mock Preview Bubble
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Mock Dispatch Preview',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (t.templateType == 'EMAIL_BACKUP') ...[
                            Text(
                              'Subject: ${_subjectController.text.replaceAll('{shop_name}', 'Shree Ganadhish').replaceAll('{period_label}', '2026-06')}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Divider(height: 16),
                          ],
                          Text(
                            _renderMockPreview(),
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),

              // Sandbox Test triggers
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sandbox Test Dispatch',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _testMobileController,
                      keyboardType: TextInputType.phone,
                      enabled: !_isSaving && !_isTesting,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Recipient Mobile',
                        prefixIcon: Icon(Icons.phone_iphone, size: 16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _isTesting || _isSaving ? null : () => _triggerTestMessage('WHATSAPP'),
                            icon: const Icon(Icons.share, size: 14),
                            label: const TextStyle(fontSize: 12).parentText('Test WA'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _isTesting || _isSaving ? null : () => _triggerTestMessage('SMS'),
                            icon: const Icon(Icons.sms_outlined, size: 14),
                            label: const TextStyle(fontSize: 12).parentText('Test SMS'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Version history logs
          const Text(
            'Template Revision History',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, child) {
              final versionsAsync = ref.watch(templateVersionsProvider(t.id));
              return versionsAsync.when(
                data: (versions) {
                  if (versions.isEmpty) {
                    return Text(
                      'No previous versions archived.',
                      style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF64748B) : Colors.grey, fontStyle: FontStyle.italic),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: versions.length,
                    itemBuilder: (context, idx) {
                      final v = versions[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Version ${v.versionNo}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  'Archived: ${v.createdAt.substring(0, 16).replaceAll("T", " ")}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.restore, size: 16),
                              label: const Text('Restore', style: TextStyle(fontSize: 12)),
                              onPressed: _isSaving ? null : () => _restoreVersion(v.versionNo),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(color: AppTheme.primaryColor),
                error: (err, stack) => Text('Error loading history: ${ErrorParser.parse(err)}'),
              );
            },
          ),
          const SizedBox(height: 24),
          
          // Factory Restore and Save Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.settings_backup_restore, color: Colors.orange),
                label: const Text('Restore Default', style: TextStyle(color: Colors.orange)),
                onPressed: _isSaving ? null : () => _restoreVersion(null),
              ),
              const SizedBox(width: 16),
              AppButton(
                label: 'Commit & Save Version',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _updateTemplate,
              ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildLogsTable(PaginatedMessageLogs logs, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Communications Dispatch Log Registry',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _logsPage > 1
                      ? () {
                          setState(() {
                            _logsPage--;
                          });
                          ref.read(messageLogFilterProvider.notifier).update(
                            (state) => state.copyWith(page: _logsPage),
                          );
                        }
                      : null,
                ),
                Text('Page $_logsPage of ${((logs.total - 1) / logs.limit).floor() + 1}'),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _logsPage < ((logs.total - 1) / logs.limit).floor() + 1
                      ? () {
                          setState(() {
                            _logsPage++;
                          });
                          ref.read(messageLogFilterProvider.notifier).update(
                            (state) => state.copyWith(page: _logsPage),
                          );
                        }
                      : null,
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200),
          ),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1.5),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.0),
              3: FlexColumnWidth(1.5),
              4: FlexColumnWidth(3.0),
              5: FlexColumnWidth(1.0),
            },
            children: [
              // Header Row
              TableRow(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                ),
                children: const [
                  Padding(padding: EdgeInsets.all(12.0), child: Text('Sent At', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12.0), child: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12.0), child: Text('Channel', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12.0), child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12.0), child: Text('Message Body', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12.0), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              // Logs Rows
              ...logs.data.map((log) {
                Color statusColor = Colors.green;
                if (log.status == 'FAILED') statusColor = Colors.red;
                else if (log.status.startsWith('TEST')) statusColor = Colors.purple;

                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                      child: Text(log.sentAt.substring(0, 16).replaceAll("T", " ")),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                      child: Text('${log.customerName}\n${log.mobileNumber}', style: const TextStyle(fontSize: 12)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: log.channel == 'WHATSAPP'
                              ? Colors.green.withOpacity(0.1)
                              : (log.channel == 'SMS' ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.channel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: log.channel == 'WHATSAPP'
                                ? Colors.green
                                : (log.channel == 'SMS' ? Colors.blue : Colors.orange),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                      child: Text(log.messageType, style: const TextStyle(fontSize: 11)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                      child: Text(
                        log.messageBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.status,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(messageTemplatesProvider);
    final logsAsync = ref.watch(messageLogsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication Console', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.message), text: 'Message Templates'),
            Tab(icon: Icon(Icons.history), text: 'Transmission Logs'),
          ],
        ),
      ),
      body: AppScaffold(
        title: 'Communications',
        child: TabBarView(
          controller: _tabController,
          children: [
            // Message Templates Tab (Split Screen)
            Row(
              children: [
                // Left Panel: List of templates
                Expanded(
                  flex: 4,
                  child: templatesAsync.when(
                    data: (templates) {
                      if (templates.isEmpty) {
                        return const Center(child: Text('No templates configured.'));
                      }
                      if (_selectedTemplate == null) {
                        // Prefill first template on load
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _selectTemplate(templates.first);
                        });
                      }
                      return _buildTemplatesList(templates, isDark);
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
                    error: (err, stack) => Center(child: Text('Failed to load templates: ${ErrorParser.parse(err)}')),
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                // Right Panel: Template Editor
                Expanded(
                  flex: 6,
                  child: _buildEditorPanel(isDark),
                ),
              ],
            ),

            // Logs Registry Tab
            logsAsync.when(
              data: (logs) {
                if (logs.data.isEmpty) {
                  return const Center(
                    child: EmptyState(
                      title: 'Communications Archive Empty',
                      message: 'Permanent records of all SMS notifications, email database backups, and manual WhatsApp redirects will be listed here.',
                      icon: Icons.history,
                    ),
                  );
                }
                return _buildLogsTable(logs, isDark);
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
              error: (err, stack) => Center(child: Text('Failed to load logs: ${ErrorParser.parse(err)}')),
            ),
          ],
        ),
      ),
    );
  }
}

extension _ParentText on TextStyle {
  Widget parentText(String val) => Text(val, style: this);
}
