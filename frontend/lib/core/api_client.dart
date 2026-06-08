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
            connectTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 60),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          AppLogger.log('[API REQUEST] ${options.method} ${options.path}');
          final token = await _authStorage.getToken();
          if (token != null && token.trim().isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.log('[API SUCCESS] ${response.requestOptions.method} ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          AppLogger.log('[API ERROR] ${error.requestOptions.method} ${error.requestOptions.path} - Type: ${error.type}, Message: ${error.message}, Error: ${error.error}');
          
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

          final errorStr = error.toString().toLowerCase();
          final errorObjStr = error.error?.toString().toLowerCase() ?? '';
          
          final isRetryable = (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError ||
              errorStr.contains('socketexception') ||
              errorStr.contains('timeout') ||
              errorObjStr.contains('socketexception') ||
              errorObjStr.contains('timeout') ||
              errorObjStr.contains('xmlhttprequest') ||
              errorObjStr.contains('networkerror')) &&
              error.requestOptions.extra['skip_retry'] != true;

          if (isRetryable) {
            int retryCount = error.requestOptions.extra['retry_count'] ?? 0;
            if (retryCount < 3) {
              retryCount++;
              error.requestOptions.extra['retry_count'] = retryCount;
              
              int delaySeconds = 2;
              if (retryCount == 2) {
                delaySeconds = 5;
              } else if (retryCount == 3) {
                delaySeconds = 10;
              }
              
              AppLogger.log('[API RETRY] Attempt $retryCount of 3 for path ${error.requestOptions.path} in ${delaySeconds}s');
              await Future.delayed(Duration(seconds: delaySeconds));
              
              try {
                // Re-execute request
                final response = await dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                // Continue chain (might trigger another retry if retryCount < 3)
                return handler.next(retryError);
              } catch (e) {
                return handler.next(error);
              }
            }
            
            // If we ran out of retries, map to a friendly "waking up" message
            final friendlyError = error.copyWith(
              message: 'Server is starting.\n\nThis may take up to 60 seconds because the backend is waking up.\n\nPlease wait...',
            );
            return handler.next(friendlyError);
          }
          
          return handler.next(error);
        },
      ),
    );
  }
}

