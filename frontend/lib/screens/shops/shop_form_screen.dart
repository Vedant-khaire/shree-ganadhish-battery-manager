import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../providers/shop_provider.dart';
import '../../models/shop.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../core/theme.dart';

class ShopFormScreen extends ConsumerStatefulWidget {
  final String? shopId;

  const ShopFormScreen({
    super.key,
    this.shopId,
  });

  @override
  ConsumerState<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends ConsumerState<ShopFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _initialUdhariController = TextEditingController();

  bool _isPrefilled = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isEdit => widget.shopId != null;

  @override
  void dispose() {
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _initialUdhariController.dispose();
    super.dispose();
  }

  void _prefillForm(ShopDetails details) {
    if (_isPrefilled) return;
    final shop = details.shop;
    _shopNameController.text = shop.shopName;
    _ownerNameController.text = shop.ownerName;
    _mobileController.text = shop.mobile;
    _addressController.text = shop.address ?? '';
    _isPrefilled = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final Map<String, dynamic> payload = {
      'shop_name': _shopNameController.text.trim(),
      'owner_name': _ownerNameController.text.trim(),
      'mobile': _mobileController.text.trim(),
      'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
    };

    if (!isEdit) {
      final udhariStr = _initialUdhariController.text.trim();
      if (udhariStr.isNotEmpty) {
        final double? initialUdhari = double.tryParse(udhariStr);
        if (initialUdhari != null && initialUdhari > 0) {
          payload['initial_udhari'] = initialUdhari;
        }
      }
    }

    try {
      final ops = ref.read(shopOperationsProvider);
      if (isEdit) {
        await ops.updateShop(widget.shopId!, payload);
      } else {
        await ops.createShop(payload);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Shop profile updated successfully' : 'Shop registered successfully'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/shops');
      }
    } on DioException catch (e) {
      final responseData = e.response?.data;
      String detail = '';
      if (responseData is Map && responseData.containsKey('detail')) {
        detail = responseData['detail'].toString();
      }

      if (detail.startsWith('SHOP_MOBILE_EXISTS:') || detail.startsWith('SHOP_NAME_EXISTS:')) {
        final parts = detail.split(':');
        final existingId = parts[1];
        final existingName = parts[2];
        final isMobile = detail.startsWith('SHOP_MOBILE_EXISTS:');

        if (mounted) {
          _showDuplicateDialog(existingId, existingName, isMobile);
        }
      } else {
        setState(() {
          _errorMessage = detail.isNotEmpty ? detail : 'An error occurred. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showDuplicateDialog(String id, String name, bool isMobile) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Text(isMobile ? 'Mobile Already Exists' : 'Shop Name Already Exists'),
          ],
        ),
        content: Text(
          isMobile
              ? 'A shop named "$name" is already registered with this mobile number. Do you want to open its profile?'
              : 'A shop named "$name" already exists. Do you want to view its profile instead of creating a duplicate?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/shops/$id');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Profile'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isEdit) {
      final detailsAsync = ref.watch(shopDetailsProvider(widget.shopId!));
      return detailsAsync.when(
        data: (details) {
          _prefillForm(details);
          return _buildContent();
        },
        loading: () => const AppScaffold(
          title: 'Loading...',
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, stack) => AppScaffold(
          title: 'Error',
          child: Center(child: Text('Error loading shop profile: $err')),
        ),
      );
    }

    return _buildContent();
  }

  Widget _buildContent() {
    final screenTitle = isEdit ? 'Edit Shop Profile' : 'Register Shop / Retailer';

    return AppScaffold(
      title: screenTitle,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/shops'),
                ),
                const SizedBox(width: 8),
                Text(
                  screenTitle,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Form container
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade900),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          Text(
                            'Shop Profile Details',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                          ),
                          const SizedBox(height: 20),

                          AppInput(
                            controller: _shopNameController,
                            labelText: 'Shop Name *',
                            hintText: 'Enter full business name',
                            prefixIcon: Icons.store_rounded,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Shop name is required' : null,
                          ),
                          const SizedBox(height: 20),

                          AppInput(
                            controller: _ownerNameController,
                            labelText: 'Owner Name *',
                            hintText: 'Enter shop owner name',
                            prefixIcon: Icons.person_rounded,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Owner name is required' : null,
                          ),
                          const SizedBox(height: 20),

                          AppInput(
                            controller: _mobileController,
                            labelText: 'Mobile Number *',
                            hintText: 'Enter 10-digit mobile number',
                            prefixIcon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                            maxLength: 15,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Mobile number is required';
                              }
                              if (v.trim().length < 10) {
                                return 'Please enter a valid mobile number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          AppInput(
                            controller: _addressController,
                            labelText: 'Address (Optional)',
                            hintText: 'Enter shop address details',
                            prefixIcon: Icons.location_on_rounded,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),

                          if (!isEdit) ...[
                            AppInput(
                              controller: _initialUdhariController,
                              labelText: 'Old Udhaari / Opening Balance (Optional)',
                              hintText: 'Enter initial outstanding balance, if any',
                              prefixIcon: Icons.currency_rupee_rounded,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final val = double.tryParse(v.trim());
                                  if (val == null || val < 0) {
                                    return 'Please enter a valid positive amount';
                                  }
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: _isSubmitting ? null : () => context.go('/shops'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                ),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 16),
                              AppButton(
                                label: isEdit ? 'Save Updates' : 'Register Shop',
                                isLoading: _isSubmitting,
                                icon: isEdit ? Icons.save_rounded : Icons.check_circle_rounded,
                                onPressed: _submit,
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
          ],
        ),
      ),
    );
  }
}
