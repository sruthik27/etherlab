# Member Link Failure

Starts from the healthy LACP baseline with one Linux trunk host on each side, records switch state, then drops one physical member link from `Port-channel1`.

The expected result is that the logical bundle stays up with a single active member and host traffic continues to pass on both VLANs.

Running the scenario capture script writes a `.pcap` and decoded `.txt` under `local/artifacts/lag/member-link-failure/` alongside the before and after switch snapshots.

## Commands

- `bin/lag info member-link-failure`
- `bin/lag up member-link-failure`
- `bin/lag status member-link-failure`
- `bin/lag down member-link-failure`
