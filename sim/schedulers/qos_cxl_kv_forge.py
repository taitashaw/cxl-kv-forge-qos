"""
QoS_CxlKvForge - the target scheduler the RTL emulates.

Mirrors the Phase 1 hardware policy at clock-cycle granularity:

  1. Per-tenant token-bucket credit limits. A bulk noisy-neighbor cannot
     monopolize the core because once its bucket is empty it must wait for the
     refill timer.
  2. Priority class first; lower number wins.
  3. Within the same priority class, the earliest absolute deadline wins.
  4. Round-robin tie-break (handled implicitly by FIFO order within priority).
  5. Chunked execution at the same CHUNK_US granularity as B2 so we don't
     credit ourselves with any micro-architectural advantage that the
     baselines don't have.

Refill model: every REFILL_PERIOD_US microseconds, each tenant's bucket gets
its per-tenant `refill_rate` credits, capped at `burst_cap`. The credit cost
per request is request.payload_tokens (a soft proxy for "how much KV the
request touches"); for the test workloads, premium reads cost ~1-4 tokens,
bulk writes cost ~8-32 tokens, so bulk drains its bucket fast.

This mirrors what kvq_credit_engine.sv + kvq_token_bucket.sv enforce in
hardware. The hardware uses cycles; here we use microseconds.
"""

from __future__ import annotations

import heapq
from dataclasses import dataclass
from itertools import count
from typing import Dict, List, Optional, Tuple

from ..adversarial.workload_generator import Request
from .base import SchedulerBase


CHUNK_US = 100.0
REFILL_PERIOD_US = 256.0


@dataclass
class TenantContract:
    burst_cap: int
    refill_rate: int        # credits per refill window
    priority_floor: int     # min priority (used to flag premium tenants)
    sla_class: str


DEFAULT_CONTRACTS: Dict[str, TenantContract] = {
    "premium":     TenantContract(burst_cap=64,  refill_rate=8,  priority_floor=1, sla_class="premium"),
    "standard":    TenantContract(burst_cap=128, refill_rate=12, priority_floor=4, sla_class="standard"),
    "best_effort": TenantContract(burst_cap=48,  refill_rate=1,  priority_floor=12, sla_class="best_effort"),
}


class QoSCxlKvForge(SchedulerBase):
    name = "QoS_CxlKvForge"

    def __init__(
        self,
        chunk_us: float = CHUNK_US,
        refill_period_us: float = REFILL_PERIOD_US,
        contracts: Optional[Dict[str, TenantContract]] = None,
    ) -> None:
        super().__init__()
        self.chunk_us = chunk_us
        self.refill_period_us = refill_period_us
        self.contracts = dict(contracts or DEFAULT_CONTRACTS)
        # heap key: (priority, deadline_us, tie, Request)
        self._heap: List[Tuple[int, float, int, Request]] = []
        self._tie = count()
        self._buckets: Dict[int, int] = {}
        self._last_refill: float = 0.0
        # tenant_id -> sla_class, populated as tenants arrive
        self._tenant_class: Dict[int, str] = {}

    # ------------------------------------------------------------------
    def _refill_to(self, t: float) -> None:
        if t <= self._last_refill:
            return
        periods = int((t - self._last_refill) // self.refill_period_us)
        if periods <= 0:
            return
        for tid, cls in self._tenant_class.items():
            ct = self.contracts.get(cls, self.contracts["best_effort"])
            current = self._buckets.get(tid, ct.burst_cap)
            current = min(ct.burst_cap, current + ct.refill_rate * periods)
            self._buckets[tid] = current
        self._last_refill += periods * self.refill_period_us

    def _ensure_tenant(self, req: Request) -> None:
        if req.tenant_id in self._tenant_class:
            return
        self._tenant_class[req.tenant_id] = req.sla_class
        ct = self.contracts.get(req.sla_class, self.contracts["best_effort"])
        self._buckets[req.tenant_id] = ct.burst_cap

    def _has_credit(self, req: Request) -> bool:
        self._refill_to(self.now)
        return self._buckets.get(req.tenant_id, 0) >= max(1, req.payload_tokens)

    # ------------------------------------------------------------------
    # SchedulerBase hooks
    # ------------------------------------------------------------------
    def on_arrival(self, req: Request) -> None:
        self._ensure_tenant(req)
        heapq.heappush(
            self._heap, (req.priority, req.deadline_us, next(self._tie), req)
        )

    def has_pending(self) -> bool:
        return bool(self._heap)

    def select_next(self) -> Optional[Request]:
        if not self._heap:
            return None
        # Walk the heap and pick the highest-priority request whose tenant
        # still has credit. If none do, take the head anyway (degrade
        # gracefully rather than deadlock).
        held: List[Tuple[int, float, int, Request]] = []
        chosen: Optional[Request] = None
        self._refill_to(self.now)
        while self._heap:
            entry = heapq.heappop(self._heap)
            req = entry[3]
            if self._buckets.get(req.tenant_id, 0) >= max(1, req.payload_tokens):
                chosen = req
                break
            held.append(entry)

        for e in held:
            heapq.heappush(self._heap, e)

        if chosen is None and held:
            # Fallback: take the highest-priority queued request.
            entry = held[0]
            # Remove the chosen one from heap (re-pop in order then push back).
            self._heap.clear()
            for e in held[1:]:
                heapq.heappush(self._heap, e)
            chosen = entry[3]

        if chosen is not None:
            cost = max(1, chosen.payload_tokens)
            self._buckets[chosen.tenant_id] = max(
                0, self._buckets.get(chosen.tenant_id, 0) - cost
            )
        return chosen

    def service_chunk_us(self, req: Request) -> float:
        return self.chunk_us

    def on_chunk_complete(self, req: Request, remaining_us: float) -> None:
        # Re-enqueue the tail at the same priority/deadline.
        heapq.heappush(
            self._heap, (req.priority, req.deadline_us, next(self._tie), req)
        )
