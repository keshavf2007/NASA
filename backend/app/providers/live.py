from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path

from .mock import MockProvider


class LiveProvider:
    """Reads precomputed JSON first and falls back per request to MockProvider."""

    def __init__(self, data_dir: Path, plots_file: Path, ttl_seconds: int = 86400) -> None:
        self.data_dir = data_dir
        self.plots_file = plots_file
        self.ttl_seconds = ttl_seconds
        self.mock = MockProvider()
        self._dataset_state: dict[str, dict] = {}

    def plots(self) -> list[dict]:
        plots = self._load_json(self.plots_file).get("plots", [])
        return [dict(plot, source="live cache") for plot in plots] if plots else self.mock.plots()

    def status(self, plot_id: str) -> dict:
        try:
            plot = self._plot(plot_id)
            layers = {
                "water": self._cached(plot_id, "smap_l4"),
                "crop_health": self._cached(plot_id, "hls"),
                "heat": self._cached(plot_id, "nasa_power"),
            }
            return {"plot": plot, "source": "live cache", "layers": layers}
        except Exception as error:
            return dict(self.mock.status(plot_id), fallback_reason=str(error))

    def timeseries(self, plot_id: str, layer: str, start: str | None, end: str | None) -> dict:
        try:
            self._plot(plot_id)
            record = self._cached(plot_id, layer)
            values = record.get("values")
            if not isinstance(values, list):
                values = [{"observed_at": record.get("observed_at"), "value": values}]
            return {"plot_id": plot_id, "layer": layer, "source": record["source"], "estimated": record["estimated"], "values": values}
        except Exception as error:
            result = self.mock.timeseries(plot_id, layer, start, end)
            result["fallback_reason"] = str(error)
            return result

    def rotation(self, plot_id: str) -> dict:
        try:
            status = self.status(plot_id)
            result = self.mock.rotation(plot_id)
            result["source"] = status["source"]
            return result
        except Exception:
            return self.mock.rotation(plot_id)

    def sources(self) -> dict:
        return {"provider": "live cache with demo fallback", "datasets": self._dataset_state}

    def health(self) -> dict:
        return {"provider": "live cache", "status": "ok", "datasets": self._dataset_state}

    def _cached(self, plot_id: str, layer: str) -> dict:
        path = self.data_dir / plot_id / f"{layer}.json"
        if not path.exists():
            raise FileNotFoundError(f"cache missing: {path}")
        age = time.time() - path.stat().st_mtime
        record = self._load_json(path)
        if record.get("values") is None or "live retrieval failed" in record.get("quality_flags", []):
            raise RuntimeError(f"cache contains a failed retrieval: {path}")
        state = {
            "status": "fresh" if age <= self.ttl_seconds else "stale",
            "last_fetched": record.get("fetched_at"),
            "age_seconds": max(0, int(age)),
        }
        self._dataset_state[layer] = state
        if age > self.ttl_seconds:
            raise RuntimeError(f"cache expired: {path}")
        record["data_age_seconds"] = max(0, int(age))
        return record

    def _plot(self, plot_id: str) -> dict:
        for plot in self.plots():
            if plot["id"] == plot_id:
                return plot
        raise KeyError(plot_id)

    @staticmethod
    def _load_json(path: Path) -> dict:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
