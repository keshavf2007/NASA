import 'dart:convert';
import 'dart:io';

import 'package:field_shift_server/nasa_gateway.dart';
import 'package:field_shift_server/appeears_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final gateway = NasaGateway();
  final appeears = AppeearsClient();
  final router = Router();

  router.get('/api/health', (Request request) => Response.ok(jsonEncode({
        'status': 'ok',
        'provider': 'nasa-gateway',
        'offline_fallback': true,
      }), headers: {'content-type': 'application/json'}));

  router.get('/api/dashboard', (Request request) async {
    final latitude = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final longitude = double.tryParse(request.url.queryParameters['lon'] ?? '');
    if (latitude == null || longitude == null) {
      return Response(400, body: jsonEncode({'error': 'lat and lon are required'}));
    }
    try {
      final result = await gateway.dashboard(latitude: latitude, longitude: longitude);
      return _json(result);
    } catch (error) {
      return _json({'error': 'NASA live request failed', 'detail': error.toString()}, status: 502);
    }
  });

  router.get('/api/sources', (Request request) => _json({
        'smap_l4': {'provider': 'NASA', 'resolution': 'about 9 km', 'role': 'regional context'},
        'landsat_8_9': {'provider': 'NASA/USGS', 'resolution': '30 m', 'role': 'crop health'},
        'modis': {'provider': 'NASA', 'resolution': '250 m', 'role': 'longer history'},
        'nasa_power': {'provider': 'NASA', 'resolution': 'about 50 km', 'role': 'weather context'},
        'soilgrids': {'provider': 'ISRIC', 'resolution': 'about 250 m', 'role': 'soil baseline'},
        'srtm': {'provider': 'NASA', 'resolution': '30 m', 'role': 'terrain'},
        'nex_gddp_cmip6': {'provider': 'NASA', 'resolution': 'about 25 km', 'role': 'climate scenarios'},
      }));

  router.get('/api/granules', (Request request) async {
    final latitude = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final longitude = double.tryParse(request.url.queryParameters['lon'] ?? '');
    if (latitude == null || longitude == null) {
      return Response(400, body: jsonEncode({'error': 'lat and lon are required'}));
    }
    final end = DateTime.now().toUtc();
    final result = await gateway.granules(
      latitude: latitude,
      longitude: longitude,
      start: end.subtract(const Duration(days: 30)),
      end: end,
    );
    return _json({'coordinates': {'latitude': latitude, 'longitude': longitude}, 'datasets': result});
  });

  router.post('/api/appeears/tasks', (Request request) async {
    if (!appeears.configured) {
      return _json({'error': 'Earthdata credentials are not configured.'}, status: 503);
    }
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final polygon = (body['polygon'] as List<dynamic>)
        .map((point) => (point as List<dynamic>).map((value) => (value as num).toDouble()).toList())
        .toList();
    final result = await appeears.submitAreaTask(
      polygon: polygon,
      startDate: body['start_date'] as String,
      endDate: body['end_date'] as String,
    );
    return _json(result, status: 202);
  });

  router.get('/api/appeears/tasks/<taskId>', (Request request, String taskId) async {
    if (!appeears.configured) {
      return _json({'error': 'Earthdata credentials are not configured.'}, status: 503);
    }
    return _json(await appeears.task(taskId));
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Field Shift NASA gateway listening on http://${server.address.host}:$port');
}

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
