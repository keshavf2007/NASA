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

  Future<Map<String, dynamic>?> loadDashboard({
    double latitude = 21.1458,
    double longitude = 79.0882,
    DateTime? date,
  }) async {
    try {
      final query = <String, String>{
        'lat': '$latitude',
        'lon': '$longitude',
      };
      if (date != null) {
        query['date'] = _date(date);
      }
      final response = await _client.get(Uri.parse('$baseUrl/dashboard').replace(queryParameters: query)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      developer.log('Dashboard request failed', name: 'field_shift.api', error: error);
      return null;
    }

  }

  Future<Map<String, dynamic>?> loadRecommendations({
    required String currentCrop,
    required String season,
    required double soilPh,
    required List<String> priorities,
    Map<String, double> priorityWeights = const {},
    String? soilType,
    Map<String, dynamic>? weather,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/recommendations'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'current_crop': currentCrop,
          'season': season,
          'soil_ph': soilPh,
          'soil_type': soilType,
          'priorities': priorities,
          'priority_weights': priorityWeights,
          'weather': weather ?? const {},
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw StateError('Recommendation request failed (${response.statusCode}): ${response.body}');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      developer.log('Recommendation request failed', name: 'field_shift.api', error: error);
      rethrow;
    }
  }

  String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
