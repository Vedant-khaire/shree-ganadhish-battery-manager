import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/message_template.dart';

// ---------------------------------------------------------------------------
// Shop Settings Provider
// ---------------------------------------------------------------------------

class ShopSettingsNotifier extends AsyncNotifier<ShopSettings> {
  @override
  Future<ShopSettings> build() async {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.dio.get('/message-templates/shop-settings');
    return ShopSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateSettings(Map<String, dynamic> data) async {
    final apiClient = ref.read(apiClientProvider);
    state = const AsyncValue.loading();
    try {
      final response = await apiClient.dio.put('/message-templates/shop-settings', data: data);
      final updated = ShopSettings.fromJson(response.data as Map<String, dynamic>);
      state = AsyncValue.data(updated);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

final shopSettingsProvider = AsyncNotifierProvider<ShopSettingsNotifier, ShopSettings>(() {
  return ShopSettingsNotifier();
});

// ---------------------------------------------------------------------------
// Message Templates Provider
// ---------------------------------------------------------------------------

class MessageTemplatesNotifier extends AsyncNotifier<List<MessageTemplate>> {
  @override
  Future<List<MessageTemplate>> build() async {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.dio.get('/message-templates');
    final list = response.data as List<dynamic>? ?? [];
    return list.map((item) => MessageTemplate.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<void> updateTemplate(String id, Map<String, dynamic> data) async {
    final apiClient = ref.read(apiClientProvider);
    state = const AsyncValue.loading();
    try {
      await apiClient.dio.put('/message-templates/$id', data: data);
      ref.invalidateSelf();
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> restoreTemplate(String id, int? versionNo) async {
    final apiClient = ref.read(apiClientProvider);
    state = const AsyncValue.loading();
    try {
      await apiClient.dio.post(
        '/message-templates/$id/restore',
        queryParameters: {
          if (versionNo != null) 'version_no': versionNo,
        },
      );
      ref.invalidateSelf();
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

final messageTemplatesProvider = AsyncNotifierProvider<MessageTemplatesNotifier, List<MessageTemplate>>(() {
  return MessageTemplatesNotifier();
});

// ---------------------------------------------------------------------------
// Message Log Filter & Paginated Provider
// ---------------------------------------------------------------------------

class MessageLogFilter {
  final String channel;
  final int page;
  final int limit;

  MessageLogFilter({
    this.channel = 'ALL',
    this.page = 1,
    this.limit = 20,
  });

  MessageLogFilter copyWith({
    String? channel,
    int? page,
    int? limit,
  }) {
    return MessageLogFilter(
      channel: channel ?? this.channel,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}

final messageLogFilterProvider = StateProvider<MessageLogFilter>((ref) {
  return MessageLogFilter();
});

class PaginatedMessageLogs {
  final List<MessageLog> data;
  final int total;
  final int page;
  final int limit;

  PaginatedMessageLogs({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedMessageLogs.fromJson(Map<String, dynamic> json) {
    final list = json['data'] as List<dynamic>? ?? [];
    return PaginatedMessageLogs(
      data: list.map((c) => MessageLog.fromJson(c as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

class MessageLogsNotifier extends AsyncNotifier<PaginatedMessageLogs> {
  @override
  Future<PaginatedMessageLogs> build() async {
    final filter = ref.watch(messageLogFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.dio.get(
      '/message-templates/logs',
      queryParameters: {
        if (filter.channel != 'ALL') 'channel': filter.channel,
        'page': filter.page,
        'limit': filter.limit,
      },
    );

    return PaginatedMessageLogs.fromJson(response.data as Map<String, dynamic>);
  }
}

final messageLogsProvider = AsyncNotifierProvider<MessageLogsNotifier, PaginatedMessageLogs>(() {
  return MessageLogsNotifier();
});

// ---------------------------------------------------------------------------
// Template Versions & Operations
// ---------------------------------------------------------------------------

final templateVersionsProvider = FutureProvider.family<List<MessageTemplateVersion>, String>((ref, templateId) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get('/message-templates/$templateId/versions');
  final list = response.data as List<dynamic>? ?? [];
  return list.map((item) => MessageTemplateVersion.fromJson(item as Map<String, dynamic>)).toList();
});

final templateOperationsProvider = Provider((ref) => TemplateOperations(ref));

class TemplateOperations {
  final Ref _ref;
  TemplateOperations(this._ref);

  Future<Map<String, dynamic>> sendTestMessage(String templateId, String channel, String mobileNumber) async {
    final apiClient = _ref.read(apiClientProvider);
    final response = await apiClient.dio.post(
      '/message-templates/$templateId/test',
      queryParameters: {
        'channel': channel,
        'mobile_number': mobileNumber,
      },
    );
    _ref.invalidate(messageLogsProvider);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> renderMessagePreview(String reminderId, {String channel = 'whatsapp'}) async {
    final apiClient = _ref.read(apiClientProvider);
    final response = await apiClient.dio.get(
      '/reminders/$reminderId/render-message',
      queryParameters: {
        'channel': channel,
      },
    );
    return response.data as Map<String, dynamic>;
  }
}
