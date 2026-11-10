import 'package:flutter/material.dart';

enum TxnType { debit, credit }

/// sms: read from the inbox. manual: typed in the app.
/// imported: restored from an exported Excel/CSV file.
enum TxnSource { sms, manual, imported }

extension TxnSourceLabel on TxnSource {
  String get label => switch (this) {
        TxnSource.sms => 'SMS',
        TxnSource.manual => 'Manual',
        TxnSource.imported => 'Imported',
      };
}

enum AccountKind { bank, card, wallet }

T _byName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

/// One money movement. Amounts are stored as integer paise to avoid
/// floating-point rounding errors in totals.
class Txn {
  final int? id;
  final TxnSource source;
  final TxnType type;
  final int amount; // paise, always positive
  final DateTime occurredAt;
  final String? bank;
  final String? account; // last digits only, e.g. "1234"
  final AccountKind? accountKind;
  final String? counterparty;
  final int? balance; // paise, bank-reported "Avl Bal" after this txn
  final int? tagId;
  final String note;
  final bool archived;
  final DateTime? archivedAt;
  final String? smsKey; // unique fingerprint of the SMS, prevents re-import
  final String? smsSender;
  final String? smsBody;
  final DateTime createdAt;

  const Txn({
    this.id,
    required this.source,
    required this.type,
    required this.amount,
    required this.occurredAt,
    this.bank,
    this.account,
    this.accountKind,
    this.counterparty,
    this.balance,
    this.tagId,
    this.note = '',
    this.archived = false,
    this.archivedAt,
    this.smsKey,
    this.smsSender,
    this.smsBody,
    required this.createdAt,
  });

  bool get isSms => source == TxnSource.sms;

  /// Only manual entries can be edited or deleted. SMS and imported rows
  /// can only be archived, so their de-duplication key is never lost.
  bool get isManual => source == TxnSource.manual;

  /// True when the original SMS text is kept (SMS rows and imported SMS rows).
  bool get hasSmsText => smsBody != null && smsBody!.isNotEmpty;

  /// Signed amount: credits positive, debits negative.
  int get signed => type == TxnType.credit ? amount : -amount;

  String get title {
    if (counterparty != null && counterparty!.trim().isNotEmpty) {
      return counterparty!;
    }
    if (bank != null && bank!.isNotEmpty) return bank!;
    return type == TxnType.debit ? 'Debit' : 'Credit';
  }

  String? get accountLabel {
    final parts = <String>[
      if (bank != null && bank!.isNotEmpty) bank!,
      if (account != null && account!.isNotEmpty)
        '${accountKind == AccountKind.card ? 'Card' : 'A/c'} ••$account',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'source': source.name,
        'type': type.name,
        'amount': amount,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'bank': bank,
        'account': account,
        'account_kind': accountKind?.name,
        'counterparty': counterparty,
        'balance': balance,
        'tag_id': tagId,
        'note': note,
        'archived': archived ? 1 : 0,
        'archived_at': archivedAt?.millisecondsSinceEpoch,
        'sms_key': smsKey,
        'sms_sender': smsSender,
        'sms_body': smsBody,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Txn.fromRow(Map<String, Object?> r) => Txn(
        id: r['id'] as int,
        source: _byName(TxnSource.values, r['source'] as String?, TxnSource.manual),
        type: _byName(TxnType.values, r['type'] as String?, TxnType.debit),
        amount: r['amount'] as int,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(r['occurred_at'] as int),
        bank: r['bank'] as String?,
        account: r['account'] as String?,
        accountKind: r['account_kind'] == null
            ? null
            : _byName(AccountKind.values, r['account_kind'] as String?, AccountKind.bank),
        counterparty: r['counterparty'] as String?,
        balance: r['balance'] as int?,
        tagId: r['tag_id'] as int?,
        note: (r['note'] as String?) ?? '',
        archived: (r['archived'] as int? ?? 0) == 1,
        archivedAt: r['archived_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['archived_at'] as int),
        smsKey: r['sms_key'] as String?,
        smsSender: r['sms_sender'] as String?,
        smsBody: r['sms_body'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );
}

class Tag {
  final int? id;
  final String name;
  final int color; // ARGB

  const Tag({this.id, required this.name, required this.color});

  Color get colorValue => Color(color);

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'color': color,
      };

  factory Tag.fromRow(Map<String, Object?> r) =>
      Tag(id: r['id'] as int, name: r['name'] as String, color: r['color'] as int);
}

class Totals {
  final int debit;
  final int credit;
  final int count;
  const Totals({this.debit = 0, this.credit = 0, this.count = 0});
  int get net => credit - debit;
}

class TagTotal {
  final int? tagId; // null = "No tag"
  final int amount;
  final int count;
  const TagTotal(this.tagId, this.amount, this.count);
}

class AccountBalance {
  final String? bank;
  final String? account;
  final AccountKind? kind;
  final int balance;
  final DateTime asOf;
  const AccountBalance(this.bank, this.account, this.kind, this.balance, this.asOf);
}

/// Filter applied to transaction queries. [end] is exclusive.
class TxnFilter {
  final DateTime? start;
  final DateTime? end;
  final TxnType? type;
  final TxnSource? source;
  final String? bank;
  final int? tagId;
  final bool untaggedOnly;
  final String search;
  final bool archived;

  const TxnFilter({
    this.start,
    this.end,
    this.type,
    this.source,
    this.bank,
    this.tagId,
    this.untaggedOnly = false,
    this.search = '',
    this.archived = false,
  });

  static const _keep = Object();

  TxnFilter copyWith({
    Object? start = _keep,
    Object? end = _keep,
    Object? type = _keep,
    Object? source = _keep,
    Object? bank = _keep,
    Object? tagId = _keep,
    bool? untaggedOnly,
    String? search,
    bool? archived,
  }) =>
      TxnFilter(
        start: identical(start, _keep) ? this.start : start as DateTime?,
        end: identical(end, _keep) ? this.end : end as DateTime?,
        type: identical(type, _keep) ? this.type : type as TxnType?,
        source: identical(source, _keep) ? this.source : source as TxnSource?,
        bank: identical(bank, _keep) ? this.bank : bank as String?,
        tagId: identical(tagId, _keep) ? this.tagId : tagId as int?,
        untaggedOnly: untaggedOnly ?? this.untaggedOnly,
        search: search ?? this.search,
        archived: archived ?? this.archived,
      );

  String get _key =>
      '$start|$end|$type|$source|$bank|$tagId|$untaggedOnly|$search|$archived';

  @override
  bool operator ==(Object other) => other is TxnFilter && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}
