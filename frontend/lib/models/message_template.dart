class MessageTemplate {
  final String id;
  final String templateName;
  final String templateType;
  final String? messageSubject;
  final String messageBody;
  final bool isActive;
  final int versionNo;
  final String createdAt;
  final String updatedAt;

  MessageTemplate({
    required this.id,
    required this.templateName,
    required this.templateType,
    this.messageSubject,
    required this.messageBody,
    required this.isActive,
    required this.versionNo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MessageTemplate.fromJson(Map<String, dynamic> json) {
    return MessageTemplate(
      id: json['id'] as String,
      templateName: json['template_name'] as String? ?? '',
      templateType: json['template_type'] as String? ?? '',
      messageSubject: json['message_subject'] as String?,
      messageBody: json['message_body'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      versionNo: json['version_no'] as int? ?? 1,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'template_name': templateName,
      'template_type': templateType,
      'message_subject': messageSubject,
      'message_body': messageBody,
      'is_active': isActive,
      'version_no': versionNo,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  MessageTemplate copyWith({
    String? id,
    String? templateName,
    String? templateType,
    String? messageSubject,
    String? messageBody,
    bool? isActive,
    int? versionNo,
    String? createdAt,
    String? updatedAt,
  }) {
    return MessageTemplate(
      id: id ?? this.id,
      templateName: templateName ?? this.templateName,
      templateType: templateType ?? this.templateType,
      messageSubject: messageSubject ?? this.messageSubject,
      messageBody: messageBody ?? this.messageBody,
      isActive: isActive ?? this.isActive,
      versionNo: versionNo ?? this.versionNo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class MessageTemplateVersion {
  final String id;
  final String templateId;
  final int versionNo;
  final String? messageSubject;
  final String messageBody;
  final String createdAt;

  MessageTemplateVersion({
    required this.id,
    required this.templateId,
    required this.versionNo,
    this.messageSubject,
    required this.messageBody,
    required this.createdAt,
  });

  factory MessageTemplateVersion.fromJson(Map<String, dynamic> json) {
    return MessageTemplateVersion(
      id: json['id'] as String,
      templateId: json['template_id'] as String? ?? '',
      versionNo: json['version_no'] as int? ?? 1,
      messageSubject: json['message_subject'] as String?,
      messageBody: json['message_body'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'template_id': templateId,
      'version_no': versionNo,
      'message_subject': messageSubject,
      'message_body': messageBody,
      'created_at': createdAt,
    };
  }
}

class MessageLog {
  final String id;
  final String customerName;
  final String mobileNumber;
  final String channel;
  final String messageType;
  final String messageBody;
  final String status;
  final String sentAt;
  final String? providerId;

  MessageLog({
    required this.id,
    required this.customerName,
    required this.mobileNumber,
    required this.channel,
    required this.messageType,
    required this.messageBody,
    required this.status,
    required this.sentAt,
    this.providerId,
  });

  factory MessageLog.fromJson(Map<String, dynamic> json) {
    return MessageLog(
      id: json['id'] as String,
      customerName: json['customer_name'] as String? ?? '',
      mobileNumber: json['mobile_number'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      messageType: json['message_type'] as String? ?? '',
      messageBody: json['message_body'] as String? ?? '',
      status: json['status'] as String? ?? '',
      sentAt: json['sent_at'] as String? ?? '',
      providerId: json['provider_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'mobile_number': mobileNumber,
      'channel': channel,
      'message_type': messageType,
      'message_body': messageBody,
      'status': status,
      'sent_at': sentAt,
      'provider_id': providerId,
    };
  }
}

class ShopSettings {
  final String id;
  final String shopName;
  final String shopAddress;
  final String shopMobile;
  final String whatsappNumber;
  final String? gstNumber;
  final String? logoUrl;
  final String backupEmail;
  final String smsSenderName;
  final String createdAt;
  final String updatedAt;

  ShopSettings({
    required this.id,
    required this.shopName,
    required this.shopAddress,
    required this.shopMobile,
    required this.whatsappNumber,
    this.gstNumber,
    this.logoUrl,
    required this.backupEmail,
    required this.smsSenderName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ShopSettings.fromJson(Map<String, dynamic> json) {
    return ShopSettings(
      id: json['id'] as String,
      shopName: json['shop_name'] as String? ?? 'Shree Ganadhish Battery Services',
      shopAddress: json['shop_address'] as String? ?? 'Pune, Maharashtra, India',
      shopMobile: json['shop_mobile'] as String? ?? '9730911213',
      whatsappNumber: json['whatsapp_number'] as String? ?? '9730911213',
      gstNumber: json['gst_number'] as String?,
      logoUrl: json['logo_url'] as String?,
      backupEmail: json['backup_email'] as String? ?? 'shreeganadhishbattery@gmail.com',
      smsSenderName: json['sms_sender_name'] as String? ?? 'SGABPL',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_mobile': shopMobile,
      'whatsapp_number': whatsappNumber,
      'gst_number': gstNumber,
      'logo_url': logoUrl,
      'backup_email': backupEmail,
      'sms_sender_name': smsSenderName,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  ShopSettings copyWith({
    String? id,
    String? shopName,
    String? shopAddress,
    String? shopMobile,
    String? whatsappNumber,
    String? gstNumber,
    String? logoUrl,
    String? backupEmail,
    String? smsSenderName,
    String? createdAt,
    String? updatedAt,
  }) {
    return ShopSettings(
      id: id ?? this.id,
      shopName: shopName ?? this.shopName,
      shopAddress: shopAddress ?? this.shopAddress,
      shopMobile: shopMobile ?? this.shopMobile,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      gstNumber: gstNumber ?? this.gstNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      backupEmail: backupEmail ?? this.backupEmail,
      smsSenderName: smsSenderName ?? this.smsSenderName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
