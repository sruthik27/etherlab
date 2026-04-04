# Protocol Mismatch

One side of the bundle is configured for LACP and the other for PAgP, while one Linux trunk host sits on each switch for optional reachability checks.

The expected result is that `Port-channel1` does not form cleanly, and the switch CLI shows a protocol mismatch rather than a healthy bundled state.

Running the scenario capture script writes a `.pcap` and decoded `.txt` under `local/artifacts/lag/protocol-mismatch/` alongside the switch and host logs.

## Commands

- `bin/lag info protocol-mismatch`
- `bin/lag up protocol-mismatch`
- `bin/lag status protocol-mismatch`
- `bin/lag down protocol-mismatch`
