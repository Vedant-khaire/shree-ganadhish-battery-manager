import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'api_client.dart';
import 'utils.dart';

final healthServiceProvider = Provider<HealthService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final service = HealthService(apiClient);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class HealthService {
  final ApiClient _apiClient;
  DateTime? _lastSuccessTime;
  Timer? _keepAliveTimer;

  HealthService(this._apiClient) {
    _startKeepAliveTimer();
  }

  /// Check if the backend is healthy/awake
  Future<bool> checkHealth() async {
    // If we had a successful check in the last 30 seconds, return true
    if (_lastSuccessTime != null &&
        DateTime.now().difference(_lastSuccessTime!) < const Duration(seconds: 30)) {
      AppLogger.log('[HEALTH] Using cached health status (last success: $_lastSuccessTime)');
      return true;
    }

    try {
      AppLogger.log('[HEALTH] Checking backend health...');
      final response = await _apiClient.dio.get(
        '/health',
        options: Options(
          extra: {'skip_retry': true}, // We handle countdown/retry state machines at the auth/UI level
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _lastSuccessTime = DateTime.now();
        AppLogger.log('[HEALTH] Backend is awake and healthy.');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.log('[HEALTH] Health check failed: $e');
      return false;
    }
  }

  /// Start background keep-alive timer that runs every 12 minutes
  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    AppLogger.log('[HEALTH] Starting background warmup keep-alive service (runs every 12 mins)');
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 12), (timer) async {
      AppLogger.log('[HEALTH] Keep-alive timer fired. Waking up backend...');
      try {
        await _apiClient.dio.get(
          '/health',
          options: Options(
            extra: {'skip_retry': true},
          ),
        );
        AppLogger.log('[HEALTH] Keep-alive ping succeeded.');
      } catch (e) {
        AppLogger.log('[HEALTH] Keep-alive ping failed: $e');
      }
    });
  }

  void dispose() {
    _keepAliveTimer?.cancel();
  }
}
