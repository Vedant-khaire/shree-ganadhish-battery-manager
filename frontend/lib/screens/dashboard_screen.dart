import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/pwa_helper.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/toast_helper.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardProvider);
    final filters = ref.watch(dashboardFiltersProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1000;
    final isMobile = width < 700;

    return AppScaffold(
      title: 'Control Center & Analytics',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
        },
        color: AppTheme.primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Hero Welcome & Business Summary Header
              _HeroBusinessHeader(filters: filters),
              const SizedBox(height: 24),

              statsAsync.when(
                data: (stats) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. Critical glowing out-of-stock and overdue alert bar
                      if (stats.inventoryOutOfStockCount > 0 || stats.inventoryLowStockCount > 0) ...[
                        _BusinessAlertCenter(stats: stats, isMobile: isMobile),
                        const SizedBox(height: 24),
                      ],

                      // 3. KPI Analytics Grid (10 Animated Metrics)
                      _KpiAnalyticsGrid(stats: stats, isMobile: isMobile),
                      const SizedBox(height: 28),

                      // Smart Follow-ups & Reminders Center
                      _SmartRemindersPanel(stats: stats, isMobile: isMobile),
                      const SizedBox(height: 28),

                      // 3.5. SMART Recovery & Udhari Analytics Section
                      _UdhariRecoveryAnalytics(stats: stats, isMobile: isMobile),
                      const SizedBox(height: 28),

                      // Shops & Retailers Analytics Section (Refinement 5)
                      _ShopRetailerAnalytics(stats: stats, isMobile: isMobile),
                      const SizedBox(height: 28),

                      // 4. Quick Action Control Center
                      _QuickActionPanel(isMobile: isMobile),
                      const SizedBox(height: 28),

                      // 5. FlChart Cinematic Visual Analytics (Double column on desktop, single on mobile)
                      _CinematicChartSection(stats: stats, isDesktop: isDesktop),
                      const SizedBox(height: 28),

                      // 6. Tabular Insights & Activity Timeline Logs
                      _InsightsAndActivityTimeline(stats: stats, isDesktop: isDesktop),
                    ],
                  );
                },
                loading: () => Column(
                  children: [
                    const LoadingSkeleton(width: double.infinity, height: 160),
                    const SizedBox(height: 24),
                    const LoadingSkeleton(width: double.infinity, height: 120),
                    const SizedBox(height: 24),
                    LoadingSkeleton.table(rows: 4),
                  ],
                ),
                error: (err, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text('Failed to load dashboard statistics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(ErrorParser.parse(err), style: const TextStyle(color: Color(0xFF64748B))),
                        const SizedBox(height: 20),
                        AppButton(
                          label: 'Reload Dashboard',
                          onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Hero Business Header widget
// ---------------------------------------------------------------------------
class _HeroBusinessHeader extends ConsumerWidget {
  final DashboardFilters filters;
  const _HeroBusinessHeader({required this.filters});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final todayStr = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppTheme.secondaryColor,
            AppTheme.secondaryColor.withAlpha(220),
            const Color(0xFF1E3A8A), // Cinematic Deep Navy Accent
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isMobile
            ? null
            : [
                BoxShadow(
                  color: AppTheme.secondaryColor.withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.shopFullName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Welcome Back, Admin • Live Control Center',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: isMobile ? 12 : 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canInstallPwa()) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrangeAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () {
                        installPwa();
                      },
                      icon: const Icon(Icons.download_for_offline, size: 16),
                      label: const Text('Install App', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (!isMobile)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Colors.deepOrangeAccent, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            todayStr,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Divider(height: 32, color: Colors.white12),
          // Interactive Filters Row inside Header
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Reporting Period:',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              _buildHeaderChoiceChip(context, ref, 'Today', 'today'),
              _buildHeaderChoiceChip(context, ref, 'This Week', 'this_week'),
              _buildHeaderChoiceChip(context, ref, 'This Month', 'this_month'),
              _buildHeaderChoiceChip(context, ref, 'This Year', 'this_year'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChoiceChip(BuildContext context, WidgetRef ref, String label, String value) {
    final isSelected = filters.period == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppTheme.primaryColor,
      backgroundColor: Colors.white.withOpacity(0.06),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
      onSelected: (selected) {
        if (selected) {
          ref.read(dashboardFiltersProvider.notifier).update(
                (state) => state.copyWith(period: value),
              );
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Business Alert Center (Out of Stock / Critical warnings with glowing pulse animation)
// ---------------------------------------------------------------------------
class _BusinessAlertCenter extends StatefulWidget {
  final DashboardStats stats;
  final bool isMobile;
  const _BusinessAlertCenter({required this.stats, required this.isMobile});

  @override
  State<_BusinessAlertCenter> createState() => _BusinessAlertCenterState();
}

class _BusinessAlertCenterState extends State<_BusinessAlertCenter> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 3.0, end: 12.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2), // Light red warning bg
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
            boxShadow: widget.isMobile
                ? null
                : [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.12),
                      blurRadius: _glowAnimation.value,
                      spreadRadius: _glowAnimation.value / 3,
                    )
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'CRITICAL ALERT: ${stats.inventoryOutOfStockCount} Battery Models Out of Stock & ${stats.inventoryLowStockCount} Low Stock Warnings!',
                        style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (stats.inventoryOutOfStockModels.isNotEmpty) ...[
                const Divider(height: 1, color: Color(0xFFFCA5A5)),
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: stats.inventoryOutOfStockModels.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.withOpacity(0.2)),
                        ),
                        child: Text(
                          '${item.modelName} [${item.batteryType}]',
                          style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  ),
                )
              ]
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. KPI Grid with Animated Value Rollers
// ---------------------------------------------------------------------------
class _KpiAnalyticsGrid extends StatelessWidget {
  final DashboardStats stats;
  final bool isMobile;
  const _KpiAnalyticsGrid({required this.stats, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final double recoveryDays = stats.avgPaymentRecoveryDays;

    return GridView.count(
      crossAxisCount: isMobile ? 2 : (MediaQuery.of(context).size.width > 1200 ? 5 : 4),
      crossAxisSpacing: isMobile ? 12 : 16,
      mainAxisSpacing: isMobile ? 12 : 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: isMobile ? 0.95 : 1.25,
      children: [
        _buildAnimatedKpiCard(
          title: 'Total Customers',
          value: stats.customersTotalActive.toDouble(),
          trendLabel: 'Active Base',
          icon: Icons.people_outline,
          color: Colors.blue,
          isCurrency: false,
        ),
        _buildAnimatedKpiCard(
          title: "Today's Ledger",
          value: stats.todayTotalSalesAmount,
          trendLabel: 'Daily Booked',
          icon: Icons.menu_book,
          color: Colors.purple,
          isCurrency: true,
        ),
        _buildAnimatedKpiCard(
          title: "Today's Collections",
          value: stats.todayTotalCollection,
          trendLabel: 'Cash Collected',
          icon: Icons.payments,
          color: Colors.green,
          isCurrency: true,
        ),
        _buildAnimatedKpiCard(
          title: 'Pending Udhari',
          value: stats.salesTotalPendingUdhari,
          trendLabel: 'Outstanding Ledger',
          icon: Icons.account_balance_wallet,
          color: Colors.red,
          isCurrency: true,
        ),
        _buildAnimatedKpiCard(
          title: 'Repeat Customers',
          value: stats.repeatCustomersCount.toDouble(),
          trendLabel: 'Purchased > 1',
          icon: Icons.replay,
          color: Colors.indigo,
          isCurrency: false,
        ),
        _buildAnimatedKpiCard(
          title: 'Total Stock Units',
          value: stats.inventoryTotalStockUnits.toDouble(),
          trendLabel: '${stats.inventoryTotalStockModels} unique models',
          icon: Icons.inventory_2_outlined,
          color: Colors.teal,
          isCurrency: false,
        ),
        _buildAnimatedKpiCard(
          title: 'Low Stock Models',
          value: stats.inventoryLowStockCount.toDouble(),
          trendLabel: 'Below threshold',
          icon: Icons.report_problem_outlined,
          color: Colors.orange,
          isCurrency: false,
          isAlert: stats.inventoryLowStockCount > 0,
        ),
        _buildAnimatedKpiCard(
          title: 'Service Reminders',
          value: stats.upcomingServiceRemindersCount.toDouble(),
          trendLabel: 'Pending Maintenance',
          icon: Icons.build_circle_outlined,
          color: Colors.amber,
          isCurrency: false,
        ),
        _buildAnimatedKpiCard(
          title: 'Expiring Guarantees',
          value: stats.warrantyExpiringSoon30Days.toDouble(),
          trendLabel: 'Next 30 Days',
          icon: Icons.gavel_outlined,
          color: Colors.deepOrange,
          isCurrency: false,
        ),
        _buildAnimatedKpiCard(
          title: 'Recovery Average',
          value: recoveryDays,
          trendLabel: 'Avg Recovery Days',
          icon: Icons.timelapse,
          color: Colors.brown,
          isCurrency: false,
          customSuffix: ' days',
        ),
      ],
    );
  }

  Widget _buildAnimatedKpiCard({
    required String title,
    required double value,
    required String trendLabel,
    required IconData icon,
    required Color color,
    required bool isCurrency,
    String? customSuffix,
    bool isAlert = false,
  }) {
    return _HoverScaleContainer(
      child: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: isAlert ? const Color(0xFFFFFBEB) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAlert
                ? const Color(0xFFFDE68A)
                : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 10.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 16),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: value),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.fastOutSlowIn,
                    builder: (context, val, child) {
                      String valueText = '';
                      if (isCurrency) {
                        valueText = FormatUtils.formatIndianCurrency(val);
                      } else {
                        // Support double display like recovery average
                        valueText = val % 1 == 0 ? '${val.toInt()}' : val.toStringAsFixed(1);
                      }
                      if (customSuffix != null) {
                        valueText = '$valueText$customSuffix';
                      }

                      return Text(
                        valueText,
                        style: TextStyle(
                          fontSize: isMobile ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: isAlert ? const Color(0xFFB45309) : AppTheme.secondaryColor,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trendLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: isAlert ? const Color(0xFFB45309).withOpacity(0.8) : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Quick Action panel (Hover scale actions buttons)
// ---------------------------------------------------------------------------
class _QuickActionPanel extends StatelessWidget {
  final bool isMobile;
  const _QuickActionPanel({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Operations',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isMobile ? 2 : 6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isMobile ? 2.5 : 2.0,
          children: [
            _buildActionCard(context, 'Add Customer', Icons.person_add_alt_1, '/customers/new', Colors.deepOrange),
            _buildActionCard(context, 'Udhari (Payments)', Icons.payment, '/payments', Colors.green),
            _buildActionCard(context, 'Follow-up Center', Icons.contact_phone_outlined, '/follow-ups', Colors.blue),
            _buildActionCard(context, 'Stock Directory', Icons.inventory_2, '/stock', Colors.purple),
            _buildActionCard(context, 'Export Center', Icons.download_done_outlined, '/exports', Colors.teal),
            _buildActionCard(context, 'Shop Settings', Icons.settings, '/dashboard', Colors.blueGrey, isStub: true),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, String label, IconData icon, String route, Color themeColor, {bool isStub = false}) {
    return _HoverScaleContainer(
      child: InkWell(
        onTap: () {
          if (isStub) {
            ToastHelper.show(context, 'System configuration settings are auto-managed.');
          } else {
            context.go(route);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: themeColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.secondaryColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. fl_chart Cinematic visual charts
// ---------------------------------------------------------------------------
class _CinematicChartSection extends StatelessWidget {
  final DashboardStats stats;
  final bool isDesktop;
  const _CinematicChartSection({required this.stats, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Visual Trends & Ledgers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
        ),
        const SizedBox(height: 12),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildSalesLineChart()),
              const SizedBox(width: 20),
              Expanded(child: _buildCollectionBarChart()),
            ],
          )
        else ...[
          _buildSalesLineChart(),
          const SizedBox(height: 16),
          _buildCollectionBarChart(),
        ]
      ],
    );
  }

  Widget _buildSalesLineChart() {
    final points = stats.monthlySalesTrend;
    if (points.isEmpty) return const SizedBox.shrink();

    // Mapping month labels to numerical values for LineChart
    List<FlSpot> spots = [];
    for (int i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].value));
    }

    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.show_chart, color: AppTheme.primaryColor, size: 18),
              SizedBox(width: 8),
              Text('Monthly Battery Sales Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < points.length) {
                          return Text(
                            points[idx].month,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppTheme.primaryColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppTheme.primaryColor.withOpacity(0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionBarChart() {
    final points = stats.paymentCollectionTrend;
    if (points.isEmpty) return const SizedBox.shrink();

    List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < points.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: points[i].value,
              color: Colors.green,
              width: 14,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            )
          ],
        ),
      );
    }

    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_outlined, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('Monthly Collections Ledger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < points.length) {
                          return Text(
                            points[idx].month,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Tabular Insights Grid (Villages, Models, Pending) and Activity Feed Timeline
// ---------------------------------------------------------------------------
class _InsightsAndActivityTimeline extends StatelessWidget {
  final DashboardStats stats;
  final bool isDesktop;
  const _InsightsAndActivityTimeline({required this.stats, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildInsightsTables(context)),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: _buildActivityTimeline()),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInsightsTables(context),
          const SizedBox(height: 24),
          _buildActivityTimeline(),
        ],
      );
    }
  }

  Widget _buildInsightsTables(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Most Pending Outstanding Udhari table
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_outlined, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  const Text('Top Pending Payments (Udhari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
                ],
              ),
              const SizedBox(height: 12),
              if (stats.mostPendingCustomers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('All customer payments are settled!', style: TextStyle(color: Colors.grey, fontSize: 12))),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stats.mostPendingCustomers.length,
                  separatorBuilder: (ctx, index) => const Divider(color: Color(0xFFF1F5F9), height: 12),
                  itemBuilder: (ctx, index) {
                    final item = stats.mostPendingCustomers[index];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(item.mobileNumber, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        Text(
                          FormatUtils.formatIndianCurrency(item.pendingAmount),
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                        )
                      ],
                    );
                  },
                )
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. Top Sold Models table
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.star_border, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Text('Top Selling Battery Models', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
                ],
              ),
              const SizedBox(height: 12),
              if (stats.topSellingModels.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No battery sales recorded yet.', style: TextStyle(color: Colors.grey, fontSize: 12))),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stats.topSellingModels.length,
                  separatorBuilder: (ctx, index) => const Divider(color: Color(0xFFF1F5F9), height: 12),
                  itemBuilder: (ctx, index) {
                    final item = stats.topSellingModels[index];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.modelName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(item.batteryType, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        Text(
                          '${item.salesCount} sold',
                          style: const TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                        )
                      ],
                    );
                  },
                )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityTimeline() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_toggle_off, color: Colors.teal, size: 18),
              const SizedBox(width: 8),
              Text('Live Business Log Feed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
            ],
          ),
          const SizedBox(height: 16),
          if (stats.recentActivities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Timeline logs appear here when events occur.', style: TextStyle(color: Colors.grey, fontSize: 12))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stats.recentActivities.length,
              itemBuilder: (ctx, index) {
                final log = stats.recentActivities[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _getLogColor(log.action).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_getLogIcon(log.action), color: _getLogColor(log.action), size: 14),
                        ),
                        if (index < stats.recentActivities.length - 1)
                          Container(width: 2, height: 26, color: const Color(0xFFF1F5F9)),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.action.replaceAll('_', ' '),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.secondaryColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            FormatUtils.formatDate(log.createdAt),
                            style: const TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  ],
                );
              },
            )
        ],
      ),
    );
  }

  IconData _getLogIcon(String action) {
    if (action.contains('ADDED')) return Icons.add_circle;
    if (action.contains('UPDATED')) return Icons.edit;
    if (action.contains('DELETED')) return Icons.delete_outline;
    if (action.contains('REDUCED') || action.contains('DECREASED')) return Icons.trending_down;
    return Icons.check_circle_outline;
  }

  Color _getLogColor(String action) {
    if (action.contains('DELETED')) return Colors.red;
    if (action.contains('ADDED')) return Colors.green;
    if (action.contains('REDUCED') || action.contains('DECREASED')) return Colors.orange;
    return Colors.teal;
  }
}

// ---------------------------------------------------------------------------
// Hover Scale Container helper (Applies smooth hover animation)
// ---------------------------------------------------------------------------
class _HoverScaleContainer extends StatefulWidget {
  final Widget child;
  const _HoverScaleContainer({required this.child});

  @override
  State<_HoverScaleContainer> createState() => _HoverScaleContainerState();
}

class _HoverScaleContainerState extends State<_HoverScaleContainer> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    if (isMobile) return widget.child;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: _isHovered ? (Matrix4.identity()..scale(1.025)) : Matrix4.identity(),
        child: widget.child,
      ),
    );
  }
}

class _UdhariRecoveryAnalytics extends StatelessWidget {
  final DashboardStats stats;
  final bool isMobile;
  const _UdhariRecoveryAnalytics({required this.stats, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SMART Recovery & Udhari Analytics',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondaryColor,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isMobile ? 2 : 4,
          crossAxisSpacing: isMobile ? 12 : 16,
          mainAxisSpacing: isMobile ? 12 : 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isMobile ? 0.95 : 1.25,
          children: [
            _buildRecoveryCard(
              title: 'Pending Customers',
              value: stats.totalPendingUdhariCustomers.toDouble(),
              subtitle: 'Active Debtors',
              icon: Icons.assignment_ind_outlined,
              color: Colors.deepOrange,
              isCurrency: false,
            ),
            _buildRecoveryCard(
              title: 'Weekly Recovery Due',
              value: stats.weeklyRecoveryDue,
              subtitle: 'Recovery forecast (7d)',
              icon: Icons.calendar_today_outlined,
              color: Colors.blue,
              isCurrency: true,
            ),
            _buildRecoveryCard(
              title: 'Overdue Collections',
              value: stats.overdueCollections,
              subtitle: 'Action required!',
              icon: Icons.dangerous_outlined,
              color: Colors.red,
              isCurrency: true,
              isOverdue: stats.overdueCollections > 0,
            ),
            _buildRecoveryCard(
              title: 'Collection Efficiency',
              value: stats.collectionEfficiencyPct,
              subtitle: 'Settled vs Total',
              icon: Icons.percent,
              color: Colors.green,
              isCurrency: false,
              isPercentage: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecoveryCard({
    required String title,
    required double value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isCurrency,
    bool isPercentage = false,
    bool isOverdue = false,
  }) {
    Widget cardContent = Container(
      decoration: BoxDecoration(
        color: isOverdue ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
          width: isOverdue ? 1.5 : 1.0,
        ),
      ),
      padding: EdgeInsets.all(isMobile ? 10.0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isOverdue ? const Color(0xFF991B1B) : const Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: value),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.fastOutSlowIn,
                builder: (context, val, child) {
                  String text = '';
                  if (isCurrency) {
                    text = FormatUtils.formatIndianCurrency(val);
                  } else if (isPercentage) {
                    text = '${val.toStringAsFixed(1)}%';
                  } else {
                    text = '${val.toInt()}';
                  }
                  return Text(
                    text,
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: isOverdue ? const Color(0xFFB91C1C) : AppTheme.secondaryColor,
                    ),
                  );
                },
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isOverdue ? const Color(0xFFB91C1C).withOpacity(0.8) : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (isOverdue) {
      return _OverdueRecoveryPulseWrapper(
        child: _HoverScaleContainer(child: cardContent),
      );
    }

    return _HoverScaleContainer(child: cardContent);
  }
}

class _OverdueRecoveryPulseWrapper extends StatefulWidget {
  final Widget child;
  const _OverdueRecoveryPulseWrapper({required this.child});

  @override
  State<_OverdueRecoveryPulseWrapper> createState() => _OverdueRecoveryPulseWrapperState();
}

class _OverdueRecoveryPulseWrapperState extends State<_OverdueRecoveryPulseWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 2.0, end: 10.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.25),
                blurRadius: _animation.value,
                spreadRadius: _animation.value / 3,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SmartRemindersPanel extends StatelessWidget {
  final DashboardStats stats;
  final bool isMobile;
  const _SmartRemindersPanel({required this.stats, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Follow-ups & Reminders Center',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondaryColor,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isMobile ? 2 : 5,
          crossAxisSpacing: isMobile ? 12 : 16,
          mainAxisSpacing: isMobile ? 12 : 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isMobile ? 0.95 : 1.25,
          children: [
            _buildReminderCard(
              context: context,
              title: 'Due Today',
              value: stats.remindersDueToday.toDouble(),
              subtitle: 'Urgent follow-ups',
              icon: Icons.alarm,
              color: Colors.red,
              route: '/follow-ups?tab=reminders&filter=today',
              isAlert: stats.remindersDueToday > 0,
            ),
            _buildReminderCard(
              context: context,
              title: 'Service Due',
              value: stats.remindersServiceDue.toDouble(),
              subtitle: 'Maintenance due',
              icon: Icons.build,
              color: Colors.amber,
              route: '/follow-ups?tab=reminders&filter=service',
            ),
            _buildReminderCard(
              context: context,
              title: 'Water Checks Due',
              value: stats.remindersWaterChecksDue.toDouble(),
              subtitle: 'Inverter top-ups',
              icon: Icons.water_drop,
              color: Colors.blue,
              route: '/follow-ups?tab=reminders&filter=water_check',
            ),
            _buildReminderCard(
              context: context,
              title: 'Upcoming Warranty',
              value: stats.remindersUpcomingWarrantyExpiry.toDouble(),
              subtitle: 'Guarantee expiries',
              icon: Icons.verified_user,
              color: Colors.deepOrange,
              route: '/follow-ups?tab=reminders&filter=warranty_expiry',
            ),
            _buildReminderCard(
              context: context,
              title: 'Pending Udhari',
              value: stats.remindersPendingUdhariRecovery.toDouble(),
              subtitle: 'Outstanding recovery',
              icon: Icons.money_off,
              color: Colors.redAccent,
              route: '/follow-ups?tab=udhari',
              isAlert: stats.remindersPendingUdhariRecovery > 0,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReminderCard({
    required BuildContext context,
    required String title,
    required double value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String route,
    bool isAlert = false,
  }) {
    return _HoverScaleContainer(
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isAlert ? const Color(0xFFFEF2F2) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAlert ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
              width: isAlert ? 1.5 : 1.0,
            ),
          ),
          padding: EdgeInsets.all(isMobile ? 10.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: isAlert ? const Color(0xFF991B1B) : const Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 16),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: value),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.fastOutSlowIn,
                    builder: (context, val, child) {
                      return Text(
                        '${val.toInt()}',
                        style: TextStyle(
                          fontSize: isMobile ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: isAlert ? const Color(0xFFB91C1C) : AppTheme.secondaryColor,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: isAlert ? const Color(0xFFB91C1C).withOpacity(0.8) : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopRetailerAnalytics extends StatelessWidget {
  final DashboardStats stats;
  final bool isMobile;
  const _ShopRetailerAnalytics({required this.stats, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final shops = stats.shopsSummary;
    final isDesktop = MediaQuery.of(context).size.width > 1000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shops & Retailers Summary',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondaryColor,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isMobile ? 2 : 4,
          crossAxisSpacing: isMobile ? 12 : 16,
          mainAxisSpacing: isMobile ? 12 : 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isMobile ? 0.95 : 1.25,
          children: [
            _buildShopCard(
              title: 'Total Shops',
              value: shops.totalShops.toDouble(),
              subtitle: 'Registered profiles',
              icon: Icons.store_rounded,
              color: Colors.blue,
              isCurrency: false,
            ),
            _buildShopCard(
              title: 'Total Outstanding Udhari',
              value: shops.totalShopUdhari,
              subtitle: 'Shop consolidated debt',
              icon: Icons.pending_actions_rounded,
              color: Colors.red,
              isCurrency: true,
              isAlert: shops.totalShopUdhari > 0,
            ),
            _buildShopCard(
              title: 'Highest Shop Balance',
              value: shops.highestOutstandingShopBalance,
              subtitle: 'Peak retailer debt',
              icon: Icons.priority_high_rounded,
              color: Colors.deepOrange,
              isCurrency: true,
            ),
            _buildShopCard(
              title: 'Shop Purchases Value',
              value: shops.totalShopPurchasesValue,
              subtitle: 'Logged invoice value',
              icon: Icons.shopping_cart_checkout_rounded,
              color: Colors.teal,
              isCurrency: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // List top shops
        isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildTopPendingShops(context, shops.topPendingShops)),
                  const SizedBox(width: 20),
                  Expanded(child: _buildTopPurchasingShops(context, shops.topPurchasingShops)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopPendingShops(context, shops.topPendingShops),
                  const SizedBox(height: 16),
                  _buildTopPurchasingShops(context, shops.topPurchasingShops),
                ],
              ),
      ],
    );
  }

  Widget _buildShopCard({
    required String title,
    required double value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isCurrency,
    bool isAlert = false,
  }) {
    return _HoverScaleContainer(
      child: Container(
        decoration: BoxDecoration(
          color: isAlert ? const Color(0xFFFFF5F5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAlert ? const Color(0xFFFEB2B2) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        padding: EdgeInsets.all(isMobile ? 10.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: isAlert ? const Color(0xFF9B2C2C) : const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: value),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.fastOutSlowIn,
                  builder: (context, val, child) {
                    return Text(
                      isCurrency ? FormatUtils.formatIndianCurrency(val) : '${val.toInt()}',
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color: isAlert ? const Color(0xFFC53030) : AppTheme.secondaryColor,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: isAlert ? const Color(0xFFC53030).withOpacity(0.8) : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPendingShops(BuildContext context, List<TopPendingShop> topPending) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.report_gmailerrorred_rounded, color: Colors.redAccent, size: 18),
              SizedBox(width: 8),
              Text('Top Pending Shops (Udhari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
            ],
          ),
          const SizedBox(height: 12),
          if (topPending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('All shops outstanding balances are settled!', style: TextStyle(color: Colors.grey, fontSize: 12))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topPending.length,
              separatorBuilder: (ctx, index) => const Divider(color: Color(0xFFF1F5F9), height: 12),
              itemBuilder: (ctx, index) {
                final item = topPending[index];
                return InkWell(
                  onTap: () => context.go('/shops/${item.shopId}'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        FormatUtils.formatIndianCurrency(item.pendingAmount),
                        style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, fontSize: 12),
                      )
                    ],
                  ),
                );
              },
            )
        ],
      ),
    );
  }

  Widget _buildTopPurchasingShops(BuildContext context, List<TopPurchasingShop> topPurchasing) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star_purple500_rounded, color: Colors.teal, size: 18),
              SizedBox(width: 8),
              Text('Top Purchasing Shops / Retailers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryColor)),
            ],
          ),
          const SizedBox(height: 12),
          if (topPurchasing.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No shop purchases logged yet.', style: TextStyle(color: Colors.grey, fontSize: 12))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topPurchasing.length,
              separatorBuilder: (ctx, index) => const Divider(color: Color(0xFFF1F5F9), height: 12),
              itemBuilder: (ctx, index) {
                final item = topPurchasing[index];
                return InkWell(
                  onTap: () => context.go('/shops/${item.shopId}'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        FormatUtils.formatIndianCurrency(item.totalAmount),
                        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12),
                      )
                    ],
                  ),
                );
              },
            )
        ],
      ),
    );
  }
}
