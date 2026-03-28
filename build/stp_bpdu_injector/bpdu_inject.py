#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import socket
import time


TEMPLATE_HEX = (
    "01000ccccccdaabbcc0002208100000a0032aaaa0300000c010b000002021f10"
    "0aaabbcc00010000000064200aaabbcc00020080030100140002000f00000000"
    "0002000a"
)

ETH_DST_SLICE = slice(0, 6)
ETH_SRC_SLICE = slice(6, 12)
VLAN_SLICE = slice(14, 16)
PROTO_ID_SLICE = slice(26, 28)
PROTO_VERSION_OFFSET = 28
BPDU_TYPE_OFFSET = 29
FLAGS_OFFSET = 30
ROOT_ID_SLICE = slice(31, 39)
ROOT_PATH_COST_SLICE = slice(39, 43)
BRIDGE_ID_SLICE = slice(43, 51)
PORT_ID_SLICE = slice(51, 53)
MESSAGE_AGE_SLICE = slice(53, 55)
MAX_AGE_SLICE = slice(55, 57)
HELLO_SLICE = slice(57, 59)
FORWARD_DELAY_SLICE = slice(59, 61)
VLAN_TRAILER_SLICE = slice(67, 69)


def parse_mac(mac: str) -> bytes:
    return bytes(int(part, 16) for part in mac.split(":"))


def encode_bridge_id(raw_priority: int, mac: str) -> bytes:
    return raw_priority.to_bytes(2, "big") + parse_mac(mac)


def encode_timer(seconds: float) -> bytes:
    return int(round(seconds * 256)).to_bytes(2, "big")


def build_config_frame(args: argparse.Namespace) -> bytes:
    frame = bytearray.fromhex(TEMPLATE_HEX)
    frame[ETH_DST_SLICE] = parse_mac(args.dst_mac)
    frame[ETH_SRC_SLICE] = parse_mac(args.src_mac)
    frame[VLAN_SLICE] = args.vlan.to_bytes(2, "big")
    frame[PROTO_ID_SLICE] = b"\x00\x00"
    frame[PROTO_VERSION_OFFSET] = args.protocol_version
    frame[BPDU_TYPE_OFFSET] = args.bpdu_type
    frame[FLAGS_OFFSET] = args.flags
    frame[ROOT_ID_SLICE] = encode_bridge_id(args.root_priority, args.root_mac)
    frame[ROOT_PATH_COST_SLICE] = args.root_path_cost.to_bytes(4, "big")
    frame[BRIDGE_ID_SLICE] = encode_bridge_id(args.bridge_priority, args.bridge_mac)
    frame[PORT_ID_SLICE] = args.port_id.to_bytes(2, "big")
    frame[MESSAGE_AGE_SLICE] = encode_timer(args.message_age)
    frame[MAX_AGE_SLICE] = encode_timer(args.max_age)
    frame[HELLO_SLICE] = encode_timer(args.hello_time)
    frame[FORWARD_DELAY_SLICE] = encode_timer(args.forward_delay)
    frame[VLAN_TRAILER_SLICE] = args.vlan.to_bytes(2, "big")
    return bytes(frame)


def build_tcn_frame(args: argparse.Namespace) -> bytes:
    payload = bytearray()
    payload.extend(b"\xaa\xaa\x03\x00\x00\x0c\x01\x0b")
    payload.extend(b"\x00\x00")
    payload.append(args.protocol_version)
    payload.append(args.bpdu_type)

    frame = bytearray()
    frame.extend(parse_mac(args.dst_mac))
    frame.extend(parse_mac(args.src_mac))
    frame.extend(b"\x81\x00")
    frame.extend(args.vlan.to_bytes(2, "big"))
    frame.extend(len(payload).to_bytes(2, "big"))
    frame.extend(payload)
    return bytes(frame)


def build_frame(args: argparse.Namespace) -> bytes:
    if args.frame_kind == "tcn":
        frame = build_tcn_frame(args)
    else:
        frame = build_config_frame(args)

    if args.truncate_bytes:
        if args.truncate_bytes >= len(frame):
            raise ValueError("truncate-bytes removes the entire frame")
        frame = frame[: len(frame) - args.truncate_bytes]

    return frame


def frame_metadata(args: argparse.Namespace, frame: bytes) -> dict:
    return {
        "frame_kind": args.frame_kind,
        "iface": getattr(args, "iface", None),
        "dst_mac": args.dst_mac,
        "vlan": args.vlan,
        "protocol_version": args.protocol_version,
        "bpdu_type": args.bpdu_type,
        "flags": args.flags,
        "src_mac": args.src_mac,
        "root_priority_raw": args.root_priority,
        "root_mac": args.root_mac,
        "bridge_priority_raw": args.bridge_priority,
        "bridge_mac": args.bridge_mac,
        "root_path_cost": args.root_path_cost,
        "port_id": args.port_id,
        "message_age": args.message_age,
        "max_age": args.max_age,
        "hello_time": args.hello_time,
        "forward_delay": args.forward_delay,
        "truncate_bytes": args.truncate_bytes,
        "interval": getattr(args, "interval", None),
        "count": getattr(args, "count", None),
        "frame_length": len(frame),
        "frame_hex": frame.hex(),
    }


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--frame-kind", choices=["config", "tcn"], default="config")
    parser.add_argument("--vlan", type=int, default=10)
    parser.add_argument("--dst-mac", default="01:00:0c:cc:cc:cd")
    parser.add_argument("--protocol-version", type=int, default=2)
    parser.add_argument("--bpdu-type", type=lambda x: int(x, 0), default=2)
    parser.add_argument("--flags", type=lambda x: int(x, 0), default=0x3C)
    parser.add_argument("--src-mac", required=True)
    parser.add_argument("--root-priority", type=int, required=True)
    parser.add_argument("--root-mac", required=True)
    parser.add_argument("--bridge-priority", type=int, required=True)
    parser.add_argument("--bridge-mac", required=True)
    parser.add_argument("--root-path-cost", type=int, default=0)
    parser.add_argument("--port-id", type=lambda x: int(x, 0), default=0x8001)
    parser.add_argument("--message-age", type=float, default=0.0)
    parser.add_argument("--max-age", type=float, default=20.0)
    parser.add_argument("--hello-time", type=float, default=2.0)
    parser.add_argument("--forward-delay", type=float, default=15.0)
    parser.add_argument("--truncate-bytes", type=int, default=0)


def dry_run(args: argparse.Namespace) -> int:
    frame = build_frame(args)
    print(json.dumps(frame_metadata(args, frame), indent=2, sort_keys=True))
    return 0


def send(args: argparse.Namespace) -> int:
    frame = build_frame(args)
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    sock.bind((args.iface, 0))
    try:
        for _ in range(args.count):
            sock.send(frame)
            time.sleep(args.interval)
    finally:
        sock.close()
    print(json.dumps(frame_metadata(args, frame), sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    dry_parser = subparsers.add_parser("dry-run")
    add_common_arguments(dry_parser)
    dry_parser.set_defaults(func=dry_run)

    send_parser = subparsers.add_parser("send")
    add_common_arguments(send_parser)
    send_parser.add_argument("--iface", required=True)
    send_parser.add_argument("--interval", type=float, default=1.0)
    send_parser.add_argument("--count", type=int, default=10)
    send_parser.set_defaults(func=send)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
