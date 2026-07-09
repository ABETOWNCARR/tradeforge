import 'package:intl/intl.dart';

class Fmt {
  static final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  static final _moneyCompact = NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 1);
  static final _pct = NumberFormat('0.00');

  static String money(num? v) => _money.format(v ?? 0);
  static String moneyCompact(num? v) => _moneyCompact.format(v ?? 0);

  static String signedMoney(num? v) {
    final n = v ?? 0;
    final s = _money.format(n.abs());
    if (n > 0) return '+$s';
    if (n < 0) return '-$s';
    return s;
  }

  static String pct(num? v, {bool signed = false}) {
    final n = (v ?? 0).toDouble();
    final body = '${_pct.format(n)}%';
    if (!signed) return body;
    if (n > 0) return '+$body';
    return body;
  }

  static String confidence(num? v) {
    final n = ((v ?? 0).toDouble() * (v != null && v <= 1 ? 100 : 1));
    return '${n.round()}%';
  }

  static String timeAgo(DateTime? t) {
    if (t == null) return 'Never';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 45) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  static String shortIso(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('MMM d · h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
