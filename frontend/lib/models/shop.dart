class Shop {
  final String id;
  final String shopName;
  final String ownerName;
  final String mobile;
  final String? address;
  final bool isArchived;
  final String createdAt;
  final String? updatedAt;
  final int totalPurchases;
  final double pendingUdhari;

  Shop({
    required this.id,
    required this.shopName,
    required this.ownerName,
    required this.mobile,
    this.address,
    required this.isArchived,
    required this.createdAt,
    this.updatedAt,
    this.totalPurchases = 0,
    this.pendingUdhari = 0.0,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] as String,
      shopName: json['shop_name'] as String,
      ownerName: json['owner_name'] as String,
      mobile: json['mobile'] as String,
      address: json['address'] as String?,
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String?,
      totalPurchases: json['total_purchases'] as int? ?? 0,
      pendingUdhari: (json['pending_udhari'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_name': shopName,
      'owner_name': ownerName,
      'mobile': mobile,
      'address': address,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'total_purchases': totalPurchases,
      'pending_udhari': pendingUdhari,
    };
  }
}

class ShopPurchase {
  final String id;
  final String shopId;
  final String batteryModel;
  final String serialNumber;
  final String invoiceNumber;
  final int quantity;
  final String purchaseDate;
  final double amount;
  final double udhariAmount;
  final String createdAt;
  final String? paymentMode;

  ShopPurchase({
    required this.id,
    required this.shopId,
    required this.batteryModel,
    required this.serialNumber,
    required this.invoiceNumber,
    required this.quantity,
    required this.purchaseDate,
    required this.amount,
    required this.udhariAmount,
    required this.createdAt,
    this.paymentMode,
  });

  factory ShopPurchase.fromJson(Map<String, dynamic> json) {
    return ShopPurchase(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      batteryModel: json['battery_model'] as String,
      serialNumber: json['serial_number'] as String,
      invoiceNumber: json['invoice_number'] as String,
      quantity: json['quantity'] as int? ?? 1,
      purchaseDate: json['purchase_date'] as String,
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      udhariAmount: (json['udhari_amount'] as num? ?? 0.0).toDouble(),
      createdAt: json['created_at'] as String,
      paymentMode: json['payment_mode'] as String?,
    );
  }
}

class ShopPayment {
  final String id;
  final String shopId;
  final double totalAmount;
  final double paidAmount;
  final double pendingAmount;
  final bool isSettled;
  final String createdAt;

  ShopPayment({
    required this.id,
    required this.shopId,
    required this.totalAmount,
    required this.paidAmount,
    required this.pendingAmount,
    required this.isSettled,
    required this.createdAt,
  });

  factory ShopPayment.fromJson(Map<String, dynamic> json) {
    return ShopPayment(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      totalAmount: (json['total_amount'] as num? ?? 0.0).toDouble(),
      paidAmount: (json['paid_amount'] as num? ?? 0.0).toDouble(),
      pendingAmount: (json['pending_amount'] as num? ?? 0.0).toDouble(),
      isSettled: json['is_settled'] as bool? ?? false,
      createdAt: json['created_at'] as String,
    );
  }
}

class ShopPaymentTransaction {
  final String id;
  final String paymentId;
  final String shopId;
  final String transactionType;
  final double amount;
  final String? notes;
  final String createdAt;
  final String? paymentMode;

  ShopPaymentTransaction({
    required this.id,
    required this.paymentId,
    required this.shopId,
    required this.transactionType,
    required this.amount,
    this.notes,
    required this.createdAt,
    this.paymentMode,
  });

  factory ShopPaymentTransaction.fromJson(Map<String, dynamic> json) {
    return ShopPaymentTransaction(
      id: json['id'] as String,
      paymentId: json['payment_id'] as String,
      shopId: json['shop_id'] as String,
      transactionType: json['transaction_type'] as String,
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String,
      paymentMode: json['payment_mode'] as String?,
    );
  }
}

class ShopDetails {
  final Shop shop;
  final List<ShopPurchase> purchases;
  final ShopPayment? payment;
  final List<ShopPaymentTransaction> transactions;

  ShopDetails({
    required this.shop,
    required this.purchases,
    this.payment,
    required this.transactions,
  });

  factory ShopDetails.fromJson(Map<String, dynamic> json) {
    return ShopDetails(
      shop: Shop.fromJson(json['shop'] as Map<String, dynamic>),
      purchases: (json['purchases'] as List<dynamic>?)
              ?.map((e) => ShopPurchase.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      payment: json['payment'] != null
          ? ShopPayment.fromJson(json['payment'] as Map<String, dynamic>)
          : null,
      transactions: (json['transactions'] as List<dynamic>?)
              ?.map((e) => ShopPaymentTransaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
