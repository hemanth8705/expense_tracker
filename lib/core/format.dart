import 'package:intl/intl.dart';

final _money0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _money2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Formats paise as rupees. Whole amounts drop the ".00".
String money(int paise, {bool signed = false}) {
  final abs = paise.abs();
  final f = abs % 100 == 0 ? _money0 : _money2;
  final s = f.format(abs / 100);
  if (paise < 0) return '−$s';
  if (signed && paise > 0) return '+$s';
  return s;
}

/// Parses user input like "1,250.50" into paise. Returns null if invalid.
int? parseMoney(String input) {
  final cleaned = input.replaceAll(RegExp(r'[,\s₹]'), '');
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null || v <= 0 || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

final dayFmt = DateFormat('EEE, d MMM yyyy');
final shortDayFmt = DateFormat('d MMM');
final timeFmt = DateFormat('h:mm a');
final dateTimeFmt = DateFormat('d MMM yyyy, h:mm a');
final monthFmt = DateFormat('MMMM yyyy');
final shortMonthFmt = DateFormat('MMM yyyy');
