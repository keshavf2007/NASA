import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

class DashboardApi {
  DashboardApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080/api',
  );

  Future<bool> isLive() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> loadDashboard({double latitude = 21.1458, double longitude = 79.0882}) async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/dashboard').replace(queryParameters: {
        'lat': '$latitude',
        'lon': '$longitude',
      })).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      developer.log('Dashboard request failed', name: 'field_shift.api', error: error);
      return null;
    }
  }
}
