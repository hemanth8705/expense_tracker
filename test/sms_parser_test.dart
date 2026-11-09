import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedSms? p(String sender, String body) => SmsParser.parse(sender: sender, body: body);

void main() {
  group('accepts real transactions', () {
    test('HDFC UPI debit', () {
      final r = p('VM-HDFCBK',
          'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 05/11/26\nRef 612345678901\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808')!;
      expect(r.type, TxnType.debit);
      expect(r.amount, 25000);
      expect(r.bank, 'HDFC Bank');
      expect(r.account, '1234');
      expect(r.counterparty, 'SWIGGY');
    });

    test('SBI UPI debit without currency symbol', () {
      final r = p('JD-SBIUPI-S',
          'Dear UPI user A/C X5678 debited by 120.0 on date 04Nov26 trf to RAMESH KUMAR Refno 530812345678. If not u? call 1800111109. -SBI')!;
      expect(r.type, TxnType.debit);
      expect(r.amount, 12000);
      expect(r.bank, 'SBI');
      expect(r.account, '5678');
      expect(r.counterparty, 'RAMESH KUMAR');
    });

    test('ICICI credit with available balance', () {
      final r = p('AD-ICICIT',
          'ICICI Bank Acct XX901 credited with Rs 15,000.00 on 01-Nov-26; ACME PVT LTD credited. UPI:530912345678. Avl Bal Rs 42,315.50')!;
      expect(r.type, TxnType.credit);
      expect(r.amount, 1500000);
      expect(r.balance, 4231550);
      expect(r.account, '901');
      expect(r.bank, 'ICICI Bank');
    });

    test('credit card spend is a debit, not a credit', () {
      final r = p('BZ-HDFCBK',
          'Rs.1,499.00 spent on HDFC Bank Credit Card xx4321 at AMAZON on 2026-11-03:10:22:11. Avl Lmt: Rs.85,000. Not you? Call 18002586161')!;
      expect(r.type, TxnType.debit);
      expect(r.amount, 149900);
      expect(r.balance, isNull); // limit is not a balance
      expect(r.accountKind, AccountKind.card);
      expect(r.account, '4321');
      expect(r.counterparty, 'AMAZON');
    });

    test('salary credit via NEFT', () {
      final r = p('VK-AXISBK',
          'INR 85,000.00 credited to A/c no. XX7788 on 31-10-26 at 10:15:00 IST. Info- NEFT/AXIR123/ACME CORP. Avl Bal- INR 1,02,000.00 - Axis Bank')!;
      expect(r.type, TxnType.credit);
      expect(r.amount, 8500000);
      expect(r.balance, 10200000);
      expect(r.account, '7788');
    });

    test('ATM withdrawal', () {
      final r = p('AX-KOTAKB', 'Rs 2000 withdrawn at ATM from Kotak A/c X3344 on 02-11-2026. Bal: Rs 8,500')!;
      expect(r.type, TxnType.debit);
      expect(r.amount, 200000);
      expect(r.balance, 850000);
      expect(r.bank, 'Kotak Bank');
    });

    test('refund for failed transaction is a credit', () {
      final r = p('VM-HDFCBK', 'Rs 499 refunded to your A/c XX1234 for failed txn ref 1234. -HDFC Bank')!;
      expect(r.type, TxnType.credit);
      expect(r.amount, 49900);
    });

    test('₹ symbol', () {
      final r = p('AD-PAYTMB', '₹75 paid to Chai Point from Paytm Payments Bank a/c 9876 UPI Ref 123')!;
      expect(r.type, TxnType.debit);
      expect(r.amount, 7500);
    });
  });

  group('ignores non-transactions', () {
    final ignored = <String, (String, String)>{
      'OTP': ('VM-HDFCBK', 'OTP for txn of Rs 2,000 at AMAZON on card xx4321 is 123456. Do not share.'),
      'collect request': ('VM-HDFCBK', 'XYZ has requested money from you on Google Pay. On approving, Rs 500 will be debited from A/c XX1234'),
      'bill due': ('AD-SBICRD', 'Your SBI Card statement: Total Amt Due Rs 12,400, Min Amt Due Rs 620, due by 15-Nov.'),
      'offer': ('AD-HDFCBK', 'Congratulations! You are eligible for a pre-approved loan of Rs 5,00,000. Apply now'),
      'failed': ('VM-ICICIT', 'Your transaction of Rs 300 on ICICI Bank Card XX11 has failed due to insufficient balance'),
      'promo cashback': ('AD-AMZPAY', 'Get Rs 100 cashback on your first UPI payment! Hurry, offer valid till Sunday. T&C apply'),
      'future debit': ('VM-AXISBK', 'Rs 999 will be debited from your A/c XX12 on 10-Nov for Netflix mandate'),
      'balance only': ('VM-SBIINB', 'Your A/c XX1234 balance is Rs 10,000 as on 05-Nov-26'),
      'personal sms': ('+919876543210', 'Paid you Rs 500 via UPI, check your account'),
      'no money': ('VM-HDFCBK', 'Your HDFC Bank NetBanking password was changed successfully.'),
    };
    ignored.forEach((name, sms) {
      test(name, () => expect(p(sms.$1, sms.$2), isNull));
    });
  });
}
