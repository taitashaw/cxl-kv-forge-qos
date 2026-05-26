"""B0 - Shared FIFO baseline. One queue, first-come-first-served. No priority."""

from __future__ import annotations

from collections import deque
from typing import Optional

from ..adversarial.workload_generator import Request
from .base import SchedulerBase


class B0SharedFIFO(SchedulerBase):
    name = "B0 Shared FIFO"

    def __init__(self) -> None:
        super().__init__()
        self.q: deque[Request] = deque()

    def on_arrival(self, req: Request) -> None:
        self.q.append(req)

    def has_pending(self) -> bool:
        return bool(self.q)

    def select_next(self) -> Optional[Request]:
        return self.q.popleft() if self.q else None
