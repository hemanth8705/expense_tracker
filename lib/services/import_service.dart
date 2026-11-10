import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/models.dart';
import 'sms_parser.dart';

/// One row read from an export file, before it becomes a [Txn].
class ImportRow {
  final int line; // 1-based row number in the sheet, for error messages
  final DateTime at;
  final TxnType type;
  final int amount; // paise
  final String? bank;
  final String? account;
  final String? counterparty;
  final String? tag;
  final String note;
  final int? balance;
  final String? smsSender;
  final String? smsBody;

  const ImportRow({
    required this.line,
    required this.at,
    required this.type,
    required this.amount,
    this.bank,
    this.account,
    this.counterparty,
    this.tag,
    this.note = '',
    this.balance,
    this.smsSender,
    this.smsBody,
  });

  bool get hasSms => smsBody != null && smsBody!.isNotEmpty && smsSender != null && smsSender!.isNotEmpty;

  /// Card / bank / wallet is not exported, so recover it from the SMS text.
  AccountKind? get accountKind {
    if (!hasSms) return null;
    return SmsParser.parse(sender: smsSender!, body: smsBody!)?.accountKind;
  }
}

class ImportFileResult {
  final List<ImportRow> rows;
  final List<String> errors; // rows that could not be read, with reasons
  final Map<String, int> tagColors; // from the optional "Tags" sheet
  const ImportFileResult(this.rows, this.errors, this.tagColors);
}

class ImportFormatException implements Exception {
  final String message;
  const ImportFormatException(this.message);
  @override
  String toString() => message;
}

/// Reads files produced by [ExportService]: the "Transactions" sheet of an
/// .xlsx (the "Summary" sheet is ignored) or the CSV export.
class ImportService {
  static ImportFileResult parse(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv')) return _fromTable(_parseCsv(utf8.decode(bytes, allowMalformed: true)), const {});
    if (lower.endsWith('.xlsx')) return _parseXlsx(bytes);
    throw const ImportFormatException('Choose an .xlsx or .csv file exported from this app.');
  }

  // ------------------------------------------------------------------ xlsx

  static ImportFileResult _parseXlsx(Uint8List bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const ImportFormatException('This file could not be opened as an Excel workbook.');
    }
    final sheet = excel.tables['Transactions'] ??
        (excel.tables.isEmpty ? null : excel.tables.values.first);
    if (sheet == null) throw const ImportFormatException('The workbook has no sheets.');
    final table = sheet.rows.map((r) => r.map((c) => _cellText(c?.value)).toList()).toList();

    final colors = <String, int>{};
    final tagsSheet = excel.tables['Tags'];
    if (tagsSheet != null) {
      for (final r in tagsSheet.rows.skip(1)) {
        final name = r.isNotEmpty ? _cellText(r[0]?.value)?.trim() : null;
        final hex = r.length > 1 ? _cellText(r[1]?.value)?.trim() : null;
        final c = hex == null ? null : int.tryParse(hex.replaceFirst('#', ''), radix: 16);
        if (name != null && name.isNotEmpty && c != null) colors[name.toLowerCase()] = 0xFF000000 | c;
      }
    }
    return _fromTable(table, colors);
  }

  static String? _cellText(CellValue? v) => switch (v) {
        null => null,
        TextCellValue t => t.value.toString(),
        IntCellValue i => '${i.value}',
        DoubleCellValue d => '${d.value}',
        BoolCellValue b => '${b.value}',
        DateCellValue d => '${d.year.toString().padLeft(4, '0')}-${_pad(d.month)}-${_pad(d.day)}',
        TimeCellValue t => '${_pad(t.hour)}:${_pad(t.minute)}',
        DateTimeCellValue d => '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}',
        FormulaCellValue f => f.formula,
      };

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ------------------------------------------------------------------- csv

  static List<List<String?>> _parseCsv(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = <List<String?>>[];
    var row = <String?>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String?>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    // Undo the export's formula-injection guard (a leading apostrophe).
    return rows
        .map((r) => r.map((v) => (v != null && v.length > 1 && v[0] == "'" && '=+-@'.contains(v[1])) ? v.substring(1) : v).toList())
        .toList();
  }

  // ----------------------------------------------------------------- rows

  static ImportFileResult _fromTable(List<List<String?>> table, Map<String, int> colors) {
    final headerIdx = table.indexWhere((r) => r.any((c) => c?.trim().toLowerCase() == 'date') &&
        r.any((c) => c?.trim().toLowerCase().startsWith('amount') ?? false));
    if (headerIdx < 0) {
      throw const ImportFormatException(
          'No "Date" and "Amount" header row found. Use a file exported from this app.');
    }
    final header = table[headerIdx].map((c) => (c ?? '').trim().toLowerCase()).toList();
    int col(String name) => header.indexWhere((h) => h == name || h.startsWith('$name '));
    final cDate = col('date'), cTime = col('time'), cType = col('type'), cAmount = col('amount');
    final cBank = col('bank'), cAccount = col('account'), cParty = col('counterparty'), cTag = col('tag');
    final cNote = col('note'), cBal = col('balance after'), cSender = col('sms sender'), cBody = col('sms text');
    if (cType < 0) throw const ImportFormatException('The "Type" column is missing.');

    String? at(List<String?> r, int i) {
      if (i < 0 || i >= r.length) return null;
      final v = r[i]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final rows = <ImportRow>[];
    final errors = <String>[];
    for (var i = headerIdx + 1; i < table.length; i++) {
      final r = table[i];
      if (r.every((c) => c == null || c.trim().isEmpty)) continue;
      final line = i + 1;

      final date = _parseDate(at(r, cDate), at(r, cTime));
      if (date == null) {
        errors.add('Row $line: unreadable date "${at(r, cDate) ?? ''}"');
        continue;
      }
      final typeText = at(r, cType)?.toLowerCase();
      final type = typeText == 'debit' ? TxnType.debit : typeText == 'credit' ? TxnType.credit : null;
      if (type == null) {
        errors.add('Row $line: type must be Debit or Credit');
        continue;
      }
      final amount = _paise(at(r, cAmount));
      if (amount == null || amount <= 0) {
        errors.add('Row $line: invalid amount "${at(r, cAmount) ?? ''}"');
        continue;
      }
      final acct = at(r, cAccount)?.replaceAll(RegExp(r'\D'), '');
      final bal = _paise(at(r, cBal));
      rows.add(ImportRow(
        line: line,
        at: date,
        type: type,
        amount: amount,
        bank: at(r, cBank),
        account: (acct == null || acct.isEmpty) ? null : acct,
        counterparty: at(r, cParty),
        tag: at(r, cTag),
        note: at(r, cNote) ?? '',
        balance: bal,
        smsSender: at(r, cSender),
        // Keep the SMS text exactly (only trimmed), it feeds the duplicate check.
        smsBody: (cBody >= 0 && cBody < r.length) ? r[cBody]?.trim().nullIfEmpty : null,
      ));
    }
    return ImportFileResult(rows, errors, colors);
  }

  static int? _paise(String? s) {
    if (s == null) return null;
    final v = double.tryParse(s.replaceAll(RegExp(r'[,\s₹]'), ''));
    return v == null ? null : (v * 100).round();
  }

  /// Accepts "2026-11-01" + "13:35", "01/11/2026", "2026-11-01 13:35",
  /// ISO timestamps, and Excel serial day numbers.
  static DateTime? _parseDate(String? d, String? t) {
    if (d == null) return null;
    var date = DateTime.tryParse(d.contains(' ') && t == null ? d.replaceFirst(' ', 'T') : d.split(' ').first);
    if (date == null) {
      final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(d);
      if (m != null) date = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    }
    if (date == null) {
      final serial = double.tryParse(d);
      if (serial != null && serial > 20000 && serial < 80000) {
        date = DateTime(1899, 12, 30).add(Duration(minutes: (serial * 24 * 60).round()));
      }
    }
    if (date == null) return null;
    if (t != null) {
      final tm = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(t);
      if (tm != null) {
        return DateTime(date.year, date.month, date.day, int.parse(tm[1]!), int.parse(tm[2]!));
      }
      final frac = double.tryParse(t); // Excel time as fraction of a day
      if (frac != null && frac >= 0 && frac < 1) {
        final mins = (frac * 24 * 60).round();
        return DateTime(date.year, date.month, date.day, mins ~/ 60, mins % 60);
      }
    }
    return DateTime(date.year, date.month, date.day, date.hour, date.minute);
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
