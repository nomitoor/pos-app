import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/navigation.dart';
import '../../core/theme/app_theme.dart';
import '../../models/online_order.dart';
import 'online_orders.dart';
import 'online_store_service.dart';
import 'screens/online_orders_screen.dart';

final _money = NumberFormat('#,##0', 'en_US');

/// Phone / browser notifications for new online orders.
///
/// They fire while the POS app is open or recently used (the order list is
/// kept fresh by Supabase Realtime plus a one-minute check). A fully closed
/// app gets no alert; the dashboard shows the new orders when it opens.
class OrderNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Set when the app was started by tapping an order notification;
  /// [MainShell] opens the orders screen once the app has loaded.
  static bool pendingOpen = false;

  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  static const _android = AndroidNotificationDetails(
    'online_orders',
    'Online orders',
    channelDescription: 'A customer placed an order on the online store',
    importance: Importance.high,
    priority: Priority.high,
    color: AppTheme.gold,
    category: AndroidNotificationCategory.message,
  );

  static Future<void> init() async {
    if (!supported || _ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(
          '@mipmap/ic_launcher_foreground',
        ),
        web: WebInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (_) => openOrders(),
    );
    if (!kIsWeb) {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) pendingOpen = true;
    }
    _ready = true;
  }

  static WebFlutterLocalNotificationsPlugin? get _web => _plugin
      .resolvePlatformSpecificImplementation<
        WebFlutterLocalNotificationsPlugin
      >();

  static AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether the user has allowed notifications (null if unknown).
  static Future<bool?> allowed() async {
    if (!supported) return false;
    await init();
    if (kIsWeb) {
      return _web?.permissionStatus == WebNotificationPermission.granted;
    }
    return _androidPlugin?.areNotificationsEnabled();
  }

  /// Shows the system permission prompt. On the web this must run from a
  /// button tap, or the browser may block notifications for good.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    final ok = kIsWeb
        ? await _web?.requestNotificationsPermission()
        : await _androidPlugin?.requestNotificationsPermission();
    return ok ?? false;
  }

  /// Notifies about [order]. Returns false if no system notification could
  /// be shown (not allowed / unsupported), so the caller can fall back.
  static Future<bool> show(OnlineOrder order) async {
    if (await allowed() != true) return false;
    final pieces = order.items.fold<int>(0, (s, i) => s + i.quantity);
    await _plugin.show(
      id: order.id & 0x7fffffff,
      title: 'New online order ${order.orderNo}',
      body:
          '${order.customerName}, $pieces item${pieces == 1 ? '' : 's'}, '
          'Rs ${_money.format(order.total)}',
      notificationDetails: const NotificationDetails(
        android: _android,
        web: WebNotificationDetails(requireInteraction: true),
      ),
    );
    return true;
  }

  /// Sample alert from Settings, to check sound and permission.
  static Future<bool> test() async {
    if (await allowed() != true) return false;
    await _plugin.show(
      id: 0,
      title: 'Order alerts are on',
      body: "You'll see this when a customer orders online.",
      notificationDetails: const NotificationDetails(android: _android),
    );
    return true;
  }

  static void openOrders() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      pendingOpen = true;
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => const OnlineOrdersScreen()));
  }
}

/// Watches the order list and alerts once per newly arrived order.
/// Orders already waiting when the app starts are not announced (the
/// dashboard badge covers them). Watched by [MainShell].
final orderAlertsProvider = Provider<void>((ref) {
  if (ref.watch(shopOwnerProvider).value != true) return;
  // Android may ask on its own; browsers only allow it after a tap
  // (Settings → Online order alerts).
  if (!kIsWeb) OrderNotifications.requestPermission();
  Set<int>? seen;

  ref.listen<AsyncValue<List<OnlineOrder>>>(onlineOrdersProvider, (_, next) {
    if (next.isLoading || !next.hasValue) return;
    final orders = next.value!;
    if (seen == null) {
      seen = {for (final o in orders) o.id};
      return;
    }
    final fresh = orders
        .where((o) => o.isNew && !seen!.contains(o.id))
        .toList();
    seen!.addAll(orders.map((o) => o.id));
    for (final o in fresh.reversed) {
      _alert(o);
    }
  }, fireImmediately: true);
});

Future<void> _alert(OnlineOrder o) async {
  final shown = await OrderNotifications.show(o);
  if (shown) return;
  // No system notification (not allowed, or desktop): tell the person at
  // the screen instead.
  appMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('New online order ${o.orderNo} from ${o.customerName}'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'View',
        onPressed: OrderNotifications.openOrders,
      ),
    ),
  );
}
