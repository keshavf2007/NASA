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
- `POST /api/recommendations` - applies farmer priorities, current crop, and optional soil type to the rotation analysis. Priority bar values are sent as `priority_weights` from 0 to 1.
- `GET /api/granules?lat=21.1458&lon=79.0882` - spatial/temporal CMR granules with data links.
- `POST /api/appeears/tasks` - submits a real AppEEARS polygon sample for MODIS NDVI and land-surface temperature.
- `GET /api/appeears/tasks/:taskId` - checks an AppEEARS task.

The dashboard response also contains:

- `processed`: normalized temperature, rainfall, solar radiation, moisture outlook, granule count, and data quality.
- `rotation_analysis`: five ranked crops, a two-season plan, component scores, plain-language reasons, confidence, risks, and the scoring weights.

The recommendation engine is explainable and rule-based rather than a black-box
model. It uses crop family, water need, soil pH, NASA POWER weather context,
season, and heat tolerance. Until SoilGrids and authenticated field-polygon
sampling are connected, the demo plot uses its configured soil pH and cotton as
the current crop; the response labels unavailable weather values and lowers
confidence instead of treating NASA sentinel values as measurements.

The gateway calls NASA POWER, NASA CMR, and AppEEARS. CMR provides authenticated data links for SMAP L4, Landsat 8/9, MODIS, SRTM, and NEX-GDDP-CMIP6. AppEEARS performs area sampling for configured products. Granule downloads and AppEEARS tasks require Earthdata access; the Flutter app stays blocked until the live gateway responds successfully.
