import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

final _minute = DateFormat('yyyy-MM-dd HH:mm');

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Fingerprint of an SMS: sender + time to the minute + text.
///
/// Minute precision on purpose: an Excel export only keeps HH:mm, so an SMS
/// restored from a file and the same SMS read again from the inbox produce
/// the same key. That is what stops "import file, then refresh" from creating
/// duplicates. Stored in the UNIQUE `sms_key` column.
String smsDedupeKey(String sender, DateTime at, String body) =>
    sha1.convert(utf8.encode('sms|${sender.trim()}|${_minute.format(at)}|${_norm(body)}')).toString();

/// Fingerprint of an imported row that has no SMS text (originally manual).
/// Makes importing the same file twice harmless.
String entryDedupeKey(TxnType type, int amount, DateTime at, String? counterparty, String note) =>
    sha1.convert(utf8.encode(
            'entry|${type.name}|$amount|${_minute.format(at)}|${_norm(counterparty ?? '')}|${_norm(note)}'))
        .toString();
