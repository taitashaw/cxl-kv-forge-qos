# Phase 1 — final pointer

Phase 1 in this repo was iterated through three intermediate closures
on its way to the eventual Phase 2 / Phase 2.1 silicon-signed-off
numbers. This file exists as a single entry point into the Phase 1
artifacts and decisions; the canonical authoritative source is
`docs/architecture.md`.

## Reading order

1. `docs/rtl_phase1_microarchitecture.md` — the structural Phase 1
   spec (RTL module list, AXI4-Stream / AXI4-Lite contracts, BD wrap).
2. `docs/rtl_phase1_verification_plan.md` — XSim test plan + assertions.
3. `docs/vivado_phase1_flow.md` — Vivado driver flow and per-strategy
   conventions established during Phase 1.
4. `docs/phase1_known_limitations.md` — what was deliberately MVP.

## Phase 1 closure progression

| stage | part | RTL state | Achieved Fmax |
|---|---|---|---|
| 2-stage qmgr pipeline on xczu3eg (WebPack fallback) | xczu3eg-sbva484-1-e | combinational arbiter | 80 MHz |
| 2-stage qmgr pipeline on xczu7ev | xczu7ev-ffvc1156-2-e | combinational arbiter | 86 MHz |
| 3-stage + retiming on xczu7ev (Phase 1 final) | xczu7ev-ffvc1156-2-e | combinational arbiter + retimed post-comb register | 86 MHz |

The 86 MHz ceiling was set by the arbiter's 36-level combinational
priority+slack compare cone. Retiming the inserted post-comb register
backward through the cone reduced logic depth (42 → 36 levels) but
not the routing delay (~8 ns), so Fmax didn't move meaningfully.

Per-build detail reports live alongside this file:

- `results/impl/xczu7ev-ffvc1156-2-e_results.md` — Phase 1, 2-stage on xczu7ev
- `results/impl/xczu7ev-ffvc1156-2-e_stage3_retiming_results.md` — Phase 1 final, 3-stage + retiming on xczu7ev

## What followed

The Phase 1 closure capped at 86 MHz forced an architectural rewrite:
the single-cycle 8-way arbiter became a 3-level pairwise tournament
tree in Phase 2 (Fmax 306 MHz), and Phase 2.1 added one more pipeline
stage inside `kvq_token_bucket` to lift Fmax to **350 MHz** with clean
timing closure.

See `results/PHASE2_1_FINAL.md` for the current project signoff.
