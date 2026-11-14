# Field Shift NASA gateway

This is the Dart backend for the Flutter app.

```bash
cd server
dart pub get
dart run bin/server.dart
```

Optional Earthdata configuration:

```bash
EARTHDATA_TOKEN=... dart run bin/server.dart
```

Live endpoints:

- `GET /api/dashboard?lat=21.1458&lon=79.0882` - NASA POWER, CMR collections, and recent granules.
- `GET /api/granules?lat=21.1458&lon=79.0882` - spatial/temporal CMR granules with data links.
- `POST /api/appeears/tasks` - submits a real AppEEARS polygon sample for MODIS NDVI and land-surface temperature.
- `GET /api/appeears/tasks/:taskId` - checks an AppEEARS task.

The gateway calls NASA POWER, NASA CMR, and AppEEARS. CMR provides authenticated data links for SMAP L4, Landsat 8/9, MODIS, SRTM, and NEX-GDDP-CMIP6. AppEEARS performs area sampling for configured products. Granule downloads and AppEEARS tasks require Earthdata access; the Flutter app stays blocked until the live gateway responds successfully.
