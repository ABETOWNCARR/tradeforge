import 'dart:convert';

import 'package:http/http.dart' as http;

import 'device_service.dart';

class ApiService {
  /// Override at build time: --dart-define=BASE_URL=http://127.0.0.1:8000
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://tradeforge-production-4b30.up.railway.app',
  );

  static const Duration _timeout = Duration(seconds: 45);

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path')).timeout(_timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(res.body);
      data = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      throw Exception('Invalid JSON (HTTP ${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      throw Exception(data['detail']?.toString() ?? 'HTTP ${res.statusCode}');
    }
    return data;
  }

  Future<Map<String, dynamic>> health() => _get('/');

  Future<Map<String, dynamic>> scan({List<String>? tickers, double minConfidence = 0}) {
    return _post('/scan', {
      if (tickers != null) 'tickers': tickers,
      'min_confidence': minConfidence,
    });
  }

  Future<Map<String, double>> quotes(List<String> tickers) async {
    if (tickers.isEmpty) return {};
    final data = await _post('/quotes', {'tickers': tickers});
    final q = data['quotes'];
    if (q is! Map) return {};
    return q.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }

  Future<List<Map<String, dynamic>>> candles(String ticker, {String timeframe = '3mo'}) async {
    final data = await _get('/candles/$ticker?timeframe=$timeframe');
    final list = data['candles'];
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> register({required String deviceId}) {
    // Heartbeat only — server keeps existing risk settings for known devices.
    return _post('/register', {'device_id': deviceId});
  }

  Future<Map<String, dynamic>> riskStatus(String deviceId) => _get('/config/$deviceId');

  Future<Map<String, dynamic>> updateConfig(Map<String, dynamic> body) => _post('/config', body);

  Future<Map<String, dynamic>> portfolio(String deviceId) => _get('/portfolio/$deviceId');

  Future<Map<String, dynamic>> resetPortfolio(String deviceId) =>
      _post('/portfolio/$deviceId/reset', {});

  Future<List<Map<String, dynamic>>> journal(String deviceId) async {
    final data = await _get('/journal/$deviceId');
    final trades = data['trades'];
    if (trades is! List) return [];
    return trades.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> trade({
    required String deviceId,
    required String ticker,
    required String side,
    double? dollarAmount,
    double? quantity,
    String reason = 'manual',
    double? stopLevel,
    double? targetLevel,
  }) {
    return _post('/trade', {
      'device_id': deviceId,
      'ticker': ticker,
      'side': side,
      if (dollarAmount != null) 'dollar_amount': dollarAmount,
      if (quantity != null) 'quantity': quantity,
      'reason': reason,
      if (stopLevel != null) 'stop_level': stopLevel,
      if (targetLevel != null) 'target_level': targetLevel,
    });
  }

  Future<List<Map<String, dynamic>>> approvals(String deviceId) async {
    final data = await _get('/approvals/$deviceId');
    final list = data['approvals'];
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> resolveApproval({
    required String deviceId,
    required String approvalId,
    required bool approve,
  }) {
    return _post('/approvals/resolve', {
      'device_id': deviceId,
      'approval_id': approvalId,
      'approve': approve,
    });
  }

  Future<Map<String, dynamic>> runAutoCycle() => _post('/auto/run', {});

  Future<Map<String, dynamic>> runAutoForDevice(String deviceId) =>
      _post('/auto/run/$deviceId', {});

  Future<Map<String, dynamic>> lastCycle(String deviceId) async {
    final data = await _get('/config/$deviceId');
    final last = data['last_cycle'];
    if (last is Map<String, dynamic>) return last;
    if (last is Map) return Map<String, dynamic>.from(last);
    return {};
  }

  Future<String> ensureRegistered() async {
    final id = await DeviceService.getDeviceId();
    try {
      await register(deviceId: id);
    } catch (_) {
      // offline / first run — still return id
    }
    return id;
  }
}
