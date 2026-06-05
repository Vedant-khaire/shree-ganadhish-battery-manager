import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/stock.dart';
import 'dashboard_provider.dart';

// State holder for Stock List Search & Pagination
class StockListFilter {
  final String search;
  final int page;
  final int limit;
  final bool archived;
  final bool lowStock;

  StockListFilter({
    this.search = '',
    this.page = 1,
    this.limit = 20,
    this.archived = false,
    this.lowStock = false,
  });

  StockListFilter copyWith({
    String? search,
    int? page,
    int? limit,
    bool? archived,
    bool? lowStock,
  }) {
    return StockListFilter(
      search: search ?? this.search,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      archived: archived ?? this.archived,
      lowStock: lowStock ?? this.lowStock,
    );
  }
}

// Global provider for filters
final stockFilterProvider = StateProvider<StockListFilter>((ref) {
  return StockListFilter();
});

// Paginated Stock response holder
class PaginatedStock {
  final List<Stock> data;
  final int total;
  final int page;
  final int limit;

  PaginatedStock({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedStock.fromJson(Map<String, dynamic> json) {
    final list = json['data'] as List<dynamic>? ?? [];
    return PaginatedStock(
      data: list.map((c) => Stock.fromJson(c as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

// Paginated Stock List Notifier (re-fetches when stockFilterProvider changes)
class StockListNotifier extends AsyncNotifier<PaginatedStock> {
  @override
  Future<PaginatedStock> build() async {
    final filter = ref.watch(stockFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.dio.get(
      '/stock',
      queryParameters: {
        'search': filter.search,
        'page': filter.page,
        'limit': filter.limit,
        'archived': filter.archived,
        'low_stock': filter.lowStock,
      },
    );

    return PaginatedStock.fromJson(response.data as Map<String, dynamic>);
  }

  // Update local cache state for optimistic UI
  void updateState(PaginatedStock updated) {
    state = AsyncValue.data(updated);
  }
}

final stockListProvider = AsyncNotifierProvider<StockListNotifier, PaginatedStock>(() {
  return StockListNotifier();
});

// Single Stock Item Notifier
final stockDetailsProvider = FutureProvider.family<Stock, String>((ref, stockId) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get('/stock/$stockId');
  return Stock.fromJson(response.data as Map<String, dynamic>);
});

// Stock Operations Provider for write actions (create, edit, archive, restore, increase, decrease)
final stockOperationsProvider = Provider((ref) => StockOperations(ref));

class StockOperations {
  final Ref _ref;
  StockOperations(this._ref);

  Future<Stock> createStock(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    // API returns 210 for create stock
    final response = await apiClient.dio.post('/stock', data: data);
    
    // Refresh the list cache and dashboard stats
    _ref.invalidate(stockListProvider);
    _ref.invalidate(dashboardProvider);
    
    return Stock.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<Stock> updateStock(String id, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    final response = await apiClient.dio.put('/stock/$id', data: data);
    
    // Refresh list, details and dashboard caches
    _ref.invalidate(stockListProvider);
    _ref.invalidate(stockDetailsProvider(id));
    _ref.invalidate(dashboardProvider);
    
    return Stock.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> archiveStock(String id) async {
    final listState = _ref.read(stockListProvider);
    
    // Optimistic list update (remove stock item from active list)
    if (listState is AsyncData<PaginatedStock>) {
      final paginated = listState.value;
      final filteredList = paginated.data.where((s) => s.id != id).toList();
      _ref.read(stockListProvider.notifier).updateState(
        PaginatedStock(
          data: filteredList,
          total: paginated.total - (filteredList.length < paginated.data.length ? 1 : 0),
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }
    
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/stock/$id/archive');
      
      _ref.invalidate(stockListProvider);
      _ref.invalidate(stockDetailsProvider(id));
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(stockListProvider);
      rethrow;
    }
  }

  Future<void> restoreStock(String id) async {
    final listState = _ref.read(stockListProvider);
    
    // Optimistic list update (remove stock item from archived list)
    if (listState is AsyncData<PaginatedStock>) {
      final paginated = listState.value;
      final filteredList = paginated.data.where((s) => s.id != id).toList();
      _ref.read(stockListProvider.notifier).updateState(
        PaginatedStock(
          data: filteredList,
          total: paginated.total - (filteredList.length < paginated.data.length ? 1 : 0),
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.patch('/stock/$id/restore');
      
      _ref.invalidate(stockListProvider);
      _ref.invalidate(stockDetailsProvider(id));
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(stockListProvider);
      rethrow;
    }
  }

  /// Adjust quantity of a stock item with optimistic updates and rollback safety
  Future<void> adjustQuantity(String id, int amount, bool increase) async {
    final listState = _ref.read(stockListProvider);
    if (listState is AsyncData<PaginatedStock>) {
      final paginated = listState.value;
      final index = paginated.data.indexWhere((s) => s.id == id);
      if (index != -1) {
        final currentStock = paginated.data[index];
        final newQuantity = increase 
            ? currentStock.quantity + amount 
            : currentStock.quantity - amount;
        
        if (newQuantity < 0) {
          throw Exception("Quantity cannot be negative");
        }

        // Optimistically update the UI state
        final updatedData = List<Stock>.from(paginated.data);
        updatedData[index] = currentStock.copyWith(quantity: newQuantity);
        
        _ref.read(stockListProvider.notifier).updateState(
          PaginatedStock(
            data: updatedData,
            total: paginated.total,
            page: paginated.page,
            limit: paginated.limit,
          ),
        );

        try {
          final apiClient = _ref.read(apiClientProvider);
          final path = increase ? 'increase' : 'decrease';
          await apiClient.dio.patch('/stock/$id/$path', data: {'quantity': amount});
          
          // Invalidate to make sure we are fully in sync and refresh dashboard statistics
          _ref.invalidate(stockListProvider);
          _ref.invalidate(dashboardProvider);
        } catch (e) {
          // Rollback: restore the previous paginated state
          _ref.read(stockListProvider.notifier).updateState(paginated);
          rethrow;
        }
      }
    }
  }

  Future<void> deleteStock(String id) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.delete('/stock/$id');
      _ref.invalidate(stockListProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      rethrow;
    }
  }
}
