import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import 'customer_provider.dart';
import '../models/customer.dart';
import 'dashboard_provider.dart';
import 'reminder_provider.dart';

// Provider for Battery Operations
final batteryOperationsProvider = Provider((ref) => BatteryOperations(ref));

class BatteryOperations {
  final Ref _ref;
  BatteryOperations(this._ref);

  void _invalidateAll() {
    _ref.invalidate(reminderListProvider);
    _ref.invalidate(reminderStatsProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> createBattery(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/batteries', data: data);
    
    // Invalidate details for the associated customer so the details screen refreshes
    final customerId = data['customer_id'] as String?;
    if (customerId != null) {
      _ref.invalidate(customerDetailsProvider(customerId));
    }
    _invalidateAll();
  }

  Future<void> updateBattery(String id, String customerId, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.put('/batteries/$id', data: data);
    _ref.invalidate(customerDetailsProvider(customerId));
    _invalidateAll();
  }

  Future<void> archiveBattery(String id, String customerId) async {
    // Optimistic details list update (remove battery from detail list immediately)
    final detailState = _ref.read(customerDetailsProvider(customerId));
    if (detailState is AsyncData<CustomerWithDetails>) {
      final details = detailState.value;
      final filteredBatteries = details.batteries.where((b) => b.id != id).toList();
      _ref.read(customerDetailsProvider(customerId).notifier).updateState(
        CustomerWithDetails(
          customer: details.customer,
          batteries: filteredBatteries,
          payments: details.payments,
          reminders: details.reminders,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/batteries/$id/archive');
      
      _ref.invalidate(customerDetailsProvider(customerId));
      _invalidateAll();
    } catch (e) {
      _ref.invalidate(customerDetailsProvider(customerId));
      _invalidateAll();
      rethrow;
    }
  }

  Future<void> deleteBattery(String id, String customerId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.delete('/batteries/$id');
      _ref.invalidate(customerDetailsProvider(customerId));
      _invalidateAll();
    } catch (e) {
      rethrow;
    }
  }
}
