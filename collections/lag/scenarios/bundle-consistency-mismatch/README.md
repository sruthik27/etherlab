# Bundle Consistency Mismatch

One member of the EtherChannel is configured with a different allowed VLAN list from the rest of the bundle, with one Linux trunk host on each switch for optional reachability checks.

The expected result is that the Port-channel stays partially formed while at least one member is suspended or excluded due to configuration inconsistency.

Running the scenario capture script writes a `.pcap` and decoded `.txt` under `local/artifacts/lag/bundle-consistency-mismatch/` alongside the switch and host logs.

## Commands

- `bin/lag info bundle-consistency-mismatch`
- `bin/lag up bundle-consistency-mismatch`
- `bin/lag status bundle-consistency-mismatch`
- `bin/lag down bundle-consistency-mismatch`
