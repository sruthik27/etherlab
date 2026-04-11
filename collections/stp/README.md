# STP Collection

Cisco-IOL-based spanning-tree labs and fault scenarios for learning, experimentation, and packet capture.

## Prerequisites

To run these scenarios successfully, make sure you have:

- Docker installed and running.
- Containerlab installed natively, or the bundled `bin/clab` wrapper available as the fallback runtime.
- `python3` installed for the summary and decode helpers used by the run workflows.
- `screen` installed if you want to use `bin/stp run <scenario>`.
- A compatible Cisco IOL image available locally as `vrnetlab/cisco_iol:L2-15.1a`, or exported through `STP_SWITCH_IMAGE`.
- Permission to run privileged containers and create the network plumbing that containerlab needs.

If you have not prepared the Cisco image yet, follow [docs/byoi-cisco-iol.md](../../docs/byoi-cisco-iol.md) first.

## Baseline Flow

Use the baseline scenario first to confirm the runtime is working:

- `bin/ethl stp up baseline`
- `bin/ethl stp status baseline`
- `bin/ethl stp down baseline`

Once the baseline lab works, move on to the fault scenarios with:

- `bin/ethl stp list`
- `bin/ethl stp info <scenario>`
- `bin/ethl stp run <scenario> [args...]`

## Commands

- `bin/ethl stp list`
- `bin/ethl stp info <scenario>`
- `bin/ethl stp up <scenario>`
- `bin/ethl stp run <scenario> [args...]`
- `bin/ethl stp status <scenario>`
- `bin/ethl stp down <scenario>`

## Artifacts

- `.pcap`
- decoded `.txt`
- scenario `summary.json`

Artifacts are written to `local/artifacts/stp/<scenario>/`.

## Scenarios

- `baseline`: two-switch redundant-trunk baseline for convergence and verification.
- `root-instability`: transient root changes caused by pausing and unpausing the root bridge.
- `rogue-root`: a lower-priority rogue switch joins a converged domain through a relay.
- `bpdu-silence`: the active root disappears long enough to create a BPDU gap.
- `slow-reconvergence`: failover is forced to rely on timers instead of immediate BPDU-driven convergence.
- `link-anomalies`: capture either unidirectional BPDU loss or self-loop BPDU reflection.
- `root-misconfiguration`: superior PVST+ BPDUs are injected with a non-standard raw priority.
- `timer-misconfigurations`: a superior root is injected with inconsistent STP timers.
- `path-cost-conflicts`: dual-homed downstream switching exposes tie-break and extreme-cost behavior.
- `port-stuck-nonforwarding`: the backup path never reaches forwarding after the primary path fails.
- `version-mismatch`: legacy PVST and Rapid PVST are mixed on the same topology.
- `bpdu-guard-violations`: a rogue switch hits a PortFast + BPDU Guard access port.
- `proposal-agreement-failure`: an RSTP re-proposal is forced while return agreements are dropped.
- `dispute-detection`: inferior designated BPDUs are injected onto an otherwise forwarding segment.
- `tcn-ack-failure`: a legacy PVST downstream flap produces unacknowledged TCNs.
- `bpdu-malformation`: malformed BPDUs are injected and decoded with raw hex output.
- `bpdu-rate-anomalies`: bursty and jittery synthetic BPDU streams are measured against the hello timer.

## Batch Workflows

- `bin/stp-phase2-batch`
- `bin/stp-phase3-batch`
