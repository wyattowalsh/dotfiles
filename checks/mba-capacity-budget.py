"""Offline APFS peak-budget arithmetic; reads bounded JSON from stdin only.

Schema v2 lists every target volume and selected Draw Things / LM Studio model.
Schema v3 is opt-in via mode=single_inflight_file_same_volume. It checks
both a pre-E0 and a fresh post-E0 baseline independently. The post-E0 free
count already includes resident E0 media: E1 charges only new/changed/retained
bytes, snapshot divergence and one temporary file, never an E0 full retry.
V3 optionally accepts pre_e0_anchor for a frozen campaign-start observation;
post-E0 must still be fresh. Anchor receipt hashes are unverified references.
V3 attestations and dates are supplied assertions, not live host proofs.
Each allocation and model component is a *peak additional* byte count on its
named volume. Downloads and installed weights are charged concurrently, as are
outputs, scratch, context/KV and swap; none is a reclaim or memory credit.
Volumes sharing an APFS container share ONE observed pre-staging free count:
their peaks are added before checking that container's low-water threshold.
The eligible_media allocation bounds the full local logical payload plus
positive target filesystem overhead. The retry bound covers a complete target
copy. peak_staging_overlap includes concurrent retry and publication copies
beyond eligible_media: one retry for same-volume rename, or a retry and a
publication copy for second_copy. It is not counted twice.

This is not a census, proof of current MBA free space, or permission to stage,
download, allocate a VM, delete or reclaim data. Supplied dates, identities and
booleans do not prove freshness, placement, provenance or unified-memory fit.
"""

from __future__ import annotations

import hashlib
import json
import sys
import unicodedata
from datetime import date, datetime, timedelta, timezone
from typing import Any

SCHEMA_VERSION = 2
MAX_INPUT_BYTES = 65_536
MAX_INTEGER = (1 << 63) - 1
MAX_MODELS = 32
ALLOCATIONS = (
    "eligible_media",
    "peak_staging_overlap",
    "growth",
    "navidrome_state",
    "syncthing_state",
    "docker_vm_cap",
    "docker_images_volumes_cap",
    "mcphub_state_cap",
    "os_container_reserve",
)
POSITIVE_ALLOCATIONS = set(ALLOCATIONS) - {"peak_staging_overlap"}
MODEL_BYTES = (
    "weights_bytes",
    "download_peak_bytes",
    "outputs_bytes",
    "scratch_bytes",
    "context_kv_bytes",
    "swap_bytes",
)
POSITIVE_MODEL_BYTES = {
    "Draw Things": {"weights_bytes", "download_peak_bytes", "outputs_bytes", "scratch_bytes"},
    "LM Studio": {"weights_bytes", "download_peak_bytes", "context_kv_bytes", "swap_bytes"},
}


class InvalidBudget(ValueError):
    """A required observation is missing, unknown or internally inconsistent."""


def fields(value: Any, names: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != names:
        raise InvalidBudget("invalid_schema")
    return value


def integer(value: Any, *, positive: bool = False) -> int:
    if (
        type(value) is not int
        or not (0 <= value <= MAX_INTEGER)
        or (positive and value == 0)
    ):
        raise InvalidBudget("invalid_or_unknown_bytes")
    return value


def add_bounded(left: int, right: int) -> int:
    if left > MAX_INTEGER - right:
        raise InvalidBudget("overflow")
    return left + right


def identity(value: Any) -> str:
    if (
        not isinstance(value, str)
        or not value
        or len(value) > 128
        or value.strip() != value
    ):
        raise InvalidBudget("invalid_identity")
    return value


def observed(value: Any) -> str:
    if not isinstance(value, str) or len(value) != 10:
        raise InvalidBudget("invalid_date")
    try:
        if date.fromisoformat(value).isoformat() != value:
            raise InvalidBudget("invalid_date")
    except ValueError as exc:
        raise InvalidBudget("invalid_date") from exc
    return value


def confirmed(value: Any) -> None:
    if value is not True:
        raise InvalidBudget("incomplete_measurement")


def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidBudget("duplicate_field")
        result[key] = value
    return result


def evaluate_v2(raw: Any) -> dict[str, Any]:
    data = fields(
        raw,
        {
            "schema_version",
            "observed_on",
            "source",
            "targets",
            "publication_mode",
            "peak_retry_allocation_bytes",
            "growth_horizon_days",
            "allocations",
            "models",
        },
    )
    if type(data["schema_version"]) is not int or data["schema_version"] != SCHEMA_VERSION:
        raise InvalidBudget("invalid_schema")
    day = observed(data["observed_on"])
    if data["publication_mode"] not in ("same_volume_rename", "second_copy"):
        raise InvalidBudget("invalid_publication_mode")
    retry = integer(data["peak_retry_allocation_bytes"], positive=True)
    integer(data["growth_horizon_days"], positive=True)

    source = fields(
        data["source"],
        {
            "volume_id",
            "container_id",
            "eligible_allocated_local_bytes",
            "eligible_logical_bytes",
            "target_copy_overhead_bytes",
            "complete",
            "local_only",
            "overlapping_views_resolved",
            "symlink_targets_deduplicated",
            "eligible_cloud_placeholders",
            "unknown_bytes",
            "read_errors",
            "unsized_paths",
        },
    )
    identity(source["volume_id"])
    identity(source["container_id"])
    allocated = integer(source["eligible_allocated_local_bytes"], positive=True)
    logical = integer(source["eligible_logical_bytes"], positive=True)
    overhead = integer(source["target_copy_overhead_bytes"], positive=True)
    for key in (
        "complete",
        "local_only",
        "overlapping_views_resolved",
        "symlink_targets_deduplicated",
    ):
        confirmed(source[key])
    for key in (
        "eligible_cloud_placeholders",
        "unknown_bytes",
        "read_errors",
        "unsized_paths",
    ):
        if integer(source[key]) != 0:
            raise InvalidBudget("incomplete_measurement")

    targets = data["targets"]
    if not isinstance(targets, list) or not targets:
        raise InvalidBudget("invalid_schema")
    volumes: dict[str, dict[str, Any]] = {}
    containers: dict[str, dict[str, Any]] = {}
    for entry in targets:
        target = fields(
            entry,
            {
                "volume_id",
                "container_id",
                "container_capacity_bytes",
                "container_free_bytes",
                "low_water_abort_bytes",
                "complete",
                "snapshots_accounted",
                "baseline",
            },
        )
        volume_id = identity(target["volume_id"])
        container_id = identity(target["container_id"])
        capacity = integer(target["container_capacity_bytes"], positive=True)
        free = integer(target["container_free_bytes"])
        low_water = integer(target["low_water_abort_bytes"], positive=True)
        if (
            free > capacity
            or low_water > capacity
            or target["baseline"] != "pre_staging"
        ):
            raise InvalidBudget("inconsistent_target_measurement")
        confirmed(target["complete"])
        confirmed(target["snapshots_accounted"])
        if volume_id in volumes:
            raise InvalidBudget("invalid_target_volumes")
        measurement = (capacity, free, low_water)
        if container_id in containers:
            if containers[container_id]["measurement"] != measurement:
                raise InvalidBudget("inconsistent_target_measurement")
        else:
            containers[container_id] = {"measurement": measurement, "peak": 0}
        volumes[volume_id] = {
            "container_id": container_id,
            "base": 0,
            "model": {key: 0 for key in MODEL_BYTES},
            "peak": 0,
        }

    def target_for(volume_id: Any, container_id: Any) -> dict[str, Any]:
        volume = volumes.get(identity(volume_id))
        if volume is None or volume["container_id"] != identity(container_id):
            raise InvalidBudget("cross_container_or_volume_allocation")
        return volume

    def charge(volume: dict[str, Any], amount: int) -> None:
        volume["peak"] = add_bounded(volume["peak"], amount)
        container = containers[volume["container_id"]]
        container["peak"] = add_bounded(container["peak"], amount)

    entries = data["allocations"]
    if not isinstance(entries, list) or len(entries) != len(ALLOCATIONS):
        raise InvalidBudget("invalid_allocations")
    amounts: dict[str, int] = {}
    locations: dict[str, str] = {}
    for entry in entries:
        item = fields(entry, {"name", "volume_id", "container_id", "bytes"})
        name = item["name"]
        if not isinstance(name, str) or name not in ALLOCATIONS or name in amounts:
            raise InvalidBudget("invalid_allocations")
        volume = target_for(item["volume_id"], item["container_id"])
        amount = integer(item["bytes"], positive=name in POSITIVE_ALLOCATIONS)
        charge(volume, amount)
        volume["base"] = add_bounded(volume["base"], amount)
        amounts[name] = amount
        locations[name] = item["volume_id"]
    if (
        set(amounts) != set(ALLOCATIONS)
        or amounts["eligible_media"] < add_bounded(max(allocated, logical), overhead)
    ):
        raise InvalidBudget("inconsistent_source_allocation")
    if locations["eligible_media"] != locations["peak_staging_overlap"]:
        raise InvalidBudget("cross_volume_media_overlap")
    media = amounts["eligible_media"]
    if retry < media:
        raise InvalidBudget("insufficient_retry_allocation")
    required_overlap = (
        add_bounded(retry, media)
        if data["publication_mode"] == "second_copy"
        else retry
    )
    if amounts["peak_staging_overlap"] < required_overlap:
        reason = (
            "insufficient_second_copy_overlap"
            if data["publication_mode"] == "second_copy"
            else "insufficient_retry_overlap"
        )
        raise InvalidBudget(reason)

    models = data["models"]
    if not isinstance(models, list) or not (2 <= len(models) <= MAX_MODELS):
        raise InvalidBudget("invalid_models")
    selected: set[tuple[str, str]] = set()
    selected_models: list[dict[str, Any]] = []
    for entry in models:
        model = fields(
            entry,
            {"app", "model_id", "volume_id", "container_id", *MODEL_BYTES},
        )
        app = model["app"]
        if not isinstance(app, str) or app not in POSITIVE_MODEL_BYTES:
            raise InvalidBudget("invalid_models")
        key = (app, identity(model["model_id"]))
        if key in selected:
            raise InvalidBudget("invalid_models")
        selected.add(key)
        volume = target_for(model["volume_id"], model["container_id"])
        model_peak = 0
        for field in MODEL_BYTES:
            amount = integer(model[field], positive=field in POSITIVE_MODEL_BYTES[app])
            charge(volume, amount)
            model_peak = add_bounded(model_peak, amount)
            volume["model"][field] = add_bounded(volume["model"][field], amount)
        selected_models.append(
            {
                "app": app,
                "model_id": key[1],
                "volume_id": model["volume_id"],
                "container_id": model["container_id"],
                "peak_additional_bytes": model_peak,
            }
        )
    if {app for app, _ in selected} != set(POSITIVE_MODEL_BYTES):
        raise InvalidBudget("invalid_models")
    if any(volume["peak"] == 0 for volume in volumes.values()):
        raise InvalidBudget("invalid_target_volumes")

    per_container = []
    shortfall = 0
    peak = 0
    for container_id, item in containers.items():
        capacity, free, low_water = item["measurement"]
        projected = free - item["peak"]
        deficit = max(0, low_water - projected)
        shortfall = add_bounded(shortfall, deficit)
        peak = add_bounded(peak, item["peak"])
        per_container.append(
            {
                "container_id": container_id,
                "container_capacity_bytes": capacity,
                "container_free_bytes": free,
                "peak_additional_bytes": item["peak"],
                "projected_free_bytes": projected,
                "low_water_abort_bytes": low_water,
                "shortfall_bytes": deficit,
            }
        )
    per_volume = [
        {
            "volume_id": volume_id,
            "container_id": volume["container_id"],
            "base_allocations_bytes": volume["base"],
            "model_peak_bytes": volume["model"],
            "peak_additional_bytes": volume["peak"],
        }
        for volume_id, volume in volumes.items()
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "PASS" if shortfall == 0 else "BLOCKED",
        "observed_on": day,
        "media_volume_id": locations["eligible_media"],
        "peak_additional_bytes": peak,
        "shortfall_bytes": shortfall,
        "per_volume": per_volume,
        "per_container": per_container,
        "selected_models": selected_models,
        "scope": "supplied-input ARITHMETIC ONLY",
        "limitation": "Supplied dates, IDs and booleans are not proof of freshness or provenance; no live MBA free-space census, model memory fit, recovery, reclaim or approval proof.",
    }


# Version 3 uses a different topology and separate measured free baselines. Do not
# merge these fields into v2: its full-library retry and output are a compatibility
# contract for all existing inputs.
V3_MODE = "single_inflight_file_same_volume"
V3_ALLOCATIONS = tuple(name for name in ALLOCATIONS if name not in (
    "eligible_media", "peak_staging_overlap"
))


def fresh_day(value: Any, today: str) -> str:
    day = observed(value)
    if day != today:
        raise InvalidBudget("stale_measurement")
    return day


def timestamp(value: Any) -> datetime:
    if not isinstance(value, str) or len(value) != 20 or not value.endswith("Z"):
        raise InvalidBudget("invalid_timestamp")
    try:
        instant = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise InvalidBudget("invalid_timestamp") from exc
    if instant.strftime("%Y-%m-%dT%H:%M:%SZ") != value:
        raise InvalidBudget("invalid_timestamp")
    return instant


def fresh_timestamp(
    value: Any, observed_on: Any, *, as_of: datetime | None = None
) -> datetime:
    measured = timestamp(value)
    now = datetime.now(timezone.utc) if as_of is None else as_of
    if (
        measured > now
        or now - measured > timedelta(hours=1)
        or observed(observed_on) != measured.date().isoformat()
    ):
        raise InvalidBudget("stale_measurement")
    return measured


def pre_e0_measurement_digest(data: dict[str, Any]) -> str:
    """Canonical frozen measurement: exact census, target observations and E0 setup.

    Only publication time is omitted: it is not known at the campaign start.
    A matching digest proves input equality, not that a start receipt exists or
    that its supplied timestamp, epoch or measurement came from a real host.
    """
    measurement = {
        "source": data["source"],
        "targets": sorted(data["targets"], key=lambda target: target["volume_id"]),
        "e0": {
            key: value for key, value in data["e0"].items() if key != "published_at"
        },
    }
    encoded = json.dumps(
        measurement, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def v3_root(value: Any, volume_id: str, container_id: str) -> str:
    root = fields(value, {"path", "volume_id", "container_id", "symlink_free", "identity_confirmed"})
    path = root["path"]
    if not isinstance(path, str):
        raise InvalidBudget("invalid_root")
    # Conservative comparison: APFS path spellings may alias by normalization
    # or case even though the supplied byte strings differ. Validate the
    # canonical form too, so compatibility characters cannot hide traversal.
    canonical = unicodedata.normalize("NFKC", path).casefold()
    if (
        not path.startswith("/")
        or not canonical.startswith("/")
        or canonical == "/"
        or "//" in canonical
        or any(part in (".", "..") for part in canonical.split("/"))
        or canonical.endswith("/")
        or "\x00" in canonical
    ):
        raise InvalidBudget("invalid_root")
    if identity(root["volume_id"]) != volume_id or identity(root["container_id"]) != container_id:
        raise InvalidBudget("wrong_root_volume")
    confirmed(root["symlink_free"])
    confirmed(root["identity_confirmed"])
    return canonical


def evaluate_v3(raw: Any) -> dict[str, Any]:
    """Check two independent APFS low-water boundaries for the opt-in topology.

    E0 peak = complete_target + max_one_file_temp + temp_overhead + common.
    E1 peak = added + replaced + retained + snapshot_divergence
              + max_one_file_temp + temp_overhead + common, from observed
              post-E0 free (never subtract resident E0 twice or credit replaces).
    `common` includes growth, states, VM/images, OS reserve and all selected
    model weights/downloads/outputs/scratch/KV/swap, summed once per container.
    All target volumes share one APFS container and one pre-E0 measurement.
    Supplied root attestations/epochs are unverified by this offline tool.
    """
    required = {
        "schema_version", "mode", "observed_on", "source", "targets", "e0", "e1",
        "growth_horizon_days", "allocations", "models",
    }
    if isinstance(raw, dict) and "pre_e0_anchor" in raw:
        required.add("pre_e0_anchor")
    data = fields(raw, required)
    if type(data["schema_version"]) is not int or data["schema_version"] != 3 or data["mode"] != V3_MODE:
        raise InvalidBudget("invalid_schema")
    today = datetime.now(timezone.utc).date().isoformat()
    day = fresh_day(data["observed_on"], today)
    integer(data["growth_horizon_days"], positive=True)
    anchor = None
    started_at = None
    if "pre_e0_anchor" in data:
        anchor = fields(data["pre_e0_anchor"], {
            "e0_epoch", "started_at", "measurement_sha256", "start_receipt_sha256",
        })
        identity(anchor["e0_epoch"])
        started_at = timestamp(anchor["started_at"])
        if started_at > datetime.now(timezone.utc):
            raise InvalidBudget("invalid_pre_e0_anchor")
        for field in ("measurement_sha256", "start_receipt_sha256"):
            digest = anchor[field]
            if (not isinstance(digest, str) or len(digest) != 64
                    or any(character not in "0123456789abcdef" for character in digest)):
                raise InvalidBudget("invalid_pre_e0_anchor")

    source = fields(data["source"], {
        "volume_id", "container_id", "eligible_allocated_local_bytes", "eligible_logical_bytes",
        "target_copy_overhead_bytes", "max_file_bytes", "observed_on", "root", "complete",
        "local_only", "overlapping_views_resolved", "symlink_targets_deduplicated",
        "max_file_census_complete", "eligible_cloud_placeholders", "unknown_bytes",
        "read_errors", "unsized_paths",
    })
    source_volume = identity(source["volume_id"])
    source_container = identity(source["container_id"])
    v3_root(source["root"], source_volume, source_container)
    source_day = (
        fresh_day(source["observed_on"], today)
        if anchor is None else observed(source["observed_on"])
    )
    allocated = integer(source["eligible_allocated_local_bytes"], positive=True)
    logical = integer(source["eligible_logical_bytes"], positive=True)
    max_file = integer(source["max_file_bytes"], positive=True)
    overhead = integer(source["target_copy_overhead_bytes"], positive=True)
    if max_file > logical:
        raise InvalidBudget("inconsistent_source_allocation")
    for key in ("complete", "local_only", "overlapping_views_resolved",
                "symlink_targets_deduplicated", "max_file_census_complete"):
        confirmed(source[key])
    for key in ("eligible_cloud_placeholders", "unknown_bytes", "read_errors", "unsized_paths"):
        if integer(source[key]) != 0:
            raise InvalidBudget("incomplete_measurement")

    targets = data["targets"]
    if not isinstance(targets, list) or not (1 <= len(targets) <= 64):
        raise InvalidBudget("invalid_target_volumes")
    volumes: dict[str, dict[str, Any]] = {}
    container_id: str | None = None
    initial_measurement: tuple[int, int, int] | None = None
    observed_at: datetime | None = None
    for entry in targets:
        target = fields(entry, {
            "volume_id", "container_id", "container_capacity_bytes", "container_free_bytes",
            "low_water_abort_bytes", "complete", "snapshots_accounted", "baseline", "observed_on", "observed_at",
        })
        vol_id = identity(target["volume_id"])
        cid = identity(target["container_id"])
        capacity = integer(target["container_capacity_bytes"], positive=True)
        free = integer(target["container_free_bytes"])
        low = integer(target["low_water_abort_bytes"], positive=True)
        measured = fresh_timestamp(
            target["observed_at"], target["observed_on"], as_of=started_at
        )
        if observed_at is not None and measured != observed_at:
            raise InvalidBudget("inconsistent_target_measurement")
        observed_at = measured
        confirmed(target["complete"])
        confirmed(target["snapshots_accounted"])
        if free > capacity or low > capacity or target["baseline"] != "pre_staging":
            raise InvalidBudget("inconsistent_target_measurement")
        if vol_id in volumes or (container_id is not None and cid != container_id):
            raise InvalidBudget("invalid_target_volumes")
        measurement = (capacity, free, low)
        if initial_measurement is not None and measurement != initial_measurement:
            raise InvalidBudget("inconsistent_target_measurement")
        container_id, initial_measurement = cid, measurement
        volumes[vol_id] = {"container_id": cid, "base": 0,
                           "model": {key: 0 for key in MODEL_BYTES}}
    assert initial_measurement is not None and container_id is not None
    capacity, free_e0, low_water = initial_measurement
    if anchor is not None:
        assert started_at is not None and observed_at is not None
        # A long campaign may span UTC dates. An anchored census must belong
        # to its pre-observation/start window, never an arbitrary older day.
        if source_day not in {
            observed_at.date().isoformat(), started_at.date().isoformat()
        }:
            raise InvalidBudget("stale_measurement")

    def target_for(volume_id: Any, cid: Any) -> dict[str, Any]:
        volume = volumes.get(identity(volume_id))
        if volume is None or volume["container_id"] != identity(cid):
            raise InvalidBudget("cross_container_or_volume_allocation")
        return volume

    e0 = fields(data["e0"], {
        "volume_id", "container_id", "staging_root", "published_root", "e0_epoch",
        "published_at", "complete_target_bytes", "max_inflight_temp_bytes", "temp_overhead_bytes", "concurrency",
    })
    media_vol = identity(e0["volume_id"])
    target_for(media_vol, e0["container_id"])
    if type(e0["concurrency"]) is not int or e0["concurrency"] != 1:
        raise InvalidBudget("unbounded_concurrency")
    staging = v3_root(e0["staging_root"], media_vol, container_id)
    published = v3_root(e0["published_root"], media_vol, container_id)
    if staging == published or staging.startswith(published + "/") or published.startswith(staging + "/"):
        raise InvalidBudget("invalid_root")
    epoch = identity(e0["e0_epoch"])
    published_at = timestamp(e0["published_at"])
    if observed_at is None or not observed_at < published_at <= datetime.now(timezone.utc):
        raise InvalidBudget("inconsistent_e1_baseline")
    if anchor is not None and (
        anchor["e0_epoch"] != epoch or started_at > published_at
        or anchor["measurement_sha256"] != pre_e0_measurement_digest(data)
    ):
        raise InvalidBudget("invalid_pre_e0_anchor")
    media = integer(e0["complete_target_bytes"], positive=True)
    temp_e0 = integer(e0["max_inflight_temp_bytes"], positive=True)
    overhead_e0 = integer(e0["temp_overhead_bytes"], positive=True)
    if media < add_bounded(max(allocated, logical), overhead) or temp_e0 < max_file:
        raise InvalidBudget("insufficient_single_file_bound")
    e0_media_peak = add_bounded(add_bounded(media, temp_e0), overhead_e0)

    e1 = fields(data["e1"], {
        "volume_id", "container_id", "baseline", "e0_epoch", "observed_on", "observed_at",
        "container_free_bytes", "complete", "snapshots_accounted", "delta_complete",
        "snapshot_divergence_complete", "max_file_census_complete", "max_file_bytes",
        "added_bytes", "replaced_bytes", "retained_bytes", "snapshot_divergence_bytes",
        "max_inflight_temp_bytes", "temp_overhead_bytes", "concurrency",
    })
    if identity(e1["volume_id"]) != media_vol:
        raise InvalidBudget("wrong_root_volume")
    target_for(e1["volume_id"], e1["container_id"])
    e1_observed_at = fresh_timestamp(e1["observed_at"], e1["observed_on"])
    if (e1["baseline"] != "post_e0" or identity(e1["e0_epoch"]) != epoch
            or e1_observed_at <= published_at):
        raise InvalidBudget("inconsistent_e1_baseline")
    for key in ("complete", "snapshots_accounted", "delta_complete",
                "snapshot_divergence_complete", "max_file_census_complete"):
        confirmed(e1[key])
    if type(e1["concurrency"]) is not int or e1["concurrency"] != 1:
        raise InvalidBudget("unbounded_concurrency")
    free_e1 = integer(e1["container_free_bytes"])
    if free_e1 > capacity:
        raise InvalidBudget("inconsistent_e1_baseline")
    max_e1_file = integer(e1["max_file_bytes"], positive=True)
    temp_e1 = integer(e1["max_inflight_temp_bytes"], positive=True)
    overhead_e1 = integer(e1["temp_overhead_bytes"], positive=True)
    if temp_e1 < max_e1_file:
        raise InvalidBudget("insufficient_single_file_bound")
    e1_charges = {key: integer(e1[key]) for key in (
        "added_bytes", "replaced_bytes", "retained_bytes", "snapshot_divergence_bytes"
    )}
    e1_media_peak = 0
    for amount in (*e1_charges.values(), temp_e1, overhead_e1):
        e1_media_peak = add_bounded(e1_media_peak, amount)

    entries = data["allocations"]
    if not isinstance(entries, list) or len(entries) != len(V3_ALLOCATIONS):
        raise InvalidBudget("invalid_allocations")
    names: set[str] = set()
    common = 0
    for entry in entries:
        item = fields(entry, {"name", "volume_id", "container_id", "bytes"})
        name = item["name"]
        if not isinstance(name, str) or name not in V3_ALLOCATIONS or name in names:
            raise InvalidBudget("invalid_allocations")
        volume = target_for(item["volume_id"], item["container_id"])
        amount = integer(item["bytes"], positive=True)
        volume["base"] = add_bounded(volume["base"], amount)
        common = add_bounded(common, amount)
        names.add(name)
    if names != set(V3_ALLOCATIONS):
        raise InvalidBudget("invalid_allocations")

    models = data["models"]
    if not isinstance(models, list) or not (2 <= len(models) <= MAX_MODELS):
        raise InvalidBudget("invalid_models")
    selected: set[tuple[str, str]] = set()
    selected_models: list[dict[str, Any]] = []
    for entry in models:
        model = fields(entry, {"app", "model_id", "volume_id", "container_id", *MODEL_BYTES})
        app = model["app"]
        if not isinstance(app, str) or app not in POSITIVE_MODEL_BYTES:
            raise InvalidBudget("invalid_models")
        key = (app, identity(model["model_id"]))
        if key in selected:
            raise InvalidBudget("invalid_models")
        selected.add(key)
        volume = target_for(model["volume_id"], model["container_id"])
        model_peak = 0
        for field in MODEL_BYTES:
            amount = integer(model[field], positive=field in POSITIVE_MODEL_BYTES[app])
            common = add_bounded(common, amount)
            model_peak = add_bounded(model_peak, amount)
            volume["model"][field] = add_bounded(volume["model"][field], amount)
        selected_models.append({"app": app, "model_id": key[1],
                                "volume_id": model["volume_id"],
                                "container_id": model["container_id"],
                                "peak_additional_bytes": model_peak})
    if {app for app, _ in selected} != set(POSITIVE_MODEL_BYTES):
        raise InvalidBudget("invalid_models")
    if any(vol["base"] == 0 and not any(vol["model"].values()) and vol_id != media_vol
           for vol_id, vol in volumes.items()):
        raise InvalidBudget("invalid_target_volumes")

    def phase(free: int, media_peak: int) -> dict[str, int]:
        peak = add_bounded(media_peak, common)
        projected = free - peak
        deficit = max(0, low_water - projected)
        if deficit > MAX_INTEGER:
            raise InvalidBudget("overflow")
        return {"container_capacity_bytes": capacity, "container_free_bytes": free,
                "peak_additional_bytes": peak, "projected_free_bytes": projected,
                "low_water_abort_bytes": low_water,
                "shortfall_bytes": deficit}

    e0_result = phase(free_e0, e0_media_peak)
    e1_result = phase(free_e1, e1_media_peak)
    e0_result.update({"complete_target_bytes": media, "max_inflight_temp_bytes": temp_e0,
                      "temp_overhead_bytes": overhead_e0})
    e1_result.update({**e1_charges, "max_inflight_temp_bytes": temp_e1,
                      "temp_overhead_bytes": overhead_e1})
    result = {
        "schema_version": 3, "mode": V3_MODE,
        "status": "PASS" if not (e0_result["shortfall_bytes"] or e1_result["shortfall_bytes"]) else "BLOCKED",
        "observed_on": day, "container_id": container_id, "media_volume_id": media_vol,
        "e0": e0_result, "e1": e1_result,
        "per_volume": [{"volume_id": vol_id, "container_id": vol["container_id"],
                        "base_allocations_bytes": vol["base"], "model_peak_bytes": vol["model"]}
                       for vol_id, vol in volumes.items()],
        "selected_models": selected_models, "scope": "supplied-input ARITHMETIC ONLY",
        "limitation": "Dates, root identities, one-file concurrency and snapshot attestations are supplied assertions, not live provenance or permission to stage; no measured Neo4j reclaim is credited.",
    }
    if anchor is not None:
        result["pre_e0_anchor"] = {**anchor, "receipt_verified": False}
    return result


def evaluate(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict) and type(raw.get("schema_version")) is int and raw["schema_version"] == 3:
        return evaluate_v3(raw)
    return evaluate_v2(raw)


def main() -> int:
    try:
        payload = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(payload) > MAX_INPUT_BYTES:
            raise InvalidBudget("input_too_large")
        raw = json.loads(
            payload.decode("utf-8"),
            object_pairs_hook=unique_pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(
                InvalidBudget("invalid_number")
            ),
        )
        result = evaluate(raw)
    except (InvalidBudget, ValueError, UnicodeError, RecursionError) as exc:
        reason = str(exc) if isinstance(exc, InvalidBudget) else "invalid_json"
        error_version = (3 if isinstance(locals().get("raw"), dict)
                         and type(raw.get("schema_version")) is int
                         and raw["schema_version"] == 3 else SCHEMA_VERSION)
        print(
            json.dumps({"schema_version": error_version, "status": "UNKNOWN", "reason": reason}),
            file=sys.stdout,
        )
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
