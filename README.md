# POS App — Point of Sale & Inventory Management

A full-featured, offline-first Point of Sale and Inventory Management mobile application built with Flutter. Designed for small retail shops and supermarkets, it supports barcode scanning, real-time cart management with stock validation, PDF bill generation, and complete billing history.

---

### App Initial version v1.0.0. View releases tab to download the APK and try the app.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [Getting Started](#getting-started)
- [Building for Production](#building-for-production)
- [Module Breakdown](#module-breakdown)
- [State Management](#state-management)
- [PDF Generation](#pdf-generation)
- [Stock Validation Logic](#stock-validation-logic)
- [Known Limitations](#known-limitations)
- [Roadmap](#roadmap)

---

## Features

### Inventory Management
- Add, edit, and delete products
- Scan product barcodes via camera or enter manually
- Track stock quantity per product
- Visual low-stock indicators (green / orange / red dot)
- Warning badge for products with 5 or fewer units remaining

### Billing / Point of Sale
- Tap-to-open barcode scanner for fast checkout
- Auto-fetch product details from local DB on scan
- Real-time cart with quantity controls
- Stock-aware quantity limits — cart cannot exceed available stock
- `+` button auto-disables when stock limit is reached
- Live subtotal and grand total calculation
- One-tap checkout with automatic stock deduction

### Bill Generation
- Unique bill number generated per transaction (`BILL-XXXXXXXX`)
- PDF receipt rendered with item breakdown, quantities, prices, and total
- Print dialog opened automatically after checkout via system print share sheet
- Receipts are A4-formatted and suitable for digital sharing or thermal printing

### Bills History
- Full list of past bills sorted by newest first
- Tap any bill to view itemized breakdown in a bottom sheet
- Re-print or re-share any past bill as PDF
- Delete individual bills

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| State Management | Riverpod 2.x (`AsyncNotifierProvider`, `NotifierProvider`, `StateProvider`) |
| Local Database | SQLite via `sqflite` |
| Barcode Scanning | `mobile_scanner` (MLKit + CameraX) |
| PDF Generation | `pdf` + `printing` |
| Unique IDs | `uuid` v4 |
| Date Formatting | `intl` |
| Path Resolution | `path` |

### Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter
  mobile_scanner: ^6.0.0
  sqflite: ^2.3.3+1
  path: ^1.9.0
  pdf: ^3.11.1
  printing: ^5.13.1
  flutter_riverpod: ^2.5.1
  riverpod: ^2.5.1
  intl: ^0.19.0
  uuid: ^4.4.0
```

---

## Project Structure

```
lib/
├── main.dart                          # App entry, MaterialApp, MainShell, DashboardScreen
│
├── core/
│   └── database/
│       └── database_helper.dart       # SQLite singleton, all CRUD operations
│
├── models/
│   ├── product.dart                   # Product model with toMap/fromMap
│   └── bill.dart                      # Bill + BillItem models
│
├── features/
│   ├── inventory/
│   │   ├── providers/
│   │   │   └── inventory_provider.dart    # AsyncNotifier for product list
│   │   └── screens/
│   │       ├── inventory_screen.dart      # Product list with stock indicators
│   │       └── add_product_screen.dart    # Add/edit product with barcode scan
│   │
│   ├── billing/
│   │   ├── providers/
│   │   │   └── billing_provider.dart      # CartNotifier with stock validation
│   │   └── screens/
│   │       └── billing_screen.dart        # Scanner + cart + checkout
│   │
│   └── bills/
│       ├── providers/
│       │   └── bills_provider.dart        # AsyncNotifier for bill history
│       └── screens/
│           └── bills_history_screen.dart  # Bill list + detail bottom sheet
│
└── shared/
    └── services/
        └── pdf_service.dart               # PDF layout and print/share trigger
```

---

## Architecture

The app follows a **feature-first layered architecture** with clear separation between data, state, and UI.

```
┌─────────────────────────────────────┐
│              UI Layer               │
│   Screens / Widgets (ConsumerWidget)│
└────────────────┬────────────────────┘
                 │ watches / reads
┌────────────────▼────────────────────┐
│           State Layer               │
│   Riverpod Providers / Notifiers    │
└────────────────┬────────────────────┘
                 │ calls
┌────────────────▼────────────────────┐
│            Data Layer               │
│   DatabaseHelper (SQLite singleton) │
└─────────────────────────────────────┘
```

Data flows strictly downward. UI never touches the database directly — it always goes through a provider. Providers invalidate themselves after mutations, causing dependent widgets to rebuild automatically.

---

## Database Schema

### `products` table

```sql
CREATE TABLE products (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  barcode   TEXT    NOT NULL UNIQUE,
  name      TEXT    NOT NULL,
  price     REAL    NOT NULL,
  quantity  INTEGER NOT NULL DEFAULT 0
);
```

### `bills` table

```sql
CREATE TABLE bills (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  bill_number  TEXT    NOT NULL,
  items        TEXT    NOT NULL,   -- JSON-encoded list of BillItem
  total_amount REAL    NOT NULL,
  created_at   TEXT    NOT NULL    -- ISO 8601 datetime string
);
```

Bill items are stored as a JSON array inside a single `TEXT` column. This keeps the schema simple while allowing full reconstruction of itemized receipts without a separate join table.

---

## Getting Started

### Prerequisites

- Flutter SDK `>=3.0.0`
- Dart SDK `>=3.0.0`
- Android Studio or VS Code with Flutter extension
- Android device or emulator (API 21+)
- Java 17 (required by Gradle)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-username/pos_app.git
cd pos_app

# 2. Install dependencies
flutter pub get

# 3. Create env files from the example and fill in Supabase values
cp .env.example .env.dev    # set APP_ENV=dev, use a test Supabase project
cp .env.example .env.prod   # the shop's real project

# 4. Run the dev app on a connected device or emulator
flutter run --flavor dev --dart-define-from-file=.env.dev
```

### Dev and prod apps

There are two Android flavors, so both can be installed on one phone with separate data:

| Flavor | App ID | App name | Env file |
| --- | --- | --- | --- |
| `dev` | `com.example.pos_app.dev` | Urban Thread Dev (gold DEV badge) | `.env.dev` |
| `prod` | `com.example.pos_app` | Urban Thread | `.env.prod` |

Android builds now need `--flavor dev` or `--flavor prod`. Web has no flavors: pass the env file only. VS Code's Run menu has ready-made Dev and Prod launch configs.

### Android Permissions

The following permissions are required and must be present in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>
```

Camera permission is requested at runtime on first scanner open. If denied, the scanner shows an error with a Retry button.

---

## Building for Production

### Android APK

```bash
flutter build apk --release --flavor prod --dart-define-from-file=.env.prod
```

Output: `build/app/outputs/flutter-apk/app-prod-release.apk`

### Android App Bundle (for Play Store)

```bash
flutter build appbundle --release --flavor prod --dart-define-from-file=.env.prod
```

Output: `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

### Gradle Configuration (`android/app/build.gradle.kts`)

```kotlin
defaultConfig {
    applicationId = "com.example.pos_app"
    minSdk = 21
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}

buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
        isMinifyEnabled = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
```

### ProGuard Rules (`android/app/proguard-rules.pro`)

Required to prevent MLKit and CameraX classes from being stripped in release builds:

```pro
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
```

---

## Module Breakdown

### `DatabaseHelper`

Singleton accessed via `DatabaseHelper.instance`. Exposes:

| Method | Description |
|---|---|
| `insertProduct(product)` | Insert or replace a product |
| `getAllProducts()` | Fetch all products ordered by name |
| `getProductByBarcode(barcode)` | Lookup single product by barcode |
| `updateProduct(product)` | Full product update by ID |
| `updateProductQuantity(barcode, qty)` | Targeted stock update |
| `deleteProduct(id)` | Delete product by ID |
| `insertBill(bill)` | Persist a completed bill |
| `getAllBills()` | Fetch all bills newest-first |
| `deleteBill(id)` | Delete a bill by ID |

### `InventoryNotifier`

`AsyncNotifierProvider<InventoryNotifier, List<Product>>`

Loads all products on build. Exposes `addProduct`, `updateProduct`, `deleteProduct`, and `getByBarcode`. Calls `ref.invalidateSelf()` after every mutation to trigger UI rebuild.

### `CartNotifier`

`NotifierProvider<CartNotifier, List<BillItem>>`

Manages the active billing cart. Maintains an internal `_stockMap` that caches the real available stock for each product added to cart. This allows instant synchronous stock checks on quantity increment without hitting the database repeatedly.

| Method | Returns | Description |
|---|---|---|
| `addItem(product)` | `Future<bool>` | Adds item or increments; returns false if at stock limit |
| `incrementItem(barcode)` | `bool` | Increments qty; returns false if at stock limit |
| `decrementItem(barcode)` | `void` | Decrements or removes if qty reaches 0 |
| `removeItem(barcode)` | `void` | Removes item from cart entirely |
| `clearCart()` | `void` | Empties cart and stock map |
| `availableStock(barcode)` | `int` | Returns cached stock for a barcode |
| `inCartQty(barcode)` | `int` | Returns current cart quantity for a barcode |

### `BillsNotifier`

`AsyncNotifierProvider<BillsNotifier, List<Bill>>`

Loads all bills on build. Exposes `deleteBill` and `refresh`.

---

## State Management

The app uses Riverpod 2.x throughout. The nav tab index is managed by a `StateProvider<int>` at the app root, allowing any widget in the tree to switch tabs without `setState` or `InheritedWidget`.

```dart
// Defined in main.dart
final navIndexProvider = StateProvider<int>((ref) => 0);

// Used anywhere in the tree
ref.read(navIndexProvider.notifier).state = 2; // switch to Billing tab
```

Provider invalidation pattern — after any DB write, the notifier calls `ref.invalidateSelf()`, which marks the async state as loading and re-runs `build()`, fetching fresh data from SQLite and pushing it to all watching widgets.

---

## PDF Generation

Bills are rendered using the `pdf` package and opened via `printing`'s `Printing.layoutPdf()`, which opens the native system print/share dialog. The layout is A4 with:

- Shop name header
- Bill number and timestamp
- Columnar item table (name, qty, unit price, subtotal)
- Grand total
- Thank you footer

The same `PdfService.generateAndOpenBill(bill)` method is called both immediately after checkout and from the Bills History screen for reprints.

---

## Stock Validation Logic

Stock enforcement happens at two levels:

**Level 1 — Scan (async):** When a barcode is scanned during billing, `addItem()` re-fetches the product from SQLite to get the current stock, then checks how many units are already in the cart. If `inCart >= stock`, it returns `false` and a toast is shown instead of adding the item.

**Level 2 — Manual increment (sync):** The `+` button in the cart card calls `incrementItem()`, which checks `_stockMap` synchronously. If at the limit, it returns `false`, the button is visually disabled (greyed out), and a toast explains why.

**Level 3 — UI:** The cart item card shows `Stock: X | In cart: Y` and disables the `+` button at the widget level when `inCart >= stock`, preventing any tap event from firing.

This three-layer approach ensures stock can never go negative regardless of how the user interacts with the cart.

---

## Known Limitations

- **Single device only** — data is stored locally in SQLite with no sync. Two devices cannot share inventory.
- **No user authentication** — any person with the app installed has full access.
- **No tax or discount support** — prices are flat with no GST/VAT calculation.
- **No product images** — products are identified by name and barcode only.
- **Thermal printer support** — PDF printing works via the system dialog; direct Bluetooth thermal printer support is not yet implemented.
- **No categories** — all products are in a single flat list.

---

## Roadmap

- [ ] Cloud sync via PocketBase (self-hosted) for multi-device support
- [ ] Tax / GST configuration per product or globally
- [ ] Discount support (flat or percentage per bill)
- [ ] Product categories and search/filter in inventory
- [ ] Bluetooth thermal printer direct integration (`blue_thermal_printer`)
- [ ] Daily / weekly sales reports with charts
- [ ] Barcode label printing for unlabelled products
- [ ] Multi-user support with cashier PIN login
- [ ] Low stock alerts / push notifications
- [ ] CSV export of inventory and bills

---

## License

MIT License. Free to use, modify, and distribute.