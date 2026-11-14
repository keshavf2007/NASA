# Field Shift

Field Shift is an offline-first Flutter app for crop-rotation decisions in Nagpur district, Maharashtra.

The prototype is now a single Flutter + Dart application. Mock data and the rotation logic are local, so the demo does not depend on a server or network connection.

## Run locally with live NASA data

```bash
./scripts/run_live.sh
```

The script starts the Dart NASA gateway, waits for `/api/health`, and then launches Flutter with the correct API URL. For a different Flutter device:

```bash
./scripts/run_live.sh chrome
```

For a production web build:

```bash
flutter build web
```

Do not run only `flutter run` in strict live mode; that starts the app without the NASA gateway and will correctly show the live-data-required screen.

The current app includes the five demo plots, plain-language statuses, rotation rankings, details/source cards, language switching, text-to-speech, WhatsApp sharing, and a low-data map view.

The header location button requests device/browser location permission, sends the detected latitude/longitude to the Dart gateway, and refreshes the live NASA dashboard request. Web location requires a secure context; `localhost` is allowed during local development.

## NASA backend

The Flutter app can use the Dart NASA gateway in [`server/`](/Users/yashashribopche/Desktop/hackathon2/server):

```bash
# Terminal 1
cd server
dart pub get
dart run bin/server.dart

# Terminal 2
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

The gateway connects to NASA POWER and NASA CMR, exposes GIBS browse-tile metadata, and reports source/resolution information for SMAP L4, Landsat 8/9, MODIS, SRTM, and NEX-GDDP-CMIP6. Authenticated Earthdata granule access can be enabled later with `EARTHDATA_TOKEN` or `EARTHDATA_USERNAME` and `EARTHDATA_PASSWORD`.

CMR collection discovery is live metadata, not a plot-level measurement. SMAP is regional context, while Landsat is the intended plot-health source. The UI keeps these distinctions visible and retains the deterministic fallback until authenticated granule download, reprojection, cloud masking, and field-polygon aggregation are configured.

The UI never calls NASA services directly. The app is now strict live mode: it blocks the dashboard until the gateway returns a successful NASA response. There is no demo-mode success state.

## Product constraints

- Mock data is the default and does not require network access.
- Flutter is the only runtime required for the app.
- The UI uses plain-language status labels and keeps raw measurements in Details.
- Plot-level moisture is explicitly estimated/demo data because SMAP is regional context.
- The standard disclaimer is shown wherever recommendations are presented:
  > Estimates from satellite and climate data. Confirm with a local soil test and your agriculture officer.

