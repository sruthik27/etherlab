# Link Anomalies

Captures either unidirectional BPDU loss or self-loop BPDU reflection on the redundant path.

Artifacts land in `local/artifacts/stp/link-anomalies/`.

## Commands

- `bin/stp info link-anomalies`
- `bin/stp run link-anomalies`
- `bin/stp run link-anomalies self-loop`
- `bin/stp status link-anomalies`
- `bin/stp down link-anomalies`

Use `self-loop` as an extra argument if you want the reflected-BPDU mode.
