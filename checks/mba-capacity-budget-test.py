"""Synthetic-only tests for the offline capacity budget; no host storage is read."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

SCRIPT = Path(__file__).with_name("mba-capacity-budget.py")
VALUES = {
    "eligible_media": 110,
    "peak_staging_overlap": 110,
    "growth": 10,
    "navidrome_state": 5,
    "syncthing_state": 5,
    "docker_vm_cap": 20,
    "docker_images_volumes_cap": 10,
    "mcphub_state_cap": 5,
    "os_container_reserve": 25,
}


def fixture() -> dict:
    return {
        "schema_version": 2,
        "observed_on": "2026-10-06",
        "source": {
            "volume_id": "source-volume-synthetic",
            "container_id": "source-container-synthetic",
            "eligible_allocated_local_bytes": 80,
            "eligible_logical_bytes": 100,
            "target_copy_overhead_bytes": 10,
            "complete": True,
            "local_only": True,
            "overlapping_views_resolved": True,
            "symlink_targets_deduplicated": True,
            "eligible_cloud_placeholders": 0,
            "unknown_bytes": 0,
            "read_errors": 0,
            "unsized_paths": 0,
        },
        "targets": [
            {
                "volume_id": "target-volume-synthetic",
                "container_id": "target-container-synthetic",
                "container_capacity_bytes": 1000,
                "container_free_bytes": 400,
                "low_water_abort_bytes": 50,
                "complete": True,
                "snapshots_accounted": True,
                "baseline": "pre_staging",
            }
        ],
        "publication_mode": "same_volume_rename",
        "peak_retry_allocation_bytes": 110,
        "growth_horizon_days": 30,
        "allocations": [
            {
                "name": name,
                "volume_id": "target-volume-synthetic",
                "container_id": "target-container-synthetic",
                "bytes": amount,
            }
            for name, amount in VALUES.items()
        ],
        "models": [
            {
                "app": "Draw Things",
                "model_id": "selected-draw-synthetic",
                "volume_id": "target-volume-synthetic",
                "container_id": "target-container-synthetic",
                "weights_bytes": 8,
                "download_peak_bytes": 8,
                "outputs_bytes": 3,
                "scratch_bytes": 3,
                "context_kv_bytes": 0,
                "swap_bytes": 2,
            },
            {
                "app": "LM Studio",
                "model_id": "selected-lm-synthetic",
                "volume_id": "target-volume-synthetic",
                "container_id": "target-container-synthetic",
                "weights_bytes": 7,
                "download_peak_bytes": 7,
                "outputs_bytes": 2,
                "scratch_bytes": 2,
                "context_kv_bytes": 3,
                "swap_bytes": 3,
            },
        ],
    }


def v3_fixture() -> dict:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    today = now.date().isoformat()
    data = fixture()
    data["schema_version"] = 3
    data["mode"] = "single_inflight_file_same_volume"
    data["observed_on"] = today
    data["source"].update(observed_on=today, max_file_bytes=20, max_file_census_complete=True,
                          root={"path": "/synthetic/source", "volume_id": "source-volume-synthetic",
                                "container_id": "source-container-synthetic", "symlink_free": True,
                                "identity_confirmed": True})
    as_text = lambda instant: instant.strftime("%Y-%m-%dT%H:%M:%SZ")
    pre_e0 = now - timedelta(minutes=2)
    data["targets"][0].update(observed_on=pre_e0.date().isoformat(), observed_at=as_text(pre_e0))
    data["targets"][0]["container_free_bytes"] = 400
    data.pop("peak_retry_allocation_bytes")
    data.pop("publication_mode")
    data["allocations"] = data["allocations"][2:]
    root = lambda path: {"path": path, "volume_id": "target-volume-synthetic",
                         "container_id": "target-container-synthetic",
                         "symlink_free": True, "identity_confirmed": True}
    data["e0"] = {
        "volume_id": "target-volume-synthetic", "container_id": "target-container-synthetic",
        "staging_root": root("/synthetic/internal/staging"),
        "published_root": root("/synthetic/internal/served"),
        "e0_epoch": "epoch-synthetic", "published_at": as_text(now - timedelta(minutes=1)),
        "complete_target_bytes": 110,
        "max_inflight_temp_bytes": 20, "temp_overhead_bytes": 2, "concurrency": 1,
    }
    data["e1"] = {
        "volume_id": "target-volume-synthetic", "container_id": "target-container-synthetic",
        "baseline": "post_e0", "e0_epoch": "epoch-synthetic", "observed_on": today,
        "observed_at": as_text(now),
        "container_free_bytes": 280, "complete": True, "snapshots_accounted": True,
        "delta_complete": True, "snapshot_divergence_complete": True,
        "max_file_census_complete": True, "max_file_bytes": 20,
        "added_bytes": 10, "replaced_bytes": 8, "retained_bytes": 6,
        "snapshot_divergence_bytes": 4, "max_inflight_temp_bytes": 20,
        "temp_overhead_bytes": 2, "concurrency": 1,
    }
    return data


def anchor_measurement(data: dict) -> str:
    payload = {
        "source": data["source"],
        "targets": sorted(data["targets"], key=lambda entry: entry["volume_id"]),
        "e0": {
            key: value for key, value in data["e0"].items() if key != "published_at"
        },
    }
    return hashlib.sha256(
        json.dumps(
            payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True
        ).encode("utf-8")
    ).hexdigest()


def anchored_v3_fixture() -> dict:
    data = v3_fixture()
    now = datetime.strptime(data["e1"]["observed_at"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    started = now - timedelta(hours=26)
    measured = started - timedelta(minutes=2)
    data["source"]["observed_on"] = measured.date().isoformat()
    data["targets"][0].update(
        observed_on=measured.date().isoformat(),
        observed_at=measured.strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    data["pre_e0_anchor"] = {
        "e0_epoch": data["e0"]["e0_epoch"],
        "started_at": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "measurement_sha256": anchor_measurement(data),
        "start_receipt_sha256": hashlib.sha256(
            b"synthetic start receipt only"
        ).hexdigest(),
    }
    return data


class BudgetTests(unittest.TestCase):
    def invoke(self, payload: dict | bytes) -> tuple[int, dict]:
        content = (
            payload
            if isinstance(payload, bytes)
            else json.dumps(payload).encode("utf-8")
        )
        env = os.environ.copy()
        env["UV_NO_PROJECT"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run(
            ["uv", "run", "--offline", "python", "-I", str(SCRIPT)],
            input=content,
            capture_output=True,
            env=env,
            timeout=20,
            check=False,
        )
        self.assertFalse(result.stderr, result.stderr.decode("utf-8", errors="replace"))
        return result.returncode, json.loads(result.stdout)

    def blocked(self, payload: dict | bytes, reason: str | None = None) -> None:
        code, report = self.invoke(payload)
        self.assertEqual(code, 2, report)
        self.assertEqual(report["status"], "UNKNOWN")
        if reason:
            self.assertEqual(report["reason"], reason)
        self.assertNotIn("peak_additional_bytes", report)

    def test_required_copy_and_retry_bounds_are_not_optional(self) -> None:
        data = fixture()
        del data["source"]["target_copy_overhead_bytes"]
        self.blocked(data, "invalid_schema")
        data = fixture()
        del data["peak_retry_allocation_bytes"]
        self.blocked(data, "invalid_schema")

    def test_same_volume_rename_cannot_have_zero_retry_overlap(self) -> None:
        data = fixture()
        data["allocations"][1]["bytes"] = 0
        self.blocked(data, "insufficient_retry_overlap")

    def test_pass_uses_peak_and_all_reserves(self) -> None:
        code, report = self.invoke(fixture())
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["schema_version"], 2)
        self.assertEqual(report["peak_additional_bytes"], 348)
        self.assertEqual(report["per_container"][0]["projected_free_bytes"], 52)
        self.assertEqual(report["shortfall_bytes"], 0)
        self.assertEqual(report["per_volume"][0]["base_allocations_bytes"], 300)
        self.assertEqual(report["per_volume"][0]["peak_additional_bytes"], 348)
        self.assertEqual(report["per_volume"][0]["model_peak_bytes"], {
            "weights_bytes": 15,
            "download_peak_bytes": 15,
            "outputs_bytes": 5,
            "scratch_bytes": 5,
            "context_kv_bytes": 3,
            "swap_bytes": 5,
        })
        self.assertEqual(report["scope"], "supplied-input ARITHMETIC ONLY")
        self.assertIn("no live MBA free-space census", report["limitation"])
        self.assertEqual(report["per_container"][0]["container_id"], "target-container-synthetic")
        self.assertEqual(
            {(m["app"], m["model_id"], m["peak_additional_bytes"]) for m in report["selected_models"]},
            {
                ("Draw Things", "selected-draw-synthetic", 24),
                ("LM Studio", "selected-lm-synthetic", 24),
            },
        )

    def test_low_water_at_boundary_and_below(self) -> None:
        data = fixture()
        data["targets"][0]["low_water_abort_bytes"] = 52
        self.assertEqual(self.invoke(data)[0], 0)
        data["targets"][0]["low_water_abort_bytes"] = 53
        code, report = self.invoke(data)
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertEqual(report["shortfall_bytes"], 1)

    def test_negative_projected_free_is_blocked_not_unknown(self) -> None:
        data = fixture()
        data["targets"][0]["container_free_bytes"] = 50
        code, report = self.invoke(data)
        self.assertEqual(code, 1)
        self.assertEqual(report["per_container"][0]["projected_free_bytes"], -298)

    def test_second_copy_requires_full_overlap(self) -> None:
        data = fixture()
        data["publication_mode"] = "second_copy"
        self.blocked(data, "insufficient_second_copy_overlap")
        data["allocations"][1]["bytes"] = 219
        self.blocked(data, "insufficient_second_copy_overlap")
        data["allocations"][1]["bytes"] = 220
        data["targets"][0]["container_free_bytes"] = 510
        code, report = self.invoke(data)
        self.assertEqual(code, 0)
        self.assertEqual(report["peak_additional_bytes"], 458)

    def test_cross_container_or_volume_must_not_be_aggregated(self) -> None:
        for key, value in (
            ("container_id", "other-container"),
            ("volume_id", "other-volume"),
        ):
            with self.subTest(key=key):
                data = fixture()
                data["allocations"][4][key] = value
                self.blocked(data, "cross_container_or_volume_allocation")

    def test_target_copy_bound_must_cover_logical_and_allocated_source(self) -> None:
        data = fixture()
        data["source"]["eligible_logical_bytes"] = 101
        self.blocked(data, "inconsistent_source_allocation")
        data = fixture()
        data["source"]["eligible_allocated_local_bytes"] = 101
        self.blocked(data, "inconsistent_source_allocation")
        data = fixture()
        data["allocations"][0]["bytes"] = 100
        self.blocked(data, "inconsistent_source_allocation")
        data = fixture()
        data["allocations"][0]["bytes"] = 120
        data["peak_retry_allocation_bytes"] = 120
        data["allocations"][1]["bytes"] = 120
        data["targets"][0]["container_free_bytes"] = 450
        self.assertEqual(self.invoke(data)[0], 0)

    def test_retry_allocation_must_bound_a_complete_target_copy(self) -> None:
        data = fixture()
        data["peak_retry_allocation_bytes"] = 109
        self.blocked(data, "insufficient_retry_allocation")
        data = fixture()
        data["peak_retry_allocation_bytes"] = 111
        self.blocked(data, "insufficient_retry_overlap")
        data["allocations"][1]["bytes"] = 111
        self.assertEqual(self.invoke(data)[0], 0)

    def test_required_bounds_reject_negative_zero_null_and_unknown(self) -> None:
        for amount in (-1, 0, None, "unknown", True):
            with self.subTest(amount=amount):
                data = fixture()
                data["source"]["target_copy_overhead_bytes"] = amount
                self.blocked(data, "invalid_or_unknown_bytes")
                data = fixture()
                data["peak_retry_allocation_bytes"] = amount
                self.blocked(data, "invalid_or_unknown_bytes")

    def test_incomplete_census_never_treats_unknown_as_zero(self) -> None:
        for key in (
            "complete",
            "local_only",
            "overlapping_views_resolved",
            "symlink_targets_deduplicated",
        ):
            with self.subTest(key=key):
                data = fixture()
                data["source"][key] = False
                self.blocked(data, "incomplete_measurement")
        for key in (
            "eligible_cloud_placeholders",
            "unknown_bytes",
            "read_errors",
            "unsized_paths",
        ):
            with self.subTest(key=key):
                data = fixture()
                data["source"][key] = 1
                self.blocked(data, "incomplete_measurement")
        for key in ("complete", "snapshots_accounted"):
            data = fixture()
            data["targets"][0][key] = False
            self.blocked(data, "incomplete_measurement")

    def test_missing_null_and_unrecognized_fields_fail_closed(self) -> None:
        data = fixture()
        del data["targets"][0]["container_id"]
        self.blocked(data, "invalid_schema")
        data = fixture()
        data["allocations"][2]["bytes"] = None
        self.blocked(data, "invalid_or_unknown_bytes")
        data = fixture()
        data["projected_reclaim_bytes"] = 999
        self.blocked(data, "invalid_schema")

    def test_invalid_numbers_caps_dates_and_capacity(self) -> None:
        for amount in (-1, True, 1.5, 0):
            with self.subTest(amount=amount):
                data = fixture()
                data["allocations"][5]["bytes"] = amount
                self.blocked(data, "invalid_or_unknown_bytes")
        for name in (
            "growth",
            "navidrome_state",
            "syncthing_state",
            "mcphub_state_cap",
            "os_container_reserve",
        ):
            with self.subTest(name=name):
                data = fixture()
                next(item for item in data["allocations"] if item["name"] == name)[
                    "bytes"
                ] = 0
                self.blocked(data, "invalid_or_unknown_bytes")
        data = fixture()
        data["targets"][0]["container_free_bytes"] = 1001
        self.blocked(data, "inconsistent_target_measurement")
        data = fixture()
        data["targets"][0]["low_water_abort_bytes"] = 1001
        self.blocked(data, "inconsistent_target_measurement")
        data = fixture()
        data["observed_on"] = "2026-02-30"
        self.blocked(data, "invalid_date")
        data = fixture()
        data["growth_horizon_days"] = 0
        self.blocked(data, "invalid_or_unknown_bytes")

    def test_no_post_staging_free_or_projected_savings(self) -> None:
        data = fixture()
        data["targets"][0]["baseline"] = "after_reclaim_estimate"
        self.blocked(data, "inconsistent_target_measurement")
        data = fixture()
        data["targets"][0]["projected_savings_bytes"] = 300
        self.blocked(data, "invalid_schema")

    def test_duplicate_fields_json_and_duplicate_allocations(self) -> None:
        self.blocked(b'{"schema_version":2,"schema_version":2}', "duplicate_field")
        data = fixture()
        data["allocations"][1]["name"] = "eligible_media"
        self.blocked(data, "invalid_allocations")
        self.blocked(b'{"schema_version":NaN}', "invalid_number")
        self.blocked(b"not json", "invalid_json")

    def test_bounded_payload_and_integer_overflow(self) -> None:
        self.blocked(b" " * 65_537, "input_too_large")
        data = fixture()
        data["targets"][0]["container_capacity_bytes"] = (1 << 63) - 1
        data["targets"][0]["container_free_bytes"] = (1 << 63) - 1
        data["allocations"][1]["bytes"] = (1 << 63) - 1
        self.blocked(data, "overflow")

    def test_list_is_not_a_container_census(self) -> None:
        data = fixture()
        data["targets"][0] = [copy.deepcopy(data["targets"][0]), copy.deepcopy(data["targets"][0])]
        self.blocked(data, "invalid_schema")

    def test_v1_and_old_single_target_input_fail_closed(self) -> None:
        data = fixture()
        data["schema_version"] = 1
        self.blocked(data, "invalid_schema")
        data = fixture()
        data["target"] = data.pop("targets")[0]
        self.blocked(data, "invalid_schema")

    def test_selected_model_set_and_every_byte_field_are_mandatory(self) -> None:
        data = fixture()
        del data["models"]
        self.blocked(data, "invalid_schema")
        data = fixture()
        del data["models"][0]
        self.blocked(data, "invalid_models")
        data = fixture()
        data["models"].append(copy.deepcopy(data["models"][0]))
        self.blocked(data, "invalid_models")
        data = fixture()
        data["models"][0]["app"] = "unselected app"
        self.blocked(data, "invalid_models")
        for key in (
            "weights_bytes",
            "download_peak_bytes",
            "outputs_bytes",
            "scratch_bytes",
            "context_kv_bytes",
            "swap_bytes",
        ):
            for model_index in (0, 1):
                with self.subTest(field=key, model_index=model_index):
                    data = fixture()
                    del data["models"][model_index][key]
                    self.blocked(data, "invalid_schema")
                    data = fixture()
                    data["models"][model_index][key] = None
                    self.blocked(data, "invalid_or_unknown_bytes")

    def test_required_model_peaks_cannot_be_zero_or_invalid(self) -> None:
        for model_index, fields in (
            (0, ("weights_bytes", "download_peak_bytes", "outputs_bytes", "scratch_bytes")),
            (1, ("weights_bytes", "download_peak_bytes", "context_kv_bytes", "swap_bytes")),
        ):
            for field in fields:
                with self.subTest(model_index=model_index, field=field):
                    data = fixture()
                    data["models"][model_index][field] = 0
                    self.blocked(data, "invalid_or_unknown_bytes")
        for value in (True, -1, 1.5, "unknown"):
            with self.subTest(value=value):
                data = fixture()
                data["models"][0]["swap_bytes"] = value
                self.blocked(data, "invalid_or_unknown_bytes")

    def test_model_components_affect_low_water_and_are_not_credits(self) -> None:
        for index, field in (
            (0, "weights_bytes"),
            (0, "download_peak_bytes"),
            (0, "outputs_bytes"),
            (0, "scratch_bytes"),
            (1, "context_kv_bytes"),
            (1, "swap_bytes"),
        ):
            with self.subTest(field=field):
                data = fixture()
                data["models"][index][field] += 3
                code, report = self.invoke(data)
                self.assertEqual(code, 1, report)
                self.assertEqual(report["status"], "BLOCKED")
                self.assertEqual(report["per_container"][0]["projected_free_bytes"], 49)
                self.assertEqual(report["per_container"][0]["shortfall_bytes"], 1)

    def test_multiple_selected_models_accumulate_their_full_peak(self) -> None:
        data = fixture()
        additional = copy.deepcopy(data["models"][1])
        additional["model_id"] = "second-lm-model-synthetic"
        data["models"].append(additional)
        data["targets"][0]["container_free_bytes"] = 500
        code, report = self.invoke(data)
        self.assertEqual(code, 0, report)
        self.assertEqual(report["peak_additional_bytes"], 372)
        self.assertEqual(len(report["selected_models"]), 3)
        self.assertEqual(report["per_volume"][0]["model_peak_bytes"]["context_kv_bytes"], 6)
        self.assertEqual(report["per_container"][0]["projected_free_bytes"], 128)

    def test_model_volume_must_be_declared_and_identified(self) -> None:
        data = fixture()
        data["models"][0]["volume_id"] = "undeclared"
        self.blocked(data, "cross_container_or_volume_allocation")
        data = fixture()
        data["models"][1]["container_id"] = "wrong-container"
        self.blocked(data, "cross_container_or_volume_allocation")
        data = fixture()
        data["models"][0]["model_id"] = None
        self.blocked(data, "invalid_identity")
        data = fixture()
        data["models"][0]["unexpected_credit_bytes"] = 1000
        self.blocked(data, "invalid_schema")

    def test_shared_container_sums_distinct_volumes_without_double_free(self) -> None:
        data = fixture()
        second = copy.deepcopy(data["targets"][0])
        second["volume_id"] = "models-volume-synthetic"
        data["targets"].append(second)
        for model in data["models"]:
            model["volume_id"] = second["volume_id"]
        code, report = self.invoke(data)
        self.assertEqual(code, 0, report)
        self.assertEqual(len(report["per_container"]), 1)
        self.assertEqual(report["per_container"][0]["peak_additional_bytes"], 348)
        self.assertEqual(report["per_container"][0]["projected_free_bytes"], 52)
        self.assertEqual(
            {v["volume_id"]: v["peak_additional_bytes"] for v in report["per_volume"]},
            {"target-volume-synthetic": 300, "models-volume-synthetic": 48},
        )
        data["targets"][0]["container_free_bytes"] = 340
        data["targets"][1]["container_free_bytes"] = 340
        code, report = self.invoke(data)
        self.assertEqual(code, 1, report)
        self.assertEqual(report["per_container"][0]["projected_free_bytes"], -8)

    def test_distinct_containers_apply_distinct_low_water_thresholds(self) -> None:
        data = fixture()
        second = copy.deepcopy(data["targets"][0])
        second.update(
            volume_id="models-volume-synthetic",
            container_id="models-container-synthetic",
            container_capacity_bytes=200,
            container_free_bytes=50,
            low_water_abort_bytes=10,
        )
        data["targets"].append(second)
        for model in data["models"]:
            model["volume_id"] = second["volume_id"]
            model["container_id"] = second["container_id"]
        code, report = self.invoke(data)
        self.assertEqual(code, 1, report)  # 50 - 48 = 2, below its 10-byte threshold.
        self.assertEqual(report["peak_additional_bytes"], 348)
        self.assertEqual(report["shortfall_bytes"], 8)
        per_container = {v["container_id"]: v for v in report["per_container"]}
        self.assertEqual(per_container["target-container-synthetic"]["projected_free_bytes"], 100)
        self.assertEqual(per_container["models-container-synthetic"]["projected_free_bytes"], 2)
        data["targets"][1]["container_free_bytes"] = 58
        self.assertEqual(self.invoke(data)[0], 0)

    def test_target_identity_and_shared_observation_must_be_consistent(self) -> None:
        data = fixture()
        data["targets"].append(copy.deepcopy(data["targets"][0]))
        self.blocked(data, "invalid_target_volumes")
        data["targets"][1]["volume_id"] = "other-volume"
        data["targets"][1]["container_free_bytes"] = 401
        self.blocked(data, "inconsistent_target_measurement")
        data["targets"][1]["container_free_bytes"] = 400
        self.blocked(data, "invalid_target_volumes")  # Declared but unbudgeted.
        data = fixture()
        data["targets"][0]["complete"] = False
        self.blocked(data, "incomplete_measurement")

    def test_media_and_staging_overlap_cannot_straddle_volumes(self) -> None:
        data = fixture()
        second = copy.deepcopy(data["targets"][0])
        second["volume_id"] = "other-volume"
        data["targets"].append(second)
        data["allocations"][1]["volume_id"] = second["volume_id"]
        self.blocked(data, "cross_volume_media_overlap")

    def test_v2_full_retry_receipt_and_unknown_output_remain_exact(self) -> None:
        data = fixture()
        code, report = self.invoke(data)
        self.assertEqual(code, 0)
        self.assertEqual(report["schema_version"], 2)
        self.assertNotIn("mode", report)
        self.assertNotIn("e0", report)
        self.assertEqual(report["peak_additional_bytes"], 348)
        data["peak_retry_allocation_bytes"] = 109
        self.assertEqual(self.invoke(data), (2, {"schema_version": 2, "status": "UNKNOWN",
                                                "reason": "insufficient_retry_allocation"}))
        data = fixture()
        data["mode"] = "single_inflight_file_same_volume"
        self.blocked(data, "invalid_schema")

    def test_v3_two_phase_budget_does_not_double_charge_e0_resident_bytes(self) -> None:
        code, report = self.invoke(v3_fixture())
        self.assertEqual(code, 0, report)
        self.assertEqual(report["schema_version"], 3)
        self.assertEqual(report["mode"], "single_inflight_file_same_volume")
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["e0"]["peak_additional_bytes"], 260)
        self.assertEqual(report["e0"]["projected_free_bytes"], 140)
        self.assertEqual(report["e1"]["peak_additional_bytes"], 178)
        self.assertEqual(report["e1"]["projected_free_bytes"], 102)
        self.assertEqual(report["e1"]["snapshot_divergence_bytes"], 4)
        self.assertEqual(report["per_volume"][0]["base_allocations_bytes"], 80)
        self.assertEqual(len(report["selected_models"]), 2)
        self.assertEqual(report["scope"], "supplied-input ARITHMETIC ONLY")
        self.assertNotIn("pre_e0_anchor", report)

    def test_v3_anchored_long_campaign_keeps_post_e0_fresh(self) -> None:
        data = anchored_v3_fixture()
        code, report = self.invoke(data)
        self.assertEqual(code, 0, report)
        self.assertEqual(report["e0"]["peak_additional_bytes"], 260)
        self.assertEqual(report["e1"]["peak_additional_bytes"], 178)
        self.assertEqual(
            report["pre_e0_anchor"]["measurement_sha256"], anchor_measurement(data)
        )
        self.assertIs(report["pre_e0_anchor"]["receipt_verified"], False)
        del data["pre_e0_anchor"]
        self.blocked(data, "stale_measurement")

    def test_v3_anchored_census_window_crosses_midnight(self) -> None:
        for census_at_start in (False, True):
            with self.subTest(census_at_start=census_at_start):
                data = anchored_v3_fixture()
                now = datetime.now(timezone.utc)
                measured = (now - timedelta(days=2)).replace(
                    hour=23, minute=59, second=0, microsecond=0
                )
                started = measured + timedelta(minutes=2)
                data["targets"][0].update(
                    observed_on=measured.date().isoformat(),
                    observed_at=measured.strftime("%Y-%m-%dT%H:%M:%SZ"),
                )
                data["source"]["observed_on"] = (
                    (started if census_at_start else measured).date().isoformat()
                )
                data["pre_e0_anchor"]["started_at"] = started.strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
                data["pre_e0_anchor"]["measurement_sha256"] = anchor_measurement(data)
                self.assertEqual(self.invoke(data)[0], 0)

    def test_v3_anchor_rejects_epoch_measurement_and_receipt_mismatch(self) -> None:
        for change in ("epoch", "free", "source", "root", "digest", "receipt"):
            with self.subTest(change=change):
                data = anchored_v3_fixture()
                if change == "epoch":
                    data["pre_e0_anchor"]["e0_epoch"] = "another-campaign"
                elif change == "free":
                    data["targets"][0]["container_free_bytes"] += 1
                elif change == "source":
                    data["source"]["eligible_allocated_local_bytes"] += 1
                elif change == "root":
                    data["e0"]["staging_root"]["path"] = "/synthetic/different-staging"
                elif change == "digest":
                    data["pre_e0_anchor"]["measurement_sha256"] = "0" * 64
                else:
                    data["pre_e0_anchor"]["start_receipt_sha256"] = "not-a-sha256"
                self.blocked(data, "invalid_pre_e0_anchor")

    def test_v3_anchor_requires_start_and_observation_time_order(self) -> None:
        for change in (
            "pre_too_old",
            "pre_after_start",
            "start_after_publication",
            "future_start",
        ):
            with self.subTest(change=change):
                data = anchored_v3_fixture()
                started = datetime.strptime(
                    data["pre_e0_anchor"]["started_at"], "%Y-%m-%dT%H:%M:%SZ"
                ).replace(tzinfo=timezone.utc)
                if change in ("pre_too_old", "pre_after_start"):
                    measured = started + (
                        timedelta(seconds=1)
                        if change == "pre_after_start"
                        else -timedelta(hours=2)
                    )
                    data["targets"][0].update(
                        observed_on=measured.date().isoformat(),
                        observed_at=measured.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    )
                    data["source"]["observed_on"] = measured.date().isoformat()
                    reason = "stale_measurement"
                elif change == "start_after_publication":
                    data["e0"]["published_at"] = (
                        started - timedelta(seconds=1)
                    ).strftime("%Y-%m-%dT%H:%M:%SZ")
                    reason = "invalid_pre_e0_anchor"
                else:
                    data["pre_e0_anchor"]["started_at"] = (
                        datetime.now(timezone.utc) + timedelta(hours=1)
                    ).strftime("%Y-%m-%dT%H:%M:%SZ")
                    reason = "invalid_pre_e0_anchor"
                data["pre_e0_anchor"]["measurement_sha256"] = anchor_measurement(data)
                self.blocked(data, reason)

    def test_v3_anchor_cannot_exempt_stale_post_or_unrelated_source_census(
        self,
    ) -> None:
        data = anchored_v3_fixture()
        stale = datetime.now(timezone.utc) - timedelta(hours=2)
        data["e0"]["published_at"] = (stale - timedelta(minutes=1)).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        data["e1"].update(
            observed_on=stale.date().isoformat(),
            observed_at=stale.strftime("%Y-%m-%dT%H:%M:%SZ"),
        )
        self.blocked(data, "stale_measurement")
        data = anchored_v3_fixture()
        data["source"]["observed_on"] = "2000-01-01"
        data["pre_e0_anchor"]["measurement_sha256"] = anchor_measurement(data)
        self.blocked(data, "stale_measurement")

    def test_v3_anchor_schema_is_exact_and_v2_does_not_accept_it(self) -> None:
        for value in (
            None,
            {},
            {**anchored_v3_fixture()["pre_e0_anchor"], "receipt_verified": True},
        ):
            with self.subTest(value=value):
                data = anchored_v3_fixture()
                data["pre_e0_anchor"] = value
                self.blocked(data, "invalid_schema")
        data = fixture()
        data["pre_e0_anchor"] = anchored_v3_fixture()["pre_e0_anchor"]
        self.blocked(data, "invalid_schema")

    def test_v3_e0_and_e1_one_byte_low_water_failures(self) -> None:
        for phase_name, boundary in (("e0", 140), ("e1", 102)):
            with self.subTest(phase=phase_name):
                data = v3_fixture()
                data["targets"][0]["low_water_abort_bytes"] = boundary
                if phase_name == "e0":
                    data["e1"]["container_free_bytes"] = 350
                else:
                    data["targets"][0]["container_free_bytes"] = 500
                code, report = self.invoke(data)
                self.assertEqual(code, 0, report)
                self.assertEqual(report[phase_name]["shortfall_bytes"], 0)
                data["targets"][0]["low_water_abort_bytes"] = boundary + 1
                code, report = self.invoke(data)
                self.assertEqual(code, 1, report)
                self.assertEqual(report["status"], "BLOCKED")
                self.assertEqual(report[phase_name]["shortfall_bytes"], 1)

    def test_v3_max_file_temp_and_concurrency_are_mandatory(self) -> None:
        for field in ("max_file_bytes", "max_file_census_complete"):
            data = v3_fixture()
            del data["source"][field]
            self.blocked(data, "invalid_schema")
        for section in ("e0", "e1"):
            for value in (0, 2, True, "one", None):
                with self.subTest(section=section, concurrency=value):
                    data = v3_fixture()
                    data[section]["concurrency"] = value
                    self.blocked(data, "unbounded_concurrency")
            data = v3_fixture()
            data[section]["max_inflight_temp_bytes"] = 19
            self.blocked(data, "insufficient_single_file_bound")
            data = v3_fixture()
            data[section]["temp_overhead_bytes"] = 0
            self.blocked(data, "invalid_or_unknown_bytes")
        data = v3_fixture()
        data["source"]["max_file_bytes"] = None
        self.blocked(data, "invalid_or_unknown_bytes")
        data = v3_fixture()
        data["e1"]["max_file_bytes"] = None
        self.blocked(data, "invalid_or_unknown_bytes")
        data = v3_fixture()
        data["e0"]["complete_target_bytes"] = 109
        self.blocked(data, "insufficient_single_file_bound")

    def test_v3_stale_incomplete_and_snapshot_uncertainty_fail_closed(self) -> None:
        yesterday = (date.today() - timedelta(days=1)).isoformat()
        for section in ("source", "e1"):
            data = v3_fixture()
            data[section]["observed_on"] = yesterday
            self.blocked(data, "stale_measurement")
        data = v3_fixture()
        data["targets"][0].update(observed_on=datetime.now(timezone.utc).date().isoformat(),
                                  observed_at="2000-01-01T00:00:00Z")
        self.blocked(data, "stale_measurement")
        data = v3_fixture()
        data["targets"][0]["observed_on"] = "2000-01-01"
        self.blocked(data, "stale_measurement")
        for section, field in (("source", "max_file_census_complete"),
                               ("source", "complete"), ("e1", "delta_complete"),
                               ("e1", "snapshot_divergence_complete"),
                               ("e1", "snapshots_accounted"),
                               ("e1", "max_file_census_complete")):
            with self.subTest(section=section, field=field):
                data = v3_fixture()
                data[section][field] = False
                self.blocked(data, "incomplete_measurement")
        data = v3_fixture()
        data["e1"]["snapshot_divergence_bytes"] = None
        self.blocked(data, "invalid_or_unknown_bytes")
        data = v3_fixture()
        data["source"]["unsized_paths"] = 1
        self.blocked(data, "incomplete_measurement")
        data = v3_fixture()
        data["source"]["root"]["symlink_free"] = False
        self.blocked(data, "incomplete_measurement")
        data = v3_fixture()
        data["source"]["root"]["volume_id"] = "wrong-volume"
        self.blocked(data, "wrong_root_volume")
        data = v3_fixture()
        data["targets"][0]["snapshots_accounted"] = False
        self.blocked(data, "incomplete_measurement")

    def test_v3_same_volume_roots_and_post_e0_baseline_are_strict(self) -> None:
        for name in ("staging_root", "published_root"):
            for field, bad in (("volume_id", "wrong-volume"),
                               ("container_id", "wrong-container")):
                data = v3_fixture()
                data["e0"][name][field] = bad
                self.blocked(data, "wrong_root_volume")
            data = v3_fixture()
            data["e0"][name]["symlink_free"] = False
            self.blocked(data, "incomplete_measurement")
            data = v3_fixture()
            data["e0"][name]["path"] = "/synthetic/../escape"
            self.blocked(data, "invalid_root")
        data = v3_fixture()
        data["e0"]["published_root"] = copy.deepcopy(data["e0"]["staging_root"])
        self.blocked(data, "invalid_root")
        for alias in ("/synthetic/internal/STAGING", "/synthetic/internal/ＳＴＡＧＩＮＧ",
                      "/synthetic/internal/StaGiNg/child", "/synthetic/internal/staging／child"):
            with self.subTest(alias=alias):
                data = v3_fixture()
                data["e0"]["published_root"]["path"] = alias
                self.blocked(data, "invalid_root")
        data = v3_fixture()
        data["e0"]["published_root"]["path"] = "/synthetic/internal/．．/escape"
        self.blocked(data, "invalid_root")
        data = v3_fixture()
        data["e1"]["baseline"] = "pre_staging"
        self.blocked(data, "inconsistent_e1_baseline")
        data = v3_fixture()
        data["e1"]["e0_epoch"] = "other-epoch"
        self.blocked(data, "inconsistent_e1_baseline")
        data = v3_fixture()
        data["e1"]["container_free_bytes"] = 1001
        self.blocked(data, "inconsistent_e1_baseline")
        data = v3_fixture()
        data["e1"]["container_free_bytes"] = 401  # Fresh measured free can reflect real releases.
        self.assertEqual(self.invoke(data)[0], 0)
        data = v3_fixture()
        data["e1"]["observed_at"] = data["e0"]["published_at"]
        self.blocked(data, "inconsistent_e1_baseline")
        data = v3_fixture()
        data["e1"]["observed_at"] = (datetime.now(timezone.utc) - timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.blocked(data, "stale_measurement")
        data = v3_fixture()
        data["e0"]["published_at"] = data["targets"][0]["observed_at"]
        self.blocked(data, "inconsistent_e1_baseline")
        data = v3_fixture()
        data["e1"]["container_id"] = "other-container"
        self.blocked(data, "cross_container_or_volume_allocation")

    def test_v3_shared_apfs_volume_charges_models_vm_and_growth_once(self) -> None:
        data = v3_fixture()
        second = copy.deepcopy(data["targets"][0])
        second["volume_id"] = "synthetic-models-volume"
        data["targets"].append(second)
        for model in data["models"]:
            model["volume_id"] = second["volume_id"]
        for allocation in data["allocations"]:
            if allocation["name"] in ("docker_vm_cap", "growth"):
                allocation["volume_id"] = second["volume_id"]
        code, report = self.invoke(data)
        self.assertEqual(code, 0, report)
        self.assertEqual(report["e0"]["peak_additional_bytes"], 260)
        self.assertEqual(report["e1"]["peak_additional_bytes"], 178)
        data["targets"][1]["container_free_bytes"] = 399
        self.blocked(data, "inconsistent_target_measurement")
        data = v3_fixture()
        second = copy.deepcopy(data["targets"][0])
        second.update(volume_id="other-volume", container_id="other-container")
        data["targets"].append(second)
        self.blocked(data, "invalid_target_volumes")
        for name in ("docker_vm_cap", "growth", "os_container_reserve"):
            data = v3_fixture()
            next(a for a in data["allocations"] if a["name"] == name)["bytes"] += 53
            code, report = self.invoke(data)
            self.assertEqual(code, 1, report)
            self.assertEqual(report["e1"]["shortfall_bytes"], 1)
        data = v3_fixture()
        data["models"][0]["download_peak_bytes"] += 53
        self.assertEqual(self.invoke(data)[1]["e1"]["shortfall_bytes"], 1)

    def test_v3_delta_snapshot_and_retained_bytes_each_affect_low_water(self) -> None:
        for field in ("added_bytes", "replaced_bytes", "retained_bytes",
                      "snapshot_divergence_bytes", "max_inflight_temp_bytes"):
            with self.subTest(field=field):
                data = v3_fixture()
                data["e1"][field] += 53
                code, report = self.invoke(data)
                self.assertEqual(code, 1, report)
                self.assertEqual(report["e1"]["shortfall_bytes"], 1)
        data = v3_fixture()
        data["neo4j_projected_savings_bytes"] = 999
        self.blocked(data, "invalid_schema")
        data = v3_fixture()
        data["e1"]["snapshot_divergence_bytes"] = -1
        self.blocked(data, "invalid_or_unknown_bytes")

    def test_v3_overflow_is_unknown_not_pass(self) -> None:
        data = v3_fixture()
        data["e1"]["snapshot_divergence_bytes"] = (1 << 63) - 1
        self.blocked(data, "overflow")
        data = v3_fixture()
        data["e0"]["complete_target_bytes"] = (1 << 63) - 1
        self.blocked(data, "overflow")
        data = v3_fixture()
        data["e1"]["added_bytes"] = 1 << 63
        self.blocked(data, "invalid_or_unknown_bytes")
        data = v3_fixture()
        data["targets"][0].update(container_capacity_bytes=(1 << 63) - 1,
                                   low_water_abort_bytes=(1 << 63) - 1,
                                   container_free_bytes=0)
        data["e1"]["container_free_bytes"] = 0
        self.blocked(data, "overflow")


if __name__ == "__main__":
    unittest.main()
