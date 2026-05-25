"""
Common discrete-event simulator base for the four Phase 0 schedulers.

The simulator models a single-server compute core. Requests arrive over time
(from the workload generator), join a per-scheduler queueing structure, and the
scheduler picks the next request to run when the core becomes free.

All four schedulers (B0/B1/B2/QoS) share the event loop and metric collection;
they differ in how they pick which queued request to run next and (for B2) how
they may pre-empt long-running requests at chunk boundaries.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from ..adversarial.workload_generator import Request


@dataclass
class CompletionRecord:
    request_id: int
    tenant_id: int
    sla_class: str
    priority: int
    arrival_us: float
    start_us: float
    complete_us: float
    deadline_us: float
    service_us: float

    @property
    def latency_us(self) -> float:
        return self.complete_us - self.arrival_us

    @property
    def queueing_us(self) -> float:
        return self.start_us - self.arrival_us

    @property
    def deadline_miss(self) -> bool:
        return self.complete_us > self.deadline_us


@dataclass
class SimResult:
    scheduler_name: str
    records: List[CompletionRecord]
    tenant_classes: Dict[int, str] = field(default_factory=dict)


class SchedulerBase:
    """Abstract base. Subclasses implement select_next() and on_arrival()."""

    name: str = "base"

    def __init__(self) -> None:
        self.now: float = 0.0
        self.core_free_at: float = 0.0
        self.records: List[CompletionRecord] = []
        # subclass state goes in __init__ overrides

    # ------------------------------------------------------------------
    # Hooks subclasses override
    # ------------------------------------------------------------------
    def on_arrival(self, req: Request) -> None:
        raise NotImplementedError

    def select_next(self) -> Optional[Request]:
        """Return the next request to run, or None if queue is empty."""
        raise NotImplementedError

    def has_pending(self) -> bool:
        raise NotImplementedError

    def service_chunk_us(self, req: Request) -> float:
        """How much service time to apply in one slice. Override for chunking."""
        return req.service_us

    def on_chunk_complete(self, req: Request, remaining_us: float) -> None:
        """Called when a slice ends. Default: no chunking, request is done."""
        return None

    # ------------------------------------------------------------------
    # Event loop
    # ------------------------------------------------------------------
    def run(self, requests: List[Request], tenant_classes: Dict[int, str]) -> SimResult:
        events = sorted(requests, key=lambda r: r.arrival_us)
        # Mutable per-request remaining service tracked via a dict so chunking
        # schedulers can re-enqueue tail work.
        remaining: Dict[int, float] = {r.request_id: r.service_us for r in events}
        start_us: Dict[int, float] = {}  # first time a request hits the core
        arrive_idx = 0

        while arrive_idx < len(events) or self.has_pending():
            # Inject any arrivals up to "now" or the core-free time.
            while arrive_idx < len(events) and events[arrive_idx].arrival_us <= max(
                self.now, self.core_free_at
            ):
                self.on_arrival(events[arrive_idx])
                arrive_idx += 1

            if not self.has_pending():
                # Jump to next arrival.
                if arrive_idx < len(events):
                    self.now = events[arrive_idx].arrival_us
                    continue
                break

            # Advance the clock if the core is idle.
            if self.core_free_at > self.now:
                self.now = self.core_free_at

            nxt = self.select_next()
            if nxt is None:
                # Nothing eligible. Tick forward to the next arrival.
                if arrive_idx < len(events):
                    self.now = max(self.now, events[arrive_idx].arrival_us)
                    continue
                break

            if nxt.request_id not in start_us:
                start_us[nxt.request_id] = self.now

            slice_us = min(remaining[nxt.request_id], self.service_chunk_us(nxt))
            self.now += slice_us
            self.core_free_at = self.now
            remaining[nxt.request_id] -= slice_us

            # Inject any arrivals that happened during this slice.
            while (
                arrive_idx < len(events)
                and events[arrive_idx].arrival_us <= self.now
            ):
                self.on_arrival(events[arrive_idx])
                arrive_idx += 1

            if remaining[nxt.request_id] <= 1e-9:
                self.records.append(
                    CompletionRecord(
                        request_id=nxt.request_id,
                        tenant_id=nxt.tenant_id,
                        sla_class=nxt.sla_class,
                        priority=nxt.priority,
                        arrival_us=nxt.arrival_us,
                        start_us=start_us[nxt.request_id],
                        complete_us=self.now,
                        deadline_us=nxt.deadline_us,
                        service_us=nxt.service_us,
                    )
                )
            else:
                self.on_chunk_complete(nxt, remaining[nxt.request_id])

        return SimResult(
            scheduler_name=self.name,
            records=self.records,
            tenant_classes=dict(tenant_classes),
        )
