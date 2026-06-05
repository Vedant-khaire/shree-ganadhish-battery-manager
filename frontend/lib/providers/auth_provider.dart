import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/auth_storage.dart';
import '../core/utils.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? errorMessage;
  final String? username;

  AuthState({
    required this.isAuthenticated,
    required this.isLoading,
    this.errorMessage,
    this.username,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? errorMessage,
    String? username,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      username: username ?? this.username,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthStorage _authStorage;
  final ApiClient _apiClient;

  AuthNotifier(this._authStorage, this._apiClient)
      : super(AuthState(isAuthenticated: false, isLoading: true)) {
    _checkToken();
    // Register unauthorized 401 callback
    _apiClient.onUnauthorized = logout;
  }

  Future<void> _checkToken() async {
    final token = await _authStorage.getToken();
    final username = await _authStorage.getUsername();
    if (token != null) {
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        username: username,
      );
    } else {
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
      );
    }
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

        state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          username: username,
        );
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
    state = state.copyWith(isLoading: true);
    await _authStorage.clearAll();
    state = AuthState(
      isAuthenticated: false,
      isLoading: false,
    );
  }
}

// Global provider for authentication
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authStorage = ref.watch(authStorageProvider);
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(authStorage, apiClient);
});
