import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// All on-device storage. No server: data lives in a local SQLite file.
///
/// Invariants that every query below respects:
///  * Archived rows are excluded from lists, totals, reports, balances,
///    the widget and exports, unless a query explicitly asks for archived.
///  * Archived SMS rows are never deleted, so their `sms_key` keeps the
///    same SMS from being imported again on the next refresh.
///  * SMS rows can only be archived, never deleted. Manual rows can be deleted.
class Repository {
  Repository(this.db);
  final Database db;

  static Future<Repository> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'expense_tracker.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tags(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE,
            color INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE txns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL CHECK(source IN ('sms','manual')),
            type TEXT NOT NULL CHECK(type IN ('debit','credit')),
            amount INTEGER NOT NULL CHECK(amount > 0),
            occurred_at INTEGER NOT NULL,
            bank TEXT,
            account TEXT,
            account_kind TEXT,
            counterparty TEXT,
            balance INTEGER,
            tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL,
            note TEXT NOT NULL DEFAULT '',
            archived INTEGER NOT NULL DEFAULT 0,
            archived_at INTEGER,
            sms_key TEXT UNIQUE,
            sms_sender TEXT,
            sms_body TEXT,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_txns_time ON txns(archived, occurred_at)');
        await db.execute('CREATE INDEX idx_txns_tag ON txns(tag_id)');
      },
    );
    return Repository(db);
  }

  // ---------------------------------------------------------------- filters

  (String, List<Object?>) _where(TxnFilter f) {
    final w = <String>['archived = ?'];
    final a = <Object?>[f.archived ? 1 : 0];
    if (f.start != null) {
      w.add('occurred_at >= ?');
      a.add(f.start!.millisecondsSinceEpoch);
    }
    if (f.end != null) {
      w.add('occurred_at < ?');
      a.add(f.end!.millisecondsSinceEpoch);
    }
    if (f.type != null) {
      w.add('type = ?');
      a.add(f.type!.name);
    }
    if (f.source != null) {
      w.add('source = ?');
      a.add(f.source!.name);
    }
    if (f.bank != null) {
      w.add('bank = ?');
      a.add(f.bank);
    }
    if (f.untaggedOnly) {
      w.add('tag_id IS NULL');
    } else if (f.tagId != null) {
      w.add('tag_id = ?');
      a.add(f.tagId);
    }
    final q = f.search.trim();
    if (q.isNotEmpty) {
      w.add("(counterparty LIKE ? ESCAPE '\\' OR note LIKE ? ESCAPE '\\' "
          "OR bank LIKE ? ESCAPE '\\' OR sms_body LIKE ? ESCAPE '\\')");
      final like = '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      a.addAll([like, like, like, like]);
    }
    return (w.join(' AND '), a);
  }

  // ------------------------------------------------------------------ reads

  Future<List<Txn>> query(TxnFilter f, {int? limit}) async {
    final (where, args) = _where(f);
    final rows = await db.query('txns',
        where: where,
        whereArgs: args,
        orderBy: f.archived ? 'archived_at DESC, occurred_at DESC' : 'occurred_at DESC, id DESC',
        limit: limit);
    return rows.map(Txn.fromRow).toList();
  }

  Future<Txn?> byId(int id) async {
    final rows = await db.query('txns', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Txn.fromRow(rows.first);
  }

  Future<Totals> totals(TxnFilter f) async {
    final (where, args) = _where(f);
    final r = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type='debit' THEN amount END), 0) AS d,
        COALESCE(SUM(CASE WHEN type='credit' THEN amount END), 0) AS c,
        COUNT(*) AS n
      FROM txns WHERE $where''', args)).first;
    return Totals(debit: r['d'] as int, credit: r['c'] as int, count: r['n'] as int);
  }

  /// Per-tag totals for one direction. Tag rows + "No tag" sum to the total.
  Future<List<TagTotal>> totalsByTag(TxnFilter f) async {
    final (where, args) = _where(f);
    final rows = await db.rawQuery('''
      SELECT tag_id, SUM(amount) AS s, COUNT(*) AS n
      FROM txns WHERE $where GROUP BY tag_id ORDER BY s DESC''', args);
    return rows
        .map((r) => TagTotal(r['tag_id'] as int?, r['s'] as int, r['n'] as int))
        .toList();
  }

  /// Latest bank-reported balance per account (from non-archived SMS).
  Future<List<AccountBalance>> latestBalances() async {
    final rows = await db.rawQuery('''
      SELECT t.bank, t.account, t.account_kind, t.balance, t.occurred_at
      FROM txns t
      WHERE t.archived = 0 AND t.balance IS NOT NULL AND t.id = (
        SELECT t2.id FROM txns t2
        WHERE t2.archived = 0 AND t2.balance IS NOT NULL
          AND t2.bank IS t.bank AND t2.account IS t.account
        ORDER BY t2.occurred_at DESC, t2.id DESC LIMIT 1)
      ORDER BY t.occurred_at DESC''');
    return rows
        .map((r) => AccountBalance(
              r['bank'] as String?,
              r['account'] as String?,
              r['account_kind'] == null
                  ? null
                  : AccountKind.values.firstWhere((k) => k.name == r['account_kind'],
                      orElse: () => AccountKind.bank),
              r['balance'] as int,
              DateTime.fromMillisecondsSinceEpoch(r['occurred_at'] as int),
            ))
        .toList();
  }

  Future<List<String>> banks() async {
    final rows = await db.rawQuery(
        'SELECT DISTINCT bank FROM txns WHERE archived = 0 AND bank IS NOT NULL ORDER BY bank');
    return rows.map((r) => r['bank'] as String).toList();
  }

  Future<int> count(TxnFilter f) async => (await totals(f)).count;

  // ----------------------------------------------------------------- writes

  /// Inserts SMS transactions, skipping any SMS seen before (including
  /// archived ones). Returns the number actually inserted.
  Future<int> insertSmsTxns(List<Txn> txns) async {
    if (txns.isEmpty) return 0;
    var inserted = 0;
    await db.transaction((tx) async {
      for (final t in txns) {
        final id = await tx.insert('txns', t.toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id > 0) inserted++;
      }
    });
    return inserted;
  }

  Future<Set<String>> existingSmsKeys(Iterable<String> keys) async {
    final list = keys.toList();
    final out = <String>{};
    const chunk = 500;
    for (var i = 0; i < list.length; i += chunk) {
      final part = list.sublist(i, i + chunk > list.length ? list.length : i + chunk);
      final rows = await db.query('txns',
          columns: ['sms_key'],
          where: 'sms_key IN (${List.filled(part.length, '?').join(',')})',
          whereArgs: part);
      out.addAll(rows.map((r) => r['sms_key'] as String));
    }
    return out;
  }

  Future<int> insertManual(Txn t) => db.insert('txns', t.toRow());

  Future<void> updateManual(Txn t) => db.update(
        'txns',
        {
          'type': t.type.name,
          'amount': t.amount,
          'occurred_at': t.occurredAt.millisecondsSinceEpoch,
          'bank': t.bank,
          'counterparty': t.counterparty,
          'tag_id': t.tagId,
          'note': t.note,
        },
        where: "id = ? AND source = 'manual'",
        whereArgs: [t.id],
      );

  /// Permanently deletes manual entries only. SMS rows are ignored here.
  Future<int> deleteManual(List<int> ids) => db.delete('txns',
      where: "source = 'manual' AND id IN (${List.filled(ids.length, '?').join(',')})",
      whereArgs: ids);

  Future<void> setTag(List<int> ids, int? tagId) => db.update('txns', {'tag_id': tagId},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);

  Future<void> setNote(int id, String note) =>
      db.update('txns', {'note': note}, where: 'id = ?', whereArgs: [id]);

  Future<int> setArchived(List<int> ids, bool archived) => db.update(
        'txns',
        {
          'archived': archived ? 1 : 0,
          'archived_at': archived ? DateTime.now().millisecondsSinceEpoch : null,
        },
        where: 'archived = ? AND id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: [archived ? 0 : 1, ...ids],
      );

  /// Archives every visible transaction in [start, end).
  Future<int> archiveRange(DateTime start, DateTime end) => db.update(
        'txns',
        {'archived': 1, 'archived_at': DateTime.now().millisecondsSinceEpoch},
        where: 'archived = 0 AND occurred_at >= ? AND occurred_at < ?',
        whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      );

  // ------------------------------------------------------------------- tags

  Future<List<Tag>> tags() async =>
      (await db.query('tags', orderBy: 'name COLLATE NOCASE')).map(Tag.fromRow).toList();

  Future<int> insertTag(Tag t) => db.insert('tags', t.toRow());

  Future<void> updateTag(Tag t) =>
      db.update('tags', t.toRow(), where: 'id = ?', whereArgs: [t.id]);

  /// Deletes a tag; its transactions (archived too) become untagged.
  Future<void> deleteTag(int id) => db.transaction((tx) async {
        await tx.update('txns', {'tag_id': null}, where: 'tag_id = ?', whereArgs: [id]);
        await tx.delete('tags', where: 'id = ?', whereArgs: [id]);
      });

  Future<int> tagUsage(int id) async => Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM txns WHERE tag_id = ? AND archived = 0', [id])) ??
      0;

  Future<bool> tagNameExists(String name, {int? exceptId}) async {
    final rows = await db.query('tags',
        where: exceptId == null ? 'name = ? COLLATE NOCASE' : 'name = ? COLLATE NOCASE AND id != ?',
        whereArgs: exceptId == null ? [name] : [name, exceptId]);
    return rows.isNotEmpty;
  }
}
