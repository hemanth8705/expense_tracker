import 'package:flutter/services.dart';

class RawSms {
  final int id;
  final String address;
  final String body;
  final DateTime date;
  const RawSms(this.id, this.address, this.body, this.date);
}

/// Reads the SMS inbox through the native channel in MainActivity.kt.
class SmsReader {
  static const _channel = MethodChannel('expense_tracker/sms');

  static Future<List<RawSms>> readInbox({required DateTime since}) async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'readInbox',
      {'since': since.millisecondsSinceEpoch},
    );
    return (rows ?? const [])
        .map((r) => RawSms(
              (r['id'] as num).toInt(),
              r['address'] as String? ?? '',
              r['body'] as String? ?? '',
              DateTime.fromMillisecondsSinceEpoch((r['date'] as num).toInt()),
            ))
        .toList();
  }
}
