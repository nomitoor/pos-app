import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/product.dart';
import '../../models/bill.dart';
import '../../models/sale_return.dart';
import '../../models/promotion.dart';
import '../../models/customer.dart';
import '../../models/expense.dart';
import '../../models/held_bill.dart';
import '../../models/day_close.dart';
import '../../models/design.dart';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // One shared open-and-migrate step. Screens request the database in
  // parallel at startup; without this, each would run _ensureSchema at the
  // same time and race to add the same column. Also covers a connection
  // opened before a hot reload (_database survives, this resets to null).
  static Future<Database>? _ready;

  Future<Database> get database => _ready ??= _openAndMigrate();

  Future<Database> _openAndMigrate() async {
    try {
      final db = _database ?? await _initDB('pos_app.db');
      await _ensureSchema(db);
      _database = db;
      return db;
    } catch (_) {
      _ready = null; // let the next call retry
      rethrow;
    }
  }

  Future<Database> _initDB(String fileName) async {
    // getDatabasesPath() isn't implemented by the web database factory.
    final path = kIsWeb ? fileName : join(await getDatabasesPath(), fileName);
    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // Columns added after the original schema. _ensureSchema adds any that are
  // missing, regardless of the database's recorded version, so a new column
  // only needs listing here (and in _createDB).
  static const Map<String, Map<String, String>> _addedColumns = {
    'products': {
      'size': 'TEXT',
      'type': 'TEXT',
      'cost_price': 'REAL',
      'design_id': 'INTEGER',
    },
    'bills': {
      'discount': 'REAL NOT NULL DEFAULT 0',
      'payment_method': 'TEXT',
      'customer_id': 'INTEGER',
      'customer_name': 'TEXT',
      'customer_phone': 'TEXT',
      'voided_at': 'TEXT',
      'void_reason': 'TEXT',
      'serial': 'INTEGER',
    },
  };

  // Tables added after the original schema, created if missing.
  static const Map<String, String> _addedTables = {
    'returns': '''
      CREATE TABLE IF NOT EXISTS returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_number TEXT NOT NULL,
        bill_id INTEGER,
        bill_number TEXT NOT NULL,
        items TEXT NOT NULL,
        refund_amount REAL NOT NULL,
        refund_method TEXT NOT NULL,
        reason TEXT NOT NULL,
        note TEXT,
        is_exchange INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''',
    'promotions': '''
      CREATE TABLE IF NOT EXISTS promotions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        buy_qty INTEGER NOT NULL,
        free_qty INTEGER NOT NULL DEFAULT 0,
        value REAL NOT NULL DEFAULT 0,
        scope TEXT NOT NULL,
        scope_type TEXT,
        barcodes TEXT NOT NULL DEFAULT '[]',
        starts_at TEXT,
        ends_at TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''',
    'designs': '''
      CREATE TABLE IF NOT EXISTS designs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT,
        price REAL NOT NULL,
        cost_price REAL,
        description TEXT,
        photos TEXT NOT NULL DEFAULT '[]',
        online INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''',
    'customers': '''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''',
    'customer_payments': '''
      CREATE TABLE IF NOT EXISTS customer_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        bill_id INTEGER,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''',
    'expenses': '''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_from TEXT NOT NULL,
        note TEXT,
        date TEXT NOT NULL
      )
    ''',
    'held_bills': '''
      CREATE TABLE IF NOT EXISTS held_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        items TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''',
    'day_closes': '''
      CREATE TABLE IF NOT EXISTS day_closes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        period_start TEXT NOT NULL,
        closed_at TEXT NOT NULL,
        opening_float REAL NOT NULL,
        expected_cash REAL NOT NULL,
        counted_cash REAL NOT NULL,
        float_kept REAL NOT NULL,
        note TEXT,
        summary TEXT NOT NULL
      )
    ''',
  };

  Future<void> _ensureSchema(Database db) async {
    for (final sql in _addedTables.values) {
      await db.execute(sql);
    }
    for (final table in _addedColumns.entries) {
      final existing = await _columnsOf(db, table.key);
      for (final col in table.value.entries) {
        if (!existing.contains(col.key)) {
          try {
            await db.execute(
              'ALTER TABLE ${table.key} ADD COLUMN ${col.key} ${col.value}',
            );
          } on DatabaseException catch (e) {
            // Already added by someone else: that's the state we want.
            if (!e.toString().contains('duplicate column')) rethrow;
          }
        }
      }
    }
    // Bills are read by date range and looked up by number.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS bills_created_at ON bills (created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS bills_number ON bills (bill_number)',
    );
    // Products from before variants existed become designs with sizes.
    await db.transaction(_groupUnlinkedProducts);
    // Bills from before serials existed get them, oldest first.
    await db.transaction(_fillMissingSerials);
  }

  /// Gives bills without a serial (older bills, or ones restored from an
  /// older backup) the next serials, in the order they were made.
  Future<void> _fillMissingSerials(DatabaseExecutor db) async {
    final missing = await db.query(
      'bills',
      columns: ['id'],
      where: 'serial IS NULL',
      orderBy: 'created_at, id',
    );
    if (missing.isEmpty) return;
    var serial =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(serial) FROM bills'),
        ) ??
        0;
    for (final row in missing) {
      await db.update(
        'bills',
        {'serial': ++serial},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  // ─── DESIGN LINKING ──────────────────────────────────────

  /// Id of the design for (name, type), creating it if needed.
  Future<int> _designFor(
    DatabaseExecutor db,
    Map<String, Object?> product,
  ) async {
    final name = (product['name'] as String).trim();
    final type = product['type'] as String?;
    final found = await db.query(
      'designs',
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = ? AND type IS ?',
      whereArgs: [name.toLowerCase(), type],
      limit: 1,
    );
    if (found.isNotEmpty) return found.first['id'] as int;
    return db.insert('designs', {
      'name': name,
      'type': type,
      'price': product['price'],
      'cost_price': product['cost_price'],
      'photos': '[]',
      'online': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Links products with no design to one matching their name + type.
  Future<void> _groupUnlinkedProducts(DatabaseExecutor db) async {
    final rows = await db.query('products', where: 'design_id IS NULL');
    for (final p in rows) {
      final designId = await _designFor(db, p);
      await db.update(
        'products',
        {'design_id': designId},
        where: 'id = ?',
        whereArgs: [p['id']],
      );
    }
  }

  /// After a product's name/type changed: make sure it sits in the design
  /// that matches, then drop designs left with no sizes.
  Future<void> _relinkProduct(DatabaseExecutor db, int productId) async {
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    );
    if (rows.isEmpty) return;
    final p = rows.first;
    final current = p['design_id'] as int?;
    if (current != null) {
      final d = await db.query(
        'designs',
        where: 'id = ? AND LOWER(TRIM(name)) = ? AND type IS ?',
        whereArgs: [
          current,
          (p['name'] as String).trim().toLowerCase(),
          p['type'],
        ],
      );
      if (d.isNotEmpty) return; // still matches
    }
    await db.update(
      'products',
      {'design_id': await _designFor(db, p)},
      where: 'id = ?',
      whereArgs: [productId],
    );
    await _deleteEmptyDesigns(db);
  }

  Future<void> _deleteEmptyDesigns(DatabaseExecutor db) => db.rawDelete(
    'DELETE FROM designs WHERE id NOT IN '
    '(SELECT DISTINCT design_id FROM products WHERE design_id IS NOT NULL)',
  );

  Future<Set<String>> _columnsOf(DatabaseExecutor db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((c) => c['name'] as String).toSet();
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Recreate products table to add the quantity >= 0 check constraint.
      await db.execute('ALTER TABLE products RENAME TO products_old');
      await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0)
        )
      ''');
      await db.execute('''
        INSERT INTO products (id, barcode, name, price, quantity)
        SELECT id, barcode, name, price, MAX(quantity, 0) FROM products_old
      ''');
      await db.execute('DROP TABLE products_old');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    // Later columns (size, type, cost_price, discount, ...) are added by
    // _ensureSchema.
  }

  Future _createDB(Database db, int version) async {
    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
        size TEXT,
        type TEXT,
        cost_price REAL
      )
    ''');

    // Bills table
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_number TEXT NOT NULL,
        items TEXT NOT NULL,
        total_amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        payment_method TEXT
      )
    ''');

    // Later tables (returns, ...)
    for (final sql in _addedTables.values) {
      await db.execute(sql);
    }

    // Settings table (key-value, used for shop/invoice template details)
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ─── PRODUCT CRUD ───────────────────────────────────────

  // Fails (rather than silently replacing) if the barcode already exists.
  /// Also links the product to its design (created if needed).
  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      final id = await txn.insert(
        'products',
        product.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _relinkProduct(txn, id);
      return id;
    });
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final result = await db.query('products', orderBy: 'name ASC');
    return result.map((e) => Product.fromMap(e)).toList();
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Product.fromMap(result.first);
  }

  /// If the name or type changed, the product moves to the matching design.
  Future<int> updateProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      final map = product.toMap();
      if (product.designId == null) map.remove('design_id'); // keep link
      final n = await txn.update(
        'products',
        map,
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await _relinkProduct(txn, product.id!);
      return n;
    });
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final n = await txn.delete('products', where: 'id = ?', whereArgs: [id]);
      await _deleteEmptyDesigns(txn);
      return n;
    });
  }

  // ─── DESIGNS (products with sizes) ──────────────────────

  Future<List<Design>> getDesigns() async {
    final db = await database;
    final rows = await db.query('designs', orderBy: 'name COLLATE NOCASE');
    return rows.map(Design.fromMap).toList();
  }

  /// Saves a design and its sizes in one go. Sizes with an id are updated,
  /// new ones inserted; shared details (name, type, cost) are copied onto
  /// every size. Sizes in [removeIds] are deleted. Throws if a barcode is
  /// already used by another product. Returns the design id.
  Future<int> saveDesign(
    Design d,
    List<Product> sizes, {
    List<int> removeIds = const [],
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final map = d.toMap()..remove('id');
      final id = d.id ?? await txn.insert('designs', map);
      if (d.id != null) {
        await txn.update('designs', map, where: 'id = ?', whereArgs: [id]);
      }
      for (final rid in removeIds) {
        await txn.delete('products', where: 'id = ?', whereArgs: [rid]);
      }
      for (final s in sizes) {
        final row = s
            .copyWith(
              designId: id,
              name: d.name,
              type: d.type,
              costPrice: d.costPrice,
            )
            .toMap();
        // copyWith can't clear values, so set type/cost explicitly.
        row['type'] = d.type;
        row['cost_price'] = d.costPrice;
        if (s.id == null) {
          row.remove('id');
          await txn.insert(
            'products',
            row,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          await txn.update('products', row, where: 'id = ?', whereArgs: [s.id]);
        }
      }
      return id;
    });
  }

  /// Updates only the design's own row (e.g. photos, online switch).
  Future<void> updateDesign(Design d) async {
    final db = await database;
    await db.update(
      'designs',
      d.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [d.id],
    );
  }

  /// Deletes a design and all its sizes. Past bills keep their lines.
  Future<void> deleteDesign(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('products', where: 'design_id = ?', whereArgs: [id]);
      await txn.delete('designs', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Quick stock correction (e.g. +1 / −1 on the design screen).
  Future<void> adjustStock(int productId, int delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE products SET quantity = MAX(quantity + ?, 0) WHERE id = ?',
      [delta, productId],
    );
  }

  // ─── BILL CRUD ───────────────────────────────────────────

  /// Throws a [StateError] the cashier can act on if any line needs more
  /// stock than is on the shelf (or the product was deleted). [extra] maps
  /// barcode → additional units needed.
  Future<void> _ensureStock(
    DatabaseExecutor txn,
    Map<String, int> extra,
    Map<String, String> names,
  ) async {
    for (final e in extra.entries) {
      if (e.value <= 0) continue;
      final rows = await txn.query(
        'products',
        columns: ['quantity'],
        where: 'barcode = ?',
        whereArgs: [e.key],
      );
      final name = names[e.key] ?? e.key;
      if (rows.isEmpty) {
        throw StateError(
          '"$name" is no longer in your stock list. '
          'Remove it from the bill.',
        );
      }
      final left = rows.first['quantity'] as int;
      if (left < e.value) {
        throw StateError(
          left == 0
              ? '"$name" is out of stock.'
              : 'Only $left of "$name" left in stock.',
        );
      }
    }
  }

  static String _lineName(BillItem i) =>
      i.size == null ? i.name : '${i.name} (${i.size})';

  /// A new unpredictable invoice number that no bill has used yet.
  Future<String> _newBillNumber(DatabaseExecutor txn) async {
    while (true) {
      final number = Bill.randomNumber();
      final taken = await txn.query(
        'bills',
        columns: ['id'],
        where: 'bill_number = ?',
        whereArgs: [number],
        limit: 1,
      );
      if (taken.isEmpty) return number;
    }
  }

  /// Next internal serial (1, 2, 3, …).
  Future<int> _nextSerial(DatabaseExecutor txn) async =>
      (Sqflite.firstIntValue(
            await txn.rawQuery('SELECT MAX(serial) FROM bills'),
          ) ??
          0) +
      1;

  /// When the last day close happened, or null if never. Bills from before
  /// then are part of a closed report and can't be edited or voided.
  Future<DateTime?> lastDayCloseAt([DatabaseExecutor? db]) async {
    final ex = db ?? await database;
    final rows = await ex.query(
      'day_closes',
      columns: ['closed_at'],
      orderBy: 'closed_at DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.first['closed_at'] as String);
  }

  /// Whether [bill] belongs to a day that has already been closed.
  Future<bool> isInClosedDay(Bill bill) async {
    final closed = await lastDayCloseAt();
    return closed != null && !bill.createdAt.isAfter(closed);
  }

  Future<void> _ensureChangeable(DatabaseExecutor txn, Bill bill) async {
    final row = await txn.query(
      'bills',
      columns: ['voided_at'],
      where: 'id = ?',
      whereArgs: [bill.id],
    );
    if (row.isEmpty) throw StateError('This bill no longer exists.');
    if (row.first['voided_at'] != null) {
      throw StateError('This bill has been voided.');
    }
    final closed = await lastDayCloseAt(txn);
    if (closed != null && !bill.createdAt.isAfter(closed)) {
      throw StateError(
        'This bill is from a day that has been closed, so it '
        "can't be changed. Use Return instead.",
      );
    }
  }

  /// Saves the bill and deducts stock, atomically. Checks every line has
  /// enough stock first. A bill with an empty [Bill.billNumber] gets a new
  /// unpredictable INV- number; every bill gets the next internal serial.
  /// For an udhaar bill, [paidNow] (cash handed over at
  /// the counter) is recorded as a customer payment against it.
  /// Returns the saved bill (with its id and number).
  Future<Bill> checkout(Bill bill, {double paidNow = 0}) async {
    final db = await database;
    return db.transaction((txn) async {
      if (bill.isUdhaar && bill.customerId == null) {
        throw StateError('Choose a customer for an udhaar sale.');
      }
      final need = <String, int>{};
      for (final i in bill.items) {
        need[i.barcode] = (need[i.barcode] ?? 0) + i.quantity;
      }
      await _ensureStock(txn, need, {
        for (final i in bill.items) i.barcode: _lineName(i),
      });

      final number = bill.billNumber.trim().isEmpty
          ? await _newBillNumber(txn)
          : bill.billNumber;
      final serial = await _nextSerial(txn);
      final map = {
        'bill_number': number,
        'serial': serial,
        'items': jsonEncode(bill.items.map((e) => e.toMap()).toList()),
        'total_amount': bill.totalAmount,
        'created_at': bill.createdAt.toIso8601String(),
        'discount': bill.discount,
        'payment_method': bill.paymentMethod,
        'customer_id': bill.customerId,
        'customer_name': bill.customerName,
        'customer_phone': bill.customerPhone,
      };
      final billId = await txn.insert('bills', map);

      if (bill.isUdhaar && paidNow > 0) {
        await txn.insert(
          'customer_payments',
          CustomerPayment(
            customerId: bill.customerId!,
            billId: billId,
            amount: paidNow > bill.totalAmount ? bill.totalAmount : paidNow,
            method: Bill.cash,
            note: 'Paid at checkout ($number)',
            createdAt: bill.createdAt,
          ).toMap()..remove('id'),
        );
      }

      for (final item in bill.items) {
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity - ? WHERE barcode = ?',
          [item.quantity, item.barcode],
        );
      }
      return bill.copyWith(id: billId, billNumber: number, serial: serial);
    });
  }

  // Replaces a bill's items/total and reconciles stock for the delta,
  // atomically. Throws (with a message for the cashier) if a quantity
  // increase exceeds available stock, if the bill has returns, is voided,
  // or belongs to a closed day.
  Future<void> updateBill(Bill oldBill, List<BillItem> newItems) async {
    final db = await database;
    await db.transaction((txn) async {
      await _ensureChangeable(txn, oldBill);
      if ((await _returnedQty(txn, oldBill.id!)).isNotEmpty) {
        throw StateError(
          'This bill has returns, so it can no longer be edited.',
        );
      }
      final oldQty = <String, int>{};
      for (final i in oldBill.items) {
        oldQty[i.barcode] = (oldQty[i.barcode] ?? 0) + i.quantity;
      }
      final newQty = <String, int>{};
      for (final i in newItems) {
        newQty[i.barcode] = (newQty[i.barcode] ?? 0) + i.quantity;
      }
      await _ensureStock(
        txn,
        {
          for (final b in newQty.keys)
            b: newQty[b]! - (oldQty[b] ?? 0), // extra units needed
        },
        {for (final i in newItems) i.barcode: _lineName(i)},
      );

      for (final barcode in {...oldQty.keys, ...newQty.keys}) {
        final delta = (oldQty[barcode] ?? 0) - (newQty[barcode] ?? 0);
        if (delta != 0) {
          await txn.rawUpdate(
            'UPDATE products SET quantity = quantity + ? WHERE barcode = ?',
            [delta, barcode],
          );
        }
      }

      // Keep the bill's discount, but never more than the new subtotal.
      final newSubtotal = newItems.fold<double>(
        0,
        (sum, i) => sum + i.subtotal,
      );
      final discount = oldBill.discount > newSubtotal
          ? newSubtotal
          : oldBill.discount;
      await txn.update(
        'bills',
        {
          'items': jsonEncode(newItems.map((e) => e.toMap()).toList()),
          'total_amount': newSubtotal - discount,
          'discount': discount,
        },
        where: 'id = ?',
        whereArgs: [oldBill.id],
      );
    });
  }

  static Bill _billFromRow(Map<String, Object?> e) {
    final itemsJson = jsonDecode(e['items'] as String) as List;
    return Bill(
      id: e['id'] as int,
      billNumber: e['bill_number'] as String,
      items: itemsJson.map((i) => BillItem.fromMap(i)).toList(),
      totalAmount: (e['total_amount'] as num).toDouble(),
      createdAt: DateTime.parse(e['created_at'] as String),
      discount: (e['discount'] as num?)?.toDouble() ?? 0,
      paymentMethod: e['payment_method'] as String?,
      customerId: e['customer_id'] as int?,
      customerName: e['customer_name'] as String?,
      customerPhone: e['customer_phone'] as String?,
      voidedAt: e['voided_at'] == null
          ? null
          : DateTime.parse(e['voided_at'] as String),
      voidReason: e['void_reason'] as String?,
      serial: e['serial'] as int?,
    );
  }

  /// Bills, newest first. Only loads what's asked for, so screens stay
  /// fast as history grows:
  /// - [from] / [to]: created in that range (inclusive / exclusive).
  /// - [includeVoided]: voided bills are left out unless asked for, so
  ///   sales, stock and udhaar figures never count them.
  /// - [withCustomer]: only bills that have a customer (for accounts).
  /// - [search]: rough text match on number, items, customer, method or
  ///   amount (callers refine it with `billMatches`).
  Future<List<Bill>> getBills({
    DateTime? from,
    DateTime? to,
    bool includeVoided = false,
    bool withCustomer = false,
    String? search,
    int? limit,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('created_at < ?');
      args.add(to.toIso8601String());
    }
    if (!includeVoided) where.add('voided_at IS NULL');
    if (withCustomer) where.add('customer_id IS NOT NULL');
    final q = search?.trim().toLowerCase() ?? '';
    if (q.isNotEmpty) {
      where.add(
        '(LOWER(bill_number) LIKE ? OR LOWER(items) LIKE ? OR '
        'LOWER(customer_name) LIKE ? OR LOWER(payment_method) LIKE ? OR '
        'CAST(CAST(total_amount AS INTEGER) AS TEXT) LIKE ?)',
      );
      args.addAll(List.filled(5, '%$q%'));
    }
    final rows = await db.query(
      'bills',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_billFromRow).toList();
  }

  /// Every bill that counts (voided ones left out). Prefer [getBills] with
  /// a date range in screens.
  Future<List<Bill>> getAllBills() => getBills();

  /// Number of bills that count (voided ones left out).
  Future<int> countBills() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM bills WHERE voided_at IS NULL',
          ),
        ) ??
        0;
  }

  /// The bill with this number (any case/spacing), voided ones included.
  /// If a number was reused after a void (an online order accepted again),
  /// the live bill wins.
  Future<Bill?> getBillByNumber(String number) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      // Ignore case, spaces and dashes, as people type them differently.
      where: "REPLACE(REPLACE(UPPER(bill_number), '-', ''), ' ', '') = ?",
      whereArgs: [Bill.normalizeNumber(number)],
      orderBy: '(voided_at IS NULL) DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _billFromRow(rows.first);
  }

  Future<Bill?> getBillById(int id) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _billFromRow(rows.first);
  }

  /// Voids (cancels) a bill instead of deleting it: its items go back into
  /// stock, an udhaar bill's paid-at-checkout cash is removed with it, and
  /// it stops counting in sales and balances. The bill itself stays in
  /// history, marked voided with [reason].
  ///
  /// Not allowed for a bill from a closed day, or one with returns: those
  /// are already in a saved report / refund, so use Return instead.
  Future<void> voidBill(Bill bill, String reason) async {
    if (reason.trim().isEmpty) throw StateError('Give a reason for voiding.');
    final db = await database;
    await db.transaction((txn) async {
      await _ensureChangeable(txn, bill);
      if ((await _returnedQty(txn, bill.id!)).isNotEmpty) {
        throw StateError(
          'This bill has returns, so it can no longer be '
          'voided. Return the remaining items instead.',
        );
      }
      for (final item in bill.items) {
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ? WHERE barcode = ?',
          [item.quantity, item.barcode],
        );
      }
      // Cash taken at checkout for this (udhaar) bill is handed back.
      await txn.delete(
        'customer_payments',
        where: 'bill_id = ?',
        whereArgs: [bill.id],
      );
      await txn.update(
        'bills',
        {
          'voided_at': DateTime.now().toIso8601String(),
          'void_reason': reason.trim(),
        },
        where: 'id = ?',
        whereArgs: [bill.id],
      );
    });
  }

  // ─── CUSTOMERS & UDHAAR ──────────────────────────────────

  Future<List<Customer>> getCustomers() async {
    final db = await database;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Customer.fromMap).toList();
  }

  /// Inserts or updates; returns the customer's id.
  Future<int> saveCustomer(Customer c) async {
    final db = await database;
    final map = c.toMap()..remove('id');
    if (c.id == null) return db.insert('customers', map);
    await db.update('customers', map, where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  /// Refuses to delete a customer who has bills or payments, so udhaar
  /// history can't be lost by accident.
  Future<void> deleteCustomer(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final used =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT (SELECT COUNT(*) FROM bills WHERE customer_id = ? '
              'AND voided_at IS NULL) + '
              '(SELECT COUNT(*) FROM customer_payments WHERE customer_id = ?)',
              [id, id],
            ),
          ) ??
          0;
      if (used > 0) {
        throw StateError(
          'This customer has bills or payments and cannot be deleted.',
        );
      }
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<CustomerPayment>> getCustomerPayments() async {
    final db = await database;
    final rows = await db.query(
      'customer_payments',
      orderBy: 'created_at DESC',
    );
    return rows.map(CustomerPayment.fromMap).toList();
  }

  Future<void> addCustomerPayment(CustomerPayment p) async {
    final db = await database;
    await db.insert('customer_payments', p.toMap()..remove('id'));
  }

  Future<void> deleteCustomerPayment(int id) async {
    final db = await database;
    await db.delete('customer_payments', where: 'id = ?', whereArgs: [id]);
  }

  // ─── EXPENSES ────────────────────────────────────────────

  Future<List<Expense>> getExpenses() async {
    final db = await database;
    final rows = await db.query('expenses', orderBy: 'date DESC');
    return rows.map(Expense.fromMap).toList();
  }

  Future<void> saveExpense(Expense e) async {
    final db = await database;
    final map = e.toMap()..remove('id');
    if (e.id == null) {
      await db.insert('expenses', map);
    } else {
      await db.update('expenses', map, where: 'id = ?', whereArgs: [e.id]);
    }
  }

  Future<void> deleteExpense(int id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ─── HELD BILLS ──────────────────────────────────────────

  Future<List<HeldBill>> getHeldBills() async {
    final db = await database;
    final rows = await db.query('held_bills', orderBy: 'created_at DESC');
    return rows.map(HeldBill.fromMap).toList();
  }

  Future<void> holdBill(HeldBill h) async {
    final db = await database;
    await db.insert('held_bills', h.toMap()..remove('id'));
  }

  Future<void> deleteHeldBill(int id) async {
    final db = await database;
    await db.delete('held_bills', where: 'id = ?', whereArgs: [id]);
  }

  // ─── DAY CLOSE ───────────────────────────────────────────

  Future<List<DayClose>> getDayCloses() async {
    final db = await database;
    final rows = await db.query('day_closes', orderBy: 'closed_at DESC');
    return rows.map(DayClose.fromMap).toList();
  }

  Future<void> saveDayClose(DayClose d) async {
    final db = await database;
    await db.insert('day_closes', d.toMap()..remove('id'));
  }

  // ─── PROMOTIONS ──────────────────────────────────────────

  Future<List<Promotion>> getPromotions() async {
    final db = await database;
    final rows = await db.query('promotions', orderBy: 'active DESC, id DESC');
    return rows.map(Promotion.fromMap).toList();
  }

  Future<void> savePromotion(Promotion p) async {
    final db = await database;
    final map = p.toMap()..remove('id');
    if (p.id == null) {
      await db.insert('promotions', map);
    } else {
      await db.update('promotions', map, where: 'id = ?', whereArgs: [p.id]);
    }
  }

  Future<void> deletePromotion(int id) async {
    final db = await database;
    await db.delete('promotions', where: 'id = ?', whereArgs: [id]);
  }

  // ─── RETURNS ─────────────────────────────────────────────

  /// Quantity already returned per barcode for a bill.
  Future<Map<String, int>> _returnedQty(DatabaseExecutor db, int billId) async {
    final rows = await db.query(
      'returns',
      columns: ['items'],
      where: 'bill_id = ?',
      whereArgs: [billId],
    );
    final out = <String, int>{};
    for (final r in rows) {
      for (final i in jsonDecode(r['items'] as String) as List) {
        final item = ReturnItem.fromMap(i as Map<String, dynamic>);
        out[item.barcode] = (out[item.barcode] ?? 0) + item.quantity;
      }
    }
    return out;
  }

  Future<Map<String, int>> returnedQtyForBill(int billId) async =>
      _returnedQty(await database, billId);

  /// Saves a return and puts restocked items back into stock, atomically.
  /// Throws [StateError] if any item would be returned more times than it
  /// was sold on [bill].
  Future<void> insertReturn(Bill bill, SaleReturn ret) async {
    final db = await database;
    await db.transaction((txn) async {
      final sold = <String, int>{};
      for (final i in bill.items) {
        sold[i.barcode] = (sold[i.barcode] ?? 0) + i.quantity;
      }
      final already = await _returnedQty(txn, bill.id!);
      final requested = <String, int>{};
      for (final i in ret.items) {
        if (i.quantity <= 0) throw StateError('Invalid return quantity.');
        requested[i.barcode] = (requested[i.barcode] ?? 0) + i.quantity;
      }
      for (final i in ret.items) {
        final left = (sold[i.barcode] ?? 0) - (already[i.barcode] ?? 0);
        if (requested[i.barcode]! > left) {
          throw StateError(
            'Only $left of "${i.name}" can still be returned on this bill.',
          );
        }
      }

      await txn.insert('returns', {
        'return_number': ret.returnNumber,
        'bill_id': ret.billId,
        'bill_number': ret.billNumber,
        'items': jsonEncode(ret.items.map((e) => e.toMap()).toList()),
        'refund_amount': ret.refundAmount,
        'refund_method': ret.refundMethod,
        'reason': ret.reason,
        'note': ret.note,
        'is_exchange': ret.isExchange ? 1 : 0,
        'created_at': ret.createdAt.toIso8601String(),
      });

      for (final i in ret.items.where((i) => i.restocked)) {
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ? WHERE barcode = ?',
          [i.quantity, i.barcode],
        );
      }
    });
  }

  Future<List<SaleReturn>> getAllReturns() async {
    final db = await database;
    final rows = await db.query('returns', orderBy: 'created_at DESC');
    return rows.map((r) {
      final items = (jsonDecode(r['items'] as String) as List)
          .map((i) => ReturnItem.fromMap(i as Map<String, dynamic>))
          .toList();
      return SaleReturn(
        id: r['id'] as int,
        returnNumber: r['return_number'] as String,
        billId: r['bill_id'] as int?,
        billNumber: r['bill_number'] as String,
        items: items,
        reason: r['reason'] as String,
        note: r['note'] as String?,
        refundMethod: r['refund_method'] as String,
        isExchange: (r['is_exchange'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  // ─── SETTINGS (key-value) ─────────────────────────────────

  Future<Map<String, String>> getSettings() async {
    final db = await database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> saveSettings(Map<String, String> values) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in values.entries) {
      batch.insert('settings', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ─── BACKUP / RESTORE ─────────────────────────────────────

  static const backupFormat = 'pos_app_backup';

  Future<List<String>> _userTables(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Every row of every table, as a JSON-encodable map.
  Future<Map<String, dynamic>> exportAll() async {
    final db = await database;
    final tables = <String, dynamic>{};
    for (final t in await _userTables(db)) {
      tables[t] = await db.query(t);
    }
    return {
      'format': backupFormat,
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// Replaces all data with [backup] (from [exportAll]) in one transaction;
  /// nothing changes if it fails. Tables or columns in the backup that this
  /// version of the app doesn't have are skipped.
  Future<void> restoreAll(Map<String, dynamic> backup) async {
    if (backup['format'] != backupFormat || backup['tables'] is! Map) {
      throw const FormatException('Not a POS app backup file');
    }
    final tables = (backup['tables'] as Map).cast<String, dynamic>();
    final db = await database;
    await db.transaction((txn) async {
      final existing = await _userTables(txn);
      for (final t in existing) {
        // Clear every table, even ones an older backup doesn't have, so no
        // current records (e.g. returns) are left pointing at old data.
        await txn.delete(t);
        if (!tables.containsKey(t)) continue;
        final cols = await _columnsOf(txn, t);
        for (final row in (tables[t] as List).cast<Map>()) {
          final filtered = {
            for (final e in row.entries)
              if (cols.contains(e.key)) e.key as String: e.value,
          };
          await txn.insert(t, filtered);
        }
      }
      // Backups from before variants: group their products into designs.
      await _groupUnlinkedProducts(txn);
      // Backups from before serials: number their bills.
      await _fillMissingSerials(txn);
    });
  }
}
