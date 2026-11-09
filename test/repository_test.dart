import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Txn sms(String key, TxnType type, int amount, DateTime at, {int? balance, String account = '1234'}) => Txn(
      source: TxnSource.sms,
      type: type,
      amount: amount,
      occurredAt: at,
      bank: 'HDFC Bank',
      account: account,
      balance: balance,
      smsKey: key,
      smsSender: 'VM-HDFCBK',
      smsBody: 'body $key',
      createdAt: DateTime(2026),
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Repository repo;
  final nov = TxnFilter(start: DateTime(2026, 11), end: DateTime(2026, 12));

  setUp(() async => repo = await Repository.open(path: inMemoryDatabasePath));
  tearDown(() => repo.db.close());

  test('same SMS is never imported twice', () async {
    final a = sms('k1', TxnType.debit, 500, DateTime(2026, 11, 2));
    expect(await repo.insertSmsTxns([a]), 1);
    expect(await repo.insertSmsTxns([a]), 0);
    expect(await repo.existingSmsKeys(['k1', 'k2']), {'k1'});
  });

  test('archived rows vanish from lists, totals, reports and balances, and are not re-imported', () async {
    await repo.insertSmsTxns([
      sms('k1', TxnType.debit, 500, DateTime(2026, 11, 2), balance: 10000),
      sms('k2', TxnType.credit, 2000, DateTime(2026, 11, 3), balance: 12000),
    ]);
    final rows = await repo.query(nov);
    final credit = rows.firstWhere((t) => t.type == TxnType.credit);

    expect((await repo.totals(nov)).net, 1500);
    expect((await repo.latestBalances()).single.balance, 12000);

    expect(await repo.setArchived([credit.id!], true), 1);
    expect((await repo.query(nov)).length, 1);
    expect((await repo.totals(nov)).credit, 0);
    expect((await repo.totalsByTag(nov.copyWith(type: TxnType.credit))), isEmpty);
    // Balance falls back to the latest non-archived SMS.
    expect((await repo.latestBalances()).single.balance, 10000);
    // Still blocks re-import.
    expect(await repo.existingSmsKeys(['k2']), {'k2'});
    expect((await repo.query(nov.copyWith(archived: true))).single.id, credit.id);

    expect(await repo.setArchived([credit.id!], false), 1);
    expect((await repo.totals(nov)).net, 1500);
  });

  test('archive by date range only touches that range', () async {
    await repo.insertSmsTxns([
      sms('a', TxnType.debit, 100, DateTime(2026, 10, 31, 23, 59)),
      sms('b', TxnType.debit, 200, DateTime(2026, 11, 1)),
      sms('c', TxnType.debit, 300, DateTime(2026, 11, 30, 23, 59)),
      sms('d', TxnType.debit, 400, DateTime(2026, 12, 1)),
    ]);
    expect(await repo.archiveRange(DateTime(2026, 11), DateTime(2026, 12)), 2);
    expect((await repo.totals(const TxnFilter())).debit, 500);
  });

  test('SMS rows cannot be deleted, manual rows can', () async {
    await repo.insertSmsTxns([sms('k1', TxnType.debit, 500, DateTime(2026, 11, 2))]);
    final manualId = await repo.insertManual(Txn(
      source: TxnSource.manual,
      type: TxnType.debit,
      amount: 900,
      occurredAt: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 11, 4),
    ));
    final smsId = (await repo.query(nov.copyWith(source: TxnSource.sms))).single.id!;
    expect(await repo.deleteManual([smsId, manualId]), 1);
    expect((await repo.query(nov)).single.id, smsId);
  });

  test('tag totals plus "No tag" add up to the total; deleting a tag untags', () async {
    final food = await repo.insertTag(const Tag(name: 'Food', color: 0xFFE53935));
    await repo.insertSmsTxns([
      sms('a', TxnType.debit, 100, DateTime(2026, 11, 2)),
      sms('b', TxnType.debit, 250, DateTime(2026, 11, 3)),
      sms('c', TxnType.debit, 400, DateTime(2026, 11, 4)),
    ]);
    final ids = (await repo.query(nov)).map((t) => t.id!).toList();
    await repo.setTag(ids.take(2).toList(), food);

    final byTag = await repo.totalsByTag(nov.copyWith(type: TxnType.debit));
    expect(byTag.fold<int>(0, (s, r) => s + r.amount), (await repo.totals(nov)).debit);
    expect(await repo.count(nov.copyWith(untaggedOnly: true)), 1);

    await repo.deleteTag(food);
    expect(await repo.count(nov.copyWith(untaggedOnly: true)), 3);
    expect(await repo.tags(), isEmpty);
  });

  test('tag names are unique ignoring case', () async {
    await repo.insertTag(const Tag(name: 'Food', color: 1));
    expect(await repo.tagNameExists('food'), isTrue);
    expect(await repo.tagNameExists('Travel'), isFalse);
  });

  test('search escapes LIKE wildcards', () async {
    await repo.insertSmsTxns([sms('a', TxnType.debit, 100, DateTime(2026, 11, 2))]);
    expect(await repo.count(nov.copyWith(search: '%')), 0);
    expect(await repo.count(nov.copyWith(search: 'body a')), 1);
  });
}
