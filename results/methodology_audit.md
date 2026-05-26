# Phase 2.2 throughput methodology audit

Status: **case (d.i) — methodology is correct, identity match across the four
schedulers is mathematically expected for the Phase 0 simulator's single-
server / no-drops model.**

No CSV regeneration is required. A clarifying note has been added to the
README adjacent to the throughput claim.

## Audit answers (with file:line citations)

### a. Where is the throughput value computed for each scheduler?

`sim/metrics.py:100` (and the per-tenant variant at `sim/metrics.py:137`):

```python
throughput_per_us=len(recs) / horizon_us,
```

`horizon_us` is computed in the enclosing function at
`sim/metrics.py:78-81`:

```python
horizon_us = (
    max((r.complete_us for r in result.records), default=0.0)
    - min((r.arrival_us for r in result.records), default=0.0)
) or 1.0
```

i.e. a single `horizon_us` is derived per `SimResult`, then reused as the
denominator for every per-class throughput inside that result.

### b. Numerator: input arrival count or output completion count?

**Output completion count.** `len(recs)` where `recs` are
`CompletionRecord` objects added at `sim/schedulers/base.py:140-148`:

```python
self.records.append(
    CompletionRecord(
        ...
        complete_us=self.now,
        ...
    )
)
```

This append only fires when `remaining[nxt.request_id] <= 1e-9` (request
fully serviced), so it's a true output-side event. Requests are never
dropped in the current schedulers (B0/B1/B2/QoS all eventually serve every
queued request), so `len(recs)` equals the input arrival count, but the
*source* of the number is the completion-event log, not the workload
arrival count.

### c. Denominator: workload constant or observed elapsed?

**Observed elapsed at the scheduler output.** `sim/metrics.py:78-81` again:
`max(complete_us) - min(arrival_us)` is the actual span between the first
request's arrival and the last request's completion, both pulled from
`result.records`. The workload-generator constant
(`generate_w4_combined`'s `horizon_us` argument, `sim/adversarial/
workload_generator.py:121-127`) is NOT what enters `metrics.py`.

### d. Why do all four schedulers report 5,668 req/s identically?

Direct re-derivation from each scheduler's `results/records/*.csv`:

| scheduler | N completions | min(arrival_us) | max(complete_us) | horizon (µs) | throughput (req/s) |
|---|---|---|---|---|---|
| B0 Shared FIFO | 55 | 0.000 | 9704.155 | 9704.155 | **5,668** |
| B1 Priority + CB | 55 | 0.000 | 9704.155 | 9704.155 | **5,668** |
| B2 Chunked Prefill | 55 | 0.000 | 9704.155 | 9704.155 | **5,668** |
| QoS_CxlKvForge | 55 | 0.000 | 9704.155 | 9704.155 | **5,668** |

The identity is **case (d.i): correct, not artifact.** Three structural
properties of the simulator make it mathematically unavoidable:

1. **Single-server.** `sim/schedulers/base.py:127-128` advances exactly one
   slice per loop iteration on a single `self.now` clock:
   `self.now += slice_us; self.core_free_at = self.now`. There is no
   multi-core dispatch.
2. **No drops.** Every `CompletionRecord` corresponds to a fully-served
   request; the schedulers never reject or expire a queued request, so
   `len(recs)` is fixed by the workload arrival count.
3. **No idle gaps when work is pending.** When `select_next()` returns
   None (no eligible work), the loop advances `self.now` to the next
   arrival time (`sim/schedulers/base.py:106-108`), not by an
   idle-tick. Conversely, whenever there *is* a queued request, the
   inner loop consumes a `service_chunk_us` slice immediately. Even
   the chunking schedulers (B2 / QoS) re-enqueue tails to the same
   priority queue and keep the core busy.

Given (1), (2), (3): the total core-occupancy time for every scheduler is
exactly `sum(req.service_us for req in workload)`. The clock starts at
`min(arrival_us)` (driven there by `sim/schedulers/base.py:106-108`) and
finishes at `min(arrival_us) + total_service`. Therefore the *observed
elapsed* span is identical across the four schedulers, and dividing the
same `N` by the same `horizon_us` produces the same number.

What the schedulers DO differentiate on is the *order in which* the same
total work gets dispatched - which shows up as per-tenant latency
(p50/p95/p99) and deadline-miss rate, not as aggregate throughput. That
differentiation is real and visible in the same CSVs:

| scheduler | premium p95 latency (µs) | premium deadline miss rate |
|---|---|---|
| B0 Shared FIFO | 1294.91 | 83.3% |
| B1 Priority + CB | 758.45 | 41.7% |
| B2 Chunked Prefill | 231.70 | 0.0% |
| QoS_CxlKvForge | 244.37 | 0.0% |

(Values from `results/adversarial_w4_summary.csv`. Latencies and miss
rates DO differ; throughput doesn't, by design.)

## Why this is the right methodology for the comparison

The Phase 0 simulator is intentionally workload-time, not RTL-cycle-time
(`Request.arrival_us` and `Request.service_us` in
`sim/adversarial/workload_generator.py:29-30`). Its purpose is to compare
*scheduler policy*, holding the underlying compute resource constant.
Total aggregate throughput is the wrong axis on which to differentiate
policy when no policy is allowed to drop or expire requests; the right
axes are latency distribution and SLA preservation, both of which the
comparison plot already shows in the first three panels of
`results/plots/adversarial_w4_baseline_comparison.png`.

## What would a "RTL throughput" claim look like instead?

A separate measure, independent of the Phase 0 simulator: the Phase 2.1
RTL closes at 350 MHz on a 256-bit AXIS request stream, so:

```
89.6 Gb/s per AXIS stream = 256 b * 350 MHz / 1000
179.2 Gb/s aggregate = request + response
```

That number lives in `README.md` and `results/PHASE2_1_FINAL.md`. It is
a property of the silicon implementation, not of the scheduler
simulator. The two metrics measure different things and should not be
conflated.

## Conditional action (per Phase 2.2 spec)

The spec branches on the verdict:

> IF throughput is correctly measured at output (case d.i):
>   - Document in methodology_audit.md why the identity match is expected
>   - Add a single-line clarifying note to README.md
>   - No CSV regeneration needed.

Verdict matches (d.i). Documentation is this file. README note added.
CSVs and plots untouched.

## File:line index used in this audit

- `sim/metrics.py:78-81` - horizon_us computation
- `sim/metrics.py:100` - throughput_per_us assignment
- `sim/metrics.py:137` - per-tenant variant
- `sim/schedulers/base.py:127-128` - single-server clock advance
- `sim/schedulers/base.py:140-148` - CompletionRecord append (output event)
- `sim/schedulers/base.py:106-108` - jump-to-next-arrival on empty queue
- `sim/adversarial/workload_generator.py:29-30` - `arrival_us` /
  `service_us` field definitions
- `sim/adversarial/workload_generator.py:121-127` - `generate_w4_combined`
  signature; the `horizon_us` argument is workload duration, not the
  denominator used in `metrics.py`
