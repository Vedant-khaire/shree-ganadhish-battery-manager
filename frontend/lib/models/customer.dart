import 'battery.dart';
import 'payment.dart';
import 'reminder.dart';

class Customer {
  final String id;
  final String name;
  final String mobile;
  final String? vehicleNo;
  final String? vehicleType;
  final String? area;
  final String? pincode;
  final String purchaseType; // 'RETAIL' or 'SHOP'
  final bool isArchived;
  final String createdAt;
  final String? updatedAt;
  final bool scrapBatteryPending;
  final String? scrapReceivedDate;
  final double scrapExpectedValue;
  final double scrapReceivedValue;

  Customer({
    required this.id,
    required this.name,
    required this.mobile,
    this.vehicleNo,
    this.vehicleType,
    this.area,
    this.pincode,
    required this.purchaseType,
    required this.isArchived,
    required this.createdAt,
    this.updatedAt,
    this.scrapBatteryPending = false,
    this.scrapReceivedDate,
    this.scrapExpectedValue = 0.0,
    this.scrapReceivedValue = 0.0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      name: json['name'] as String,
      mobile: json['mobile'] as String,
      vehicleNo: json['vehicle_no'] as String?,
      vehicleType: json['vehicle_type'] as String?,
      area: json['area'] as String?,
      pincode: json['pincode'] as String?,
      purchaseType: json['purchase_type'] as String? ?? 'RETAIL',
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String?,
      scrapBatteryPending: json['scrap_battery_pending'] as bool? ?? false,
      scrapReceivedDate: json['scrap_received_date'] as String?,
      scrapExpectedValue: (json['scrap_expected_value'] as num?)?.toDouble() ?? 0.0,
      scrapReceivedValue: (json['scrap_received_value'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Customer copyWith({
    String? id,
    String? name,
    String? mobile,
    String? vehicleNo,
    String? vehicleType,
    String? area,
    String? pincode,
    String? purchaseType,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
    bool? scrapBatteryPending,
    String? scrapReceivedDate,
    double? scrapExpectedValue,
    double? scrapReceivedValue,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      vehicleType: vehicleType ?? this.vehicleType,
      area: area ?? this.area,
      pincode: pincode ?? this.pincode,
      purchaseType: purchaseType ?? this.purchaseType,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scrapBatteryPending: scrapBatteryPending ?? this.scrapBatteryPending,
      scrapReceivedDate: scrapReceivedDate ?? this.scrapReceivedDate,
      scrapExpectedValue: scrapExpectedValue ?? this.scrapExpectedValue,
      scrapReceivedValue: scrapReceivedValue ?? this.scrapReceivedValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mobile': mobile,
      'vehicle_no': vehicleNo,
      'vehicle_type': vehicleType,
      'area': area,
      'pincode': pincode,
      'purchase_type': purchaseType,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'scrap_battery_pending': scrapBatteryPending,
      'scrap_received_date': scrapReceivedDate,
      'scrap_expected_value': scrapExpectedValue,
      'scrap_received_value': scrapReceivedValue,
    };
  }
}

class CustomerWithDetails {
  final Customer customer;
  final List<Battery> batteries;
  final List<Payment> payments;
  final List<Reminder> reminders;

  CustomerWithDetails({
    required this.customer,
    required this.batteries,
    required this.payments,
    required this.reminders,
  });

  factory CustomerWithDetails.fromJson(Map<String, dynamic> json) {
    final rawCustomer = json['customer'];
    final rawBatteries = json['batteries'] as List<dynamic>? ?? [];
    final rawPayments = json['payments'] as List<dynamic>? ?? [];
    final rawReminders = json['reminders'] as List<dynamic>? ?? [];

    return CustomerWithDetails(
      customer: rawCustomer is Map<String, dynamic>
          ? Customer.fromJson(rawCustomer)
          : Customer.fromJson(json), // Fallback if direct properties are at root
      batteries: rawBatteries
          .map((b) => Battery.fromJson(b as Map<String, dynamic>))
          .toList(),
      payments: rawPayments
          .map((p) => Payment.fromJson(p as Map<String, dynamic>))
          .toList(),
      reminders: rawReminders
          .map((r) => Reminder.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}
