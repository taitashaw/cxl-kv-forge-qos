"""Aggregate metrics over a scheduler's CompletionRecord stream."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List

import numpy as np

from .schedulers.base import CompletionRecord, SimResult


@dataclass
class MetricRow:
    scheduler: str
    sla_class: str
    n_requests: int
    p50_latency_us: float
    p95_latency_us: float
    p99_latency_us: float
    max_latency_us: float
    mean_latency_us: float
    deadline_miss_rate: float
    throughput_per_us: float


@dataclass
class TenantMetricRow:
    scheduler: str
    tenant_id: int
    sla_class: str
    n_requests: int
    p50_latency_us: float
    p95_latency_us: float
    p99_latency_us: float
    max_latency_us: float
    mean_latency_us: float
    deadline_miss_rate: float
    throughput_per_us: float


@dataclass
class FairnessRow:
    scheduler: str
    scope: str          # "all", "standard", "premium", "best_effort"
    jain_index: float
    n_tenants: int


def _percentile(xs: List[float], p: float) -> float:
    if not xs:
        return float("nan")
    return float(np.percentile(xs, p))


def _jain_index(xs: List[float]) -> float:
    """Jain's fairness index over a non-negative sample.

    J(x) = (sum(x))^2 / (n * sum(x^2)).
    1.0 means perfect equality; 1/n is the worst case (one tenant gets all).
    Returns NaN if the sample is empty or all-zero.
    """
    arr = np.asarray(xs, dtype=float)
    arr = np.clip(arr, 0.0, None)
    if arr.size == 0 or arr.sum() == 0:
        return float("nan")
    return float(arr.sum() ** 2 / (arr.size * np.sum(arr ** 2)))


def summarize(result: SimResult) -> List[MetricRow]:
    """Return one MetricRow per (scheduler, sla_class) bucket plus an overall row."""
    by_class: Dict[str, List[CompletionRecord]] = defaultdict(list)
    for r in result.records:
        by_class[r.sla_class].append(r)
    by_class["__all__"] = list(result.records)

    horizon_us = (
        max((r.complete_us for r in result.records), default=0.0)
        - min((r.arrival_us for r in result.records), default=0.0)
    ) or 1.0

    rows: List[MetricRow] = []
    for cls, recs in by_class.items():
        if not recs:
            continue
        lats = [r.latency_us for r in recs]
        misses = sum(1 for r in recs if r.deadline_miss)
        rows.append(
            MetricRow(
                scheduler=result.scheduler_name,
                sla_class=cls,
                n_requests=len(recs),
                p50_latency_us=_percentile(lats, 50),
                p95_latency_us=_percentile(lats, 95),
                p99_latency_us=_percentile(lats, 99),
                max_latency_us=float(max(lats)),
                mean_latency_us=float(np.mean(lats)),
                deadline_miss_rate=misses / len(recs),
                throughput_per_us=len(recs) / horizon_us,
            )
        )
    return rows


def summarize_per_tenant(result: SimResult) -> List[TenantMetricRow]:
    """One TenantMetricRow per tenant. Drives the fairness-per-tenant plot."""
    by_tenant: Dict[int, List[CompletionRecord]] = defaultdict(list)
    for r in result.records:
        by_tenant[r.tenant_id].append(r)

    if not result.records:
        return []
    horizon_us = (
        max(r.complete_us for r in result.records)
        - min(r.arrival_us for r in result.records)
    ) or 1.0

    rows: List[TenantMetricRow] = []
    for tid in sorted(by_tenant):
        recs = by_tenant[tid]
        cls = recs[0].sla_class
        lats = [r.latency_us for r in recs]
        misses = sum(1 for r in recs if r.deadline_miss)
        rows.append(
            TenantMetricRow(
                scheduler=result.scheduler_name,
                tenant_id=tid,
                sla_class=cls,
                n_requests=len(recs),
                p50_latency_us=_percentile(lats, 50),
                p95_latency_us=_percentile(lats, 95),
                p99_latency_us=_percentile(lats, 99),
                max_latency_us=float(max(lats)),
                mean_latency_us=float(np.mean(lats)),
                deadline_miss_rate=misses / len(recs),
                throughput_per_us=len(recs) / horizon_us,
            )
        )
    return rows


def fairness(result: SimResult, arrival_counts: Dict[int, int]) -> List[FairnessRow]:
    """Jain's fairness index over per-tenant *throughput share*.

    Each tenant's share is computed as (completed_requests / mean_latency_us).
    For a scheduler that drains all tenants equally fast, this approaches 1.0;
    for one that gives a tenant fast service while another waits, Jain drops
    toward 1/n. This is a latency-aware variant of the canonical Jain index;
    the canonical (completed / arrived) version always yields 1.0 here because
    the discrete-event simulator always drains the queue.

    `arrival_counts` is retained for completeness and exposed as a sanity-
    check side-channel even though it does not currently drive the index.
    """
    per_tenant = summarize_per_tenant(result)
    if not per_tenant:
        return []
    shares: Dict[int, float] = {}
    classes_of: Dict[int, str] = {}
    for row in per_tenant:
        # Per-tenant "service rate" - completed requests normalized by mean
        # waiting time. Higher = the tenant is being served quickly relative
        # to its load. _ = arrival_counts.get(row.tenant_id, 0)  # not used
        denom = max(row.mean_latency_us, 1e-6)
        shares[row.tenant_id] = row.n_requests / denom
        classes_of[row.tenant_id] = row.sla_class

    rows: List[FairnessRow] = []
    rows.append(
        FairnessRow(
            scheduler=result.scheduler_name,
            scope="all",
            jain_index=_jain_index(list(shares.values())),
            n_tenants=len(shares),
        )
    )
    by_class: Dict[str, List[float]] = defaultdict(list)
    for tid, val in shares.items():
        by_class[classes_of[tid]].append(val)
    for cls, vals in by_class.items():
        if len(vals) >= 2:
            rows.append(
                FairnessRow(
                    scheduler=result.scheduler_name,
                    scope=cls,
                    jain_index=_jain_index(vals),
                    n_tenants=len(vals),
                )
            )
    return rows


__all__ = [
    "MetricRow",
    "TenantMetricRow",
    "FairnessRow",
    "summarize",
    "summarize_per_tenant",
    "fairness",
]
