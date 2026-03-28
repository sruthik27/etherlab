from __future__ import annotations

from stp_summary_common import *

def proposal_agreement_failure_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    proposals = [record for record in records if has_flag(record, "proposal")]
    agreements = [record for record in records if has_flag(record, "agreement")]

    if not proposals:
        raise SystemExit("Did not observe any RSTP proposal BPDUs")

    unanswered = []
    for proposal in proposals:
        match = next(
            (
                agreement
                for agreement in agreements
                if agreement.bridge_id != proposal.bridge_id
                and 0 <= seconds_delta(proposal.seconds, agreement.seconds) <= args.agreement_timeout
            ),
            None,
        )
        if match is None:
            unanswered.append(
                {
                    "proposal": encode_metric_tuple(proposal),
                    "agreement_timeout_seconds": args.agreement_timeout,
                }
            )

    orphan_agreements = []
    for agreement in agreements:
        preceding = next(
            (
                proposal
                for proposal in reversed(proposals)
                if proposal.bridge_id != agreement.bridge_id
                and 0 <= seconds_delta(proposal.seconds, agreement.seconds) <= args.proposal_window
            ),
            None,
        )
        if preceding is None:
            orphan_agreements.append(encode_metric_tuple(agreement))

    if not unanswered:
        raise SystemExit("Did not observe any proposal without a matching agreement")

    key_evidence = unanswered[:3]
    if orphan_agreements:
        key_evidence.extend(orphan_agreements[:2])

    return summary_payload(
        "proposal-agreement-failure",
        args,
        key_evidence=key_evidence,
        metrics={
            "packet_count": len(records),
            "proposal_count": len(proposals),
            "agreement_count": len(agreements),
            "unanswered_proposals": unanswered,
            "orphan_agreements": orphan_agreements,
        },
        trigger_window={"start": proposals[0].timestamp, "end": records[-1].timestamp},
    )


def dispute_detection_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    stable_root = Counter(
        record.root_id for record in records if record.root_id is not None
    ).most_common(1)
    if not stable_root:
        raise SystemExit("Could not determine the stable root bridge for the capture")

    stable_root_id = stable_root[0][0]
    local_forwarding = next(
        (
            record
            for record in records
            if record.root_id == stable_root_id
            and record.bridge_id is not None
            and ("Forward" in record.flags or record.port_role in {"Root", "Designated"})
        ),
        None,
    )
    if local_forwarding is None:
        raise SystemExit("Did not observe a forwarding baseline before the dispute traffic")

    inferior_designated = []
    for record in records:
        if (
            record.root_id is None
            or record.bridge_id is None
            or record.root_pathcost is None
            or record.root_pathcost != 0
            or bridge_base(record.bridge_id) != record.root_id
        ):
            continue
        if bridge_priority(record.root_id) <= bridge_priority(stable_root_id):
            continue
        inferior_designated.append(
            {
                "timestamp": record.timestamp,
                "bridge_id": record.bridge_id,
                "root_id": record.root_id,
                "root_pathcost": record.root_pathcost,
                "flags": record.flags,
            }
        )

    if not inferior_designated:
        raise SystemExit("Did not observe inferior designated BPDUs consistent with a dispute condition")

    return summary_payload(
        "dispute-detection",
        args,
        key_evidence=[encode_metric_tuple(local_forwarding)] + inferior_designated[:3],
        metrics={
            "packet_count": len(records),
            "stable_root_id": stable_root_id,
            "local_forwarding_record": asdict(local_forwarding),
            "inferior_designated_bpdus": inferior_designated,
        },
        trigger_window={"start": local_forwarding.timestamp, "end": inferior_designated[-1]["timestamp"]},
    )


def tcn_ack_failure_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    tcn_records = [
        record
        for record in records
        if record.bpdu_kind is not None and "topology change" in record.bpdu_kind.lower()
    ]
    ack_records = [
        record
        for record in records
        if has_flag(record, "ack") or has_flag(record, "acknowledg")
    ]

    if not tcn_records:
        raise SystemExit("Did not observe any topology change notification BPDUs")

    unacknowledged = []
    for tcn in tcn_records:
        ack = next(
            (
                record
                for record in ack_records
                if record.bridge_id != tcn.bridge_id
                and 0 <= seconds_delta(tcn.seconds, record.seconds) <= args.ack_timeout
            ),
            None,
        )
        if ack is None:
            unacknowledged.append(encode_metric_tuple(tcn))

    if not unacknowledged:
        raise SystemExit("All observed TCN BPDUs were acknowledged")

    return summary_payload(
        "tcn-ack-failure",
        args,
        key_evidence=unacknowledged[:5],
        metrics={
            "packet_count": len(records),
            "tcn_count": len(tcn_records),
            "ack_count": len(ack_records),
            "unacknowledged_tcn_bpdus": unacknowledged,
        },
        trigger_window={"start": tcn_records[0].timestamp, "end": records[-1].timestamp},
    )


def bpdu_malformation_summary(args: argparse.Namespace) -> dict:
    blocks = parse_frame_blocks(Path(args.decoded))
    inspected = [result for result in (inspect_raw_stp_block(block) for block in blocks) if result is not None]
    anomalies = []

    for frame in inspected:
        if frame.get("malformed"):
            anomalies.append(
                {
                    "timestamp": frame["timestamp"],
                    "kind": "malformed_truncated",
                    "details": frame,
                }
            )
            continue

        if frame["protocol_version"] not in {0, 2}:
            anomalies.append(
                {
                    "timestamp": frame["timestamp"],
                    "kind": "unknown_protocol_version",
                    "details": frame,
                }
            )

        if frame["bpdu_type"] not in {0x00, 0x02, 0x80}:
            anomalies.append(
                {
                    "timestamp": frame["timestamp"],
                    "kind": "invalid_bpdu_type",
                    "details": frame,
                }
            )

        if {
            "hello_time",
            "max_age",
            "forward_delay",
        }.issubset(frame):
            hello = frame["hello_time"]
            max_age = frame["max_age"]
            forward_delay = frame["forward_delay"]
            if not (1.0 <= hello <= 10.0 and 6.0 <= max_age <= 40.0 and 4.0 <= forward_delay <= 30.0):
                anomalies.append(
                    {
                        "timestamp": frame["timestamp"],
                        "kind": "out_of_range_timers",
                        "details": frame,
                    }
                )

    observed_kinds = sorted({anomaly["kind"] for anomaly in anomalies})
    required = {
        "unknown_protocol_version",
        "invalid_bpdu_type",
        "out_of_range_timers",
        "malformed_truncated",
    }
    if not required.issubset(observed_kinds):
        missing = sorted(required - set(observed_kinds))
        raise SystemExit(f"Did not observe all malformed BPDU classes; missing {missing}")

    return summary_payload(
        "bpdu-malformation",
        args,
        key_evidence=anomalies[:6],
        metrics={
            "frame_count": len(inspected),
            "anomaly_count": len(anomalies),
            "anomaly_kinds": observed_kinds,
            "anomalies": anomalies,
        },
        trigger_window={"start": anomalies[0]["timestamp"], "end": anomalies[-1]["timestamp"]},
    )


def bpdu_rate_timing_anomalies_summary(args: argparse.Namespace) -> dict:
    records = parse_bpdu_records(Path(args.decoded))
    target_records = [
        record
        for record in records
        if record.bridge_id is not None and bridge_base(record.bridge_id) == args.bridge_base
    ]
    if len(target_records) < 4:
        raise SystemExit("Did not capture enough BPDUs from the target bridge to evaluate timing")

    deltas = [
        round(seconds_delta(previous.seconds, current.seconds), 6)
        for previous, current in zip(target_records, target_records[1:])
    ]
    burst_deltas = [delta for delta in deltas if delta < (args.hello_time / 2.0)]
    jitter_seconds = round(statistics.pstdev(deltas), 6) if len(deltas) > 1 else 0.0
    mean_delta = round(statistics.mean(deltas), 6)
    sustained_rate_deviation = abs(mean_delta - args.hello_time) > args.mean_deviation_threshold

    if not burst_deltas and jitter_seconds <= args.jitter_threshold and not sustained_rate_deviation:
        raise SystemExit("Did not observe jitter, bursts, or sustained rate deviation above the thresholds")

    return summary_payload(
        "bpdu-rate-anomalies",
        args,
        key_evidence=[
            {
                "target_bridge_base": args.bridge_base,
                "first_timestamp": target_records[0].timestamp,
                "last_timestamp": target_records[-1].timestamp,
                "burst_deltas": burst_deltas[:10],
            }
        ],
        metrics={
            "packet_count": len(records),
            "target_record_count": len(target_records),
            "inter_arrival_deltas": deltas,
            "hello_time_seconds": args.hello_time,
            "mean_delta_seconds": mean_delta,
            "jitter_seconds": jitter_seconds,
            "burst_count": len(burst_deltas),
            "burst_deltas": burst_deltas,
            "sustained_rate_deviation": sustained_rate_deviation,
        },
        trigger_window={"start": target_records[0].timestamp, "end": target_records[-1].timestamp},
    )


