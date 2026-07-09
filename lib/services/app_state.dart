import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'device_service.dart';

class AppState extends ChangeNotifier {
  final ApiService api = ApiService();

  bool loading = false;
  String? error;
  String? deviceId;

  Map<String, dynamic>? portfolio;
  Map<String, dynamic>? risk;
  List<Map<String, dynamic>> journal = [];
  List<Map<String, dynamic>> approvals = [];
  List<Map<String, dynamic>> alerts = [];
  Map<String, dynamic> scanResults = {};
  int? tickersScanned;
  DateTime? lastScan;
  bool marketOpen = false;

  bool disclaimerAccepted = false;
  bool onboardingDone = false;

  Future<void> bootstrap() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      disclaimerAccepted = prefs.getBool('disclaimer_accepted') ?? false;
      onboardingDone = prefs.getBool('onboarding_done') ?? false;
      deviceId = await DeviceService.getDeviceId();
      await api.register(deviceId: deviceId!);
      await refreshAll();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> acceptDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclaimer_accepted', true);
    disclaimerAccepted = true;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    onboardingDone = true;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    if (deviceId == null) deviceId = await DeviceService.getDeviceId();
    final id = deviceId!;
    try {
      final results = await Future.wait([
        api.portfolio(id),
        api.riskStatus(id),
        api.journal(id),
        api.approvals(id),
        api.health(),
      ]);
      portfolio = results[0] as Map<String, dynamic>;
      risk = results[1] as Map<String, dynamic>;
      journal = results[2] as List<Map<String, dynamic>>;
      approvals = results[3] as List<Map<String, dynamic>>;
      marketOpen = (results[4] as Map<String, dynamic>)['market_open'] == true;
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> runScan({double minConfidence = 0.5}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.scan(minConfidence: minConfidence);
      scanResults = Map<String, dynamic>.from(data['results'] as Map? ?? {});
      tickersScanned = data['tickers_scanned'] as int?;
      lastScan = DateTime.now();
      marketOpen = data['market_open'] == true;
      final raw = data['high_confidence_alerts'];
      if (raw is List) {
        alerts = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> updateConfig(Map<String, dynamic> updates) async {
    if (deviceId == null) return;
    await api.updateConfig({'device_id': deviceId!, ...updates});
    await refreshAll();
  }

  Future<void> setKillSwitch(bool on) async {
    await updateConfig({'kill_switch': on, 'is_paused': on});
  }

  Future<void> runBotCycle() async {
    if (deviceId == null) return;
    loading = true;
    notifyListeners();
    try {
      await api.runAutoForDevice(deviceId!);
      await refreshAll();
      await runScan(minConfidence: 0.5);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> resolveApproval(String id, bool approve) async {
    if (deviceId == null) return;
    await api.resolveApproval(deviceId: deviceId!, approvalId: id, approve: approve);
    await refreshAll();
  }

  Future<void> resetPaper() async {
    if (deviceId == null) return;
    await api.resetPortfolio(deviceId!);
    await refreshAll();
  }

  Future<void> paperTrade({
    required String ticker,
    required String side,
    double? dollars,
    String reason = 'manual',
  }) async {
    if (deviceId == null) return;
    await api.trade(
      deviceId: deviceId!,
      ticker: ticker,
      side: side,
      dollarAmount: dollars,
      reason: reason,
    );
    await refreshAll();
  }
}
