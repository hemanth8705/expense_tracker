/// Maps Indian SMS sender headers (e.g. "VM-HDFCBK", "JD-SBIUPI-S") and
/// body mentions to a readable bank / issuer name.
class BankDirectory {
  // Order matters: more specific codes first (SBI Card before SBI, etc.).
  static const List<(String, String)> _senderCodes = [
    ('SBICRD', 'SBI Card'),
    ('SBICARD', 'SBI Card'),
    ('SBMSMS', 'SBM Bank'),
    ('BOBCRD', 'BOB Card'),
    ('BOBCARD', 'BOB Card'),
    ('HDFC', 'HDFC Bank'),
    ('ICICI', 'ICICI Bank'),
    ('AXIS', 'Axis Bank'),
    ('KOTAK', 'Kotak Bank'),
    ('KOTAKB', 'Kotak Bank'),
    ('SBI', 'SBI'),
    ('ATMSBI', 'SBI'),
    ('PNB', 'PNB'),
    ('BOBTXN', 'Bank of Baroda'),
    ('BOBSMS', 'Bank of Baroda'),
    ('BARODA', 'Bank of Baroda'),
    ('CANBNK', 'Canara Bank'),
    ('CANARA', 'Canara Bank'),
    ('UNIONB', 'Union Bank'),
    ('UBOI', 'Union Bank'),
    ('IDFC', 'IDFC FIRST Bank'),
    ('INDUS', 'IndusInd Bank'),
    ('YESB', 'Yes Bank'),
    ('SCBANK', 'Standard Chartered'),
    ('STANC', 'Standard Chartered'),
    ('CITI', 'Citibank'),
    ('AMEX', 'American Express'),
    ('PAYTM', 'Paytm'),
    ('AIRBNK', 'Airtel Payments Bank'),
    ('AIRTEL', 'Airtel Payments Bank'),
    ('FEDBNK', 'Federal Bank'),
    ('FEDFIB', 'Federal Bank'),
    ('RBL', 'RBL Bank'),
    ('AUBANK', 'AU Bank'),
    ('AUSFB', 'AU Bank'),
    ('IDBI', 'IDBI Bank'),
    ('BOIIND', 'Bank of India'),
    ('BOI', 'Bank of India'),
    ('CENTBK', 'Central Bank'),
    ('CBOI', 'Central Bank'),
    ('IOB', 'Indian Overseas Bank'),
    ('INDBNK', 'Indian Bank'),
    ('UCOBNK', 'UCO Bank'),
    ('KVB', 'Karur Vysya Bank'),
    ('SIBSMS', 'South Indian Bank'),
    ('DBS', 'DBS Bank'),
    ('HSBC', 'HSBC'),
    ('ONECRD', 'OneCard'),
    ('ONECARD', 'OneCard'),
    ('SLICE', 'slice'),
    ('JUPITER', 'Jupiter'),
    ('BAJAJ', 'Bajaj Finserv'),
    ('BAJFIN', 'Bajaj Finserv'),
    ('AMZPAY', 'Amazon Pay'),
    ('PHONPE', 'PhonePe'),
    ('PHONEPE', 'PhonePe'),
    ('MOBIKW', 'MobiKwik'),
    ('EQUITAS', 'Equitas Bank'),
    ('UJJIVN', 'Ujjivan Bank'),
    ('BANDHN', 'Bandhan Bank'),
    ('DCBBNK', 'DCB Bank'),
    ('CSBBNK', 'CSB Bank'),
    ('TMBANK', 'TMB'),
    ('KBLBNK', 'Karnataka Bank'),
    ('JKBANK', 'J&K Bank'),
  ];

  static final List<(RegExp, String)> _bodyNames = [
    (RegExp(r'\bsbi\s*card\b'), 'SBI Card'),
    (RegExp(r'\bhdfc\b'), 'HDFC Bank'),
    (RegExp(r'\bicici\b'), 'ICICI Bank'),
    (RegExp(r'\baxis\b'), 'Axis Bank'),
    (RegExp(r'\bkotak\b'), 'Kotak Bank'),
    (RegExp(r'\bsbi\b|state bank of india'), 'SBI'),
    (RegExp(r'\bpnb\b|punjab national'), 'PNB'),
    (RegExp(r'bank of baroda|\bbob\b'), 'Bank of Baroda'),
    (RegExp(r'\bcanara\b'), 'Canara Bank'),
    (RegExp(r'union bank'), 'Union Bank'),
    (RegExp(r'\bidfc\b'), 'IDFC FIRST Bank'),
    (RegExp(r'\bindusind\b'), 'IndusInd Bank'),
    (RegExp(r'\byes bank\b'), 'Yes Bank'),
    (RegExp(r'federal bank'), 'Federal Bank'),
    (RegExp(r'\bidbi\b'), 'IDBI Bank'),
    (RegExp(r'\bpaytm\b'), 'Paytm'),
  ];

  /// Strips the operator prefix ("VM-") and type suffix ("-S", "-T").
  static String senderCore(String sender) {
    final parts = sender
        .toUpperCase()
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return sender.toUpperCase();
    parts.sort((a, b) => b.length.compareTo(a.length));
    return parts.first;
  }

  static String? resolve(String sender, String lowerBody) {
    final core = senderCore(sender);
    for (final (code, name) in _senderCodes) {
      if (core.contains(code)) return name;
    }
    for (final (re, name) in _bodyNames) {
      if (re.hasMatch(lowerBody)) return name;
    }
    // Unknown but alphanumeric sender: show the header itself, e.g. "XYZBNK".
    return RegExp(r'[A-Z]').hasMatch(core) ? core : null;
  }
}
