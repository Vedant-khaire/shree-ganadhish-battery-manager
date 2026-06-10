import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/shop.dart';
import '../models/stock.dart';
import 'dashboard_provider.dart';
import 'stock_provider.dart';
import 'payment_provider.dart';

// Provider to fetch active stock items for purchases selections
final activeStockModelsProvider = FutureProvider.autoDispose<List<Stock>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get('/stock', queryParameters: {'limit': 100, 'archived': false});
  final paginated = PaginatedStock.fromJson(response.data as Map<String, dynamic>);
  return paginated.data;
});

// State holder for Shop List filters
class ShopListFilter {
  final int page;
  final int limit;
  final String search;
  final String filterType; // ALL, ARCHIVED, PENDING_UDHARI, NO_PENDING_UDHARI

  ShopListFilter({
    this.page = 1,
    this.limit = 20,
    this.search = '',
    this.filterType = 'ALL',
  });

  ShopListFilter copyWith({
    int? page,
    int? limit,
    String? search,
    String? filterType,
  }) {
    return ShopListFilter(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      search: search ?? this.search,
      filterType: filterType ?? this.filterType,
    );
  }
}

// Global provider for shop filters
final shopFilterProvider = StateProvider<ShopListFilter>((ref) {
  return ShopListFilter();
});

// Paginated response wrapper for Shops
class PaginatedShops {
  final List<Shop> data;
  final int total;
  final int page;
  final int limit;

  PaginatedShops({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedShops.fromJson(Map<String, dynamic> json) {
    final list = json['data'] as List<dynamic>? ?? [];
    return PaginatedShops(
      data: list.map((p) => Shop.fromJson(p as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

// Shop list notifier
class ShopListNotifier extends AsyncNotifier<PaginatedShops> {
  @override
  Future<PaginatedShops> build() async {
    final filter = ref.watch(shopFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.dio.get(
      '/shops',
      queryParameters: {
        'page': filter.page,
        'limit': filter.limit,
        'filter_type': filter.filterType,
        if (filter.search.isNotEmpty) 'search': filter.search,
      },
    );

    return PaginatedShops.fromJson(response.data as Map<String, dynamic>);
  }

  void updateState(PaginatedShops updated) {
    state = AsyncValue.data(updated);
  }
}

final shopListProvider = AsyncNotifierProvider<ShopListNotifier, PaginatedShops>(() {
  return ShopListNotifier();
});

// Shop details future provider
final shopDetailsProvider = FutureProvider.autoDispose.family<ShopDetails, String>((ref, id) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get('/shops/$id/details');
  return ShopDetails.fromJson(response.data as Map<String, dynamic>);
});

// Shop operations notifier
final shopOperationsProvider = Provider((ref) => ShopOperations(ref));

class ShopOperations {
  final Ref _ref;
  ShopOperations(this._ref);

  Future<Shop> createShop(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    final response = await apiClient.dio.post('/shops', data: data);
    
    // Invalidate dashboard and shop list
    _ref.invalidate(shopListProvider);
    _ref.invalidate(dashboardProvider);

    return Shop.fromJson((response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  }

  Future<void> updateShop(String id, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.put('/shops/$id', data: data);
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(id));
    _ref.invalidate(dashboardProvider);
  }

  Future<void> archiveShop(String id) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.patch('/shops/$id/archive');
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(id));
    _ref.invalidate(dashboardProvider);
  }

  Future<void> restoreShop(String id) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.patch('/shops/$id/restore');
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(id));
    _ref.invalidate(dashboardProvider);
  }

  Future<void> deleteShop(String id) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.delete('/shops/$id');
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> logShopPurchase(String id, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/shops/$id/purchases', data: data);
    
    // Invalidate everything since inventory stock, shop details, list, and dashboard stats have changed
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(id));
    _ref.invalidate(dashboardProvider);
    // Invalidate stock listing
    _ref.invalidate(stockListProvider);
    // Invalidate payment lists
    _ref.invalidate(paymentListProvider);
  }

  Future<void> settleShopPayment(String id, double amount, String? notes, String paymentMode) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post(
      '/shops/$id/settle',
      queryParameters: {
        'amount': amount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'payment_mode': paymentMode,
      },
    );
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(id));
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(paymentListProvider);
  }

  Future<void> deleteShopPurchase(String shopId, String purchaseId) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.delete('/shops/$shopId/purchases/$purchaseId');
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(shopId));
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(stockListProvider);
    _ref.invalidate(paymentListProvider);
  }

  Future<void> addShopOpeningBalance(String shopId, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/shops/$shopId/opening-balance', data: data);
    
    _ref.invalidate(shopListProvider);
    _ref.invalidate(shopDetailsProvider(shopId));
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(stockListProvider);
    _ref.invalidate(paymentListProvider);
  }
}
