import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/auth_storage.dart';
import '../core/health_service.dart';
import '../core/utils.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? errorMessage;
  final String? username;
  final bool isWarmingUp;
  final bool isWarmupFailed;
  final int retryCountdown;
  final int retryAttempt;

  AuthState({
    required this.isAuthenticated,
    required this.isLoading,
    this.errorMessage,
    this.username,
    this.isWarmingUp = false,
    this.isWarmupFailed = false,
    this.retryCountdown = 0,
    this.retryAttempt = 0,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? errorMessage,
    String? username,
    bool? isWarmingUp,
    bool? isWarmupFailed,
    int? retryCountdown,
    int? retryAttempt,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      username: username ?? this.username,
      isWarmingUp: isWarmingUp ?? this.isWarmingUp,
      isWarmupFailed: isWarmupFailed ?? this.isWarmupFailed,
      retryCountdown: retryCountdown ?? this.retryCountdown,
      retryAttempt: retryAttempt ?? this.retryAttempt,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthStorage _authStorage;
  final ApiClient _apiClient;
  final HealthService _healthService;
  Timer? _countdownTimer;

  AuthNotifier(this._authStorage, this._apiClient, this._healthService)
      : super(AuthState(isAuthenticated: false, isLoading: true)) {
    _checkToken();
    // Register unauthorized 401 callback
    _apiClient.onUnauthorized = logout;
  }

  Future<void> _checkToken() async {
    final token = await _authStorage.getToken();
    final username = await _authStorage.getUsername();
    if (token != null) {
      // Token exists, but we must warm up the backend before allowing entry to dashboard
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        isWarmingUp: true,
        isWarmupFailed: false,
        retryCountdown: 0,
        retryAttempt: 0,
        username: username,
      );
      _performWarmup();
    } else {
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        isWarmingUp: false,
        isWarmupFailed: false,
        retryCountdown: 0,
        retryAttempt: 0,
      );
    }
  }

  Future<void> _performWarmup({int attempt = 1}) async {
    _countdownTimer?.cancel();
    state = state.copyWith(
      isWarmingUp: true,
      isWarmupFailed: false,
      retryAttempt: attempt,
      retryCountdown: 0,
    );

    AppLogger.log('Performing health warmup attempt $attempt...');
    final isHealthy = await _healthService.checkHealth();

    if (isHealthy) {
      AppLogger.log('Health warmup check succeeded.');
      state = state.copyWith(
        isWarmingUp: false,
        isWarmupFailed: false,
        retryAttempt: 0,
        retryCountdown: 0,
      );
    } else {
      AppLogger.log('Health warmup check failed (attempt $attempt).');
      if (attempt < 3) {
        // Wait sequence:
        // Attempt 1 fails -> wait 2 seconds before attempt 2
        // Attempt 2 fails -> wait 5 seconds before attempt 3
        int waitSeconds = attempt == 1 ? 2 : 5;
        _startCountdown(waitSeconds, () {
          _performWarmup(attempt: attempt + 1);
        });
      } else {
        // Attempt 3 fails -> wait 10 seconds? Wait, the requirement says:
        // Attempt 1: wait 2 sec
        // Attempt 2: wait 5 sec
        // Attempt 3: wait 10 sec
        // Let's count down 10 seconds before officially showing "isWarmupFailed".
        // This gives the backend a full 17 seconds of retry cooling, and then we show error.
        _startCountdown(10, () {
          AppLogger.log('Health warmup max retries exceeded. Showing manual retry options.');
          state = state.copyWith(
            isWarmingUp: false,
            isWarmupFailed: true,
            retryAttempt: 0,
            retryCountdown: 0,
          );
        });
      }
    }
  }

  void _startCountdown(int seconds, VoidCallback onFinished) {
    state = state.copyWith(retryCountdown: seconds);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = state.retryCountdown;
      if (current <= 1) {
        timer.cancel();
        onFinished();
      } else {
        state = state.copyWith(retryCountdown: current - 1);
      }
    });
  }

  Future<void> manualWarmup() async {
    _countdownTimer?.cancel();
    _performWarmup(attempt: 1);
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // Use FormData format since backend uses OAuth2PasswordRequestForm
      final formData = FormData.fromMap({
        'username': username,
        'password': password,
      });

      final response = await _apiClient.dio.post(
        '/auth/login',
        data: formData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final token = data['access_token'] as String;

        await _authStorage.saveToken(token);
        await _authStorage.saveUsername(username);

        AppLogger.log('Admin login succeeded: $username');

        // Start warmup flow before navigating to Dashboard
        state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          isWarmingUp: true,
          isWarmupFailed: false,
          retryCountdown: 0,
          retryAttempt: 0,
          username: username,
        );
        _performWarmup();
        return true;
      } else {
        state = AuthState(
          isAuthenticated: false,
          isLoading: false,
          errorMessage: 'Invalid credentials',
        );
        return false;
      }
    } on DioException catch (e) {
      String msg = 'Connection failed';
      if (e.response != null) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          msg = data['detail'].toString();
        } else {
          msg = 'Invalid username or password';
        }
      }
      AppLogger.log('Admin login failed for user: $username. Error: $msg');
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        errorMessage: msg,
      );
      return false;
    } catch (e) {
      AppLogger.log('Admin login encountered unexpected exception: $e');
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        errorMessage: 'An unexpected error occurred',
      );
      return false;
    }
  }

  Future<void> logout() async {
    AppLogger.log('Admin logout triggered');
    _countdownTimer?.cancel();
    state = state.copyWith(isLoading: true);
    await _authStorage.clearAll();
    state = AuthState(
      isAuthenticated: false,
      isLoading: false,
      isWarmingUp: false,
      isWarmupFailed: false,
      retryCountdown: 0,
      retryAttempt: 0,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}

// Global provider for authentication
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authStorage = ref.watch(authStorageProvider);
  final apiClient = ref.watch(apiClientProvider);
  final healthService = ref.watch(healthServiceProvider);
  return AuthNotifier(authStorage, apiClient, healthService);
});
