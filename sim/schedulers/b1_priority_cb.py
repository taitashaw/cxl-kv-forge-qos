"""
B1 - Priority + Continuous Batching baseline.

A single core, but the queue is priority-ordered. Within the same priority
class, FIFO. "Continuous batching" in this discrete-event model means the
scheduler accepts new arrivals at every decision point (not just when the
core idles) — the priority queue is re-evaluated cycle by cycle. There is no
per-tenant isolation: a high-rate premium tenant can starve other premiums.
"""

from __future__ import annotations

import heapq
from itertools import count
from typing import List, Optional, Tuple

from ..adversarial.workload_generator import Request
from .base import SchedulerBase


class B1PriorityContinuousBatch(SchedulerBase):
    name = "B1 Priority + Continuous Batching"

    def __init__(self) -> None:
        super().__init__()
        # heap entries: (priority, arrival_us, tie, Request)
        self._heap: List[Tuple[int, float, int, Request]] = []
        self._tie = count()

    def on_arrival(self, req: Request) -> None:
        heapq.heappush(
            self._heap, (req.priority, req.arrival_us, next(self._tie), req)
        )

    def has_pending(self) -> bool:
        return bool(self._heap)

    def select_next(self) -> Optional[Request]:
        if not self._heap:
            return None
        _, _, _, req = heapq.heappop(self._heap)
        return req
