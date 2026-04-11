# Etherlab

<p align="center">
  <img src="docs/assets/banner.png" alt="Etherlab Banner" width="100%"/>
</p>

Containerlab-based networking simulations and learning labs, organized as reusable collections.

## Current Collections

- `lag`: baseline EtherChannel labs plus member-failure and mismatch scenarios built around Cisco IOL.
- `stp`: baseline spanning-tree labs, failure scenarios, and fault-capture workflows built around Cisco IOL.

## Repo Layout

- `collections/`: public lab collections. This is the main source tree.
- `collections/lag/`: LAG collection index and scenarios.
- `collections/stp/`: STP collection index, scenarios, and workflows.
- `bin/`: unified `ethl` CLI, helper shims (`stp`, `lag`), and the `clab` wrapper.
- `docs/`: setup and bring-your-own-image guidance.
- `local/`: ignored local-only assets, captures, logs, lab state, proprietary image inputs, and any older scratch labs you want to keep around privately.

## Prerequisites

Before running the current STP collection, make sure you have:

- Docker installed and running. On macOS that usually means Docker Desktop; on Linux Docker Engine is fine.
- Containerlab available either natively on the host or through the bundled `bin/clab` wrapper.
- `python3` available for summary and decode helpers.
- `screen` installed for background fault-injection runs.
- A compatible Cisco IOL image available locally. See [docs/byoi-cisco-iol.md](./docs/byoi-cisco-iol.md).
- Sudo/root privileges for containerlab network namespace manipulation.

## Quick Start

1. Review the Cisco BYOI notes in [docs/byoi-cisco-iol.md](./docs/byoi-cisco-iol.md).
2. List available collections:
   - `bin/ethl help`
3. List STP scenarios:
   - `bin/ethl stp list`
4. Deploy the baseline STP lab:
   - `bin/ethl stp up baseline`
5. Check lab status:
   - `bin/ethl stp status baseline`
6. Run a fault scenario in `screen` (attaches captures and parsed logs):
   - `bin/ethl stp run rogue-root`
7. Destroy the lab when finished:
   - `bin/ethl stp down baseline`

The unified `ethl` CLI handles all collections using a consistent syntax: `ethl <collection> <command> <scenario>`.

- `bin/ethl <col> list`: list available scenarios.
- `bin/ethl <col> info <sce>`: print the scenario README.
- `bin/ethl <col> up <sce>`: deploy a scenario topology.
- `bin/ethl <col> down <sce>`: destroy a scenario topology.
- `bin/ethl <col> run <sce>`: launch a background run in `screen`.
- `bin/ethl <col> status <sce>`: show containers and latest artifacts.
- `bin/ethl <col> graph <sce>`: open the topology graph in your browser.

Traditional shims like `bin/stp` and `bin/lag` remain available as thin wrappers around the `ethl` core.

### **Smart Context Detection**

The `ethl` CLI is context-aware. If you run it from within a specific scenario directory, you can omit the collection and scenario names:

```bash
cd collections/stp/scenarios/rogue-root/
../../../../bin/ethl run
```

This will automatically detect that you mean the `stp` collection and the `rogue-root` scenario.

## Runtime Behavior

- Scenario artifacts go to `local/artifacts/stp/<scenario>/`.
- LAG artifacts go to `local/artifacts/lag/<scenario>/`.
- Containerlab lab-state directories default to `local/state/clab/` via `CLAB_LABDIR_BASE`.
- `collections/` is the public source of truth. The old per-scenario `bin/stp-*` commands remain as thin compatibility wrappers around `bin/stp`.
- Older private experiments should live under `local/legacy/` if you want to keep them without publishing them.

## Public Release Notes

- The repo does not track proprietary Cisco IOL binaries, capture outputs, local backups, or generated containerlab runtime state.
- Cisco IOL is the validated platform for the current STP collection, but future collections are not expected to follow the same vendor or image model.
