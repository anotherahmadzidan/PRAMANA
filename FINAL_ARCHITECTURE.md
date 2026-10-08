# PRAMANA Final Candidate Architecture

TT07 Iterative MAC (#0040) is the selected baseline.

The project-level architectural contribution is the transformation from a
single iterative MAC path into a configurable compute fabric with:

- 64 physical INT8 MAC PEs (8x8)
- adaptive output-lane activation through `lane_mask`
- zero-weight skipping
- authenticated weight-loading gate
- authenticated compute gate
- 32-bit partial-sum accumulation and registered column reduction

`auth_ok` is the boundary to the separate Root-of-Trust subsystem. A real
SHA-256/model-authentication block should drive this signal in the integrated
version.

Do not claim 64x end-to-end speedup solely from 64 physical PE. Speedup must
be measured with an equivalent workload, and timing/resource overhead must be
reported after Quartus synthesis/place-and-route.
