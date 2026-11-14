import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class NasaGateway {
  NasaGateway({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _cmr = 'https://cmr.earthdata.nasa.gov/search';
  static const _power = 'https://power.larc.nasa.gov/api/temporal/daily/point';
  static const gibsTileTemplate =
      'https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/'
      '{layer}/default/{time}/250m/{tilematrixset}/{z}/{y}/{x}.jpg';

  Future<Map<String, dynamic>> dashboard({
    required double latitude,
    required double longitude,
    DateTime? date,
  }) async {
    final day = date ?? DateTime.now().toUtc();
    final dayText = _date(day);
    final results = await Future.wait([
      power(latitude: latitude, longitude: longitude, start: dayText, end: dayText),
      earthdataCollections(),
      granules(latitude: latitude, longitude: longitude, start: day.subtract(const Duration(days: 30)), end: day),
    ]);
    return {
      'provider': 'nasa-gateway',
      'coordinates': {'latitude': latitude, 'longitude': longitude},
      'updated': dayText,
      'power': results[0],
      'earthdata': results[1],
      'granules': results[2],
      'gibs': {
        'tile_template': gibsTileTemplate,
        'note': 'GIBS provides browse imagery; it is not a plot-level measurement.',
      },
    };
  }

  Future<List<Map<String, dynamic>>> granules({
    required double latitude,
    required double longitude,
    required DateTime start,
    required DateTime end,
  }) async {
    const datasets = <Map<String, String>>[
      {'key': 'smap_l4', 'short_name': 'SPL4SMGP'},
      {'key': 'landsat_8_9', 'short_name': 'LANDSAT_LC08_C02_T1_L2'},
      {'key': 'modis_ndvi', 'short_name': 'MOD13Q1'},
      {'key': 'srtm', 'short_name': 'SRTMGL1'},
      {'key': 'nex_gddp_cmip6', 'short_name': 'NEX-GDDP-CMIP6'},
    ];
    final output = <Map<String, dynamic>>[];
    for (final dataset in datasets) {
      try {
        final uri = Uri.parse('$_cmr/granules.json').replace(queryParameters: {
          'short_name': dataset['short_name']!,
          'point': '$longitude,$latitude',
          'temporal': '${_dateTime(start)},${_dateTime(end)}',
          'page_size': '5',
          'sort_key': '-start_date',
        });
        final response = await _client.get(uri, headers: _earthdataHeaders());
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('CMR granule search returned ${response.statusCode}');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final entries = (body['feed']?['entry'] as List<dynamic>? ?? const []);
        output.add({
          'key': dataset['key'],
          'short_name': dataset['short_name'],
          'count': entries.length,
          'granules': entries.map(_granuleSummary).toList(),
        });
      } catch (error) {
        output.add({'key': dataset['key'], 'short_name': dataset['short_name'], 'count': 0, 'error': error.toString()});
      }
    }
    return output;
  }

  Future<Map<String, dynamic>> power({
    required double latitude,
    required double longitude,
    required String start,
    required String end,
  }) async {
    final uri = Uri.parse(_power).replace(queryParameters: {
      'parameters': 'T2M,PRECTOTCORR,ALLSKY_SFC_SW_DWN',
      'community': 'AG',
      'longitude': longitude.toString(),
      'latitude': latitude.toString(),
      'start': start.replaceAll('-', ''),
      'end': end.replaceAll('-', ''),
      'format': 'JSON',
    });
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('NASA POWER returned ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> earthdataCollections() async {
    const datasets = <Map<String, String>>[
      {'key': 'smap_l4', 'short_name': 'SPL4SMGP'},
      {'key': 'landsat_8_9', 'short_name': 'LANDSAT_LC08_C02_T1_L2'},
      {'key': 'modis_ndvi', 'short_name': 'MOD13Q1'},
      {'key': 'srtm', 'short_name': 'SRTMGL1'},
      {'key': 'nex_gddp_cmip6', 'short_name': 'NEX-GDDP-CMIP6'},
    ];
    final output = <Map<String, dynamic>>[];
    for (final dataset in datasets) {
      try {
        final uri = Uri.parse('$_cmr/collections.json').replace(queryParameters: {
          'short_name': dataset['short_name']!,
          'page_size': '1',
        });
        final response = await _client.get(uri, headers: _earthdataHeaders());
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('CMR returned ${response.statusCode}');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final entries = (body['feed']?['entry'] as List<dynamic>? ?? const []);
        output.add({
          'key': dataset['key'],
          'short_name': dataset['short_name'],
          'available': entries.isNotEmpty,
          'collection': entries.isEmpty ? null : entries.first,
          'access': 'CMR metadata live; granule download requires Earthdata access.',
        });
      } catch (error) {
        output.add({
          'key': dataset['key'],
          'short_name': dataset['short_name'],
          'available': false,
          'error': error.toString(),
          'access': 'Using demo fallback until Earthdata credentials are configured.',
        });
      }
    }
    return output;
  }

  Map<String, String> _earthdataHeaders() {
    final token = Platform.environment['EARTHDATA_TOKEN'];
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
    final username = Platform.environment['EARTHDATA_USERNAME'];
    final password = Platform.environment['EARTHDATA_PASSWORD'];
    if (username != null && password != null) {
      final encoded = base64Encode(utf8.encode('$username:$password'));
      return {'Authorization': 'Basic $encoded'};
    }
    return const {};
  }

  String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _dateTime(DateTime value) => '${_date(value)}T00:00:00Z';

  Map<String, dynamic> _granuleSummary(dynamic value) {
    final entry = value as Map<String, dynamic>;
    final links = (entry['links'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((link) => (link['rel'] as String? ?? '').contains('data#'))
        .map((link) => link['href'])
        .whereType<String>()
        .toList();
    return {
      'id': entry['id'],
      'title': entry['title'],
      'time_start': entry['time_start'],
      'data_links': links,
    };
  }
}
