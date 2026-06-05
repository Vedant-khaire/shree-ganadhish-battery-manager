class Reminder {
  final String id;
  final String? customerId;
  final String? batteryId;
  final String customerName;
  final String mobileNumber;
  final String? batteryModel;
  final String? batterySerial;
  final String? batteryType;
  final String reminderType; // 'WATER_CHECK', 'SERVICE', 'WARRANTY_EXPIRY'
  final String reminderDate;
  final String? warrantyExpiry;
  final String reminderStatus; // 'UPCOMING', 'DUE', 'OVERDUE', 'COMPLETED', 'EXPIRED'
  final bool messageSent;
  final String? sentAt;
  final bool isCompleted;
  final bool isArchived;
  final String? notes;
  final String? whatsappTemplate;
  final String whatsappDeliveryStatus;
  final String? whatsappMessageId;
  final String createdAt;
  final String? updatedAt;
  final String? reminderCategory;
  final String? linkedPaymentId;
  final int recurringIntervalDays;
  final bool stopWhenSettled;

  Reminder({
    required this.id,
    this.customerId,
    this.batteryId,
    required this.customerName,
    required this.mobileNumber,
    this.batteryModel,
    this.batterySerial,
    this.batteryType,
    required this.reminderType,
    required this.reminderDate,
    this.warrantyExpiry,
    required this.reminderStatus,
    required this.messageSent,
    this.sentAt,
    required this.isCompleted,
    required this.isArchived,
    this.notes,
    this.whatsappTemplate,
    required this.whatsappDeliveryStatus,
    this.whatsappMessageId,
    required this.createdAt,
    this.updatedAt,
    this.reminderCategory = 'BATTERY',
    this.linkedPaymentId,
    this.recurringIntervalDays = 7,
    this.stopWhenSettled = true,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      customerId: json['customer_id'] as String?,
      batteryId: json['battery_id'] as String?,
      customerName: json['customer_name'] as String? ?? '',
      mobileNumber: json['mobile_number'] as String? ?? '',
      batteryModel: json['battery_model'] as String?,
      batterySerial: json['battery_serial'] as String?,
      batteryType: json['battery_type'] as String?,
      reminderType: json['reminder_type'] as String? ?? '',
      reminderDate: json['reminder_date'] as String? ?? '',
      warrantyExpiry: json['warranty_expiry'] as String?,
      reminderStatus: json['reminder_status'] as String? ?? 'UPCOMING',
      messageSent: json['message_sent'] as bool? ?? false,
      sentAt: json['sent_at'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? false,
      notes: json['notes'] as String?,
      whatsappTemplate: json['whatsapp_template'] as String?,
      whatsappDeliveryStatus: json['whatsapp_delivery_status'] as String? ?? 'PENDING',
      whatsappMessageId: json['whatsapp_message_id'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String?,
      reminderCategory: json['reminder_category'] as String? ?? 'BATTERY',
      linkedPaymentId: json['linked_payment_id'] as String?,
      recurringIntervalDays: json['recurring_interval_days'] as int? ?? 7,
      stopWhenSettled: json['stop_when_settled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'battery_id': batteryId,
      'customer_name': customerName,
      'mobile_number': mobileNumber,
      'battery_model': batteryModel,
      'battery_serial': batterySerial,
      'battery_type': batteryType,
      'reminder_type': reminderType,
      'reminder_date': reminderDate,
      'warranty_expiry': warrantyExpiry,
      'reminder_status': reminderStatus,
      'message_sent': messageSent,
      'sent_at': sentAt,
      'is_completed': isCompleted,
      'is_archived': isArchived,
      'notes': notes,
      'whatsapp_template': whatsappTemplate,
      'whatsapp_delivery_status': whatsappDeliveryStatus,
      'whatsapp_message_id': whatsappMessageId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'reminder_category': reminderCategory,
      'linked_payment_id': linkedPaymentId,
      'recurring_interval_days': recurringIntervalDays,
      'stop_when_settled': stopWhenSettled,
    };
  }

  Reminder copyWith({
    String? id,
    String? customerId,
    String? batteryId,
    String? customerName,
    String? mobileNumber,
    String? batteryModel,
    String? batterySerial,
    String? batteryType,
    String? reminderType,
    String? reminderDate,
    String? warrantyExpiry,
    String? reminderStatus,
    bool? messageSent,
    String? sentAt,
    bool? isCompleted,
    bool? isArchived,
    String? notes,
    String? whatsappTemplate,
    String? whatsappDeliveryStatus,
    String? whatsappMessageId,
    String? createdAt,
    String? updatedAt,
    String? reminderCategory,
    String? linkedPaymentId,
    int? recurringIntervalDays,
    bool? stopWhenSettled,
  }) {
    return Reminder(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      batteryId: batteryId ?? this.batteryId,
      customerName: customerName ?? this.customerName,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      batteryModel: batteryModel ?? this.batteryModel,
      batterySerial: batterySerial ?? this.batterySerial,
      batteryType: batteryType ?? this.batteryType,
      reminderType: reminderType ?? this.reminderType,
      reminderDate: reminderDate ?? this.reminderDate,
      warrantyExpiry: warrantyExpiry ?? this.warrantyExpiry,
      reminderStatus: reminderStatus ?? this.reminderStatus,
      messageSent: messageSent ?? this.messageSent,
      sentAt: sentAt ?? this.sentAt,
      isCompleted: isCompleted ?? this.isCompleted,
      isArchived: isArchived ?? this.isArchived,
      notes: notes ?? this.notes,
      whatsappTemplate: whatsappTemplate ?? this.whatsappTemplate,
      whatsappDeliveryStatus: whatsappDeliveryStatus ?? this.whatsappDeliveryStatus,
      whatsappMessageId: whatsappMessageId ?? this.whatsappMessageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderCategory: reminderCategory ?? this.reminderCategory,
      linkedPaymentId: linkedPaymentId ?? this.linkedPaymentId,
      recurringIntervalDays: recurringIntervalDays ?? this.recurringIntervalDays,
      stopWhenSettled: stopWhenSettled ?? this.stopWhenSettled,
    );
  }
}

class ReminderStats {
  final int todayFollowups;
  final int overdueCount;
  final int upcomingExpiry;
  final int waterChecksDue;
  final int pendingService;
  final int completed;

  ReminderStats({
    required this.todayFollowups,
    required this.overdueCount,
    required this.upcomingExpiry,
    required this.waterChecksDue,
    required this.pendingService,
    required this.completed,
  });

  factory ReminderStats.fromJson(Map<String, dynamic> json) {
    return ReminderStats(
      todayFollowups: json['today_followups'] as int? ?? 0,
      overdueCount: json['overdue_count'] as int? ?? 0,
      upcomingExpiry: json['upcoming_expiry'] as int? ?? 0,
      waterChecksDue: json['water_checks_due'] as int? ?? 0,
      pendingService: json['pending_service'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
    );
  }
}
