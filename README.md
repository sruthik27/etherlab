# Networking Labs

Containerlab-based networking simulations and learning labs, organized as reusable collections.

The repo is intentionally collection-oriented rather than protocol-specific. STP is the first collection, and the structure is designed so future wired-networking collections such as DHCP, DNS, LAG, switching, and fault-injection labs can be added without another repo-wide rework.

## Current Collections

- `lag`: baseline EtherChannel labs plus member-failure and mismatch scenarios built around Cisco IOL.
- `stp`: baseline spanning-tree labs, failure scenarios, and fault-capture workflows built around Cisco IOL.

## Repo Layout

- `collections/`: public lab collections. This is the main source tree.
- `collections/lag/`: LAG collection index and scenarios.
- `collections/stp/`: STP collection index, scenarios, and workflows.
- `bin/`: command entrypoints such as `bin/netlab`, `bin/stp`, and `bin/clab`.
- `docs/`: setup and bring-your-own-image guidance.
- `local/`: ignored local-only assets, captures, logs, lab state, proprietary image inputs, and any older scratch labs you want to keep around privately.

## Prerequisites

Before running the current STP collection, make sure you have:

- Docker installed and running. On macOS that usually means Docker Desktop; on Linux Docker Engine is fine.
- Containerlab available either natively on the host or through the bundled `bin/clab` wrapper.
- `python3` available for the STP summary and decode helpers.
- `screen` installed if you want to use `bin/stp run <scenario>` for longer fault-injection workflows.
- A compatible Cisco IOL image available locally. See [docs/byoi-cisco-iol.md](/Users/sruthiki/containerlab/docs/byoi-cisco-iol.md).
- Enough privileges for privileged containers and network namespace manipulation, which containerlab requires.

## Quick Start

1. Review the Cisco BYOI notes in [docs/byoi-cisco-iol.md](/Users/sruthiki/containerlab/docs/byoi-cisco-iol.md) and make sure the expected local image tag exists.
2. Confirm Docker is running and that either `containerlab` or `bin/clab` is available.
3. List available collections:
   - `bin/netlab collections`
4. List STP scenarios:
   - `bin/netlab stp list`
5. List LAG scenarios:
   - `bin/netlab lag list`
6. Bring up the baseline LAG lab:
   - `bin/lag up baseline`
7. Check the baseline LAG lab status:
   - `bin/lag status baseline`
8. Tear the baseline LAG lab down when finished:
   - `bin/lag down baseline`
9. Run a fault scenario in `screen` when you want captures and parsed output:
   - `bin/stp run rogue-root`

## Commands

- `bin/netlab collections`: list available collections.
- `bin/netlab lag list`: list LAG scenarios.
- `bin/netlab stp list`: list STP scenarios.
- `bin/lag info <scenario>`: print the scenario README.
- `bin/lag up <scenario>`: deploy a scenario topology.
- `bin/lag down <scenario>`: destroy a scenario topology.
- `bin/lag run <scenario>`: launch the scenario run in `screen`.
- `bin/lag status <scenario>`: show containers and recent artifacts.
- `bin/lag graph <scenario>`: open the topology graph via containerlab.
- `bin/stp info <scenario>`: print the scenario README.
- `bin/stp up <scenario>`: deploy a scenario topology.
- `bin/stp down <scenario>`: destroy a scenario topology.
- `bin/stp run <scenario>`: launch the scenario run in `screen`.
- `bin/stp status <scenario>`: show containers and recent artifacts.
- `bin/stp graph <scenario>`: open the topology graph via containerlab.

## Runtime Behavior

- Scenario artifacts go to `local/artifacts/stp/<scenario>/`.
- LAG artifacts go to `local/artifacts/lag/<scenario>/`.
- Containerlab lab-state directories default to `local/state/clab/` via `CLAB_LABDIR_BASE`.
- `collections/` is the public source of truth. The old per-scenario `bin/stp-*` commands remain as thin compatibility wrappers around `bin/stp`.
- Older private experiments should live under `local/legacy/` if you want to keep them without publishing them.
- `notify_when_done` is optional. If it exists in your shell setup, STP runs will use it; otherwise the command still launches and prints the `screen` session and log path.

## Public Release Notes

- The repo does not track proprietary Cisco IOL binaries, capture outputs, local backups, or generated containerlab runtime state.
- Cisco IOL is the validated platform for the current STP collection, but future collections are not expected to follow the same vendor or image model.
