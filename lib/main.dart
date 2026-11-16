import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'features/inventory/screens/inventory_screen.dart';
import 'features/billing/screens/billing_screen.dart';
import 'features/bills/screens/bills_history_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/settings/cloud_backup_service.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'core/config/app_env.dart';
import 'core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'core/navigation.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/brand.dart';
import 'features/splash/splash_screen.dart';
import 'features/online/online_store_service.dart';
import 'features/online/order_alerts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite has no native implementation on desktop or web.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  // Notifications for new online orders (also notes if one launched us).
  await OrderNotifications.init();

  runApp(const ProviderScope(child: MyApp()));

  // Daily cloud backup, in the background (no-op if signed out or done).
  CloudBackupService.autoBackupIfDue();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppEnv.isDev ? '${Brand.name} Dev' : Brand.name,
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.light(),
      // Corner badge so a test install is never mistaken for the real till.
      builder: AppEnv.isDev
          ? (context, child) => Banner(
              message: 'DEV',
              location: BannerLocation.topEnd,
              color: AppTheme.gold,
              textStyle: const TextStyle(
                color: AppTheme.ink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
              child: child!,
            )
          : null,
      home: const SplashGate(child: MainShell()),
    );
  }
}

// ─── MAIN SHELL ───────────────────────────────────────────
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const List<Widget> _screens = [
    DashboardScreen(),
    InventoryScreen(),
    BillingScreen(),
    BillsHistoryScreen(),
    SettingsScreen(),
  ];

  static const _destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Home'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Stock'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Billing'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Bills'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  /// At this width and up (a counter PC or tablet in landscape), the
  /// tabs move from the bottom bar to a side rail.
  static const railBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navIndexProvider);
    // Keeps the online store's catalogue in step with the POS.
    ref.watch(catalogSyncProvider);
    // Phone/browser alert when a new online order arrives.
    ref.watch(orderAlertsProvider);
    // App was opened by tapping an order notification: show the orders.
    if (OrderNotifications.pendingOpen) {
      OrderNotifications.pendingOpen = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => OrderNotifications.openOrders(),
      );
    }
    void go(int index) => ref.read(navIndexProvider.notifier).state = index;

    final wide = MediaQuery.sizeOf(context).width >= railBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _SideRail(selected: currentIndex, onSelect: go),
            Expanded(child: _screens[currentIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _screens[currentIndex],
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: go,
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── SIDE RAIL (wide screens) ─────────────────────────────
class _SideRail extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _SideRail({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      color: AppTheme.ink,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 20),
            Semantics(
              label: Brand.name,
              child: Image.asset(
                Brand.markOnDark,
                width: 44,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(height: 28),
            for (var i = 0; i < MainShell._destinations.length; i++)
              // Settings sits apart at the bottom.
              if (i != Tabs.settings)
                _RailItem(
                  dest: MainShell._destinations[i],
                  selected: selected == i,
                  onTap: () => onSelect(i),
                ),
            const Spacer(),
            _RailItem(
              dest: MainShell._destinations[Tabs.settings],
              selected: selected == Tabs.settings,
              onTap: () => onSelect(Tabs.settings),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final (IconData, IconData, String) dest;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, selectedIcon, label) = dest;
    final fg = selected ? Colors.white : const Color(0xFF9A9BA1);

    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            focusColor: AppTheme.gold.withValues(alpha: 0.25),
            hoverColor: Colors.white.withValues(alpha: 0.05),
            child: SizedBox(
              width: 96,
              height: 68,
              child: Stack(
                children: [
                  // The active tab is marked by a gold thread on the left edge.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    left: 0,
                    top: selected ? 14 : 34,
                    bottom: selected ? 14 : 34,
                    width: 3,
                    child: ColoredBox(
                      color: selected ? AppTheme.gold : Colors.transparent,
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? selectedIcon : icon,
                          color: fg,
                          size: 24,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
