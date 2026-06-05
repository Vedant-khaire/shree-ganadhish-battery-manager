import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/customer.dart';
import 'dashboard_provider.dart';
import 'reminder_provider.dart';
import 'payment_provider.dart';

// State holder for Customer List Search & Pagination
class CustomerListFilter {
  final String search;
  final int page;
  final int limit;
  final bool archived;
  final String filterType; // 'ALL', 'SCRAP_PENDING', 'ACTIVE_WARRANTIES', 'PENDING_UDHARI'

  CustomerListFilter({
    this.search = '',
    this.page = 1,
    this.limit = 20,
    this.archived = false,
    this.filterType = 'ALL',
  });

  CustomerListFilter copyWith({
    String? search,
    int? page,
    int? limit,
    bool? archived,
    String? filterType,
  }) {
    return CustomerListFilter(
      search: search ?? this.search,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      archived: archived ?? this.archived,
      filterType: filterType ?? this.filterType,
    );
  }
}

// Global provider for filters
final customerFilterProvider = StateProvider<CustomerListFilter>((ref) {
  return CustomerListFilter();
});

// Paginated Customer response holder
class PaginatedCustomers {
  final List<Customer> data;
  final int total;
  final int page;
  final int limit;

  PaginatedCustomers({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedCustomers.fromJson(Map<String, dynamic> json) {
    final list = json['data'] as List<dynamic>? ?? [];
    return PaginatedCustomers(
      data: list.map((c) => Customer.fromJson(c as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

// Paginated Customer List Notifier (re-fetches when customerFilterProvider changes)
class CustomerListNotifier extends AsyncNotifier<PaginatedCustomers> {
  @override
  Future<PaginatedCustomers> build() async {
    final filter = ref.watch(customerFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.dio.get(
      '/customers',
      queryParameters: {
        'search': filter.search,
        'page': filter.page,
        'limit': filter.limit,
        'archived': filter.archived,
        'filter_type': filter.filterType,
      },
    );

    return PaginatedCustomers.fromJson(response.data as Map<String, dynamic>);
  }

  // Update local cache state for optimistic UI
  void updateState(PaginatedCustomers updated) {
    state = AsyncValue.data(updated);
  }
}

final customerListProvider = AsyncNotifierProvider<CustomerListNotifier, PaginatedCustomers>(() {
  return CustomerListNotifier();
});

// Customer Details Notifier
class CustomerDetailsNotifier extends FamilyAsyncNotifier<CustomerWithDetails, String> {
  @override
  Future<CustomerWithDetails> build(String arg) async {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.dio.get('/customers/$arg/details');
    return CustomerWithDetails.fromJson(response.data as Map<String, dynamic>);
  }

  // Update local cache state for optimistic UI
  void updateState(CustomerWithDetails updated) {
    state = AsyncValue.data(updated);
  }
}

final customerDetailsProvider = AsyncNotifierProvider.family<CustomerDetailsNotifier, CustomerWithDetails, String>(() {
  return CustomerDetailsNotifier();
});

// Customer Operations Provider for write actions (create, edit, archive, restore)
final customerOperationsProvider = Provider((ref) => CustomerOperations(ref));

class CustomerOperations {
  final Ref _ref;
  CustomerOperations(this._ref);

  Future<Customer> createCustomer(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    final response = await apiClient.dio.post('/customers', data: data);
    
    // Refresh the list cache
    _ref.invalidate(customerListProvider);
    _ref.invalidate(scrapBatteriesProvider);
    
    return Customer.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<Customer> updateCustomer(String id, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    final response = await apiClient.dio.put('/customers/$id', data: data);
    
    // Refresh details, lists and dashboard
    _ref.invalidate(customerListProvider);
    _ref.invalidate(customerDetailsProvider(id));
    _ref.invalidate(scrapBatteriesProvider);
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(paymentListProvider);
    _ref.invalidate(reminderListProvider);
    
    return Customer.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> archiveCustomer(String id) async {
    final listState = _ref.read(customerListProvider);
    
    // Optimistic list update (remove customer from active directory)
    if (listState is AsyncData<PaginatedCustomers>) {
      final paginated = listState.value;
      final filteredList = paginated.data.where((c) => c.id != id).toList();
      _ref.read(customerListProvider.notifier).updateState(
        PaginatedCustomers(
          data: filteredList,
          total: paginated.total - (filteredList.length < paginated.data.length ? 1 : 0),
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }
    
    // Optimistic detail update (set isArchived = true)
    final detailState = _ref.read(customerDetailsProvider(id));
    if (detailState is AsyncData<CustomerWithDetails>) {
      final details = detailState.value;
      _ref.read(customerDetailsProvider(id).notifier).updateState(
        CustomerWithDetails(
          customer: details.customer.copyWith(isArchived: true),
          batteries: details.batteries,
          payments: details.payments,
          reminders: details.reminders,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/customers/$id/archive');
      
      // Invalidate to fetch exact sync in background
      _ref.invalidate(customerListProvider);
      _ref.invalidate(customerDetailsProvider(id));
      _ref.invalidate(scrapBatteriesProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      // Revert optimistic state on failure
      _ref.invalidate(customerListProvider);
      _ref.invalidate(customerDetailsProvider(id));
      _ref.invalidate(scrapBatteriesProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> restoreCustomer(String id) async {
    final listState = _ref.read(customerListProvider);
    
    // Optimistic list update (remove customer from archived directory)
    if (listState is AsyncData<PaginatedCustomers>) {
      final paginated = listState.value;
      final filteredList = paginated.data.where((c) => c.id != id).toList();
      _ref.read(customerListProvider.notifier).updateState(
        PaginatedCustomers(
          data: filteredList,
          total: paginated.total - (filteredList.length < paginated.data.length ? 1 : 0),
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }
    
    // Optimistic detail update (set isArchived = false)
    final detailState = _ref.read(customerDetailsProvider(id));
    if (detailState is AsyncData<CustomerWithDetails>) {
      final details = detailState.value;
      _ref.read(customerDetailsProvider(id).notifier).updateState(
        CustomerWithDetails(
          customer: details.customer.copyWith(isArchived: false),
          batteries: details.batteries,
          payments: details.payments,
          reminders: details.reminders,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/customers/$id/restore');
      
      _ref.invalidate(customerListProvider);
      _ref.invalidate(customerDetailsProvider(id));
      _ref.invalidate(scrapBatteriesProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(customerListProvider);
      _ref.invalidate(customerDetailsProvider(id));
      _ref.invalidate(scrapBatteriesProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> createCombinedCustomer(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/customers/combined', data: data);
    
    // Invalidate list cache and dashboard statistics
    _ref.invalidate(customerListProvider);
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(reminderListProvider);
    _ref.invalidate(reminderStatsProvider);
    _ref.invalidate(paymentListProvider);
    _ref.invalidate(scrapBatteriesProvider);
  }

  Future<void> deleteCustomer(String id) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.delete('/customers/$id');
      
      _ref.invalidate(customerListProvider);
      _ref.invalidate(dashboardProvider);
      _ref.invalidate(paymentListProvider);
      _ref.invalidate(scrapBatteriesProvider);
    } catch (e) {
      rethrow;
    }
  }
}

// Scrap battery specific filter and list providers
class ScrapFilter {
  final String search;
  final int page;
  final int limit;

  ScrapFilter({this.search = '', this.page = 1, this.limit = 20});

  ScrapFilter copyWith({String? search, int? page, int? limit}) {
    return ScrapFilter(
      search: search ?? this.search,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}

final scrapFilterProvider = StateProvider<ScrapFilter>((ref) => ScrapFilter());

final scrapBatteriesProvider = AsyncNotifierProvider<ScrapBatteriesNotifier, PaginatedCustomers>(() {
  return ScrapBatteriesNotifier();
});

class ScrapBatteriesNotifier extends AsyncNotifier<PaginatedCustomers> {
  @override
  Future<PaginatedCustomers> build() async {
    final filter = ref.watch(scrapFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.dio.get(
      '/customers',
      queryParameters: {
        'search': filter.search,
        'page': filter.page,
        'limit': filter.limit,
        'filter_type': 'SCRAP_PENDING',
      },
    );
    return PaginatedCustomers.fromJson(response.data as Map<String, dynamic>);
  }

  void updateState(PaginatedCustomers updated) {
    state = AsyncValue.data(updated);
  }
}
