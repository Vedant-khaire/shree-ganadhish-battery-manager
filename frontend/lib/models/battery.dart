class Battery {
  final String id;
  final String customerId;
  final String batteryType; // '2W', '4W', 'TRUCK', 'INVERTER'
  final String? modelNumber;
  final String? serialNumber;
  final String saleDate; // YYYY-MM-DD
  final int warrantyMonths;
  final String warrantyExpiry; // YYYY-MM-DD
  final String warrantyReminderDate; // YYYY-MM-DD
  final String? invoiceImageUrl;
  final String? notes;
  final bool isArchived;
  final String createdAt;
  final String? updatedAt;
  final int? serviceReminderIntervalMonths;
  final int? waterCheckIntervalMonths;

  Battery({
    required this.id,
    required this.customerId,
    required this.batteryType,
    this.modelNumber,
    this.serialNumber,
    required this.saleDate,
    required this.warrantyMonths,
    required this.warrantyExpiry,
    required this.warrantyReminderDate,
    this.invoiceImageUrl,
    this.notes,
    required this.isArchived,
    required this.createdAt,
    this.updatedAt,
    this.serviceReminderIntervalMonths,
    this.waterCheckIntervalMonths,
  });

  factory Battery.fromJson(Map<String, dynamic> json) {
    return Battery(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      batteryType: json['battery_type'] as String,
      modelNumber: json['model_number'] as String?,
      serialNumber: json['serial_number'] as String?,
      saleDate: json['sale_date'] as String,
      warrantyMonths: json['warranty_months'] as int,
      warrantyExpiry: json['warranty_expiry'] as String,
      warrantyReminderDate: json['warranty_reminder_date'] as String,
      invoiceImageUrl: json['invoice_image_url'] as String?,
      notes: json['notes'] as String?,
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String?,
      serviceReminderIntervalMonths: json['service_reminder_interval_months'] as int?,
      waterCheckIntervalMonths: json['water_check_interval_months'] as int?,
    );
  }

  Battery copyWith({
    String? id,
    String? customerId,
    String? batteryType,
    String? modelNumber,
    String? serialNumber,
    String? saleDate,
    int? warrantyMonths,
    String? warrantyExpiry,
    String? warrantyReminderDate,
    String? invoiceImageUrl,
    String? notes,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
    int? serviceReminderIntervalMonths,
    int? waterCheckIntervalMonths,
  }) {
    return Battery(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      batteryType: batteryType ?? this.batteryType,
      modelNumber: modelNumber ?? this.modelNumber,
      serialNumber: serialNumber ?? this.serialNumber,
      saleDate: saleDate ?? this.saleDate,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      warrantyExpiry: warrantyExpiry ?? this.warrantyExpiry,
      warrantyReminderDate: warrantyReminderDate ?? this.warrantyReminderDate,
      invoiceImageUrl: invoiceImageUrl ?? this.invoiceImageUrl,
      notes: notes ?? this.notes,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      serviceReminderIntervalMonths: serviceReminderIntervalMonths ?? this.serviceReminderIntervalMonths,
      waterCheckIntervalMonths: waterCheckIntervalMonths ?? this.waterCheckIntervalMonths,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'battery_type': batteryType,
      'model_number': modelNumber,
      'serial_number': serialNumber,
      'sale_date': saleDate,
      'warranty_months': warrantyMonths,
      'warranty_expiry': warrantyExpiry,
      'warranty_reminder_date': warrantyReminderDate,
      'invoice_image_url': invoiceImageUrl,
      'notes': notes,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'service_reminder_interval_months': serviceReminderIntervalMonths,
      'water_check_interval_months': waterCheckIntervalMonths,
    };
  }
}
