import 'env.dart';

class AppConstants {
  static const String appName = 'Shree Ganadhish';
  static const String shopFullName = 'Shree Ganadhish Auto Ele & Battery Services';
  
  // API URL - set via --dart-define=API_BASE_URL=...
  static const String apiBaseUrl = Env.apiBaseUrl;
  
  // Storage Keys
  static const String tokenKey = 'jwt_token';
  static const String usernameKey = 'admin_username';
}

