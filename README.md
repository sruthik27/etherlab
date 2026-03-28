# Networking Labs

Containerlab-based networking simulations and learning labs, organized as reusable collections.

The repo is intentionally collection-oriented rather than protocol-specific. STP is the first collection, and the structure is designed so future wired-networking collections such as DHCP, DNS, LAG, switching, and fault-injection labs can be added without another repo-wide rework.

## Current Collections

- `stp`: baseline spanning-tree labs, failure scenarios, and fault-capture workflows built around Cisco IOL.

## Repo Layout

- `collections/`: public lab collections. This is the main source tree.
- `collections/stp/`: STP collection index, scenarios, and workflows.
- `bin/`: command entrypoints such as `bin/netlab`, `bin/stp`, and `bin/clab`.
- `docs/`: setup and bring-your-own-image guidance.
- `legacy/`: preserved older examples that are not part of the primary collection UX.
- `local/`: ignored local-only assets, captures, logs, lab state, and proprietary image inputs.

## Quick Start

1. Review the Cisco BYOI notes in [docs/byoi-cisco-iol.md](/Users/sruthiki/containerlab/docs/byoi-cisco-iol.md).
2. List available collections:
   - `bin/netlab collections`
3. List STP scenarios:
   - `bin/netlab stp list`
4. Bring up the baseline STP lab:
   - `bin/stp up baseline`
5. Run a fault scenario in `screen`:
   - `bin/stp run rogue-root`

## Commands

- `bin/netlab collections`: list available collections.
- `bin/netlab stp list`: list STP scenarios.
- `bin/stp info <scenario>`: print the scenario README.
- `bin/stp up <scenario>`: deploy a scenario topology.
- `bin/stp down <scenario>`: destroy a scenario topology.
- `bin/stp run <scenario>`: launch the scenario run in `screen`.
- `bin/stp status <scenario>`: show containers and recent artifacts.
- `bin/stp graph <scenario>`: open the topology graph via containerlab.

## Runtime Behavior

- Scenario artifacts go to `local/artifacts/stp/<scenario>/`.
- Containerlab lab-state directories default to `local/state/clab/` via `CLAB_LABDIR_BASE`.
- `collections/` is the public source of truth. The old per-scenario `bin/stp-*` commands remain as thin compatibility wrappers around `bin/stp`.
- `notify_when_done` is optional. If it exists in your shell setup, STP runs will use it; otherwise the command still launches and prints the `screen` session and log path.

## Public Release Notes

- The repo does not track proprietary Cisco IOL binaries, capture outputs, local backups, or generated containerlab runtime state.
- Cisco IOL is the validated platform for the current STP collection, but future collections are not expected to follow the same vendor or image model.
