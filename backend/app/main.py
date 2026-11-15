from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .providers.live import LiveProvider
from .providers.mock import MockProvider

ROOT = Path(__file__).resolve().parents[2]
provider_name = os.getenv("FIELD_SHIFT_PROVIDER", "mock").lower()
ttl_seconds = int(os.getenv("FIELD_SHIFT_CACHE_TTL_SECONDS", "86400"))
provider = (
    LiveProvider(ROOT / "data", ROOT / "config" / "plots.json", ttl_seconds)
    if provider_name == "live"
    else MockProvider()
)

app = FastAPI(title="Field Shift data API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _not_found(error: KeyError) -> HTTPException:
    return HTTPException(status_code=404, detail=f"Unknown plot: {error.args[0]}")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "provider": provider_name}


@app.get("/health/data")
def data_health() -> dict:
    return provider.health()


@app.get("/plots")
def plots() -> list[dict]:
    return provider.plots()


@app.get("/plots/{plot_id}/status")
def status(plot_id: str) -> dict:
    try:
        return provider.status(plot_id)
    except KeyError as error:
        raise _not_found(error) from error


@app.get("/plots/{plot_id}/timeseries")
def timeseries(
    plot_id: str,
    layer: str = Query(...),
    start: str | None = None,
    end: str | None = None,
) -> dict:
    try:
        return provider.timeseries(plot_id, layer, start, end)
    except KeyError as error:
        raise _not_found(error) from error


@app.get("/plots/{plot_id}/rotation")
def rotation(plot_id: str) -> dict:
    try:
        return provider.rotation(plot_id)
    except KeyError as error:
        raise _not_found(error) from error


@app.get("/sources")
def sources() -> dict:
    return provider.sources()


def _nearest_plot_id(latitude: float, longitude: float) -> str:
    candidates = provider.plots()
    if not candidates:
        raise HTTPException(status_code=503, detail="No plots are configured")
    return min(
        candidates,
        key=lambda plot: (
            (plot.get("point", {}).get("latitude", latitude) - latitude) ** 2
            + (plot.get("point", {}).get("longitude", longitude) - longitude) ** 2
        ),
    )["id"]


@app.get("/api/health")
def compatibility_health() -> dict:
    return {"status": "ok", "provider": "field-shift-python", "offline_fallback": True}


@app.get("/api/dashboard")
def compatibility_dashboard(lat: float = Query(...), lon: float = Query(...)) -> dict:
    plot_id = _nearest_plot_id(lat, lon)
    plot_status = provider.status(plot_id)
    plot_rotation = provider.rotation(plot_id)
    return {
        "provider": "field-shift-python",
        "plot": plot_status["plot"],
        "status": plot_status,
        "processed": {"source": plot_status.get("source", "demo data")},
        "rotation_analysis": {
            "recommendations": plot_rotation.get("recommendations", []),
            "two_season_plan": plot_rotation.get("two_season_plan", []),
            "risks": plot_rotation.get("risks", []),
        },
        "granules": [],
    }


@app.post("/api/recommendations")
def compatibility_recommendations() -> dict:
    plots = provider.plots()
    if not plots:
        raise HTTPException(status_code=503, detail="No plots are configured")
    return provider.rotation(plots[0]["id"])
