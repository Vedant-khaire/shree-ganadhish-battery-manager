import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/reminder.dart';
import 'dashboard_provider.dart';

class ReminderListFilter {
  final String search;
  final String status;
  final String type;
  final int page;
  final int limit;
  final bool archived;

  ReminderListFilter({
    this.search = '',
    this.status = '',
    this.type = 'ALL',
    this.page = 1,
    this.limit = 20,
    this.archived = false,
  });

  ReminderListFilter copyWith({
    String? search,
    String? status,
    String? type,
    int? page,
    int? limit,
    bool? archived,
  }) {
    return ReminderListFilter(
      search: search ?? this.search,
      status: status ?? this.status,
      type: type ?? this.type,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      archived: archived ?? this.archived,
    );
  }
}

final reminderFilterProvider = StateProvider<ReminderListFilter>((ref) {
  return ReminderListFilter();
});

class PaginatedReminders {
  final List<Reminder> data;
  final int total;
  final int page;
  final int limit;

  PaginatedReminders({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory PaginatedReminders.fromJson(Map<String, dynamic> json) {
    final list = json['data'] as List<dynamic>? ?? [];
    return PaginatedReminders(
      data: list.map((c) => Reminder.fromJson(c as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

class ReminderListNotifier extends AsyncNotifier<PaginatedReminders> {
  @override
  Future<PaginatedReminders> build() async {
    final filter = ref.watch(reminderFilterProvider);
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.dio.get(
      '/reminders',
      queryParameters: {
        'search': filter.search,
        'status': filter.status,
        if (filter.type != 'ALL') 'type': filter.type,
        'page': filter.page,
        'limit': filter.limit,
        'archived': filter.archived,
      },
    );

    return PaginatedReminders.fromJson(response.data as Map<String, dynamic>);
  }

  void updateState(PaginatedReminders updated) {
    state = AsyncValue.data(updated);
  }
}

final reminderListProvider = AsyncNotifierProvider<ReminderListNotifier, PaginatedReminders>(() {
  return ReminderListNotifier();
});

final reminderStatsProvider = FutureProvider<ReminderStats>((ref) async {
  // Watches the reminder list provider to reload stats whenever writing operations are run
  ref.watch(reminderListProvider);
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get('/reminders/stats');
  return ReminderStats.fromJson(response.data as Map<String, dynamic>);
});

final reminderOperationsProvider = Provider((ref) => ReminderOperations(ref));

class ReminderOperations {
  final Ref _ref;
  ReminderOperations(this._ref);

  Future<void> createReminder(Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/reminders', data: data);
    _ref.invalidate(reminderListProvider);
    _ref.invalidate(reminderStatsProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> updateReminder(String id, Map<String, dynamic> data) async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.put('/reminders/$id', data: data);
    _ref.invalidate(reminderListProvider);
    _ref.invalidate(reminderStatsProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> deleteReminder(String id) async {
    final listState = _ref.read(reminderListProvider);
    
    // Optimistic UI update
    if (listState is AsyncData<PaginatedReminders>) {
      final paginated = listState.value;
      final filteredList = paginated.data.where((r) => r.id != id).toList();
      _ref.read(reminderListProvider.notifier).updateState(
        PaginatedReminders(
          data: filteredList,
          total: paginated.total - (filteredList.length < paginated.data.length ? 1 : 0),
          page: paginated.page,
          limit: paginated.limit,
        ),
      );
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.delete('/reminders/$id');
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> toggleCompletion(String id, bool completed) async {
    final listState = _ref.read(reminderListProvider);
    
    // Optimistic UI update
    if (listState is AsyncData<PaginatedReminders>) {
      final paginated = listState.value;
      final index = paginated.data.indexWhere((r) => r.id == id);
      if (index != -1) {
        final updatedData = List<Reminder>.from(paginated.data);
        updatedData[index] = updatedData[index].copyWith(
          isCompleted: completed,
          reminderStatus: completed ? 'COMPLETED' : 'UPCOMING',
        );
        _ref.read(reminderListProvider.notifier).updateState(
          PaginatedReminders(
            data: updatedData,
            total: paginated.total,
            page: paginated.page,
            limit: paginated.limit,
          ),
        );
      }
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.put('/reminders/$id', data: {'is_completed': completed});
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> markAsSent(String id, bool sent) async {
    final listState = _ref.read(reminderListProvider);
    
    // Optimistic UI update
    if (listState is AsyncData<PaginatedReminders>) {
      final paginated = listState.value;
      final index = paginated.data.indexWhere((r) => r.id == id);
      if (index != -1) {
        final updatedData = List<Reminder>.from(paginated.data);
        updatedData[index] = updatedData[index].copyWith(
          messageSent: sent,
          sentAt: sent ? DateTime.now().toIso8601String() : null,
          whatsappDeliveryStatus: sent ? 'SENT' : 'PENDING',
        );
        _ref.read(reminderListProvider.notifier).updateState(
          PaginatedReminders(
            data: updatedData,
            total: paginated.total,
            page: paginated.page,
            limit: paginated.limit,
          ),
        );
      }
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.put('/reminders/$id', data: {
        'message_sent': sent,
        'sent_at': sent ? DateTime.now().toIso8601String() : null,
        'whatsapp_delivery_status': sent ? 'SENT' : 'PENDING',
      });
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }

  Future<void> triggerDailyBatch() async {
    final apiClient = _ref.read(apiClientProvider);
    await apiClient.dio.post('/reminders/trigger-daily');
    _ref.invalidate(reminderListProvider);
    _ref.invalidate(reminderStatsProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> deleteAllReminders({String? type}) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.dio.delete(
        '/reminders',
        queryParameters: {
          if (type != null && type != 'ALL') 'type': type,
        },
      );
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      _ref.invalidate(reminderListProvider);
      _ref.invalidate(reminderStatsProvider);
      _ref.invalidate(dashboardProvider);
      rethrow;
    }
  }
}

