from __future__ import annotations

from stp_summary_common import *

def timer_misconfigurations_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    domain_timers: dict[int, set[tuple[float, float, float]]] = {}
    bridge_timers: dict[str, dict[str, set]] = {}
    ieee_violations = []

    for record in records:
        timer_values = timer_tuple(record)
        if timer_values is None or record.bridge_id is None or record.vlan is None:
            continue

        domain_timers.setdefault(record.vlan, set()).add(timer_values)
        bridge_key = bridge_base(record.bridge_id) or record.bridge_id
        bridge_state = bridge_timers.setdefault(
            bridge_key,
            {"bridge_ids": set(), "vlans": set(), "timer_tuples": set()},
        )
        bridge_state["bridge_ids"].add(record.bridge_id)
        bridge_state["vlans"].add(record.vlan)
        bridge_state["timer_tuples"].add(timer_values)

        hello_time, max_age, forward_delay = timer_values
        if not ieee_timer_valid(hello_time, max_age, forward_delay):
            ieee_violations.append(
                {
                    "timestamp": record.timestamp,
                    "bridge_id": record.bridge_id,
                    "vlan": record.vlan,
                    "hello_time": hello_time,
                    "max_age": max_age,
                    "forward_delay": forward_delay,
                }
            )

    inconsistent_domains = [
        {"vlan": vlan, "timer_tuples": sorted(timer_values)}
        for vlan, timer_values in domain_timers.items()
        if len(timer_values) > 1
    ]

    if not inconsistent_domains and not ieee_violations:
        raise SystemExit("Did not observe timer inconsistencies or IEEE timer violations")

    normalized_bridge_timers = [
        {
            "bridge_base": bridge_base_id,
            "bridge_ids": sorted(data["bridge_ids"]),
            "vlans": sorted(data["vlans"]),
            "timer_tuples": sorted(data["timer_tuples"]),
        }
        for bridge_base_id, data in sorted(bridge_timers.items())
    ]

    return summary_payload(
        "timer-misconfigurations",
        args,
        key_evidence=inconsistent_domains[:3] + ieee_violations[:3],
        metrics={
            "packet_count": len(records),
            "domains_with_inconsistent_timers": inconsistent_domains,
            "bridge_timer_profiles": normalized_bridge_timers,
            "ieee_timer_violations": ieee_violations,
        },
    )


def path_cost_conflicts_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    by_vlan_bridge: dict[int, dict[str, BpduRecord]] = {}
    by_bridge_base_vlan: dict[str, dict[int, set[int]]] = {}

    for record in records:
        if record.vlan is None or record.bridge_id is None or record.root_pathcost is None:
            continue
        bridge_key = bridge_base(record.bridge_id) or record.bridge_id
        vlan_state = by_vlan_bridge.setdefault(record.vlan, {})
        existing = vlan_state.get(bridge_key)
        if existing is None:
            vlan_state[bridge_key] = record
        elif record.root_pathcost < (existing.root_pathcost or 1 << 30):
            vlan_state[bridge_key] = record

        by_bridge_base_vlan.setdefault(bridge_key, {}).setdefault(record.vlan, set()).add(record.root_pathcost)

    tie_breaks = []
    outlier_costs = []
    cross_vlan_conflicts = []

    for vlan, bridge_records in sorted(by_vlan_bridge.items()):
        candidates = list(bridge_records.values())
        tie_groups: dict[tuple[str, int, int], list[BpduRecord]] = {}
        costs = []
        for record in candidates:
            costs.append(record.root_pathcost or 0)
            tie_key = (
                record.root_id or "unknown",
                record.root_pathcost or 0,
                bridge_base_priority(record.bridge_id, vlan) or bridge_priority(record.bridge_id),
            )
            tie_groups.setdefault(tie_key, []).append(record)

        for (root_id, root_cost, bridge_prio), group in tie_groups.items():
            if len(group) < 2:
                continue
            winning_bridge = sorted(group, key=lambda item: bridge_priority(item.bridge_id))[0].bridge_id
            tie_breaks.append(
                {
                    "vlan": vlan,
                    "root_id": root_id,
                    "root_pathcost": root_cost,
                    "bridge_priority": bridge_prio,
                    "candidate_bridges": [record.bridge_id for record in sorted(group, key=lambda item: bridge_priority(item.bridge_id))],
                    "winning_bridge": winning_bridge,
                    "tie_break": "sender-bridge-id",
                }
            )

        positive_costs = [cost for cost in costs if cost > 0]
        if len(positive_costs) >= 2:
            low = min(positive_costs)
            high = max(positive_costs)
            if low > 0 and high / low >= args.outlier_ratio:
                outlier_costs.append(
                    {
                        "vlan": vlan,
                        "min_cost": low,
                        "max_cost": high,
                        "ratio": round(high / low, 6),
                        "advertised_costs": {record.bridge_id: record.root_pathcost for record in candidates},
                    }
                )

    for bridge_key, vlan_costs in sorted(by_bridge_base_vlan.items()):
        normalized = {vlan: sorted(costs) for vlan, costs in vlan_costs.items()}
        distinct_cost_sets = {tuple(costs) for costs in normalized.values()}
        if len(distinct_cost_sets) > 1:
            cross_vlan_conflicts.append({"bridge_base": bridge_key, "costs_by_vlan": normalized})

    if not tie_breaks and not outlier_costs and not cross_vlan_conflicts:
        raise SystemExit("Did not observe path-cost ties, outlier costs, or cross-VLAN cost conflicts")

    return summary_payload(
        "path-cost-conflicts",
        args,
        key_evidence=tie_breaks[:3] + outlier_costs[:3] + cross_vlan_conflicts[:3],
        metrics={
            "packet_count": len(records),
            "tie_breaks": tie_breaks,
            "outlier_costs": outlier_costs,
            "cross_vlan_cost_conflicts": cross_vlan_conflicts,
        },
    )


def port_stuck_nonforwarding_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    trigger_seconds = timestamp_to_seconds(args.trigger_time)

    local_records = [
        record
        for record in records
        if record.seconds >= trigger_seconds
        and bridge_base(record.bridge_id) == args.local_bridge_base
        and record.port_role in {"Root", "Designated"}
    ]
    if not local_records:
        raise SystemExit("Did not observe post-trigger local BPDUs with a candidate forwarding role")

    non_forwarding = [
        record
        for record in local_records
        if "Forward" not in record.flags and "Forwarding" not in record.flags
    ]
    forwarding = [
        record for record in local_records if "Forward" in record.flags or "Forwarding" in record.flags
    ]

    if not non_forwarding:
        raise SystemExit("Did not observe the candidate port remaining in a non-forwarding BPDU state")
    if forwarding:
        raise SystemExit("Observed the candidate port transition into forwarding; it did not stay stuck")

    stuck_seconds = round(seconds_delta(non_forwarding[0].seconds, non_forwarding[-1].seconds), 6)
    if stuck_seconds < args.stuck_threshold:
        raise SystemExit(
            f"Observed non-forwarding behavior for only {stuck_seconds}s, below the threshold of {args.stuck_threshold}s"
        )

    return summary_payload(
        "port-stuck-nonforwarding",
        args,
        key_evidence=[encode_metric_tuple(non_forwarding[0]), encode_metric_tuple(non_forwarding[-1])],
        metrics={
            "packet_count": len(records),
            "local_bridge_base": args.local_bridge_base,
            "candidate_record_count": len(local_records),
            "non_forwarding_record_count": len(non_forwarding),
            "stuck_duration_seconds": stuck_seconds,
            "first_non_forwarding_record": asdict(non_forwarding[0]),
            "last_non_forwarding_record": asdict(non_forwarding[-1]),
        },
        trigger_window={"start": args.trigger_time, "end": non_forwarding[-1].timestamp},
    )


def version_mismatch_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    vlan_versions: dict[int, set[str]] = {}
    version_counts: dict[str, int] = {}
    kind_counts: dict[str, int] = {}

    for record in records:
        if record.vlan is not None and record.stp_version is not None:
            vlan_versions.setdefault(record.vlan, set()).add(record.stp_version)
        if record.stp_version is not None:
            version_counts[record.stp_version] = version_counts.get(record.stp_version, 0) + 1
        if record.bpdu_kind is not None:
            kind_counts[record.bpdu_kind] = kind_counts.get(record.bpdu_kind, 0) + 1

    mixed_domains = [
        {"vlan": vlan, "versions": sorted(versions)}
        for vlan, versions in sorted(vlan_versions.items())
        if len(versions) > 1
    ]
    fallback_records = [
        encode_metric_tuple(record)
        for record in records
        if record.stp_version == "802.1d" or (record.bpdu_kind and "Config" in record.bpdu_kind)
    ]

    if not mixed_domains and {"802.1d", "802.1w"}.issubset(version_counts):
        observed_vlans = sorted({record.vlan for record in records if record.vlan is not None})
        mixed_domains.append(
            {
                "vlan": observed_vlans[0] if observed_vlans else None,
                "versions": ["802.1d", "802.1w"],
                "inferred_from_capture": True,
            }
        )

    if not mixed_domains:
        raise SystemExit("Did not observe multiple STP versions in the same VLAN domain")

    return summary_payload(
        "version-mismatch",
        args,
        key_evidence=mixed_domains[:3] + fallback_records[:3],
        metrics={
            "packet_count": len(records),
            "mixed_domains": mixed_domains,
            "version_counts": version_counts,
            "bpdu_kind_counts": kind_counts,
            "fallback_evidence": fallback_records[:10],
        },
    )


def bpdu_guard_violations_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    local_records = [
        record
        for record in records
        if args.local_bridge_base is not None
        and record.bridge_id is not None
        and bridge_base(record.bridge_id) == args.local_bridge_base
    ]
    remote_records = [
        record
        for record in records
        if record.bridge_id is not None
        and (
            args.local_bridge_base is None
            or bridge_base(record.bridge_id) != args.local_bridge_base
        )
    ]
    if not remote_records:
        raise SystemExit("Did not capture any remote BPDUs on the guarded access port")

    last_local_before_violation = local_records[-1] if local_records else None
    if last_local_before_violation is not None:
        later_remote_records = [record for record in remote_records if record.seconds > last_local_before_violation.seconds]
        first = later_remote_records[0] if later_remote_records else remote_records[0]
    else:
        first = remote_records[0]

    burst = [first]
    burst_end_idx = records.index(first)
    for next_record in records[burst_end_idx + 1 :]:
        gap = seconds_delta(burst[-1].seconds, next_record.seconds)
        if gap <= 1.5:
            burst.append(next_record)
            burst_end_idx += 1
            continue
        break

    silence_window = None
    capture_end_seconds = records[-1].seconds
    if burst_end_idx + 1 < len(records):
        next_after_burst = records[burst_end_idx + 1]
        silence_window = round(seconds_delta(burst[-1].seconds, next_after_burst.seconds), 6)
    else:
        silence_window = round(seconds_delta(burst[-1].seconds, capture_end_seconds), 6)

    local_silence_window = None
    first_local_after_violation = None
    if args.local_bridge_base is not None:
        for record in local_records:
            if last_local_before_violation is not None and record.seconds > first.seconds:
                first_local_after_violation = record
                break

        if last_local_before_violation is not None:
            if first_local_after_violation is not None:
                local_silence_window = round(
                    seconds_delta(last_local_before_violation.seconds, first_local_after_violation.seconds), 6
                )
            else:
                local_silence_window = round(
                    seconds_delta(last_local_before_violation.seconds, capture_end_seconds), 6
                )

    if silence_window < args.silence_threshold and (
        local_silence_window is None or local_silence_window < args.silence_threshold
    ):
        raise SystemExit(
            f"Observed only {silence_window}s of post-violation wire silence"
            + (
                f" and {local_silence_window}s of local-bridge silence"
                if local_silence_window is not None
                else ""
            )
            + f", below the threshold of {args.silence_threshold}s"
        )

    key_evidence = [encode_metric_tuple(first)]
    if last_local_before_violation is not None:
        key_evidence.append(encode_metric_tuple(last_local_before_violation))

    return summary_payload(
        "bpdu-guard-violations",
        args,
        key_evidence=key_evidence,
        metrics={
            "packet_count": len(records),
            "local_bridge_base": args.local_bridge_base,
            "offending_bridge_id": first.bridge_id,
            "offending_src_mac": first.src_mac,
            "first_offending_timestamp": first.timestamp,
            "post_violation_silence_seconds": silence_window,
            "local_bridge_silence_seconds": local_silence_window,
            "offending_burst_size": len(burst),
            "first_offending_bpdu": asdict(first),
            "last_local_before_violation": asdict(last_local_before_violation) if last_local_before_violation else None,
            "first_local_after_violation": asdict(first_local_after_violation) if first_local_after_violation else None,
        },
        trigger_window={"start": first.timestamp, "end": records[-1].timestamp},
    )


