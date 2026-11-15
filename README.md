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

## Run on a physical Android phone over USB

USB debugging does not automatically make the phone's `127.0.0.1` reach the
Mac. The launcher creates an ADB reverse tunnel, so the phone can use the
local gateway safely without Wi-Fi.

1. Enable Developer options and USB debugging.
2. Connect the phone by USB and accept the RSA authorization prompt.
3. Install ADB if it is not already installed:

   ```bash
   brew install android-platform-tools
   ```

4. Verify the device:

   ```bash
   adb devices
   flutter devices
   ```

5. Start the app using the Flutter device ID:

   ```bash
   ./scripts/run_live.sh YOUR_ANDROID_DEVICE_ID
   ```

The script runs `adb reverse tcp:8080 tcp:8080` and launches Flutter with
`http://127.0.0.1:8080/api`. Keep the USB cable connected while using the app.

## Run on a physical phone over Wi-Fi

The phone and Mac must be on the same Wi-Fi network. The Mac runs the NASA gateway; the phone runs the Flutter app and connects to the Mac's LAN IP.

1. Verify the phone appears:

   ```bash
   flutter devices
   ```

2. Use the device ID from that command:

   ```bash
   ./scripts/run_live.sh YOUR_DEVICE_ID
   ```

The launcher automatically finds the Mac's Wi-Fi IP and passes it to Flutter. If it cannot find it, use:

```bash
API_HOST=192.168.1.42 ./scripts/run_live.sh YOUR_DEVICE_ID
```

Do not use `127.0.0.1` for a physical phone. That points back to the phone, not the Mac. macOS may ask to allow incoming connections for the Dart gateway; allow it.

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

