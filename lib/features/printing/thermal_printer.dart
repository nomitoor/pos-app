import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'printer_settings.dart';

/// A paired Bluetooth device the user can pick as the receipt printer.
typedef PairedDevice = ({String name, String address});

/// Talks to the Bluetooth receipt printer. Android only.
class ThermalPrinter {
  /// Bluetooth printing works in the Android app, not in the browser.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Asks for Bluetooth permission if needed. Returns an error message to
  /// show, or null when Bluetooth is ready.
  static Future<String?> _ready() async {
    if (!supported) return 'Receipt printing works in the Android app.';
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      return 'Allow "Nearby devices" for this app to use the printer.';
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      return 'Turn on Bluetooth, then try again.';
    }
    return null;
  }

  /// Devices already paired in the phone's Bluetooth settings.
  static Future<(List<PairedDevice>, String?)> paired() async {
    final error = await _ready();
    if (error != null) return (const <PairedDevice>[], error);
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return ([for (final d in list) (name: d.name, address: d.macAdress)], null);
  }

  /// Closes the Bluetooth link (e.g. before switching printers).
  static Future<void> disconnect() async {
    if (supported) await PrintBluetoothThermal.disconnect;
  }

  /// Sends [bytes] to the chosen printer, connecting first if needed.
  /// Returns an error message, or null when it printed.
  static Future<String?> printBytes(
    PrinterSettings printer,
    List<int> bytes,
  ) async {
    if (!printer.isSet) {
      return 'Choose your receipt printer in Settings first.';
    }
    final error = await _ready();
    if (error != null) return error;

    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.address!,
      );
      if (!ok) {
        return "Couldn't connect to ${printer.name ?? 'the printer'}. "
            'Check it is switched on and nearby.';
      }
    }
    final sent = await PrintBluetoothThermal.writeBytes(bytes);
    return sent ? null : 'The printer stopped responding. Try again.';
  }
}
