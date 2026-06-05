import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/message_template_provider.dart';
import '../models/message_template.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/toast_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../core/theme.dart';
import '../core/utils.dart';

class ShopSettingsScreen extends ConsumerStatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  ConsumerState<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _AppCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E293B)
              : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(24),
        child: child,
      ),
    );
  }
}

class _ShopSettingsScreenState extends ConsumerState<ShopSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _mobileController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _gstController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _backupEmailController = TextEditingController();
  final _smsSenderController = TextEditingController();

  bool _isInitialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _logoUrlController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _mobileController.dispose();
    _whatsappController.dispose();
    _gstController.dispose();
    _logoUrlController.dispose();
    _backupEmailController.dispose();
    _smsSenderController.dispose();
    super.dispose();
  }

  void _initFields(ShopSettings settings) {
    if (_isInitialized) return;
    _nameController.text = settings.shopName;
    _addressController.text = settings.shopAddress;
    _mobileController.text = settings.shopMobile;
    _whatsappController.text = settings.whatsappNumber;
    _gstController.text = settings.gstNumber ?? '';
    _logoUrlController.text = settings.logoUrl ?? '';
    _backupEmailController.text = settings.backupEmail;
    _smsSenderController.text = settings.smsSenderName;
    _isInitialized = true;
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final payload = {
      'shop_name': _nameController.text.trim(),
      'shop_address': _addressController.text.trim(),
      'shop_mobile': _mobileController.text.trim(),
      'whatsapp_number': _whatsappController.text.trim(),
      'gst_number': _gstController.text.trim().isEmpty ? null : _gstController.text.trim(),
      'logo_url': _logoUrlController.text.trim().isEmpty ? null : _logoUrlController.text.trim(),
      'backup_email': _backupEmailController.text.trim(),
      'sms_sender_name': _smsSenderController.text.trim().toUpperCase(),
    };

    try {
      await ref.read(shopSettingsProvider.notifier).updateSettings(payload);
      if (mounted) {
        ToastHelper.show(context, 'Shop Settings updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.show(context, 'Failed to update settings: ${ErrorParser.parse(e)}', isError: true);
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
    final settingsAsync = ref.watch(shopSettingsProvider);

    return Scaffold(
      body: AppScaffold(
        title: 'Shop Settings',
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: settingsAsync.when(
                data: (settings) {
                  _initFields(settings);
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  
                  return Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Shop Brand & Profile Headers
                        _AppCard(
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                                backgroundImage: _logoUrlController.text.isNotEmpty
                                    ? NetworkImage(_logoUrlController.text)
                                    : null,
                                child: _logoUrlController.text.isEmpty
                                    ? const Icon(Icons.storefront, size: 36, color: AppTheme.primaryColor)
                                    : null,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      settings.shopName,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppTheme.secondaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Configure business details, GST invoicing, backups, and messaging defaults.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Section 1: Business Profile
                        Text(
                          'Business Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFCBD5E1) : AppTheme.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppInput(
                                controller: _nameController,
                                labelText: 'Shop Name *',
                                prefixIcon: Icons.store,
                                enabled: !_isSaving,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Shop name is required';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              AppInput(
                                controller: _addressController,
                                labelText: 'Shop Address *',
                                prefixIcon: Icons.location_on_outlined,
                                enabled: !_isSaving,
                                maxLines: 2,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Shop address is required';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppInput(
                                      controller: _gstController,
                                      labelText: 'GST Number (Optional)',
                                      prefixIcon: Icons.receipt_outlined,
                                      enabled: !_isSaving,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: AppInput(
                                      controller: _logoUrlController,
                                      labelText: 'Logo Image URL',
                                      prefixIcon: Icons.image_outlined,
                                      enabled: !_isSaving,
                                      hintText: 'https://...',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Section 2: Contact Details & Channels
                        Text(
                          'Contact Channels',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFCBD5E1) : AppTheme.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: AppInput(
                                  controller: _mobileController,
                                  labelText: 'Shop Mobile *',
                                  prefixIcon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                  enabled: !_isSaving,
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Mobile is required';
                                    if (val.trim().replaceAll(RegExp(r'\D'), '').length < 10) return 'Invalid phone number';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: AppInput(
                                  controller: _whatsappController,
                                  labelText: 'WhatsApp Number *',
                                  prefixIcon: Icons.chat_bubble_outline,
                                  keyboardType: TextInputType.phone,
                                  enabled: !_isSaving,
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'WhatsApp number is required';
                                    if (val.trim().replaceAll(RegExp(r'\D'), '').length < 10) return 'Invalid WhatsApp number';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Section 3: Backup & Provider settings
                        Text(
                          'System Integrations & Backups',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFCBD5E1) : AppTheme.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: AppInput(
                                  controller: _backupEmailController,
                                  labelText: 'Backup Receiver Email *',
                                  prefixIcon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  enabled: !_isSaving,
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Backup email is required';
                                    if (!val.contains('@') || !val.contains('.')) return 'Invalid email address';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: AppInput(
                                  controller: _smsSenderController,
                                  labelText: 'SMS Sender Name (DLT Header) *',
                                  prefixIcon: Icons.sms_outlined,
                                  enabled: !_isSaving,
                                  hintText: '6-letter Sender ID',
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Sender ID is required';
                                    if (val.trim().length != 6) return 'Must be exactly 6 letters';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Action Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 16),
                            AppButton(
                              label: 'Save Configuration',
                              isLoading: _isSaving,
                              onPressed: _isSaving ? null : _saveSettings,
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
                ),
                error: (err, stack) => SizedBox(
                  height: 300,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Failed to load settings: ${ErrorParser.parse(err)}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(shopSettingsProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
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
