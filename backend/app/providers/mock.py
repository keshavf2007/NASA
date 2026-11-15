from __future__ import annotations

import hashlib
from datetime import datetime, timezone

from .base import DataProvider


class MockProvider(DataProvider):
    """Deterministic fallback used when cached live data is unavailable."""

    _plots = [
        {"id": "cotton-dry", "name": "Cotton field", "crop": "Cotton", "area_ha": 1.2},
        {"id": "soybean-ok", "name": "Soybean field", "crop": "Soybean", "area_ha": 0.9},
        {"id": "chickpea-wet", "name": "Chickpea field", "crop": "Chickpea", "area_ha": 1.0},
        {"id": "fallow", "name": "Fallow field", "crop": "Sorghum", "area_ha": 0.7},
        {"id": "mandarin", "name": "Mandarin orchard", "crop": "Mandarin", "area_ha": 1.5},
    ]

    def plots(self) -> list[dict]:
        return [dict(plot, source="demo data") for plot in self._plots]

    def status(self, plot_id: str) -> dict:
        plot = self._find(plot_id)
        statuses = {
            "cotton-dry": ("dry", "okay", "okay"),
            "soybean-ok": ("okay", "okay", "okay"),
            "chickpea-wet": ("wet", "okay", "wet"),
        }
        water, health, heat = statuses.get(plot_id, ("okay", "okay", "okay"))
        return {
            "plot": plot,
            "source": "demo data",
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "layers": {
                "water": {"status": water, "estimated": True, "confidence": "Low"},
                "crop_health": {"status": health, "estimated": True, "confidence": "Low"},
                "heat": {"status": heat, "estimated": True, "confidence": "Low"},
            },
        }

    def timeseries(self, plot_id: str, layer: str, start: str | None, end: str | None) -> dict:
        self._find(plot_id)
        seed = int(hashlib.sha256(f"{plot_id}:{layer}".encode()).hexdigest()[:8], 16)
        values = [{"date": f"demo-{index:02d}", "value": round(0.35 + ((seed + index) % 30) / 100, 3)} for index in range(14)]
        return {"plot_id": plot_id, "layer": layer, "source": "demo data", "estimated": True, "values": values}

    def rotation(self, plot_id: str) -> dict:
        plot = self._find(plot_id)
        options = [
            {"crop": "Green gram (moong)", "score": 84, "reasons": ["Low water need.", "Breaks the crop family."], "risk": "Check pests after heavy rain."},
            {"crop": "Pigeon pea (tur)", "score": 81, "reasons": ["Restores soil nitrogen.", "Fits a drier outlook."], "risk": "Confirm the sowing window."},
            {"crop": "Sunflower", "score": 74, "reasons": ["Changes the crop family.", "Handles heat well."], "risk": "Watch heat during flowering."},
        ]
        if plot["crop"] == "Mandarin":
            options = [{"crop": "Orchard management", "score": 100, "reasons": ["Perennial orchard should not be rotated."], "risk": "Check leaves and drainage."}]
        return {"plot": plot, "source": "demo data", "recommendations": options}

    def sources(self) -> dict:
        return {"provider": "demo data", "datasets": {}}

    def health(self) -> dict:
        return {"provider": "demo data", "status": "fallback", "datasets": {}}

    def _find(self, plot_id: str) -> dict:
        for plot in self._plots:
            if plot["id"] == plot_id:
                return dict(plot, source="demo data")
        raise KeyError(plot_id)
