# LAG Collection

Cisco-IOL-based EtherChannel and link-aggregation labs for baseline verification and failure analysis.

## Prerequisites

To run these scenarios successfully, make sure you have:

- Docker installed and running.
- Containerlab installed natively, or the bundled `bin/clab` wrapper available as the fallback runtime.
- `python3` installed for the screen-launched runner helpers.
- `screen` installed if you want to use `bin/lag run <scenario>`.
- A compatible Cisco IOL image available locally as `vrnetlab/cisco_iol:L2-15.1a`, or exported through `LAG_SWITCH_IMAGE`.
- Permission to run privileged containers and create the network plumbing that containerlab needs.

If you have not prepared the Cisco image yet, follow [docs/byoi-cisco-iol.md](../../docs/byoi-cisco-iol.md) first.

## Baseline Flow

Use the baseline scenario first to confirm the runtime is working:

- `bin/ethl lag up baseline`
- `bin/ethl lag status baseline`
- `bin/ethl lag down baseline`

Once the baseline lab works, move on to the fault scenarios with:

- `bin/ethl lag list`
- `bin/ethl lag info <scenario>`
- `bin/ethl lag run <scenario>`

## Commands

- `bin/ethl lag list`
- `bin/ethl lag info <scenario>`
- `bin/ethl lag up <scenario>`
- `bin/ethl lag run <scenario>`
- `bin/ethl lag status <scenario>`
- `bin/ethl lag down <scenario>`

## Artifacts

- `.pcap`
- decoded `.txt`
- switch CLI snapshots
- host ping results
- screen logs when launched via `bin/lag run`

Artifacts are written to `local/artifacts/lag/<scenario>/`.

## Scenarios

- `baseline`: two switches form an LACP Port-channel trunk carrying VLANs 10 and 20, with one Linux trunk host on each side.
- `member-link-failure`: one Port-channel member is dropped after convergence and the bundle stays up on the remaining link.
- `protocol-mismatch`: one side uses LACP while the other uses PAgP to show a control-protocol mismatch.
- `bundle-consistency-mismatch`: one member is configured with a mismatched trunk policy so the bundle becomes partially suspended.
