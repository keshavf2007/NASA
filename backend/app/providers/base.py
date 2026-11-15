from __future__ import annotations

from typing import Protocol


class DataProvider(Protocol):
    def plots(self) -> list[dict]:
        ...

    def status(self, plot_id: str) -> dict:
        ...

    def timeseries(self, plot_id: str, layer: str, start: str | None, end: str | None) -> dict:
        ...

    def rotation(self, plot_id: str) -> dict:
        ...

    def sources(self) -> dict:
        ...

    def health(self) -> dict:
        ...
