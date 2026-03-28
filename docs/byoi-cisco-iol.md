# BYOI: Cisco IOL for STP

The STP collection is published in a bring-your-own-image model.

This repo does not include Cisco IOL binaries or related local licensing material. You are expected to supply those locally and keep them under the ignored `local/` tree.

## Option 1: Build the Expected Local Tag

1. Put the binary at:
   - `local/images/cisco_iol-L2-15.1a.bin`
2. Build the local image:
   - `docker build -t vrnetlab/cisco_iol:L2-15.1a -f build/cisco_iol/Dockerfile .`
3. Run the baseline lab:
   - `bin/stp up baseline`

## Option 2: Use a Different Local Tag

If you already have a compatible image, export `STP_SWITCH_IMAGE` before running a lab.

Example:

```bash
export STP_SWITCH_IMAGE=my-local-registry/cisco-iol:l2
bin/stp up baseline
```

## Related Environment Variables

- `STP_SWITCH_IMAGE`: overrides the switch image used by STP topologies.
- `STP_BPDU_INJECTOR_IMAGE`: overrides the injector/fault helper image when a scenario needs one.
- `CLAB_CMD`: uses native `containerlab` when available, or you can point it at another compatible wrapper.
- `CLAB_LABDIR_BASE`: defaults to `local/state/clab/` so generated lab state stays out of the public source tree.

## Notes

- `bin/clab` passes the STP-related environment variables into the containerlab container, so overrides work with both native containerlab and the macOS wrapper.
- The old raw `images/` directory was moved under `local/images/` so the public repo no longer mixes proprietary inputs into tracked source.
