#!/usr/bin/env python3
"""Precompute Field Shift Earth observation data into JSON cache files.

Part 1 handles NASA POWER, SoilGrids, and the SRTM configuration check.
Part 2 adds authenticated SMAP L4, HLS, and MODIS retrieval. Raster
dependencies are loaded only for those authenticated datasets.
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import tempfile
import time
from datetime import date, timedelta, timezone, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATASETS = ROOT / "config" / "datasets.json"
DEFAULT_PLOTS = ROOT / "config" / "plots.json"
DEFAULT_OUTPUT = ROOT / "data"
USER_AGENT = "FieldShift/1.0 (+local precompute)"
_CAFILE = os.getenv("SSL_CERT_FILE") or ("/etc/ssl/cert.pem" if Path("/etc/ssl/cert.pem").exists() else None)
SSL_CONTEXT = ssl.create_default_context(cafile=_CAFILE)


def log(message: str) -> None:
    print(f"[precompute] {message}", flush=True)


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError as error:
        raise SystemExit(f"Configuration file not found: {path}") from error
    except json.JSONDecodeError as error:
        raise SystemExit(f"Invalid JSON in {path}: {error}") from error


def request_json(
    url: str,
    *,
    params: dict[str, str] | list[tuple[str, str]] | None = None,
    retries: int = 3,
) -> Any:
    target = f"{url}?{urlencode(params, doseq=True)}" if params else url
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            request = Request(target, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
                if response.status >= 400:
                    raise RuntimeError(f"HTTP {response.status}")
                return json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, ValueError, RuntimeError) as error:
            last_error = error
            if attempt + 1 < retries:
                delay = 2**attempt
                log(f"request failed ({error}); retrying in {delay}s")
                time.sleep(delay)
    raise RuntimeError(f"request failed after {retries} attempts: {last_error}") from last_error


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def base_record(
    *,
    dataset: dict[str, Any],
    observed_at: str | None,
    estimated: bool,
    confidence: str,
    quality_flags: list[str],
    values: Any,
) -> dict[str, Any]:
    return {
        "dataset_id": dataset["dataset_id"],
        "source": dataset["provider"],
        "resolution_m": dataset["resolution_m"],
        "observed_at": observed_at,
        "fetched_at": iso_now(),
        "quality_flags": quality_flags,
        "confidence": confidence,
        "estimated": estimated,
        "values": values,
    }


def fetch_power(plot: dict[str, Any], dataset: dict[str, Any], days: int) -> dict[str, Any]:
    end = date.today()
    start = end - timedelta(days=max(days - 1, 0))
    point = plot["point"]
    payload = request_json(
        dataset["endpoint"],
        params={
            "parameters": ",".join(dataset["parameters"]),
            "community": "AG",
            "longitude": str(point["longitude"]),
            "latitude": str(point["latitude"]),
            "start": start.strftime("%Y%m%d"),
            "end": end.strftime("%Y%m%d"),
            "format": "JSON",
        },
    )
    parameters = payload.get("properties", {}).get("parameter", {})
    values = {
        key: {
            day: value
            for day, value in series.items()
            if isinstance(value, (int, float)) and value > -900
        }
        for key, series in parameters.items()
    }
    return base_record(
        dataset=dataset,
        observed_at=end.isoformat(),
        estimated=False,
        confidence="Medium",
        quality_flags=["daily point context; about 50 km resolution"],
        values=values,
    )


def fetch_soilgrids(plot: dict[str, Any], dataset: dict[str, Any], days: int = 0) -> dict[str, Any]:
    point = plot["point"]
    payload = request_json(
        dataset["endpoint"],
        params=[
            ("lon", str(point["longitude"])),
            ("lat", str(point["latitude"])),
            *[("property", value) for value in dataset["properties"]],
            ("depth", "0-5cm"),
            ("depth", "5-15cm"),
            ("depth", "15-30cm"),
            ("value", "mean"),
        ],
    )
    return base_record(
        dataset=dataset,
        observed_at=None,
        estimated=False,
        confidence="Medium",
        quality_flags=["baseline soil property; about 250 m resolution"],
        values=payload,
    )


def fetch_srtm(plot: dict[str, Any], dataset: dict[str, Any], days: int = 0) -> dict[str, Any]:
    endpoint = os.getenv("SRTM_VALUE_ENDPOINT") or dataset.get("value_endpoint")
    if not endpoint:
        raise RuntimeError(
            "SRTM value endpoint is not configured. The configured LP DAAC URL is a catalog, "
            "not a point-value API. Verify a SRTM service and set SRTM_VALUE_ENDPOINT."
        )
    raise RuntimeError(
        f"SRTM endpoint {endpoint} is configured but its request/response contract must be verified before use."
    )


def earthdata_download(plot: dict[str, Any], dataset: dict[str, Any], days: int, limit: int = 20) -> list[Path]:
    token = os.getenv("EARTHDATA_TOKEN")
    if not token:
        raise RuntimeError("EARTHDATA_TOKEN is required for SMAP, HLS, and MODIS retrieval.")
    try:
        import earthaccess
    except ImportError as error:
        raise RuntimeError("Install requirements-live.txt for Earthdata retrieval.") from error

    earthaccess.login(strategy="environment", persist=False)
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)
    point = plot["point"]
    short_names = dataset.get("short_names", [dataset["short_name"]])
    granules = []
    for short_name in short_names:
        granules.extend(
            earthaccess.search_data(
                short_name=short_name,
                bounding_box=(point["longitude"], point["latitude"], point["longitude"], point["latitude"]),
                temporal=(start, end),
                count=limit,
            )
        )
    if not granules:
        raise RuntimeError(f"No Earthdata granules found for {dataset['dataset_id']}.")
    folder = Path(tempfile.mkdtemp(prefix="field-shift-earthdata-"))
    downloaded = earthaccess.download(granules, local_path=folder)
    files = [Path(item) for item in downloaded if Path(item).is_file()]
    if not files:
        raise RuntimeError(f"Earthdata returned no downloaded files for {dataset['dataset_id']}.")
    return files


def _finite_values(values: Any) -> list[float]:
    import math
    import numpy as np

    array = np.asarray(values).astype(float).reshape(-1)
    return [float(value) for value in array if math.isfinite(float(value)) and float(value) > -900]


def _find_hdf5_dataset(group: Any, names: tuple[str, ...]) -> Any:
    for name, value in group.items():
        if hasattr(value, "items"):
            found = _find_hdf5_dataset(value, names)
            if found is not None:
                return found
        elif any(name.lower().endswith(candidate.lower()) for candidate in names):
            return value
    return None


def _grid_cell_value(handle: Any, dataset: Any, plot: dict[str, Any]) -> float:
    import numpy as np

    latitude = _find_hdf5_dataset(handle, ("latitude", "lat"))
    longitude = _find_hdf5_dataset(handle, ("longitude", "lon"))
    if latitude is None or longitude is None:
        raise RuntimeError("SMAP granule has no latitude/longitude arrays for grid-cell lookup.")
    latitudes = np.asarray(latitude[...]).reshape(-1)
    longitudes = np.asarray(longitude[...]).reshape(-1)
    target = np.square(latitudes - plot["point"]["latitude"]) + np.square(longitudes - plot["point"]["longitude"])
    index = int(np.nanargmin(target))
    values = np.asarray(dataset[...]).reshape(-1).astype(float)
    if index >= len(values) or not np.isfinite(values[index]) or values[index] <= -900:
        raise RuntimeError("SMAP nearest grid cell has no valid value.")
    return float(values[index])


def fetch_smap(plot: dict[str, Any], dataset: dict[str, Any], days: int) -> dict[str, Any]:
    files = earthdata_download(plot, dataset, min(days, 14), limit=20)
    try:
        import h5py
    except ImportError as error:
        raise RuntimeError("Install requirements-live.txt for SMAP HDF5 extraction.") from error

    series: list[dict[str, Any]] = []
    for path in files:
        with h5py.File(path, "r") as handle:
            surface = _find_hdf5_dataset(handle, ("sm_surface", "soil_moisture_surface"))
            rootzone = _find_hdf5_dataset(handle, ("sm_rootzone", "soil_moisture_rootzone"))
            if surface is None or rootzone is None:
                continue
            try:
                surface_value = _grid_cell_value(handle, surface, plot)
                rootzone_value = _grid_cell_value(handle, rootzone, plot)
            except RuntimeError:
                continue
            series.append({
                "observed_at": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).date().isoformat(),
                "surface_m3_m3": surface_value,
                "root_zone_m3_m3": rootzone_value,
                "grid_lookup": "nearest SMAP grid cell; regional context, not plot-level measurement",
            })
    if not series:
        raise RuntimeError("SMAP files did not expose usable surface/root-zone datasets.")
    return base_record(
        dataset=dataset,
        observed_at=series[-1]["observed_at"],
        estimated=False,
        confidence="Medium",
        quality_flags=["about 9 km regional context", "approximately two-day latency", "not plot-level"],
        values=series,
    )


def _raster_summary(path: Path, plot: dict[str, Any], *, scale: float = 1.0, clear_band: int | None = None) -> float:
    try:
        import numpy as np
        import rasterio
    except ImportError as error:
        raise RuntimeError("Install requirements-live.txt for raster extraction.") from error
    source = rasterio.open(path)
    subdatasets = source.subdatasets
    if subdatasets:
        source.close()
        ndvi_subdataset = next((item for item in subdatasets if "NDVI" in item.upper()), subdatasets[0])
        source = rasterio.open(ndvi_subdataset)
    with source:
        row, column = source.index(plot["point"]["longitude"], plot["point"]["latitude"])
        window = rasterio.windows.Window(max(0, column - 2), max(0, row - 2), 5, 5)
        values = source.read(1, window=window).astype(float) * scale
        values = values[np.isfinite(values)]
        if clear_band is not None:
            clear = source.read(clear_band, window=window)
            values = values[clear == 0]
        if values.size == 0:
            raise RuntimeError(f"No valid raster pixels at plot point in {path.name}.")
        return float(np.mean(values))


def _find_band(files: list[Path], tokens: tuple[str, ...]) -> Path | None:
    for path in files:
        name = path.name.upper()
        if any(token in name for token in tokens) and path.suffix.lower() in (".tif", ".tiff"):
            return path
    return None


def fetch_hls(plot: dict[str, Any], dataset: dict[str, Any], days: int) -> dict[str, Any]:
    files = earthdata_download(plot, dataset, min(days, 60), limit=10)
    red = _find_band(files, ("B04", "B04.TIF", "RED"))
    nir = _find_band(files, ("B05", "B05.TIF", "NIR"))
    fmask = _find_band(files, ("FMASK",))
    if red is None or nir is None:
        raise RuntimeError("HLS granule did not include identifiable red and NIR GeoTIFF bands.")
    try:
        import numpy as np
        import rasterio
    except ImportError as error:
        raise RuntimeError("Install requirements-live.txt for HLS raster extraction.") from error
    with rasterio.open(red) as red_source, rasterio.open(nir) as nir_source:
        row, column = red_source.index(plot["point"]["longitude"], plot["point"]["latitude"])
        window = rasterio.windows.Window(max(0, column - 2), max(0, row - 2), 5, 5)
        red_values = red_source.read(1, window=window).astype(float)
        nir_values = nir_source.read(1, window=window).astype(float)
    clear = np.isfinite(red_values) & np.isfinite(nir_values) & (red_values + nir_values != 0)
    if fmask is not None:
        with rasterio.open(fmask) as mask_source:
            clear &= mask_source.read(1, window=window) == 0
    ndvi = (nir_values - red_values) / (nir_values + red_values)
    ndvi = ndvi[clear & np.isfinite(ndvi)]
    if ndvi.size == 0:
        raise RuntimeError("HLS image had no clear pixels at the plot point.")
    observed = datetime.fromtimestamp(red.stat().st_mtime, timezone.utc).date().isoformat()
    return base_record(
        dataset=dataset,
        observed_at=observed,
        estimated=False,
        confidence="High",
        quality_flags=["cloud-masked", "last clear image used", "30 m plot-health source"],
        values={"last_clear_image": observed, "ndvi": float(np.mean(ndvi)), "clear_pixel_count": int(ndvi.size)},
    )


def fetch_modis(plot: dict[str, Any], dataset: dict[str, Any], days: int) -> dict[str, Any]:
    files = earthdata_download(plot, dataset, max(days, 365), limit=30)
    values = []
    for path in files:
        if path.suffix.lower() not in (".tif", ".tiff", ".hdf", ".h5"):
            continue
        values.append({
            "observed_at": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).date().isoformat(),
            "ndvi": _raster_summary(path, plot, scale=0.0001),
        })
    if not values:
        raise RuntimeError("MODIS download did not include a readable NDVI raster.")
    return base_record(
        dataset=dataset,
        observed_at=values[-1]["observed_at"],
        estimated=False,
        confidence="Medium",
        quality_flags=["16-day composite", "250 m longer-history context"],
        values=values,
    )


FETCHERS = {
    "nasa_power": fetch_power,
    "soilgrids": fetch_soilgrids,
    "srtm": fetch_srtm,
    "smap_l4": fetch_smap,
    "hls": fetch_hls,
    "modis_ndvi": fetch_modis,
}


def write_record(output: Path, plot_id: str, layer: str, record: dict[str, Any]) -> None:
    target = output / plot_id / f"{layer}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    try:
        display_path = target.relative_to(ROOT)
    except ValueError:
        display_path = target
    log(f"wrote {display_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plots", type=Path, default=DEFAULT_PLOTS)
    parser.add_argument("--datasets", type=Path, default=DEFAULT_DATASETS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--only", choices=sorted(FETCHERS), action="append")
    parser.add_argument("--offline", action="store_true", help="Read existing cache files only; never make network requests.")
    args = parser.parse_args()
    if args.days < 1:
        parser.error("--days must be at least 1")

    plots = load_json(args.plots).get("plots", [])
    datasets = load_json(args.datasets)
    selected = args.only or list(FETCHERS)
    failures = 0

    for plot in plots:
        log(f"processing {plot['id']}")
        for layer in selected:
            target = args.output / plot["id"] / f"{layer}.json"
            if args.offline:
                if target.exists():
                    try:
                        display_path = target.relative_to(ROOT)
                    except ValueError:
                        display_path = target
                    log(f"offline cache hit {display_path}")
                else:
                    failures += 1
                    try:
                        display_path = target.relative_to(ROOT)
                    except ValueError:
                        display_path = target
                    log(f"offline cache missing {display_path}")
                continue
            try:
                record = FETCHERS[layer](plot, datasets[layer], args.days)
                write_record(args.output, plot["id"], layer, record)
            except Exception as error:
                failures += 1
                log(f"{plot['id']}/{layer} failed: {error}")
                error_record = base_record(
                    dataset=datasets[layer],
                    observed_at=None,
                    estimated=False,
                    confidence="Low",
                    quality_flags=["live retrieval failed", str(error)],
                    values=None,
                )
                write_record(args.output, plot["id"], layer, error_record)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
