"""
Phase 0 adversarial workload generator.

Produces synthetic LLM KV-cache request traces used to compare scheduler
behavior across B0 (Shared FIFO), B1 (Priority + Continuous Batching),
B2 (Chunked Prefill / Sarathi-Serve), and the QoS_CxlKvForge target.

W4 ("combined adversarial") is the headline workload: it stresses every weakness
we expect software-side LLM schedulers to exhibit when running multi-tenant
KV-cache traffic — burst interference, priority inversion, deadline pressure,
and head-of-line blocking from a long-running low-priority tenant.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional

import numpy as np


# ---------------------------------------------------------------------------
# Request record
# ---------------------------------------------------------------------------
@dataclass
class Request:
    request_id: int
    tenant_id: int
    arrival_us: float          # microseconds, simulated time
    service_us: float          # processing cost on the scheduler's compute core
    priority: int              # lower = higher priority (consistent with RTL)
    deadline_us: float         # absolute deadline (arrival + slack)
    kind: str                  # "read" | "write" | "prefetch"
    payload_tokens: int = 1    # KV-cache footprint in tokens
    sla_class: str = "best_effort"  # "premium" | "standard" | "best_effort"

    def slack_us(self) -> float:
        return self.deadline_us - self.arrival_us


# ---------------------------------------------------------------------------
# Workload metadata
# ---------------------------------------------------------------------------
@dataclass
class WorkloadSpec:
    name: str
    description: str
    requests: List[Request]
    tenant_classes: dict = field(default_factory=dict)  # tenant_id -> sla_class
    horizon_us: float = 0.0


# ---------------------------------------------------------------------------
# Sub-pattern helpers
# ---------------------------------------------------------------------------
def _premium_microburst(
    rng: np.random.Generator,
    tenant_id: int,
    start_us: float,
    burst_count: int,
    inter_arrival_us: float,
    service_us_mean: float,
    deadline_slack_us: float,
    next_id: int,
) -> List[Request]:
    """Tight short bursts from a latency-sensitive premium tenant."""
    reqs: List[Request] = []
    t = start_us
    for _ in range(burst_count):
        svc = max(0.5, rng.normal(service_us_mean, service_us_mean * 0.15))
        reqs.append(
            Request(
                request_id=next_id,
                tenant_id=tenant_id,
                arrival_us=t,
                service_us=svc,
                priority=1,
                deadline_us=t + deadline_slack_us,
                kind="read",
                payload_tokens=int(rng.integers(1, 4)),
                sla_class="premium",
            )
        )
        next_id += 1
        t += inter_arrival_us
    return reqs


def _standard_steady(
    rng: np.random.Generator,
    tenant_id: int,
    start_us: float,
    duration_us: float,
    rate_per_us: float,
    service_us_mean: float,
    deadline_slack_us: float,
    next_id: int,
) -> List[Request]:
    """Mid-priority sustained tenant — fills the pipe but should still meet SLA."""
    reqs: List[Request] = []
    if rate_per_us <= 0 or duration_us <= 0:
        return reqs
    inter = 1.0 / rate_per_us
    t = start_us
    while t < start_us + duration_us:
        svc = max(0.5, rng.normal(service_us_mean, service_us_mean * 0.2))
        reqs.append(
            Request(
                request_id=next_id,
                tenant_id=tenant_id,
                arrival_us=t,
                service_us=svc,
                priority=4,
                deadline_us=t + deadline_slack_us,
                kind="read",
                payload_tokens=int(rng.integers(1, 8)),
                sla_class="standard",
            )
        )
        next_id += 1
        t += rng.exponential(inter)
    return reqs


def _bulk_low_prio_hog(
    rng: np.random.Generator,
    tenant_id: int,
    start_us: float,
    duration_us: float,
    rate_per_us: float,
    service_us_mean: float,
    next_id: int,
) -> List[Request]:
    """The adversary: high-volume, long service, low priority. Head-of-line risk."""
    reqs: List[Request] = []
    if rate_per_us <= 0 or duration_us <= 0:
        return reqs
    inter = 1.0 / rate_per_us
    t = start_us
    while t < start_us + duration_us:
        svc = max(2.0, rng.normal(service_us_mean, service_us_mean * 0.3))
        reqs.append(
            Request(
                request_id=next_id,
                tenant_id=tenant_id,
                arrival_us=t,
                service_us=svc,
                priority=12,
                deadline_us=t + 10_000.0,  # very loose
                kind="write",
                payload_tokens=int(rng.integers(8, 32)),
                sla_class="best_effort",
            )
        )
        next_id += 1
        t += rng.exponential(inter)
    return reqs


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def generate_w4_combined(
    seed: int = 0xC0DE,
    horizon_us: float = 10_000.0,
    premium_tenants: int = 1,
    standard_tenants: int = 2,
    bulk_tenants: int = 1,
) -> WorkloadSpec:
    """
    W4 combined adversarial workload.

    Layout:
      - Premium tenants (priority 1, tight SLA): firing 4 microbursts each at
        2 ms intervals; each microburst = 8 requests at 50 us inter-arrival,
        100 us service, 200 us deadline slack. These are the SLA-protected
        tenants we want QoS_CxlKvForge to favor.
      - Standard tenants (priority 4): sustained Poisson arrivals at 0.05
        req/us with 400 us service mean and 1500 us deadline slack.
      - Bulk tenants (priority 12): high-rate writes at 0.1 req/us with
        800 us service mean and 10 ms (effectively unlimited) deadline. These
        are the "noisy neighbor" we want to prove HOL-block premium and
        standard traffic under FIFO scheduling.

    Returns a WorkloadSpec with a globally sorted Request list.
    """
    rng = np.random.default_rng(seed)
    reqs: List[Request] = []
    tenant_classes: dict = {}
    next_id = 1
    tenant_id = 0

    # Premium burst tenants - short, latency-sensitive
    for _ in range(premium_tenants):
        tenant_classes[tenant_id] = "premium"
        for k in range(4):
            burst_start = 1_000.0 + k * (horizon_us / 5.0)
            burst = _premium_microburst(
                rng,
                tenant_id=tenant_id,
                start_us=burst_start,
                burst_count=6,
                inter_arrival_us=40.0,
                service_us_mean=60.0,
                deadline_slack_us=300.0,
                next_id=next_id,
            )
            reqs.extend(burst)
            next_id += len(burst)
        tenant_id += 1

    # Standard sustained tenants - mid-rate, mid-priority
    for _ in range(standard_tenants):
        tenant_classes[tenant_id] = "standard"
        std = _standard_steady(
            rng,
            tenant_id=tenant_id,
            start_us=500.0,
            duration_us=horizon_us - 500.0,
            rate_per_us=0.0015,
            service_us_mean=180.0,
            deadline_slack_us=2_000.0,
            next_id=next_id,
        )
        reqs.extend(std)
        next_id += len(std)
        tenant_id += 1

    # Bulk noisy-neighbor tenants - sustained writes, low priority, large cost
    for _ in range(bulk_tenants):
        tenant_classes[tenant_id] = "best_effort"
        bulk = _bulk_low_prio_hog(
            rng,
            tenant_id=tenant_id,
            start_us=0.0,
            duration_us=horizon_us,
            rate_per_us=0.0008,
            service_us_mean=500.0,
            next_id=next_id,
        )
        reqs.extend(bulk)
        next_id += len(bulk)
        tenant_id += 1

    reqs.sort(key=lambda r: r.arrival_us)
    return WorkloadSpec(
        name="W4-combined",
        description="Premium microbursts + standard Poisson + bulk noisy neighbor.",
        requests=reqs,
        tenant_classes=tenant_classes,
        horizon_us=horizon_us,
    )


def generate_w1_balanced(
    seed: int = 0xB1, horizon_us: float = 5_000.0
) -> WorkloadSpec:
    """W1: balanced uniform-priority traffic (smoke-test workload)."""
    rng = np.random.default_rng(seed)
    reqs: List[Request] = []
    tenant_classes = {0: "standard", 1: "standard", 2: "standard"}
    next_id = 1
    for tid in tenant_classes:
        reqs.extend(
            _standard_steady(
                rng,
                tenant_id=tid,
                start_us=0.0,
                duration_us=horizon_us,
                rate_per_us=0.04,
                service_us_mean=300.0,
                deadline_slack_us=2_000.0,
                next_id=next_id,
            )
        )
        next_id += len(reqs)
    reqs.sort(key=lambda r: r.arrival_us)
    return WorkloadSpec(
        name="W1-balanced",
        description="Three equal-priority tenants with Poisson arrivals.",
        requests=reqs,
        tenant_classes=tenant_classes,
        horizon_us=horizon_us,
    )


__all__ = [
    "Request",
    "WorkloadSpec",
    "generate_w4_combined",
    "generate_w1_balanced",
]
