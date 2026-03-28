#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from stp_summary_common import write_summary
from stp_summary_group1 import (
    bpdu_silence_summary,
    link_anomalies_summary,
    root_instability_summary,
    root_misconfiguration_summary,
    rogue_root_summary,
    slow_reconvergence_summary,
)
from stp_summary_group2 import (
    bpdu_guard_violations_summary,
    path_cost_conflicts_summary,
    port_stuck_nonforwarding_summary,
    timer_misconfigurations_summary,
    version_mismatch_summary,
)
from stp_summary_group3 import (
    bpdu_malformation_summary,
    bpdu_rate_timing_anomalies_summary,
    dispute_detection_summary,
    proposal_agreement_failure_summary,
    tcn_ack_failure_summary,
)

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="scenario", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--decoded", required=True)
    common.add_argument("--pcap", required=True)
    common.add_argument("--summary", required=True)

    root_instability = subparsers.add_parser("root-instability", parents=[common])
    root_instability.set_defaults(func=root_instability_summary)

    rogue_root = subparsers.add_parser("rogue-root", parents=[common])
    rogue_root.set_defaults(func=rogue_root_summary)

    bpdu_silence = subparsers.add_parser("bpdu-silence", parents=[common])
    bpdu_silence.add_argument("--gap-threshold", type=float, default=20.0)
    bpdu_silence.set_defaults(func=bpdu_silence_summary)

    slow_reconv = subparsers.add_parser("slow-reconvergence", parents=[common])
    slow_reconv.add_argument("--trigger-time", required=True)
    slow_reconv.add_argument("--slow-threshold", type=float, default=6.0)
    slow_reconv.set_defaults(func=slow_reconvergence_summary)

    link_anomalies = subparsers.add_parser("link-anomalies", parents=[common])
    link_anomalies.add_argument("--mode", choices=["unidirectional", "self-loop"], required=True)
    link_anomalies.set_defaults(func=link_anomalies_summary)

    root_misconfig = subparsers.add_parser("root-misconfiguration", parents=[common])
    root_misconfig.set_defaults(func=root_misconfiguration_summary)

    timer_misconfig = subparsers.add_parser("timer-misconfigurations", parents=[common])
    timer_misconfig.set_defaults(func=timer_misconfigurations_summary)

    path_cost = subparsers.add_parser("path-cost-conflicts", parents=[common])
    path_cost.add_argument("--outlier-ratio", type=float, default=10.0)
    path_cost.set_defaults(func=path_cost_conflicts_summary)

    port_stuck = subparsers.add_parser("port-stuck-nonforwarding", parents=[common])
    port_stuck.add_argument("--trigger-time", required=True)
    port_stuck.add_argument("--local-bridge-base", required=True)
    port_stuck.add_argument("--stuck-threshold", type=float, default=8.0)
    port_stuck.set_defaults(func=port_stuck_nonforwarding_summary)

    version_mismatch = subparsers.add_parser("version-mismatch", parents=[common])
    version_mismatch.set_defaults(func=version_mismatch_summary)

    bpdu_guard = subparsers.add_parser("bpdu-guard-violations", parents=[common])
    bpdu_guard.add_argument("--local-bridge-base")
    bpdu_guard.add_argument("--silence-threshold", type=float, default=4.0)
    bpdu_guard.set_defaults(func=bpdu_guard_violations_summary)

    proposal_failure = subparsers.add_parser("proposal-agreement-failure", parents=[common])
    proposal_failure.add_argument("--agreement-timeout", type=float, default=4.0)
    proposal_failure.add_argument("--proposal-window", type=float, default=4.0)
    proposal_failure.set_defaults(func=proposal_agreement_failure_summary)

    dispute_detection = subparsers.add_parser("dispute-detection", parents=[common])
    dispute_detection.set_defaults(func=dispute_detection_summary)

    tcn_ack = subparsers.add_parser("tcn-ack-failure", parents=[common])
    tcn_ack.add_argument("--ack-timeout", type=float, default=4.0)
    tcn_ack.set_defaults(func=tcn_ack_failure_summary)

    malformation = subparsers.add_parser("bpdu-malformation", parents=[common])
    malformation.set_defaults(func=bpdu_malformation_summary)

    rate_timing = subparsers.add_parser("bpdu-rate-anomalies", parents=[common])
    rate_timing.add_argument("--bridge-base", required=True)
    rate_timing.add_argument("--hello-time", type=float, default=2.0)
    rate_timing.add_argument("--jitter-threshold", type=float, default=0.75)
    rate_timing.add_argument("--mean-deviation-threshold", type=float, default=0.5)
    rate_timing.set_defaults(func=bpdu_rate_timing_anomalies_summary)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    summary = args.func(args)
    write_summary(Path(args.summary), summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
