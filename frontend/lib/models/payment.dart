class Payment {
  final String id;
  final String customerId;
  final String? batteryId;
  final double totalAmount;
  final double paidAmount;
  final double pendingAmount;
  final String? reminderNote;
  final bool isSettled;
  final bool isArchived;
  final String createdAt;
  final String? updatedAt;
  final String? customerName;
  final String? customerMobile;

  Payment({
    required this.id,
    required this.customerId,
    this.batteryId,
    required this.totalAmount,
    required this.paidAmount,
    required this.pendingAmount,
    this.reminderNote,
    required this.isSettled,
    required this.isArchived,
    required this.createdAt,
    this.updatedAt,
    this.customerName,
    this.customerMobile,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      batteryId: json['battery_id'] as String?,
      totalAmount: (json['total_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num).toDouble(),
      pendingAmount: (json['pending_amount'] as num).toDouble(),
      reminderNote: json['reminder_note'] as String?,
      isSettled: json['is_settled'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String?,
      customerName: json['customer_name'] as String?,
      customerMobile: json['customer_mobile'] as String?,
    );
  }

  Payment copyWith({
    String? id,
    String? customerId,
    String? batteryId,
    double? totalAmount,
    double? paidAmount,
    double? pendingAmount,
    String? reminderNote,
    bool? isSettled,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
    String? customerName,
    String? customerMobile,
  }) {
    return Payment(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      batteryId: batteryId ?? this.batteryId,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      reminderNote: reminderNote ?? this.reminderNote,
      isSettled: isSettled ?? this.isSettled,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customerName: customerName ?? this.customerName,
      customerMobile: customerMobile ?? this.customerMobile,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'battery_id': batteryId,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'pending_amount': pendingAmount,
      'reminder_note': reminderNote,
      'is_settled': isSettled,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'customer_name': customerName,
      'customer_mobile': customerMobile,
    };
  }
}

class PaymentTransaction {
  final String id;
  final String paymentId;
  final String customerId;
  final String transactionType; // 'ADDITION' or 'PAYMENT'
  final double amount;
  final String? notes;
  final String createdAt;

  PaymentTransaction({
    required this.id,
    required this.paymentId,
    required this.customerId,
    required this.transactionType,
    required this.amount,
    this.notes,
    required this.createdAt,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id'] as String,
      paymentId: json['payment_id'] as String,
      customerId: json['customer_id'] as String,
      transactionType: json['transaction_type'] as String,
      amount: (json['amount'] as num).toDouble(),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
