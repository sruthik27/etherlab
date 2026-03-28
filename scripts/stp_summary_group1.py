from __future__ import annotations

from stp_summary_common import *

def root_instability_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    root_events = distinct_root_events(records)
    root_sequence = [event["root_id"] for event in root_events]
    root_flap_detected = (
        len(root_sequence) >= 3
        and root_sequence[0] == root_sequence[-1]
        and len(set(root_sequence)) > 1
    )
    if not root_flap_detected:
        raise SystemExit("Did not detect a root sequence that leaves and returns to the original root")

    return summary_payload(
        "root-instability",
        args,
        key_evidence=root_events[:6],
        metrics={
            "packet_count": len(records),
            "root_change_count": max(0, len(root_events) - 1),
            "root_sequence": root_events,
            "unique_roots": sorted(set(root_sequence)),
            "root_flap_detected": root_flap_detected,
        },
        trigger_window={
            "start": root_events[0]["timestamp"],
            "end": root_events[-1]["timestamp"],
        },
    )


def rogue_root_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    root_events = distinct_root_events(records)
    if len(root_events) < 2:
        raise SystemExit("Did not detect a rogue root takeover event")

    before_root = root_events[0]
    takeover = root_events[1]
    superior = next(
        (
            record
            for record in records
            if record.root_id == takeover["root_id"] and record.root_pathcost == 0
        ),
        None,
    )
    if superior is None:
        raise SystemExit("Could not locate the superior BPDU that introduced the new root")

    return summary_payload(
        "rogue-root",
        args,
        key_evidence=[
            {"before_root": before_root["root_id"], "after_root": takeover["root_id"]},
            encode_metric_tuple(superior),
        ],
        metrics={
            "packet_count": len(records),
            "before_root": before_root,
            "after_root": takeover,
            "triggering_bpdu": asdict(superior),
        },
        trigger_window={"start": before_root["timestamp"], "end": takeover["timestamp"]},
    )


def bpdu_silence_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    threshold = args.gap_threshold
    original_root_record = next(
        (
            record
            for record in records
            if record.root_id is not None
            and record.root_pathcost == 0
            and bridge_base(record.bridge_id) == record.root_id
        ),
        None,
    )
    if original_root_record is None:
        raise SystemExit("Could not identify the original root bridge BPDU stream")

    original_root_id = original_root_record.root_id
    root_originated = [
        record
        for record in records
        if record.root_id == original_root_id
        and record.root_pathcost == 0
        and bridge_base(record.bridge_id) == original_root_id
    ]
    if len(root_originated) < 2:
        raise SystemExit("Did not capture enough original-root BPDUs to measure silence")

    gaps = []
    for previous, current in zip(root_originated, root_originated[1:]):
        gap = seconds_delta(previous.seconds, current.seconds)
        if gap > threshold:
            gaps.append(
                {
                    "start": previous.timestamp,
                    "end": current.timestamp,
                    "gap_seconds": round(gap, 6),
                    "root_id": original_root_id,
                }
            )

    if not gaps:
        raise SystemExit(
            f"Did not observe any original-root BPDU gap greater than {threshold} seconds"
        )

    return summary_payload(
        "bpdu-silence",
        args,
        key_evidence=gaps[:5],
        metrics={
            "packet_count": len(records),
            "original_root_id": original_root_id,
            "original_root_bpdu_count": len(root_originated),
            "gap_threshold_seconds": threshold,
            "max_gap_seconds": max(gap["gap_seconds"] for gap in gaps),
            "silent_windows": gaps,
        },
        trigger_window={"start": gaps[0]["start"], "end": gaps[-1]["end"]},
    )


def slow_reconvergence_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    trigger_seconds = timestamp_to_seconds(args.trigger_time)

    bridge_ids = sorted(
        {record.bridge_id for record in records if record.bridge_id is not None},
        key=bridge_priority,
    )
    if len(bridge_ids) < 2:
        raise SystemExit("Need at least two bridge IDs on the backup-path capture to measure reconvergence")

    candidate = None
    for bridge_id in bridge_ids:
        pre_roles = [
            record.port_role
            for record in records
            if record.bridge_id == bridge_id and record.seconds < trigger_seconds
        ]
        post_records = [
            record for record in records if record.bridge_id == bridge_id and record.seconds >= trigger_seconds
        ]
        if not pre_roles or not post_records:
            continue
        if pre_roles[-1] == "Root":
            continue
        first_root = next((record for record in post_records if record.port_role == "Root"), None)
        if first_root:
            candidate = (bridge_id, first_root)
            break

    if candidate is None:
        raise SystemExit("Did not find a post-trigger root-role transition on the backup path")

    bridge_id, first_root = candidate
    convergence_seconds = round(seconds_delta(trigger_seconds, first_root.seconds), 6)
    return summary_payload(
        "slow-reconvergence",
        args,
        key_evidence=[{"bridge_id": bridge_id, "first_root_timestamp": first_root.timestamp}],
        metrics={
            "packet_count": len(records),
            "trigger_time": args.trigger_time,
            "convergence_bridge_id": bridge_id,
            "first_root_timestamp": first_root.timestamp,
            "convergence_seconds": convergence_seconds,
            "max_convergence_seconds": convergence_seconds,
            "average_convergence_seconds": convergence_seconds,
            "slow_threshold_seconds": args.slow_threshold,
            "slow_event_detected": convergence_seconds > args.slow_threshold,
        },
        trigger_window={"start": args.trigger_time, "end": first_root.timestamp},
    )


def link_anomalies_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    message_ages = [record.message_age for record in records if record.message_age is not None]
    max_message_age = max(message_ages) if message_ages else 0.0

    if args.mode == "unidirectional":
        zero_cost_non_root = []
        for record in records:
            if record.root_pathcost != 0 or record.root_id is None or record.bridge_id is None:
                continue
            if bridge_base(record.bridge_id) != record.root_id:
                zero_cost_non_root.append(
                    {
                        "timestamp": record.timestamp,
                        "bridge_id": record.bridge_id,
                        "root_id": record.root_id,
                        "port_role": record.port_role,
                    }
                )

        anomaly_detected = bool(zero_cost_non_root) or max_message_age >= 1.0
        if not anomaly_detected:
            raise SystemExit("Did not observe message-age growth or zero-cost non-root signaling")

        return summary_payload(
            "link-anomalies",
            args,
            key_evidence=zero_cost_non_root[:5] or [{"message_age_max": max_message_age}],
            metrics={
                "mode": "unidirectional",
                "packet_count": len(records),
                "message_age_range": {
                    "min": min(message_ages) if message_ages else 0.0,
                    "max": max_message_age,
                },
                "zero_cost_non_root_events": zero_cost_non_root,
                "anomaly_detected": anomaly_detected,
            },
        )

    duplicate_bursts = []
    for previous, current in zip(records, records[1:]):
        same_tuple = (
            previous.bridge_id == current.bridge_id
            and previous.root_id == current.root_id
            and previous.flags == current.flags
            and previous.port_role == current.port_role
        )
        if same_tuple and seconds_delta(previous.seconds, current.seconds) < 0.001:
            duplicate_bursts.append(
                {
                    "timestamp": current.timestamp,
                    "bridge_id": current.bridge_id,
                    "root_id": current.root_id,
                }
            )

    dominant_bridge_ids = {}
    bridge_variants = {}
    for record in records:
        dominant_bridge_ids[record.bridge_id] = dominant_bridge_ids.get(record.bridge_id, 0) + 1
        base_bridge_id = bridge_base(record.bridge_id)
        if base_bridge_id is None:
            continue
        variant = bridge_variants.setdefault(
            base_bridge_id,
            {"bridge_ids": set(), "src_macs": set(), "root_ids": set()},
        )
        if record.bridge_id is not None:
            variant["bridge_ids"].add(record.bridge_id)
        if record.src_mac is not None:
            variant["src_macs"].add(record.src_mac)
        if record.root_id is not None:
            variant["root_ids"].add(record.root_id)

    reflected_variants = []
    for base_bridge_id, variant in bridge_variants.items():
        if len(variant["bridge_ids"]) > 1 or len(variant["src_macs"]) > 1:
            reflected_variants.append(
                {
                    "base_bridge_id": base_bridge_id,
                    "bridge_ids": sorted(variant["bridge_ids"]),
                    "src_macs": sorted(variant["src_macs"]),
                    "root_ids": sorted(variant["root_ids"]),
                }
            )

    if not duplicate_bursts and not reflected_variants:
        raise SystemExit(
            "Did not observe duplicate reflected BPDUs or multiple local bridge variants consistent with a self-loop"
        )

    return summary_payload(
        "link-anomalies",
        args,
        key_evidence=duplicate_bursts[:5] + reflected_variants[:3],
        metrics={
            "mode": "self-loop",
            "packet_count": len(records),
            "dominant_bridge_ids": dominant_bridge_ids,
            "duplicate_burst_count": len(duplicate_bursts),
            "sample_duplicate_bursts": duplicate_bursts[:10],
            "reflected_variants": reflected_variants,
            "anomaly_detected": True,
        },
    )


def root_misconfiguration_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    root_events = distinct_root_events(records)
    anomalies = []

    for idx, event in enumerate(root_events):
        vlan = event["vlan"]
        raw_priority = bridge_priority(event["root_id"])
        base_priority = bridge_base_priority(event["root_id"], vlan)
        if vlan is None or base_priority is None:
            continue
        if base_priority % 4096 == 0:
            continue

        trigger_record = next(
            (
                record
                for record in records
                if record.root_id == event["root_id"] and record.root_pathcost == 0
            ),
            None,
        )
        anomalies.append(
            {
                "timestamp": event["timestamp"],
                "before_root": root_events[idx - 1]["root_id"] if idx > 0 else None,
                "after_root": event["root_id"],
                "raw_priority": raw_priority,
                "base_priority": base_priority,
                "vlan": vlan,
                "claim_type": "active_root_event",
                "triggering_bpdu": asdict(trigger_record) if trigger_record else None,
            }
        )

    if not anomalies:
        for record in records:
            if record.vlan is None or record.root_id is None:
                continue
            raw_priority = bridge_priority(record.root_id)
            base_priority = bridge_base_priority(record.root_id, record.vlan)
            if base_priority is None or base_priority % 4096 == 0:
                continue
            anomalies.append(
                {
                    "timestamp": record.timestamp,
                    "before_root": None,
                    "after_root": record.root_id,
                    "raw_priority": raw_priority,
                    "base_priority": base_priority,
                    "vlan": record.vlan,
                    "claim_type": "superior_bpdu_claim",
                    "triggering_bpdu": asdict(record),
                }
            )
            break

    if not anomalies:
        raise SystemExit("Did not observe any active root using a non-standard base priority")

    first = anomalies[0]
    return summary_payload(
        "root-misconfiguration",
        args,
        key_evidence=anomalies[:3],
        metrics={
            "packet_count": len(records),
            "root_change_count": max(0, len(root_events) - 1),
            "root_events": root_events,
            "anomaly_count": len(anomalies),
            "anomalies": anomalies,
        },
        trigger_window={"start": first["timestamp"], "end": anomalies[-1]["timestamp"]},
    )


