import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Selected bottom-navigation tab.
final navIndexProvider = StateProvider<int>((ref) => 0);

/// App-wide navigator and messenger, for things that happen outside a
/// screen (e.g. tapping an order notification).
final appNavigatorKey = GlobalKey<NavigatorState>();
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Tab indexes in MainShell.
class Tabs {
  static const dashboard = 0;
  static const inventory = 1;
  static const billing = 2;
  static const bills = 3;
  static const settings = 4;
}
