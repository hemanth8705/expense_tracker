import 'dart:io';
import 'dart:typed_data';

import 'package:expense_tracker/core/dedupe.dart';
import 'package:expense_tracker/core/period.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/export_service.dart';
import 'package:expense_tracker/services/import_service.dart';
import 'package:expense_tracker/services/repository.dart';
import 'package:expense_tracker/services/settings.dart';
import 'package:expense_tracker/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _n = 0;

/// A new, empty install. sqflite shares one instance per path, so each app
/// gets its own database file.
Future<AppState> freshApp() async {
  SharedPreferences.setMockInitialValues({});
  final dir = await Directory.systemTemp.createTemp('et_app');
  final repo = await Repository.open(path: '${dir.path}/app${_n++}.db');
  final s = AppState(repo, await Settings.load());
  s.tags = await repo.tags();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const body = 'Rs.23.00 Dr. from A/C XXXXXX6114 and Cr. to 7406124278-2@axl. Ref:630. AvlBal:Rs15255.21 - BOB';
  final smsAt = DateTime(2026, 11, 1, 18, 44, 37, 512); // inbox time has seconds + ms

  test('export → import into a fresh install restores rows, tags, colours, notes', () async {
    final a = await freshApp();
    await a.saveTag(const Tag(name: 'Groceries 2', color: 0xFF43A047));
    final tagId = (await a.repo.tags()).single.id;
    await a.repo.insertSmsTxns([
      Txn(
        source: TxnSource.sms, type: TxnType.debit, amount: 2300, occurredAt: smsAt,
        bank: 'Bank of Baroda', account: '6114', balance: 1525521, tagId: tagId, note: 'milk',
        smsKey: smsDedupeKey('JX-BOBSMS-S', smsAt, body), smsSender: 'JX-BOBSMS-S', smsBody: body,
        createdAt: smsAt,
      ),
    ]);
    await a.addManual(Txn(
        source: TxnSource.manual, type: TxnType.debit, amount: 20000, occurredAt: DateTime(2026, 11, 9, 15, 30),
        bank: 'Bob', counterparty: 'Fuel', tagId: tagId, createdAt: DateTime(2026, 11, 9)));

    final file = await ExportService.build(a.repo, Period.all, a.tags, ExportFormat.xlsx);

    final b = await freshApp();
    final parsed = ImportService.parse(file.bytes, file.name);
    expect(parsed.errors, isEmpty);
    expect(parsed.rows.length, 2);
    final out = await b.importRows(parsed);
    expect(out.added, 2);
    expect(out.tagsCreated, 1);

    final rows = await b.repo.query(const TxnFilter());
    expect(rows.every((t) => t.source == TxnSource.imported), isTrue);
    final sms = rows.firstWhere((t) => t.hasSmsText);
    expect(sms.amount, 2300);
    expect(sms.balance, 1525521);
    expect(sms.account, '6114');
    expect(sms.note, 'milk');
    expect(sms.occurredAt, DateTime(2026, 11, 1, 18, 44));
    final tags = await b.repo.tags();
    expect(tags.single.name, 'Groceries 2');
    expect(tags.single.color, 0xFF43A047); // from the Tags sheet
    expect(rows.every((t) => t.tagId == tags.single.id), isTrue);
    expect((await b.repo.totals(const TxnFilter())).debit, 22300);

    // Importing the same file again adds nothing.
    expect((await b.importRows(parsed)).added, 0);

    // A later SMS refresh of the same inbox message is recognised as a duplicate.
    expect(await b.repo.existingSmsKeys([smsDedupeKey('JX-BOBSMS-S', smsAt, body)]), isNotEmpty);
  });

  test('CSV export imports the same way', () async {
    final a = await freshApp();
    await a.addManual(Txn(
        source: TxnSource.manual, type: TxnType.credit, amount: 150050, occurredAt: DateTime(2026, 10, 3, 9, 5),
        counterparty: '=cmd, "quoted"', note: 'line1\nline2', createdAt: DateTime(2026, 10, 3)));
    final csv = await ExportService.build(a.repo, Period.all, a.tags, ExportFormat.csv);
    final parsed = ImportService.parse(csv.bytes, csv.name);
    expect(parsed.errors, isEmpty);
    final r = parsed.rows.single;
    expect(r.type, TxnType.credit);
    expect(r.amount, 150050);
    expect(r.counterparty, '=cmd, "quoted"');
    expect(r.note, 'line1\nline2');
    // Manual row typed into this same install is not duplicated by the import.
    expect((await a.importRows(parsed, dryRun: true)).added, 0);
  });

  test('bad rows are reported, good rows still import', () async {
    final a = await freshApp();
    final bytes = ImportService.parse(
      Uint8List.fromList('Date,Time,Type,Amount (INR)\n2026-11-01,10:00,Debit,50\nnot-a-date,,Debit,5\n2026-11-02,,Refund,5\n2026-11-03,,Credit,abc\n'.codeUnits),
      'x.csv',
    );
    expect(bytes.rows.length, 1);
    expect(bytes.errors.length, 3);
    expect((await a.importRows(bytes)).added, 1);
  });

  test('wrong kind of file gives a clear error', () {
    expect(() => ImportService.parse(Uint8List(4), 'photo.jpg'), throwsA(isA<ImportFormatException>()));
    expect(() => ImportService.parse(Uint8List.fromList('a,b\n1,2'.codeUnits), 'x.csv'),
        throwsA(isA<ImportFormatException>()));
  });

  test('upgrading a v1 database keeps rows and re-keys SMS', () async {
    final dir = await Directory.systemTemp.createTemp('et_mig');
    final path = '${dir.path}/v1.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE tags(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, color INTEGER NOT NULL)');
            await db.execute('''CREATE TABLE txns(id INTEGER PRIMARY KEY AUTOINCREMENT,
              source TEXT NOT NULL CHECK(source IN ('sms','manual')), type TEXT NOT NULL CHECK(type IN ('debit','credit')),
              amount INTEGER NOT NULL CHECK(amount > 0), occurred_at INTEGER NOT NULL, bank TEXT, account TEXT,
              account_kind TEXT, counterparty TEXT, balance INTEGER,
              tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL, note TEXT NOT NULL DEFAULT '',
              archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER, sms_key TEXT UNIQUE,
              sms_sender TEXT, sms_body TEXT, created_at INTEGER NOT NULL)''');
          },
        ));
    final tag = await v1.insert('tags', {'name': 'Fuel', 'color': 1});
    await v1.insert('txns', {
      'source': 'sms', 'type': 'debit', 'amount': 2300, 'occurred_at': smsAt.millisecondsSinceEpoch,
      'tag_id': tag, 'note': 'kept', 'archived': 1, 'sms_key': 'old-style-key', 'sms_sender': 'JX-BOBSMS-S',
      'sms_body': body, 'created_at': 0,
    });
    await v1.close();

    final repo = await Repository.open(path: path);
    final rows = await repo.query(const TxnFilter(archived: true));
    expect(rows.single.note, 'kept');
    expect(rows.single.tagId, tag);
    expect(rows.single.smsKey, smsDedupeKey('JX-BOBSMS-S', smsAt, body));
    // New source value is now allowed.
    await repo.insertImported([
      Txn(source: TxnSource.imported, type: TxnType.debit, amount: 1, occurredAt: smsAt, smsKey: 'x', createdAt: smsAt),
    ]);
    // Foreign keys still enforced after the rebuild.
    await repo.deleteTag(tag);
    expect((await repo.query(const TxnFilter(archived: true))).single.tagId, isNull);
    await repo.db.close();
    await dir.delete(recursive: true);
  });

  final real = Platform.environment['REAL_EXPORT'];
  test('the real exported file imports cleanly', () async {
    final parsed = ImportService.parse(await File(real!).readAsBytes(), 'expenses_All_time.xlsx');
    expect(parsed.errors, isEmpty);
    final a = await freshApp();
    final out = await a.importRows(parsed);
    // ignore: avoid_print
    print('real file: rows=${parsed.rows.length} added=${out.added} dup=${out.duplicates} tags=${out.tagsCreated} '
        'debit=${(await a.repo.totals(const TxnFilter())).debit / 100} credit=${(await a.repo.totals(const TxnFilter())).credit / 100}');
    expect(out.added, parsed.rows.length);
    expect((await a.importRows(parsed)).added, 0);
  }, skip: real == null ? 'set REAL_EXPORT to run' : false);
}
