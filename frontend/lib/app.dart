import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/customers/customer_list_screen.dart';
import 'screens/customers/customer_form_screen.dart';
import 'screens/customers/customer_detail_screen.dart';
import 'screens/customers/scrap_batteries_screen.dart';
import 'screens/batteries/battery_form_screen.dart';
import 'screens/payments/payment_form_screen.dart';
import 'screens/payments/payment_list_screen.dart';
import 'screens/export_screen.dart';
import 'screens/stock/stock_list_screen.dart';
import 'screens/stock/stock_form_screen.dart';
import 'screens/reminders/reminder_list_screen.dart';
import 'screens/follow_up_center_screen.dart';
import 'screens/message_templates_screen.dart';
import 'screens/shop_settings_screen.dart';
import 'screens/shops/shop_list_screen.dart';
import 'screens/shops/shop_form_screen.dart';
import 'screens/shops/shop_detail_screen.dart';
import 'screens/shops/shop_purchase_form_screen.dart';

// GoRouter provider that listens to authentication state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final currentPath = state.uri.path;
      final isLoggedIn = authState.isAuthenticated;

      // While authentication is initializing or backend is warming up, stay on splash screen
      if (authState.isLoading || authState.isWarmingUp) {
        if (currentPath != '/splash') {
          return '/splash';
        }
        return null;
      }

      // Once loading is complete:
      if (currentPath == '/splash') {
        return isLoggedIn ? '/dashboard' : '/login';
      }

      final isGoingToLogin = currentPath == '/login';

      if (!isLoggedIn && !isGoingToLogin) {
        return '/login';
      }

      if (isLoggedIn && isGoingToLogin) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/customers',
        builder: (context, state) => const CustomerListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const CustomerFormScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => CustomerDetailScreen(customerId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => CustomerFormScreen(customerId: state.pathParameters['id']),
              ),
              GoRoute(
                path: 'batteries/new',
                builder: (context, state) => BatteryFormScreen(customerId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'batteries/:batteryId/edit',
                builder: (context, state) => BatteryFormScreen(
                  customerId: state.pathParameters['id']!,
                  batteryId: state.pathParameters['batteryId'],
                ),
              ),
              GoRoute(
                path: 'payments/new',
                builder: (context, state) => PaymentFormScreen(customerId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/payments',
        builder: (context, state) => const PaymentListScreen(),
      ),
      GoRoute(
        path: '/stock',
        builder: (context, state) => const StockListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const StockFormScreen(),
          ),
          GoRoute(
            path: ':stockId/edit',
            builder: (context, state) => StockFormScreen(stockId: state.pathParameters['stockId']),
          ),
        ],
      ),
      GoRoute(
        path: '/exports',
        builder: (context, state) => const ExportScreen(),
      ),
      GoRoute(
        path: '/reminders',
        builder: (context, state) => const ReminderListScreen(),
      ),
      GoRoute(
        path: '/follow-ups',
        builder: (context, state) => const FollowUpCenterScreen(),
      ),
      GoRoute(
        path: '/message-templates',
        builder: (context, state) => const MessageTemplatesScreen(),
      ),
      GoRoute(
        path: '/scrap-batteries',
        builder: (context, state) => const ScrapBatteriesScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const ShopSettingsScreen(),
      ),
      GoRoute(
        path: '/shops',
        builder: (context, state) => const ShopListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const ShopFormScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => ShopDetailScreen(shopId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => ShopFormScreen(shopId: state.pathParameters['id']),
              ),
              GoRoute(
                path: 'purchases/new',
                builder: (context, state) => ShopPurchaseFormScreen(shopId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: AppConstants.shopFullName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
