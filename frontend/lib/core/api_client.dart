import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants.dart';
import 'auth_storage.dart';
import 'utils.dart';

// Providers for AuthStorage and ApiClient
final authStorageProvider = Provider<AuthStorage>((ref) {
  return AuthStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final authStorage = ref.watch(authStorageProvider);
  return ApiClient(authStorage);
});

class ApiClient {
  final Dio dio;
  final AuthStorage _authStorage;
  bool _isLoggingOut = false;
  
  // Callback that can be registered by the Auth provider to handle logouts on 401s
  void Function()? onUnauthorized;

  ApiClient(this._authStorage)
      : dio = Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authStorage.getToken();
          if (token != null && token.trim().isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            if (!_isLoggingOut) {
              _isLoggingOut = true;
              AppLogger.log('401 Unauthorized received, executing auto-logout to prevent retry loops.');
              
              // Clear credentials synchronously in storage
              await _authStorage.clearAll();
              
              // Trigger route redirection
              onUnauthorized?.call();
              
              Future.delayed(const Duration(seconds: 3), () {
                _isLoggingOut = false;
              });
            }
            // Overwrite error message to be cleaner
            final cleanError = error.copyWith(
              message: 'Session expired. Please log in again.',
            );
            return handler.next(cleanError);
          }

          // Check if server is unreachable and rewrite error with a friendly message
          final errorStr = error.toString().toLowerCase();
          final errorObjStr = error.error?.toString().toLowerCase() ?? '';
          
          final isOffline = error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError ||
              errorStr.contains('socketexception') ||
              errorStr.contains('timeout') ||
              errorObjStr.contains('socketexception') ||
              errorObjStr.contains('timeout') ||
              errorObjStr.contains('xmlhttprequest') ||
              errorObjStr.contains('networkerror');

          if (isOffline) {
            final friendlyError = error.copyWith(
              message: 'Server is offline. Please try again.',
            );
            return handler.next(friendlyError);
          }
          
          return handler.next(error);
        },
      ),
    );
  }
}

