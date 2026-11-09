import '../models/models.dart';
import 'bank_directory.dart';

class ParsedSms {
  final TxnType type;
  final int amount; // paise
  final int? balance; // paise
  final String? bank;
  final String? account;
  final AccountKind accountKind;
  final String? counterparty;

  const ParsedSms({
    required this.type,
    required this.amount,
    this.balance,
    this.bank,
    this.account,
    required this.accountKind,
    this.counterparty,
  });

  @override
  String toString() =>
      'ParsedSms($type, $amount, bal=$balance, $bank, $account, $accountKind, $counterparty)';
}

/// Turns a bank SMS into a debit/credit, or returns null for anything that
/// is not a completed money movement (OTPs, offers, due reminders, failed
/// transactions, collect requests, personal messages...).
class SmsParser {
  // Messages that mention money but are not a completed transaction.
  static final _reject = <RegExp>[
    RegExp(r'\botp\b|one[\s-]time password|verification code|security code'),
    RegExp(r'\brequested\b|collect request|payment request|\brequesting\b'),
    RegExp(r'\bis due\b|\bdue (on|by|date)\b|\b(min(imum)?|total)\.?\s*(amt\.?|amount)?\s*due\b|\boverdue\b|\bbill (is )?generated\b|\bstatement\b'),
    RegExp(r'\bwill be (debited|credited|deducted|charged|auto[\s-]?debited)\b|\bto be debited\b|\bupcoming\b'),
    RegExp(r'pre-?approved|\beligible\b|\boffers?\b|apply now|congratulations|\blucky\b|\bwin\b|\bvoucher\b|\bcoupon\b|\bdiscount\b|\bhurry\b|\bt&c\b|\btnc\b|\bavail\b'),
    RegExp(r'limit (has been |is )?(increased|enhanced|upgraded)'),
  ];

  static final _failed = RegExp(r'\b(failed|declined|unsuccessful|rejected)\b|could not be processed');
  static final _refundish = RegExp(r'\b(refund(ed)?|revers(ed|al))\b');

  static final _debitWords = RegExp(
      r'\b(debited|debit|dr|spent|withdrawn|withdrawal|paid|sent|purchased?|deducted|charged|transferred to|txn of|transaction of|used at|used for)\b');
  static final _creditWords = RegExp(
      r'\b(credited|credit|cr|received|deposited|refund(ed)?|revers(ed|al))\b');

  // Must look like it is about an account/card/payment rail.
  static final _financialContext = RegExp(
      r'a/c|\bac\b|\bacct\b|account|\bcard\b|\bupi\b|\bvpa\b|\bimps\b|\bneft\b|\brtgs\b|\batm\b|\bwallet\b|\bbank\b|\btxn\b|transaction|\bref\b|\butr\b|\bpos\b');

  static final _amountRe = RegExp(
      r'(?:(?<![a-z])(?:rs|inr)\.?|₹)\s*[:\-]?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)');
  // SBI-style "debited by 20.0" with no currency symbol.
  static final _bareAmountRe = RegExp(
      r'\b(?:debited|credited|withdrawn|paid|sent|received|deposited)\s+(?:by|with|of|for)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b');

  static final _balanceBefore = RegExp(r'(bal|balance)\b[^0-9]{0,15}$');
  static final _limitBefore = RegExp(r'(lmt|limit)\b[^0-9]{0,15}$');

  static final _accountRe = RegExp(
      r'(?:a/c|a/c\.|acct|account|\bac|card)\s*(?:no\.?|number|num)?\s*(?:ending(?:\s*(?:with|in))?)?\s*[:\-]?\s*(?:[x*#.]+\s*)?(\d{3,})\b');
  static final _maskedRe = RegExp(r'(?:^|[^a-z0-9])[x*#]{2,}(\d{3,6})\b');

  static final _vpaRe = RegExp(r'\b(?:vpa|upi id)\s*[:\-]?\s*([\w.\-]+@[\w.\-]+)', caseSensitive: false);
  static final _atRe = RegExp(
      r'\bat\s+([A-Za-z0-9@&._\-/ ]{2,40}?)(?=\s+(?:on|via|ref|refno|upi|txn|avl|avbl|for|from|dated|using|with|is|has|not|if|bal)\b|[.,;:(]|\s*$)',
      caseSensitive: false);
  static final _toRe = RegExp(
      r'\b(?:to|towards|trf to|paid to|sent to)\s+([A-Za-z0-9@&._\-/ ]{2,40}?)(?=\s+(?:on|via|ref|refno|upi|txn|avl|avbl|for|from|dated|using|with|is|has|not|if|bal)\b|[.,;:(]|\s*$)',
      caseSensitive: false);
  static final _fromRe = RegExp(
      r'\b(?:from|by)\s+([A-Za-z0-9@&._\-/ ]{2,40}?)(?=\s+(?:on|via|ref|refno|upi|txn|avl|avbl|for|to|dated|using|with|is|has|not|if|bal)\b|[.,;:(]|\s*$)',
      caseSensitive: false);
  static final _badParty = RegExp(
      r'^(a/c|ac\b|acct|account|your|you|rs\b|inr|₹|\d|card|the\b|upi\b|imps\b|neft\b|bank\b|mobile|net ?banking|x+\d)',
      caseSensitive: false);

  static bool isPersonalNumber(String sender) {
    final s = sender.replaceAll(RegExp(r'[\s\-+()]'), '');
    return RegExp(r'^\d{10,}$').hasMatch(s);
  }

  static ParsedSms? parse({required String sender, required String body}) {
    if (body.trim().isEmpty || isPersonalNumber(sender)) return null;

    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = text.toLowerCase();

    for (final re in _reject) {
      if (re.hasMatch(lower)) return null;
    }
    if (_failed.hasMatch(lower) && !_refundish.hasMatch(lower)) return null;
    if (!_financialContext.hasMatch(lower)) return null;

    // "credit card" / "debit card" are product names, not directions.
    final dirText = lower
        .replaceAll(RegExp(r'\b(credit|debit)\s+card'), 'card')
        .replaceAll(RegExp(r'\bcredit\s+limit'), 'limit')
        .replaceAll(RegExp(r'\bcredit\s+score'), 'score');
    final d = _debitWords.firstMatch(dirText);
    final c = _creditWords.firstMatch(dirText);
    TxnType? type;
    if (d != null && c != null) {
      type = d.start <= c.start ? TxnType.debit : TxnType.credit;
    } else if (d != null) {
      type = TxnType.debit;
    } else if (c != null) {
      type = TxnType.credit;
    }
    if (type == null) return null;

    int? amount;
    int? balance;
    for (final m in _amountRe.allMatches(lower)) {
      final before = lower.substring(m.start < 30 ? 0 : m.start - 30, m.start);
      final value = _toPaise(m.group(1)!);
      if (value == null) continue;
      if (_balanceBefore.hasMatch(before)) {
        balance ??= value;
      } else if (_limitBefore.hasMatch(before)) {
        continue;
      } else {
        amount ??= value;
      }
    }
    amount ??= _toPaise(_bareAmountRe.firstMatch(lower)?.group(1));
    if (amount == null || amount <= 0) return null;

    String? account;
    final am = _accountRe.firstMatch(lower) ?? _maskedRe.firstMatch(lower);
    if (am != null) {
      final digits = am.group(1)!;
      account = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
    }

    final kind = RegExp(r'credit\s*card|\bcc\b').hasMatch(lower)
        ? AccountKind.card
        : RegExp(r'\bwallet\b').hasMatch(lower)
            ? AccountKind.wallet
            : AccountKind.bank;

    return ParsedSms(
      type: type,
      amount: amount,
      balance: balance,
      bank: BankDirectory.resolve(sender, lower),
      account: account,
      accountKind: kind,
      counterparty: _counterparty(text, type),
    );
  }

  static int? _toPaise(String? raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw.replaceAll(',', ''));
    if (v == null) return null;
    return (v * 100).round();
  }

  static String? _counterparty(String text, TxnType type) {
    final vpa = _vpaRe.firstMatch(text);
    final primary = type == TxnType.debit ? [_atRe, _toRe] : [_fromRe];
    final secondary = _toRe;
    for (final re in primary) {
      for (final m in re.allMatches(text)) {
        final v = _clean(m.group(1));
        if (v != null) return v;
      }
    }
    if (vpa != null) return vpa.group(1);
    // Some banks put the party after the opposite preposition.
    if (type == TxnType.credit) {
      for (final m in secondary.allMatches(text)) {
        final v = _clean(m.group(1));
        if (v != null) return v;
      }
    }
    return null;
  }

  static String? _clean(String? raw) {
    if (raw == null) return null;
    var v = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    v = v.replaceAll(RegExp(r'^(vpa|upi)\s*[:\-]?\s*', caseSensitive: false), '');
    if (v.length < 2 || _badParty.hasMatch(v)) return null;
    // Our own account/card description, not the other party.
    if (RegExp(r'[x*]{2,}\d|a/c|\bcard\b', caseSensitive: false).hasMatch(v)) return null;
    return v;
  }
}
