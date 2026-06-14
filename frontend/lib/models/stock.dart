class Stock {
  final String id;
  final String modelName;
  final String batteryType; // '2W', '4W', 'TRUCK', 'INVERTER'
  final int quantity;
  final int lowStockThreshold;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  Stock({
    required this.id,
    required this.modelName,
    required this.batteryType,
    required this.quantity,
    required this.lowStockThreshold,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: json['id'] as String,
      modelName: json['model_name'] as String,
      batteryType: json['battery_type'] as String,
      quantity: json['quantity'] as int? ?? 0,
      lowStockThreshold: json['low_stock_threshold'] as int? ?? 2,
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Stock copyWith({
    String? id,
    String? modelName,
    String? batteryType,
    int? quantity,
    int? lowStockThreshold,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return Stock(
      id: id ?? this.id,
      modelName: modelName ?? this.modelName,
      batteryType: batteryType ?? this.batteryType,
      quantity: quantity ?? this.quantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'model_name': modelName,
      'battery_type': batteryType,
      'quantity': quantity,
      'low_stock_threshold': lowStockThreshold,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class BatteryUnit {
  final String id;
  final String modelName;
  final String batteryType;
  final String serialNumber;
  final String status;
  final String? purchaseDate;
  final String? shopSource;
  final String? shopPurchaseId;
  final String? customerBatteryId;
  final String createdAt;
  final String updatedAt;

  BatteryUnit({
    required this.id,
    required this.modelName,
    required this.batteryType,
    required this.serialNumber,
    required this.status,
    this.purchaseDate,
    this.shopSource,
    this.shopPurchaseId,
    this.customerBatteryId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BatteryUnit.fromJson(Map<String, dynamic> json) {
    return BatteryUnit(
      id: json['id'] as String,
      modelName: json['model_name'] as String,
      batteryType: json['battery_type'] as String,
      serialNumber: json['serial_number'] as String,
      status: json['status'] as String,
      purchaseDate: json['purchase_date'] as String?,
      shopSource: json['shop_source'] as String?,
      shopPurchaseId: json['shop_purchase_id'] as String?,
      customerBatteryId: json['customer_battery_id'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}
