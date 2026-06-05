import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/reminder_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/payment_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/shop_provider.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../core/pwa_install_helper.dart';
import 'dart:async';


class AppScaffold extends ConsumerStatefulWidget {
  final Widget child;
  final String title;

  const AppScaffold({
    super.key,
    required this.child,
    required this.title,
  });

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  bool _isMobileMenuExpanded = false;
  Timer? _refreshTimer;
  String? _lastRoute;
  StreamSubscription<void>? _pwaSubscription;
  bool _isPwaInstallable = false;

  @override
  void initState() {
    super.initState();
    PwaInstallHelper.init();
    _isPwaInstallable = PwaInstallHelper.isInstallable;
    _pwaSubscription = PwaInstallHelper.onInstallableChanged.listen((_) {
      if (mounted) {
        setState(() {
          _isPwaInstallable = PwaInstallHelper.isInstallable;
        });
      }
    });
  }

  void _resetTimerForRoute(String route) {
    _refreshTimer?.cancel();
    
    final isDashboard = route.startsWith('/dashboard');
    final duration = isDashboard ? const Duration(seconds: 30) : const Duration(seconds: 60);
    
    _refreshTimer = Timer.periodic(duration, (timer) {
      if (!mounted) return;
      
      if (route.startsWith('/dashboard')) {
        ref.invalidate(dashboardProvider);
      } else if (route.startsWith('/customers') || route.startsWith('/scrap-batteries')) {
        ref.invalidate(customerListProvider);
        ref.invalidate(scrapBatteriesProvider);
      } else if (route.startsWith('/payments')) {
        ref.invalidate(paymentListProvider);
      } else if (route.startsWith('/reminders') || route.startsWith('/follow-ups')) {
        ref.invalidate(reminderListProvider);
        ref.invalidate(reminderStatsProvider);
      } else if (route.startsWith('/stock')) {
        ref.invalidate(stockListProvider);
      } else if (route.startsWith('/shops')) {
        ref.invalidate(shopListProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pwaSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final authState = ref.watch(authProvider);
    final isDesktop = width > 800;

    final dashboardStateVal = ref.watch(dashboardProvider);
    final pendingPaymentsCount = dashboardStateVal.maybeWhen(
      data: (stats) => stats.paymentsPendingCount,
      orElse: () => 0,
    );
    final remindersCount = dashboardStateVal.maybeWhen(
      data: (stats) => stats.remindersDueToday + stats.remindersOverdue,
      orElse: () => 0,
    );
    final stockCount = dashboardStateVal.maybeWhen(
      data: (stats) => stats.inventoryLowStockCount + stats.inventoryOutOfStockCount,
      orElse: () => 0,
    );
    final shopUdhariCount = dashboardStateVal.maybeWhen(
      data: (stats) => stats.shopsSummary.pendingUdhariShopsCount,
      orElse: () => 0,
    );

    Widget? buildBadge(String route, int pendingPayments, int reminders, int stock, int shopUdhari) {
      int count = 0;
      Color badgeColor = Colors.orange;
      
      if (route == '/payments') {
        count = pendingPayments;
        badgeColor = Colors.redAccent;
      } else if (route == '/reminders' || route == '/follow-ups') {
        count = reminders;
        badgeColor = Colors.orange;
      } else if (route == '/stock') {
        count = stock;
        badgeColor = Colors.amber.shade700;
      } else if (route == '/shops') {
        count = shopUdhari;
        badgeColor = Colors.redAccent;
      }
      
      if (count <= 0) return null;
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // Navigation items
    final menuItems = [
      _NavigationItem(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Dashboard',
        route: '/dashboard',
      ),
      _NavigationItem(
        icon: Icons.contact_phone_outlined,
        selectedIcon: Icons.contact_phone,
        label: 'Follow-up Center',
        route: '/follow-ups',
      ),
      _NavigationItem(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: 'Customers',
        route: '/customers',
      ),
      _NavigationItem(
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        label: 'Shops / Retailers',
        route: '/shops',
      ),
      _NavigationItem(
        icon: Icons.recycling_outlined,
        selectedIcon: Icons.recycling,
        label: 'Scrap Batteries',
        route: '/scrap-batteries',
      ),
      _NavigationItem(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: 'Stock (Inventory)',
        route: '/stock',
      ),
      _NavigationItem(
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet,
        label: 'Udhari (Payments)',
        route: '/payments',
      ),
      _NavigationItem(
        icon: Icons.download_outlined,
        selectedIcon: Icons.download,
        label: 'Exports',
        route: '/exports',
      ),
      _NavigationItem(
        icon: Icons.notifications_active_outlined,
        selectedIcon: Icons.notifications_active,
        label: 'Reminders',
        route: '/reminders',
      ),
      _NavigationItem(
        icon: Icons.message_outlined,
        selectedIcon: Icons.message,
        label: 'Message Templates',
        route: '/message-templates',
      ),
      _NavigationItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Shop Settings',
        route: '/settings',
      ),
    ];

    final currentRoute = GoRouterState.of(context).uri.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currentRoute != _lastRoute) {
        _lastRoute = currentRoute;
        _resetTimerForRoute(currentRoute);
      }
    });

    Widget buildDrawerContent(bool showHeader, {bool isMobile = false}) {
      final listContent = ListView(
        shrinkWrap: isMobile,
        physics: isMobile ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        children: [
          ...menuItems.map((item) {
            final isSelected = currentRoute.startsWith(item.route);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  color: isSelected ? AppTheme.primaryColor : const Color(0xFF94A3B8),
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                selected: isSelected,
                selectedTileColor: const Color(0xFF334155),
                trailing: buildBadge(item.route, pendingPaymentsCount, remindersCount, stockCount, shopUdhariCount),
                onTap: () {
                  if (isMobile) {
                    setState(() {
                      _isMobileMenuExpanded = false;
                    });
                  }
                  // Invalidate all primary list/stats providers on menu item click
                  ref.invalidate(dashboardProvider);
                  ref.invalidate(customerListProvider);
                  ref.invalidate(scrapBatteriesProvider);
                  ref.invalidate(paymentListProvider);
                  ref.invalidate(reminderListProvider);
                  ref.invalidate(reminderStatsProvider);
                  ref.invalidate(stockListProvider);
                  ref.invalidate(shopListProvider);
                  
                  context.go(item.route);
                },
              ),
            );
          }),
          if (_isPwaInstallable) ...[
            const Divider(color: Color(0xFF334155), height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: const Icon(
                  Icons.install_mobile,
                  color: Colors.greenAccent,
                ),
                title: const Text(
                  'Install App',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                tileColor: const Color(0xFF1E293B),
                onTap: () {
                  if (isMobile) {
                    setState(() {
                      _isMobileMenuExpanded = false;
                    });
                  }
                  PwaInstallHelper.promptInstall();
                },
              ),
            ),
          ],
        ],
      );

      final userSection = Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF334155), width: 1),
          ),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppTheme.primaryColor,
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    authState.username ?? 'Admin',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Store Manager • v1.0.0',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              onPressed: () {
                ref.read(authProvider.notifier).logout();
              },
              tooltip: 'Logout',
            ),
          ],
        ),
      );

      return Container(
        color: AppTheme.secondaryColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF334155), width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Auto Ele & Battery Services',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            if (isMobile)
              listContent
            else
              Expanded(child: listContent),
            userSection,
          ],
        ),
      );
    }

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 260,
              child: Drawer(
                elevation: 0,
                child: buildDrawerContent(true),
              ),
            ),
            const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh Data',
                      onPressed: () {
                        ref.invalidate(dashboardProvider);
                        ref.invalidate(customerListProvider);
                        ref.invalidate(scrapBatteriesProvider);
                        ref.invalidate(paymentListProvider);
                        ref.invalidate(reminderListProvider);
                        ref.invalidate(reminderStatsProvider);
                        ref.invalidate(stockListProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All data refreshed successfully'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        ref.watch(themeProvider) == ThemeMode.dark
                            ? Icons.light_mode
                            : Icons.dark_mode,
                      ),
                      onPressed: () {
                        ref.read(themeProvider.notifier).toggleTheme();
                      },
                      tooltip: 'Toggle Theme Mode',
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: Icon(_isMobileMenuExpanded ? Icons.close : Icons.menu),
            onPressed: () {
              setState(() {
                _isMobileMenuExpanded = !_isMobileMenuExpanded;
              });
            },
          ),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Data',
              onPressed: () {
                ref.invalidate(dashboardProvider);
                ref.invalidate(customerListProvider);
                ref.invalidate(scrapBatteriesProvider);
                ref.invalidate(paymentListProvider);
                ref.invalidate(reminderListProvider);
                ref.invalidate(reminderStatsProvider);
                ref.invalidate(stockListProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All data refreshed successfully'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(
                ref.watch(themeProvider) == ThemeMode.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
              ),
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
              tooltip: 'Toggle Theme Mode',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              height: _isMobileMenuExpanded ? 580.0 : 0.0,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: 580.0,
                  child: buildDrawerContent(false, isMobile: true),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _NavigationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });
}
