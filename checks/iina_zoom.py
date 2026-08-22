#!/usr/bin/env python3
"""Independent percent/log2 zoom math for IINA QoL (stdlib only).

Mirrors the documented plugin contract so checks run even when plugin JS is
absent. mpv ``video-zoom`` is log2 of the scale factor:

    percent = 100 * 2 ** video_zoom

Hard bounds are 100–1000%. Zooming out into ``(100, 105]`` snaps to 100%.
Missing or non-finite cursor coordinates are fail-closed: no mutation.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from typing import Any

MIN_PERCENT = 100.0
MAX_PERCENT = 1000.0
DETENT_PERCENT = 105.0
EPSILON = 1e-9


@dataclass(frozen=True)
class ZoomResult:
    ok: bool
    percent: float
    log2: float
    mutated: bool
    reason: str | None = None


def percent_from_log2(zoom: float) -> float:
    return 100.0 * (2.0**zoom)


def log2_from_percent(percent: float) -> float:
    if percent <= 0.0 or not math.isfinite(percent):
        raise ValueError("percent must be a positive finite value")
    return math.log2(percent / 100.0)


def clamp_percent(
    percent: float,
    minimum: float = MIN_PERCENT,
    maximum: float = MAX_PERCENT,
) -> float:
    return min(max(percent, minimum), maximum)


def apply_outward_detent(
    old_percent: float,
    new_percent: float,
    detent: float = DETENT_PERCENT,
) -> float:
    """Snap ``(100, detent]`` to 100% only while zooming out."""
    if new_percent < old_percent - EPSILON and MIN_PERCENT < new_percent <= detent:
        return MIN_PERCENT
    return new_percent


def cursor_is_usable(cursor: Any) -> bool:
    if not isinstance(cursor, dict):
        return False
    raw_x = cursor.get("x")
    raw_y = cursor.get("y")
    if raw_x is None or raw_y is None:
        return False
    try:
        pos_x = float(raw_x)
        pos_y = float(raw_y)
    except (TypeError, ValueError):
        return False
    if "hover" in cursor and cursor.get("hover") is not True:
        return False
    if abs(pos_x) < EPSILON and abs(pos_y) < EPSILON:
        return False
    return math.isfinite(pos_x) and math.isfinite(pos_y)


def geometry_is_usable(geometry: Any) -> bool:
    if geometry is None:
        return True
    if not isinstance(geometry, dict):
        return False
    try:
        width = float(geometry.get("w"))
        height = float(geometry.get("h"))
    except (TypeError, ValueError):
        return False
    return math.isfinite(width) and math.isfinite(height) and width > 0.0 and height > 0.0


def zoom_at_cursor(
    old_percent: float,
    delta_log2: float,
    cursor: Any,
    geometry: Any = None,
    minimum: float = MIN_PERCENT,
    maximum: float = MAX_PERCENT,
) -> ZoomResult:
    """Clamp the requested target, apply the outward detent, fail-closed on cursor."""
    old = clamp_percent(float(old_percent), minimum, maximum)
    old_log2 = log2_from_percent(old)
    if not cursor_is_usable(cursor) or not geometry_is_usable(geometry):
        return ZoomResult(
            ok=False,
            percent=old,
            log2=old_log2,
            mutated=False,
            reason="missing-cursor",
        )

    requested = percent_from_log2(old_log2 + float(delta_log2))
    clamped = clamp_percent(requested, minimum, maximum)
    snapped = apply_outward_detent(old, clamped)
    snapped = clamp_percent(snapped, minimum, maximum)
    return ZoomResult(
        ok=True,
        percent=snapped,
        log2=log2_from_percent(snapped),
        mutated=abs(snapped - old) > EPSILON,
        reason=None,
    )


def _approx(left: float, right: float, tol: float = 1e-6) -> bool:
    return abs(left - right) <= tol


def self_test() -> int:
    cases: list[tuple[str, bool]] = []

    def check(name: str, cond: bool) -> None:
        cases.append((name, cond))

    check("percent(0)=100", _approx(percent_from_log2(0.0), 100.0))
    check("percent(1)=200", _approx(percent_from_log2(1.0), 200.0))
    check("percent(log2(10))=1000", _approx(percent_from_log2(math.log2(10.0)), 1000.0))
    check("log2(100)=0", _approx(log2_from_percent(100.0), 0.0))
    check("log2(200)=1", _approx(log2_from_percent(200.0), 1.0))
    check("clamp below", _approx(clamp_percent(50.0), 100.0))
    check("clamp above", _approx(clamp_percent(2500.0), 1000.0))
    check("clamp inside", _approx(clamp_percent(250.0), 250.0))
    check("detent outward", _approx(apply_outward_detent(110.0, 104.0), 100.0))
    check("detent outward edge", _approx(apply_outward_detent(200.0, 105.0), 100.0))
    check("detent skips above 105", _approx(apply_outward_detent(200.0, 106.0), 106.0))
    check("detent does not trap zoom-in", _approx(apply_outward_detent(100.0, 104.0), 104.0))

    cursor = {"x": 12.0, "y": 34.0}
    stepped = zoom_at_cursor(100.0, 1.0, cursor)
    check("step ok", stepped.ok and stepped.mutated and _approx(stepped.percent, 200.0))

    ceiling = zoom_at_cursor(800.0, 2.0, cursor)
    check("step clamps max", ceiling.ok and _approx(ceiling.percent, 1000.0))

    floor = zoom_at_cursor(110.0, -2.0, cursor)
    check("step clamps min", floor.ok and _approx(floor.percent, 100.0))

    detent = zoom_at_cursor(110.0, log2_from_percent(104.0) - log2_from_percent(110.0), cursor)
    check("step detent", detent.ok and _approx(detent.percent, 100.0))

    inbound = zoom_at_cursor(100.0, log2_from_percent(104.0), cursor)
    check("step zoom-in not detained", inbound.ok and _approx(inbound.percent, 104.0))

    no_hover = zoom_at_cursor(200.0, 1.0, {"x": 1.0, "y": 1.0, "hover": False})
    check("fail-closed hover false", (not no_hover.ok) and (not no_hover.mutated))

    hover_true = zoom_at_cursor(100.0, 1.0, {"x": 1.0, "y": 1.0, "hover": True})
    check("hover true still zooms", hover_true.ok and _approx(hover_true.percent, 200.0))
    origin = zoom_at_cursor(100.0, 1.0, {"x": 0.0, "y": 0.0, "hover": True})
    check("fail-closed origin 0,0", (not origin.ok) and (not origin.mutated))

    missing = zoom_at_cursor(200.0, 1.0, None)
    check(
        "fail-closed None",
        (not missing.ok) and (not missing.mutated) and _approx(missing.percent, 200.0),
    )

    nan_cursor = zoom_at_cursor(200.0, 1.0, {"x": float("nan"), "y": 1.0})
    check("fail-closed NaN", (not nan_cursor.ok) and (not nan_cursor.mutated))

    inf_cursor = zoom_at_cursor(200.0, 1.0, {"x": 1.0, "y": float("inf")})
    check("fail-closed inf", (not inf_cursor.ok) and (not inf_cursor.mutated))

    partial = zoom_at_cursor(200.0, 1.0, {"x": 1.0})
    check("fail-closed missing y", (not partial.ok) and (not partial.mutated))

    bad_geom = zoom_at_cursor(200.0, 1.0, cursor, geometry={"w": 0.0, "h": 10.0})
    check("fail-closed zero geometry", (not bad_geom.ok) and (not bad_geom.mutated))

    failed = [name for name, ok in cases if not ok]
    if failed:
        print("iina_zoom: FAIL " + ", ".join(failed), file=sys.stderr)
        return 1
    print("iina_zoom: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="IINA QoL zoom math self-test")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the independent percent/log2 clamp cases",
    )
    args = parser.parse_args(argv)
    if not args.self_test:
        parser.print_help(sys.stderr)
        return 2
    return self_test()


if __name__ == "__main__":
    raise SystemExit(main())
