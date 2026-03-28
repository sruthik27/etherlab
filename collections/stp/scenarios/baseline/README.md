# Baseline

Two Cisco IOL-L2 switches with two parallel trunk links and one access host on each side.

`sw1` is the VLAN 10 root bridge, `sw2` is the secondary root, and one redundant trunk should block after convergence.

## Commands

- `bin/stp info baseline`
- `bin/stp up baseline`
- `bin/stp status baseline`
- `bin/stp down baseline`
