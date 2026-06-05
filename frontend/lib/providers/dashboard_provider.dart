import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';

class TopSellingModel {
  final String modelName;
  final String batteryType;
  final int salesCount;

  TopSellingModel({required this.modelName, required this.batteryType, required this.salesCount});

  factory TopSellingModel.fromJson(Map<String, dynamic> json) {
    return TopSellingModel(
      modelName: json['model_name'] as String? ?? 'N/A',
      batteryType: json['battery_type'] as String? ?? 'N/A',
      salesCount: json['sales_count'] as int? ?? 0,
    );
  }
}

class MostPendingCustomer {
  final String customerName;
  final String mobileNumber;
  final double pendingAmount;

  MostPendingCustomer({required this.customerName, required this.mobileNumber, required this.pendingAmount});

  factory MostPendingCustomer.fromJson(Map<String, dynamic> json) {
    return MostPendingCustomer(
      customerName: json['customer_name'] as String? ?? 'N/A',
      mobileNumber: json['mobile_number'] as String? ?? 'N/A',
      pendingAmount: (json['pending_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MostActiveArea {
  final String area;
  final int customerCount;

  MostActiveArea({required this.area, required this.customerCount});

  factory MostActiveArea.fromJson(Map<String, dynamic> json) {
    return MostActiveArea(
      area: json['area'] as String? ?? 'N/A',
      customerCount: json['customer_count'] as int? ?? 0,
    );
  }
}

class OutOfStockModel {
  final String modelName;
  final String batteryType;

  OutOfStockModel({required this.modelName, required this.batteryType});

  factory OutOfStockModel.fromJson(Map<String, dynamic> json) {
    return OutOfStockModel(
      modelName: json['model_name'] as String? ?? 'N/A',
      batteryType: json['battery_type'] as String? ?? 'N/A',
    );
  }
}

class TrendDataPoint {
  final String month;
  final double value;

  TrendDataPoint({required this.month, required this.value});

  factory TrendDataPoint.fromJson(Map<String, dynamic> json) {
    return TrendDataPoint(
      month: json['month'] as String? ?? 'N/A',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RecentActivity {
  final String action;
  final String createdAt;

  RecentActivity({required this.action, required this.createdAt});

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      action: json['action'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class ScrapSummary {
  final int pendingCount;
  final double pendingValue;
  final double collectedValue;

  ScrapSummary({
    required this.pendingCount,
    required this.pendingValue,
    required this.collectedValue,
  });

  factory ScrapSummary.fromJson(Map<String, dynamic> json) {
    return ScrapSummary(
      pendingCount: json['pending_count'] as int? ?? 0,
      pendingValue: (json['pending_value'] as num?)?.toDouble() ?? 0.0,
      collectedValue: (json['collected_value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TopPurchasingShop {
  final String shopId;
  final String shopName;
  final double totalAmount;

  TopPurchasingShop({required this.shopId, required this.shopName, required this.totalAmount});

  factory TopPurchasingShop.fromJson(Map<String, dynamic> json) {
    return TopPurchasingShop(
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? 'N/A',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TopPendingShop {
  final String shopId;
  final String shopName;
  final double pendingAmount;

  TopPendingShop({required this.shopId, required this.shopName, required this.pendingAmount});

  factory TopPendingShop.fromJson(Map<String, dynamic> json) {
    return TopPendingShop(
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? 'N/A',
      pendingAmount: (json['pending_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ShopsSummary {
  final int totalShops;
  final double totalShopUdhari;
  final double highestOutstandingShopBalance;
  final double totalShopPurchasesValue;
  final int pendingUdhariShopsCount;
  final List<TopPurchasingShop> topPurchasingShops;
  final List<TopPendingShop> topPendingShops;

  ShopsSummary({
    required this.totalShops,
    required this.totalShopUdhari,
    required this.highestOutstandingShopBalance,
    required this.totalShopPurchasesValue,
    required this.pendingUdhariShopsCount,
    required this.topPurchasingShops,
    required this.topPendingShops,
  });

  factory ShopsSummary.fromJson(Map<String, dynamic> json) {
    final purchaseList = json['top_purchasing_shops'] as List<dynamic>? ?? [];
    final pendingList = json['top_pending_shops'] as List<dynamic>? ?? [];
    return ShopsSummary(
      totalShops: json['total_shops'] as int? ?? 0,
      totalShopUdhari: (json['total_shop_udhari'] as num?)?.toDouble() ?? 0.0,
      highestOutstandingShopBalance: (json['highest_outstanding_shop_balance'] as num?)?.toDouble() ?? 0.0,
      totalShopPurchasesValue: (json['total_shop_purchases_value'] as num?)?.toDouble() ?? 0.0,
      pendingUdhariShopsCount: json['pending_udhari_shops_count'] as int? ?? 0,
      topPurchasingShops: purchaseList.map((e) => TopPurchasingShop.fromJson(e as Map<String, dynamic>)).toList(),
      topPendingShops: pendingList.map((e) => TopPendingShop.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class DashboardStats {
  final String period;
  final double todayTotalSalesAmount;
  final double todayTotalCollection;
  final double todayTotalPending;

  // Customers
  final int customersAddedToday;
  final int customersAddedThisWeek;
  final int customersAddedThisMonth;
  final int customersTotalActive;

  // Sales
  final int salesSoldToday;
  final int salesSoldThisWeek;
  final int salesSoldThisMonth;
  final double salesTotalRevenue;
  final double salesTotalPendingUdhari;
  final double salesTotalSettledAmount;
  final String salesMostSoldModel;

  // Inventory
  final int inventoryTotalStockUnits;
  final int inventoryTotalStockModels;
  final int inventoryLowStockCount;
  final int inventoryOutOfStockCount;
  final List<OutOfStockModel> inventoryOutOfStockModels;

  // Warranty
  final int warrantyActive;
  final int warrantyExpiringSoon30Days;
  final int warrantyExpiredNoFollowup;

  // Payments
  final double paymentsTodayCollections;
  final int paymentsPendingCount;
  final int paymentsSettledCount;
  final int totalPendingUdhariCustomers;
  final double weeklyRecoveryDue;
  final double overdueCollections;
  final double collectionEfficiencyPct;

  // Lists
  final List<TopSellingModel> topSellingModels;
  final List<MostPendingCustomer> mostPendingCustomers;
  final List<MostActiveArea> mostActiveAreas;

  // Trends
  final List<TrendDataPoint> monthlySalesTrend;
  final List<TrendDataPoint> customerGrowthTrend;
  final List<TrendDataPoint> paymentCollectionTrend;

  // Smart Business Stats
  final double avgPaymentRecoveryDays;
  final double salesGrowthPct;
  final int repeatCustomersCount;
  final int upcomingServiceRemindersCount;

  // Live Activity Feed
  final List<RecentActivity> recentActivities;

  // Reminders Summary
  final int remindersDueToday;
  final int remindersOverdue;
  final int remindersUpcomingWarrantyExpiry;
  final int remindersPendingUdhariRecovery;
  final int remindersWaterChecksDue;
  final int remindersServiceDue;

  // Scrap Batteries Summary
  final ScrapSummary scrapSummary;

  // Shops Summary
  final ShopsSummary shopsSummary;

  DashboardStats({
    required this.period,
    required this.todayTotalSalesAmount,
    required this.todayTotalCollection,
    required this.todayTotalPending,
    required this.customersAddedToday,
    required this.customersAddedThisWeek,
    required this.customersAddedThisMonth,
    required this.customersTotalActive,
    required this.salesSoldToday,
    required this.salesSoldThisWeek,
    required this.salesSoldThisMonth,
    required this.salesTotalRevenue,
    required this.salesTotalPendingUdhari,
    required this.salesTotalSettledAmount,
    required this.salesMostSoldModel,
    required this.inventoryTotalStockUnits,
    required this.inventoryTotalStockModels,
    required this.inventoryLowStockCount,
    required this.inventoryOutOfStockCount,
    required this.inventoryOutOfStockModels,
    required this.warrantyActive,
    required this.warrantyExpiringSoon30Days,
    required this.warrantyExpiredNoFollowup,
    required this.paymentsTodayCollections,
    required this.paymentsPendingCount,
    required this.paymentsSettledCount,
    required this.totalPendingUdhariCustomers,
    required this.weeklyRecoveryDue,
    required this.overdueCollections,
    required this.collectionEfficiencyPct,
    required this.topSellingModels,
    required this.mostPendingCustomers,
    required this.mostActiveAreas,
    required this.monthlySalesTrend,
    required this.customerGrowthTrend,
    required this.paymentCollectionTrend,
    required this.avgPaymentRecoveryDays,
    required this.salesGrowthPct,
    required this.repeatCustomersCount,
    required this.upcomingServiceRemindersCount,
    required this.recentActivities,
    required this.remindersDueToday,
    required this.remindersOverdue,
    required this.remindersUpcomingWarrantyExpiry,
    required this.remindersPendingUdhariRecovery,
    required this.remindersWaterChecksDue,
    required this.remindersServiceDue,
    required this.scrapSummary,
    required this.shopsSummary,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final cust = json['customers'] as Map<String, dynamic>? ?? {};
    final sales = json['sales'] as Map<String, dynamic>? ?? {};
    final inv = json['inventory'] as Map<String, dynamic>? ?? {};
    final warr = json['warranty'] as Map<String, dynamic>? ?? {};
    final pay = json['payments'] as Map<String, dynamic>? ?? {};
    final trends = json['trends'] as Map<String, dynamic>? ?? {};
    final smart = json['smart_business_stats'] as Map<String, dynamic>? ?? {};
    final rem = json['reminders_summary'] as Map<String, dynamic>? ?? {};
    final scrap = json['scrap_summary'] as Map<String, dynamic>? ?? {};
    final shops = json['shops'] as Map<String, dynamic>? ?? {};

    final outOfStockList = inv['out_of_stock_models'] as List<dynamic>? ?? [];
    final topSellingList = json['top_selling_models'] as List<dynamic>? ?? [];
    final mostPendingList = json['most_pending_customers'] as List<dynamic>? ?? [];
    final activeAreasList = json['most_active_areas'] as List<dynamic>? ?? [];

    final salesTrendList = trends['monthly_sales_trend'] as List<dynamic>? ?? [];
    final growthTrendList = trends['customer_growth_trend'] as List<dynamic>? ?? [];
    final collectTrendList = trends['payment_collection_trend'] as List<dynamic>? ?? [];
    final activityList = json['recent_activities'] as List<dynamic>? ?? [];

    return DashboardStats(
      period: json['period'] as String? ?? 'this_month',
      todayTotalSalesAmount: (json['today_total_sales_amount'] as num?)?.toDouble() ?? 0.0,
      todayTotalCollection: (json['today_total_collection'] as num?)?.toDouble() ?? 0.0,
      todayTotalPending: (json['today_total_pending'] as num?)?.toDouble() ?? 0.0,

      customersAddedToday: cust['added_today'] as int? ?? 0,
      customersAddedThisWeek: cust['added_this_week'] as int? ?? 0,
      customersAddedThisMonth: cust['added_this_month'] as int? ?? 0,
      customersTotalActive: cust['total_active'] as int? ?? 0,

      salesSoldToday: sales['sold_today'] as int? ?? 0,
      salesSoldThisWeek: sales['sold_this_week'] as int? ?? 0,
      salesSoldThisMonth: sales['sold_this_month'] as int? ?? 0,
      salesTotalRevenue: (sales['total_revenue'] as num?)?.toDouble() ?? 0.0,
      salesTotalPendingUdhari: (sales['total_pending_udhari'] as num?)?.toDouble() ?? 0.0,
      salesTotalSettledAmount: (sales['total_settled_amount'] as num?)?.toDouble() ?? 0.0,
      salesMostSoldModel: sales['most_sold_model'] as String? ?? 'N/A',

      inventoryTotalStockUnits: inv['total_stock_units'] as int? ?? 0,
      inventoryTotalStockModels: inv['total_stock_models'] as int? ?? 0,
      inventoryLowStockCount: inv['low_stock_count'] as int? ?? 0,
      inventoryOutOfStockCount: inv['out_of_stock_count'] as int? ?? 0,
      inventoryOutOfStockModels: outOfStockList.map((e) => OutOfStockModel.fromJson(e as Map<String, dynamic>)).toList(),

      warrantyActive: warr['active'] as int? ?? 0,
      warrantyExpiringSoon30Days: warr['expiring_soon_30_days'] as int? ?? 0,
      warrantyExpiredNoFollowup: warr['expired_no_followup'] as int? ?? 0,

      paymentsTodayCollections: (pay['today_collections'] as num?)?.toDouble() ?? 0.0,
      paymentsPendingCount: pay['pending_count'] as int? ?? 0,
      paymentsSettledCount: pay['settled_count'] as int? ?? 0,
      totalPendingUdhariCustomers: pay['total_pending_udhari_customers'] as int? ?? 0,
      weeklyRecoveryDue: (pay['weekly_recovery_due'] as num?)?.toDouble() ?? 0.0,
      overdueCollections: (pay['overdue_collections'] as num?)?.toDouble() ?? 0.0,
      collectionEfficiencyPct: (pay['collection_efficiency_pct'] as num?)?.toDouble() ?? 0.0,

      topSellingModels: topSellingList.map((e) => TopSellingModel.fromJson(e as Map<String, dynamic>)).toList(),
      mostPendingCustomers: mostPendingList.map((e) => MostPendingCustomer.fromJson(e as Map<String, dynamic>)).toList(),
      mostActiveAreas: activeAreasList.map((e) => MostActiveArea.fromJson(e as Map<String, dynamic>)).toList(),

      monthlySalesTrend: salesTrendList.map((e) => TrendDataPoint.fromJson(e as Map<String, dynamic>)).toList(),
      customerGrowthTrend: growthTrendList.map((e) => TrendDataPoint.fromJson(e as Map<String, dynamic>)).toList(),
      paymentCollectionTrend: collectTrendList.map((e) => TrendDataPoint.fromJson(e as Map<String, dynamic>)).toList(),

      avgPaymentRecoveryDays: (smart['avg_payment_recovery_days'] as num?)?.toDouble() ?? 0.0,
      salesGrowthPct: (smart['sales_growth_pct'] as num?)?.toDouble() ?? 0.0,
      repeatCustomersCount: smart['repeat_customers_count'] as int? ?? 0,
      upcomingServiceRemindersCount: smart['upcoming_service_reminders_count'] as int? ?? 0,
      recentActivities: activityList.map((e) => RecentActivity.fromJson(e as Map<String, dynamic>)).toList(),
      remindersDueToday: rem['due_today'] as int? ?? 0,
      remindersOverdue: rem['overdue'] as int? ?? 0,
      remindersUpcomingWarrantyExpiry: rem['upcoming_warranty_expiry'] as int? ?? 0,
      remindersPendingUdhariRecovery: rem['pending_udhari_recovery'] as int? ?? 0,
      remindersWaterChecksDue: rem['water_checks_due'] as int? ?? 0,
      remindersServiceDue: rem['service_due'] as int? ?? 0,
      scrapSummary: ScrapSummary.fromJson(scrap),
      shopsSummary: ShopsSummary.fromJson(shops),
    );
  }
}

class DashboardFilters {
  final String period;
  final String? vehicleType;
  final String? purchaseType;

  DashboardFilters({
    this.period = 'this_month',
    this.vehicleType,
    this.purchaseType,
  });

  DashboardFilters copyWith({
    String? period,
    String? Function()? vehicleType,
    String? Function()? purchaseType,
  }) {
    return DashboardFilters(
      period: period ?? this.period,
      vehicleType: vehicleType != null ? vehicleType() : this.vehicleType,
      purchaseType: purchaseType != null ? purchaseType() : this.purchaseType,
    );
  }
}

final dashboardFiltersProvider = StateProvider<DashboardFilters>((ref) {
  return DashboardFilters();
});

class DashboardNotifier extends AutoDisposeAsyncNotifier<DashboardStats> {
  @override
  Future<DashboardStats> build() async {
    final filters = ref.watch(dashboardFiltersProvider);
    return _fetchStats(filters);
  }

  Future<DashboardStats> _fetchStats(DashboardFilters filters) async {
    final apiClient = ref.read(apiClientProvider);
    final queryParams = <String, dynamic>{
      'period': filters.period,
    };
    if (filters.vehicleType != null) {
      queryParams['vehicle_type'] = filters.vehicleType;
    }
    if (filters.purchaseType != null) {
      queryParams['purchase_type'] = filters.purchaseType;
    }

    final response = await apiClient.dio.get('/dashboard/stats', queryParameters: queryParams);
    return DashboardStats.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    final filters = ref.read(dashboardFiltersProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchStats(filters));
  }
}

final dashboardProvider = AsyncNotifierProvider.autoDispose<DashboardNotifier, DashboardStats>(() {
  return DashboardNotifier();
});
