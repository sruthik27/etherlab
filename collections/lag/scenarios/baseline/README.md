# Baseline

Two Cisco IOL-L2 switches form `Port-channel1` with LACP across two physical links and carry VLANs `10,20`.

Each side also has one Linux trunk host with `eth1.10` and `eth1.20` so the run can verify end-to-end reachability on both VLANs while staying within the Cisco IOL port limits.

Running the scenario capture script writes a `.pcap` and decoded `.txt` under `local/artifacts/lag/baseline/` alongside the switch and host logs.

## Commands

- `bin/lag info baseline`
- `bin/lag up baseline`
- `bin/lag status baseline`
- `bin/lag down baseline`
