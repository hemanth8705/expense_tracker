import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/period.dart';
import '../models/models.dart';
import 'repository.dart';

enum ExportFormat { csv, xlsx }

class ExportFile {
  final String name;
  final Uint8List bytes;
  final String mime;
  const ExportFile(this.name, this.bytes, this.mime);
}

/// Builds CSV / Excel files of non-archived transactions for a period.
class ExportService {
  static const _headers = [
    'Date', 'Time', 'Type', 'Amount (INR)', 'Source', 'Bank', 'Account',
    'Counterparty', 'Tag', 'Note', 'Balance after (INR)', 'SMS sender', 'SMS text',
  ];

  static Future<ExportFile> build(
      Repository repo, Period period, List<Tag> tags, ExportFormat format) async {
    final txns = (await repo.query(TxnFilter(start: period.start, end: period.end)))
        .reversed // oldest first reads better in a spreadsheet
        .toList();
    final tagName = {for (final t in tags) t.id: t.name};
    final d = DateFormat('yyyy-MM-dd');
    final tm = DateFormat('HH:mm');

    List<Object?> row(Txn t) => [
          d.format(t.occurredAt),
          tm.format(t.occurredAt),
          t.type == TxnType.debit ? 'Debit' : 'Credit',
          t.amount / 100,
          t.isSms ? 'SMS' : 'Manual',
          t.bank ?? '',
          t.account == null ? '' : 'xx${t.account}',
          t.counterparty ?? '',
          t.tagId == null ? '' : (tagName[t.tagId] ?? ''),
          t.note,
          t.balance == null ? null : t.balance! / 100,
          t.smsSender ?? '',
          t.smsBody ?? '',
        ];

    final slug = period.label.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    final base = 'expenses_${slug.isEmpty ? 'all' : slug}';

    if (format == ExportFormat.csv) {
      final sb = StringBuffer()..writeln(_headers.map(_csv).join(','));
      for (final t in txns) {
        sb.writeln(row(t).map(_csv).join(','));
      }
      // BOM so Excel opens the ₹ / non-ASCII text correctly.
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())]);
      return ExportFile('$base.csv', bytes, 'text/csv');
    }

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Transactions');
    final sheet = excel['Transactions'];
    sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
    for (final t in txns) {
      sheet.appendRow(row(t).map<CellValue?>((v) {
        if (v == null) return null;
        if (v is double) return DoubleCellValue(v);
        return TextCellValue(v.toString());
      }).toList());
    }

    // Summary sheet: per tag, debit and credit.
    final summary = excel['Summary'];
    summary.appendRow([TextCellValue('Period'), TextCellValue(period.label)]);
    final debit = txns.where((t) => t.type == TxnType.debit).fold<int>(0, (a, t) => a + t.amount);
    final credit = txns.where((t) => t.type == TxnType.credit).fold<int>(0, (a, t) => a + t.amount);
    summary.appendRow([TextCellValue('Total debited'), DoubleCellValue(debit / 100)]);
    summary.appendRow([TextCellValue('Total credited'), DoubleCellValue(credit / 100)]);
    summary.appendRow([TextCellValue('Net'), DoubleCellValue((credit - debit) / 100)]);
    summary.appendRow([]);
    summary.appendRow([TextCellValue('Tag'), TextCellValue('Debited'), TextCellValue('Credited')]);
    final byTag = <int?, (int, int)>{};
    for (final t in txns) {
      final cur = byTag[t.tagId] ?? (0, 0);
      byTag[t.tagId] = t.type == TxnType.debit ? (cur.$1 + t.amount, cur.$2) : (cur.$1, cur.$2 + t.amount);
    }
    for (final e in byTag.entries) {
      summary.appendRow([
        TextCellValue(e.key == null ? 'No tag' : (tagName[e.key] ?? 'No tag')),
        DoubleCellValue(e.value.$1 / 100),
        DoubleCellValue(e.value.$2 / 100),
      ]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    return ExportFile('$base.xlsx', bytes,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  static String _csv(Object? v) {
    if (v == null) return '';
    var s = v is double ? v.toStringAsFixed(2) : v.toString();
    // Neutralise spreadsheet formula injection from SMS text.
    if (s.isNotEmpty && '=+-@'.contains(s[0]) && v is! double) s = "'$s";
    if (s.contains(RegExp(r'[",\n\r]'))) s = '"${s.replaceAll('"', '""')}"';
    return s;
  }

  /// Opens the system "save as" dialog. Returns false if the user cancelled.
  static Future<bool> saveToDevice(ExportFile f) async {
    final uri = await FilePicker.saveFile(
      fileName: f.name,
      bytes: f.bytes,
      mimeType: f.mime,
      dialogTitle: 'Save export',
    );
    return uri != null;
  }

  static Future<void> share(ExportFile f) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${f.name}');
    await file.writeAsBytes(f.bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: f.mime)],
      subject: f.name,
    ));
  }
}
