#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import Counter
import json
import statistics
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
import re


TS_RE = re.compile(r"^(?P<ts>\d{2}:\d{2}:\d{2}\.\d+)")
MAC_RE = re.compile(r"(?P<src>[0-9a-f:]{17}) > (?P<dst>[0-9a-f:]{17})", re.IGNORECASE)
FLAGS_RE = re.compile(r"Flags \[(?P<flags>[^\]]*)\]")
BRIDGE_RE = re.compile(r"bridge-id (?P<bridge_id>[^,]+)")
VLAN_RE = re.compile(r"vlan (?P<vlan>\d+)")
MSG_RE = re.compile(
    r"message-age (?P<message_age>[\d.]+)s, max-age (?P<max_age>[\d.]+)s, "
    r"hello-time (?P<hello_time>[\d.]+)s, forwarding-delay (?P<forward_delay>[\d.]+)s"
)
ROOT_RE = re.compile(
    r"root-id (?P<root_id>[^,]+), root-pathcost (?P<root_pathcost>\d+), port-role (?P<port_role>\w+)"
)
VERSION_RE = re.compile(r"STP (?P<stp_version>802\.1[dw]), (?P<bpdu_kind>[^,]+)")
HEX_LINE_RE = re.compile(r"^\s*0x[0-9a-f]+:\s+(?P<hex>(?:[0-9a-f]{4}\s*)+)")
PVST_PREFIX = bytes.fromhex("aaaa0300000c010b")
STP_LLC_PREFIX = bytes.fromhex("424203")


@dataclass
class BpduRecord:
    timestamp: str
    seconds: float
    src_mac: str | None
    dst_mac: str | None
    vlan: int | None
    flags: list[str]
    bridge_id: str | None
    root_id: str | None
    root_pathcost: int | None
    port_role: str | None
    message_age: float | None
    max_age: float | None
    hello_time: float | None
    forwarding_delay: float | None
    stp_version: str | None
    bpdu_kind: str | None


@dataclass
class FrameBlock:
    timestamp: str
    seconds: float
    header: str
    src_mac: str | None
    dst_mac: str | None
    payload: bytes


def timestamp_to_seconds(ts: str) -> float:
    hour, minute, second = ts.split(":")
    return int(hour) * 3600 + int(minute) * 60 + float(second)


def seconds_delta(start: float, end: float) -> float:
    delta = end - start
    if delta < 0:
        delta += 86400
    return delta


def bridge_base(bridge_id: str | None) -> str | None:
    if not bridge_id or "." not in bridge_id:
        return bridge_id
    return bridge_id.rsplit(".", 1)[0]


def bridge_priority(bridge_id: str | None) -> int:
    if not bridge_id:
        return 1 << 30
    try:
        return int(bridge_id.split(".", 1)[0], 16)
    except ValueError:
        return 1 << 30


def bridge_base_priority(bridge_id: str | None, vlan: int | None) -> int | None:
    if bridge_id is None or vlan is None:
        return None
    return bridge_priority(bridge_id) - vlan


def infer_vlan_from_bridge_id(bridge_id: str | None) -> int | None:
    if not bridge_id:
        return None
    try:
        # Cisco PVST+/Rapid PVST+ encodes the extended system ID (VLAN)
        # in the lower 12 bits of the bridge priority field.
        return int(bridge_id.split(".", 1)[0], 16) & 0x0FFF
    except ValueError:
        return None


def encode_metric_tuple(record: BpduRecord) -> dict:
    return {
        "timestamp": record.timestamp,
        "bridge_id": record.bridge_id,
        "root_id": record.root_id,
        "root_pathcost": record.root_pathcost,
        "port_role": record.port_role,
        "flags": record.flags,
        "vlan": record.vlan,
        "stp_version": record.stp_version,
        "bpdu_kind": record.bpdu_kind,
    }


def parse_bpdu_records(decoded_path: Path) -> list[BpduRecord]:
    lines = decoded_path.read_text().splitlines()
    records: list[BpduRecord] = []
    idx = 0

    while idx < len(lines):
        line = lines[idx]
        ts_match = TS_RE.match(line)
        if not ts_match or "STP" not in line:
            idx += 1
            continue

        flags_match = FLAGS_RE.search(line)
        bridge_match = BRIDGE_RE.search(line)
        mac_match = MAC_RE.search(line)
        vlan_match = VLAN_RE.search(line)
        version_match = VERSION_RE.search(line)

        record = BpduRecord(
            timestamp=ts_match.group("ts"),
            seconds=timestamp_to_seconds(ts_match.group("ts")),
            src_mac=mac_match.group("src") if mac_match else None,
            dst_mac=mac_match.group("dst") if mac_match else None,
            vlan=int(vlan_match.group("vlan")) if vlan_match else None,
            flags=[flag.strip() for flag in flags_match.group("flags").split(",")] if flags_match else [],
            bridge_id=bridge_match.group("bridge_id") if bridge_match else None,
            root_id=None,
            root_pathcost=None,
            port_role=None,
            message_age=None,
            max_age=None,
            hello_time=None,
            forwarding_delay=None,
            stp_version=version_match.group("stp_version") if version_match else None,
            bpdu_kind=version_match.group("bpdu_kind") if version_match else None,
        )

        next_idx = idx + 1
        while next_idx < len(lines) and lines[next_idx].startswith(("\t", " ")):
            nested = lines[next_idx].strip()
            if nested.startswith("message-age"):
                msg_match = MSG_RE.search(nested)
                if msg_match:
                    record.message_age = float(msg_match.group("message_age"))
                    record.max_age = float(msg_match.group("max_age"))
                    record.hello_time = float(msg_match.group("hello_time"))
                    record.forwarding_delay = float(msg_match.group("forward_delay"))
            elif nested.startswith("root-id"):
                root_match = ROOT_RE.search(nested)
                if root_match:
                    record.root_id = root_match.group("root_id")
                    record.root_pathcost = int(root_match.group("root_pathcost"))
                    record.port_role = root_match.group("port_role")
            next_idx += 1

        if record.vlan is None:
            record.vlan = infer_vlan_from_bridge_id(record.root_id) or infer_vlan_from_bridge_id(record.bridge_id)

        records.append(record)
        idx = next_idx

    return records


def parse_frame_blocks(decoded_path: Path) -> list[FrameBlock]:
    lines = decoded_path.read_text().splitlines()
    blocks: list[FrameBlock] = []
    idx = 0

    while idx < len(lines):
        line = lines[idx]
        ts_match = TS_RE.match(line)
        if not ts_match:
            idx += 1
            continue

        mac_match = MAC_RE.search(line)
        payload = bytearray()
        next_idx = idx + 1
        while next_idx < len(lines) and lines[next_idx].startswith(("\t", " ")):
            nested = lines[next_idx]
            hex_match = HEX_LINE_RE.match(nested)
            if hex_match:
                payload.extend(bytes.fromhex(re.sub(r"\s+", "", hex_match.group("hex"))))
            next_idx += 1

        blocks.append(
            FrameBlock(
                timestamp=ts_match.group("ts"),
                seconds=timestamp_to_seconds(ts_match.group("ts")),
                header=line,
                src_mac=mac_match.group("src") if mac_match else None,
                dst_mac=mac_match.group("dst") if mac_match else None,
                payload=bytes(payload),
            )
        )
        idx = next_idx

    return blocks


def decode_bridge_id(raw: bytes) -> str:
    return f"{int.from_bytes(raw[:2], 'big'):04x}." + ":".join(f"{byte:02x}" for byte in raw[2:])


def decode_timer_value(raw: bytes) -> float:
    return int.from_bytes(raw, "big") / 256.0


def inspect_raw_stp_block(block: FrameBlock) -> dict | None:
    payload = block.payload
    offset = None
    encapsulation = None

    pvst_start = payload.find(PVST_PREFIX)
    stp_start = payload.find(STP_LLC_PREFIX)

    if pvst_start >= 0:
        offset = pvst_start + len(PVST_PREFIX)
        encapsulation = "pvst"
    elif stp_start >= 0:
        offset = stp_start + len(STP_LLC_PREFIX)
        encapsulation = "stp-llc"
    else:
        return None

    if len(payload) < offset + 4:
        return {
            "timestamp": block.timestamp,
            "header": block.header,
            "src_mac": block.src_mac,
            "dst_mac": block.dst_mac,
            "encapsulation": encapsulation,
            "payload_length": len(payload),
            "malformed": True,
            "malformed_reason": "truncated-header",
        }

    protocol_id = int.from_bytes(payload[offset : offset + 2], "big")
    protocol_version = payload[offset + 2]
    bpdu_type = payload[offset + 3]

    result = {
        "timestamp": block.timestamp,
        "header": block.header,
        "src_mac": block.src_mac,
        "dst_mac": block.dst_mac,
        "encapsulation": encapsulation,
        "payload_length": len(payload),
        "protocol_id": protocol_id,
        "protocol_version": protocol_version,
        "bpdu_type": bpdu_type,
        "malformed": False,
    }

    if bpdu_type in {0x00, 0x02}:
        required = offset + 35
        if len(payload) < required:
            result["malformed"] = True
            result["malformed_reason"] = "truncated-config-bpdu"
            return result

        result["flags_raw"] = payload[offset + 4]
        result["root_id"] = decode_bridge_id(payload[offset + 5 : offset + 13])
        result["root_pathcost"] = int.from_bytes(payload[offset + 13 : offset + 17], "big")
        result["bridge_id"] = decode_bridge_id(payload[offset + 17 : offset + 25])
        result["port_id"] = int.from_bytes(payload[offset + 25 : offset + 27], "big")
        result["message_age"] = decode_timer_value(payload[offset + 27 : offset + 29])
        result["max_age"] = decode_timer_value(payload[offset + 29 : offset + 31])
        result["hello_time"] = decode_timer_value(payload[offset + 31 : offset + 33])
        result["forward_delay"] = decode_timer_value(payload[offset + 33 : offset + 35])
    elif bpdu_type == 0x80:
        required = offset + 4
        if len(payload) < required:
            result["malformed"] = True
            result["malformed_reason"] = "truncated-tcn-bpdu"
            return result
    else:
        result["invalid_type"] = True

    return result


def has_flag(record: BpduRecord, fragment: str) -> bool:
    fragment = fragment.lower()
    return any(fragment in flag.lower() for flag in record.flags)


def distinct_root_events(records: list[BpduRecord]) -> list[dict]:
    events = []
    current_root = None
    for record in records:
        if not record.root_id:
            continue
        if record.root_id != current_root:
            current_root = record.root_id
            events.append(
                {
                    "timestamp": record.timestamp,
                    "root_id": record.root_id,
                    "bridge_id": record.bridge_id,
                    "flags": record.flags,
                    "vlan": record.vlan,
                }
            )
    return events


def write_summary(path: Path, summary: dict) -> None:
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")


def summary_payload(
    scenario: str,
    args: argparse.Namespace,
    key_evidence: list[dict | str],
    metrics: dict,
    trigger_window: dict | None = None,
    extra: dict | None = None,
) -> dict:
    payload = {
        "scenario": scenario,
        "success": True,
        "capture_file": args.pcap,
        "decoded_file": args.decoded,
        "trigger_window": trigger_window,
        "key_evidence": key_evidence,
        "metrics": metrics,
    }
    if extra:
        payload.update(extra)
    return payload


def timer_tuple(record: BpduRecord) -> tuple[float, float, float] | None:
    if record.hello_time is None or record.max_age is None or record.forwarding_delay is None:
        return None
    return (
        round(record.hello_time, 6),
        round(record.max_age, 6),
        round(record.forwarding_delay, 6),
    )


def ieee_timer_valid(hello_time: float, max_age: float, forward_delay: float) -> bool:
    return (2 * (forward_delay - 1)) >= max_age >= (2 * (hello_time + 1))
