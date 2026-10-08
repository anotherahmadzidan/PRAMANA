# PRAMANA RTL Final Candidate — Fixed

This package fixes the two issues found in the previous simulation:

1. The test matrix now contains exactly 16 zero weights out of 64, with no
   accidental additional zero weights. Therefore the deterministic expected
   activity is 48 / 64 / 24 / 12 for the four activity tests.
2. `active_mac_count` is cleared to zero whenever `auth_ok=0`, preventing a
   stale count from being mistaken for accepted computation.

## Main files
- `pramana_pe.sv`
- `pramana_accel.sv`
- `tb_pramana_final.sv`
- `run_questa.do`

## Run in Questa
```tcl
cd C:/PERURI/PRAMANA_RTL_FINAL_FIXED
do run_questa.do
```

## Expected final result
```text
PRAMANA FINAL CANDIDATE TB: PASS
```

Important: this is a final *candidate compute core*, not yet a proven final
chip implementation. Quartus synthesis/fit, Fmax, resource utilization, and
apple-to-apple workload benchmarking against TT07 must still be done.
