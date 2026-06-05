import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import 'customer_provider.dart';
import 'dashboard_provider.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import 'reminder_provider.dart';

// State holder for Payment List Filters (Udhari Directory)
class PaymentListFilter {
  final String customerId;
  final bool? isSettled;
  final int page;
  final int limit;
  final bool archived;
  final String search;

  PaymentListFilter({
    this.customerId = '',
    this.isSettled = false, // default: show pending udharis
    this.page = 1,
    this.limit = 20,
    this.archived = false,
    this.search = '',
  });

  PaymentListFilter copyWith({
    String? customerId,
    bool? isSettled,
    int? page,
    int? limit,
    bool? archived,
    String? search,
  }) {
    return PaymentListFilter(
      customerId: customerId ?? this.customerId,
      isSettled: isSettled ?? this.isSettled,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      archived: archived ?? this.archived,
      search: search ?? this.search,
    );
  }
}

// Global provider for payment filters
final paymentFilterProvider = StateProvider<PaymentListFilter>((ref) {
  return PaymentListFilter();
});

// Paginated Payments Response
class PaginatedPayments {
  final List<Payment> data;
  final int total;
  final int page;
  final int limit;

  PaginatedPayments({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedPayments.fromJson(Map<String, dynamic> json) {
    final list = json['data'] as List<dynamic>? ?? [];
    return PaginatedPayments(
      data: list.map((p) => Payment.fromJson(p as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

// Payment list AsyncNotifier (re-fetches when paymentFilterProvider changes)
class PaymentListNotifier extends AsyncNotifier<PaginatedPayments> {
  @override
  Future<PaginatedPayments> build() async {
    final filter = ref.watch(paymentFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final Map<String, dynamic> params = {
      'page': filter.page,
      'limit': filter.limit,
      'archived': filter.archived,
      if (filter.search.isNotEmpty) 'search': filter.search,
    };
    if (filter.customerId.isNotEmpty) {
      params['customer_id'] = filter.customerId;
    }
    if (filter.isSettled != null) {
      params['is_settled'] = filter.isSettled;
    }

    final response = await apiClient.dio.get(
      '/payments',
      queryParameters: params,
    );

    return PaginatedPayments.fromJson(response.data as Map<String, dynamic>);
  }

  void updateState(PaginatedPayments updated) {
    state = AsyncValue.data(updated);
  }
}

final paymentListProvider = AsyncNotifierProvider<PaymentListNotifier, PaginatedPayments>(() {
  return PaymentListNotifier();
});

// Provider for Payment Operations
final paymentOperationsProvider = Provider((ref) => PaymentOperations(ref));

class PaymentOperations {
  final Ref _ref;
  PaymentOperations(this._ref);

  Future<void> createPayment(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/payments', data: data);
    
    // Invalidate details, list, reminders and dashboard stats
    final customerId = data['customer_id'] as String?;
    if (customerId != null) {
      _ref.invalidate(customerDetailsProvider(customerId));
    }
    _ref.invalidate(paymentListProvider);
    _ref.invalidate(reminderListProvider);
    _ref.invalidate(reminderStatsProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> settlePayment(String id, String customerId) async {
    // 1. Optimistic details cache update
    final detailState = _ref.read(customerDetailsProvider(customerId));
    if (detailState is AsyncData<CustomerWithDetails>) {
      final details = detailState.value;
      final updatedPayments = details.payments.map((p) {
        if (p.id == id) {
          return p.copyWith(
            isSettled: true,
            paidAmount: p.totalAmount,
            pendingAmount: 0.0,
          );
        }
        return p;
      }).toList();
      
      _ref.read(customerDetailsProvider(customerId).notifier).updateState(
        CustomerWithDetails(
          customer: details.customer,
          batteries: details.batteries,
          payments: updatedPayments,
          reminders: details.reminders,
        ),
      );
    }

    // 2. Optimistic list cache update
    final listState = _ref.read(paymentListProvider);
    if (listState is AsyncData<PaginatedPayments>) {
      final paginated = listState.value;
      final updatedList = paginated.data.map((p) {
        if (p.id == id) {
          return p.copyWith(
            isSettled: true,
            paidAmount: p.totalAmount,
            pendingAmount: 0.0,
          );
        }
        return p;
      }).toList();
      _ref.read(paymentListProvider.notifier).updateState(
        PaginatedPayments(
          data: updatedList,
          total: paginated.total,
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/payments/$id/settle');
      
      // Invalidate to fetch exact sync in background
      _ref.invalidate(customerDetailsProvider(customerId));
      _ref.invalidate(paymentListProvider);
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      // Revert on failure
      _ref.invalidate(customerDetailsProvider(customerId));
      _ref.invalidate(paymentListProvider);
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> archivePayment(String id, String customerId) async {
    // 1. Optimistic details list update
    final detailState = _ref.read(customerDetailsProvider(customerId));
    if (detailState is AsyncData<CustomerWithDetails>) {
      final details = detailState.value;
      final filteredPayments = details.payments.where((p) => p.id != id).toList();
      _ref.read(customerDetailsProvider(customerId).notifier).updateState(
        CustomerWithDetails(
          customer: details.customer,
          batteries: details.batteries,
          payments: filteredPayments,
          reminders: details.reminders,
        ),
      );
    }

    // 2. Optimistic list cache update
    final listState = _ref.read(paymentListProvider);
    if (listState is AsyncData<PaginatedPayments>) {
      final paginated = listState.value;
      final filteredList = paginated.data.where((p) => p.id != id).toList();
      _ref.read(paymentListProvider.notifier).updateState(
        PaginatedPayments(
          data: filteredList,
          total: paginated.total - (filteredList.length < paginated.data.length ? 1 : 0),
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/payments/$id/archive');
      
      _ref.invalidate(customerDetailsProvider(customerId));
      _ref.invalidate(paymentListProvider);
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(customerDetailsProvider(customerId));
      _ref.invalidate(paymentListProvider);
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> deletePayment(String id, String customerId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.delete('/payments/$id');
      _ref.invalidate(customerDetailsProvider(customerId));
      _ref.invalidate(paymentListProvider);
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      rethrow;
    }
  }
}

// FutureProvider for fetching Udhari Transactions
final paymentTransactionsProvider = FutureProvider.family<List<PaymentTransaction>, String>((ref, paymentId) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get('/payments/$paymentId/transactions');
  final list = response.data as List<dynamic>? ?? [];
  return list.map((t) => PaymentTransaction.fromJson(t as Map<String, dynamic>)).toList();
});
