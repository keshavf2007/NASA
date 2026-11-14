import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AppeearsClient {
  AppeearsClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _base = 'https://appeears.earthdatacloud.nasa.gov/api';

  bool get configured =>
      (Platform.environment['EARTHDATA_TOKEN']?.isNotEmpty ?? false) ||
      ((Platform.environment['EARTHDATA_USERNAME']?.isNotEmpty ?? false) &&
          (Platform.environment['EARTHDATA_PASSWORD']?.isNotEmpty ?? false));

  Future<String> _token() async {
    final existing = Platform.environment['EARTHDATA_TOKEN'];
    if (existing != null && existing.isNotEmpty) return existing;
    final username = Platform.environment['EARTHDATA_USERNAME'];
    final password = Platform.environment['EARTHDATA_PASSWORD'];
    if (username == null || password == null) {
      throw StateError('Set EARTHDATA_TOKEN or Earthdata username/password.');
    }
    final response = await _client.post(
      Uri.parse('$_base/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('AppEEARS login returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) throw StateError('AppEEARS did not return a token.');
    return token;
  }

  Future<Map<String, dynamic>> submitAreaTask({
    required List<List<double>> polygon,
    required String startDate,
    required String endDate,
  }) async {
    final token = await _token();
    final closed = [...polygon, if (polygon.first != polygon.last) polygon.first];
    final task = {
      'task_name': 'field_shift_${DateTime.now().millisecondsSinceEpoch}',
      'task_type': 'area',
      'params': {
        'dates': [
          {
            'startDate': _appeearsDate(startDate),
            'endDate': _appeearsDate(endDate),
            'recurring': false,
            'yearRange': [2000, 2050],
          }
        ],
        'layers': [
          {'product': 'MOD13Q1.061', 'layer': '_250m_16_days_NDVI'},
          {'product': 'MOD11A2.061', 'layer': 'LST_Day_1km'},
        ],
        'geo': {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  closed.map((point) => [point[1], point[0]]).toList(),
                ],
              },
              'properties': {},
            }
          ],
        },
        'output': {
          'format': {'type': 'geotiff', 'filename_date': 'calendar'},
          'projection': 'geographic',
        },
      },
    };
    final response = await _client.post(
      Uri.parse('$_base/task'),
      headers: {'content-type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(task),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('AppEEARS task returned ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> task(String taskId) async {
    final token = await _token();
    final response = await _client.get(
      Uri.parse('$_base/task/$taskId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('AppEEARS task lookup returned ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _appeearsDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) throw FormatException('Expected YYYY-MM-DD date.');
    return '${parts[1]}-${parts[2]}-${parts[0]}';
  }
}
