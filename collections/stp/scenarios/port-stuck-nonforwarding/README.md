# Port Stuck Nonforwarding

Breaks the primary path and suppresses return BPDUs on the backup path so a candidate forwarding port never reaches forwarding state.

Artifacts land in `local/artifacts/stp/port-stuck-nonforwarding/`.

## Commands

- `bin/stp info port-stuck-nonforwarding`
- `bin/stp run port-stuck-nonforwarding`
- `bin/stp status port-stuck-nonforwarding`
- `bin/stp down port-stuck-nonforwarding`
