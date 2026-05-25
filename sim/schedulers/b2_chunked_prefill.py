"""
B2 - Chunked Prefill / Sarathi-Serve-style baseline.

Each request's service time is split into CHUNK_US slices. After every slice
the scheduler returns the partially-served request to the queue and picks the
next highest-priority request. This prevents a single long-running bulk write
from holding the core for hundreds of microseconds, which is the main
complaint Sarathi-Serve makes about prefill-heavy schedulers. It does not,
however, model per-tenant credits or deadlines explicitly.
"""

from __future__ import annotations

import heapq
from itertools import count
from typing import List, Optional, Tuple

from ..adversarial.workload_generator import Request
from .base import SchedulerBase


CHUNK_US = 100.0


class B2ChunkedPrefill(SchedulerBase):
    name = "B2 Chunked Prefill"

    def __init__(self, chunk_us: float = CHUNK_US) -> None:
        super().__init__()
        self.chunk_us = chunk_us
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

    def service_chunk_us(self, req: Request) -> float:
        return self.chunk_us

    def on_chunk_complete(self, req: Request, remaining_us: float) -> None:
        # Re-enqueue the tail of the request with its original priority so
        # other premium traffic can interleave.
        heapq.heappush(
            self._heap, (req.priority, self.now, next(self._tie), req)
        )
