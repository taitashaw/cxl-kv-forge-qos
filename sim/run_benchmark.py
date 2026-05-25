#!/usr/bin/env python3
"""
Phase 0 benchmark driver.

Generates the W4 adversarial workload, runs B0/B1/B2/QoS schedulers through it,
emits per-request CSVs and an aggregated comparison CSV, and produces the
headline plot at results/plots/adversarial_w4_baseline_comparison.png.

Usage:
    python3 sim/run_benchmark.py            # default W4 run
    python3 sim/run_benchmark.py --quick    # smaller horizon for smoke tests
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path
from typing import Dict, List

import matplotlib

matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt
import numpy as np

# Make this script runnable both as a module and as a top-level file.
THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR.parent) not in sys.path:
    sys.path.insert(0, str(THIS_DIR.parent))

from sim.adversarial.workload_generator import (  # noqa: E402
    WorkloadSpec,
    generate_w4_combined,
)
from sim.metrics import (  # noqa: E402
    FairnessRow,
    MetricRow,
    TenantMetricRow,
    fairness,
    summarize,
    summarize_per_tenant,
)
from sim.schedulers import (  # noqa: E402
    B0SharedFIFO,
    B1PriorityContinuousBatch,
    B2ChunkedPrefill,
    QoSCxlKvForge,
)
from sim.schedulers.base import SimResult  # noqa: E402


SCHEDULER_FACTORIES = [
    ("B0 Shared FIFO",                   B0SharedFIFO),
    ("B1 Priority + Continuous Batching", B1PriorityContinuousBatch),
    ("B2 Chunked Prefill",                B2ChunkedPrefill),
    ("QoS_CxlKvForge",                    QoSCxlKvForge),
]


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
def write_records_csv(result: SimResult, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "request_id", "tenant_id", "sla_class", "priority",
            "arrival_us", "start_us", "complete_us",
            "latency_us", "queueing_us", "deadline_us", "deadline_miss",
        ])
        for r in result.records:
            w.writerow([
                r.request_id, r.tenant_id, r.sla_class, r.priority,
                f"{r.arrival_us:.3f}", f"{r.start_us:.3f}", f"{r.complete_us:.3f}",
                f"{r.latency_us:.3f}", f"{r.queueing_us:.3f}",
                f"{r.deadline_us:.3f}", int(r.deadline_miss),
            ])


def write_summary_csv(rows: List[MetricRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "scheduler", "sla_class", "n_requests",
            "p50_latency_us", "p95_latency_us", "p99_latency_us",
            "max_latency_us", "mean_latency_us",
            "deadline_miss_rate", "throughput_per_us",
        ])
        for r in rows:
            w.writerow([
                r.scheduler, r.sla_class, r.n_requests,
                f"{r.p50_latency_us:.3f}", f"{r.p95_latency_us:.3f}",
                f"{r.p99_latency_us:.3f}", f"{r.max_latency_us:.3f}",
                f"{r.mean_latency_us:.3f}",
                f"{r.deadline_miss_rate:.4f}", f"{r.throughput_per_us:.6f}",
            ])


def write_per_tenant_csv(rows: List[TenantMetricRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "scheduler", "tenant_id", "sla_class", "n_requests",
            "p50_latency_us", "p95_latency_us", "p99_latency_us",
            "max_latency_us", "mean_latency_us",
            "deadline_miss_rate", "throughput_per_us",
        ])
        for r in rows:
            w.writerow([
                r.scheduler, r.tenant_id, r.sla_class, r.n_requests,
                f"{r.p50_latency_us:.3f}", f"{r.p95_latency_us:.3f}",
                f"{r.p99_latency_us:.3f}", f"{r.max_latency_us:.3f}",
                f"{r.mean_latency_us:.3f}",
                f"{r.deadline_miss_rate:.4f}", f"{r.throughput_per_us:.6f}",
            ])


def write_fairness_csv(rows: List[FairnessRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["scheduler", "scope", "jain_index", "n_tenants"])
        for r in rows:
            w.writerow([r.scheduler, r.scope, f"{r.jain_index:.6f}", r.n_tenants])


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------
def make_comparison_plot(
    workload: WorkloadSpec,
    summaries: Dict[str, List[MetricRow]],
    out_path: Path,
) -> None:
    """4-panel comparison plot for the W4 workload."""
    schedulers = list(summaries.keys())
    sla_classes = ["premium", "standard", "best_effort"]

    fig, axs = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(
        f"CXL-KV Forge-QoS - {workload.name} adversarial baseline comparison",
        fontsize=14,
    )

    # ----- Panel 1: p95 latency per SLA class per scheduler -----
    ax = axs[0, 0]
    x = np.arange(len(sla_classes))
    width = 0.2
    for i, sched in enumerate(schedulers):
        vals = []
        for cls in sla_classes:
            row = next((r for r in summaries[sched] if r.sla_class == cls), None)
            vals.append(row.p95_latency_us if row else 0.0)
        ax.bar(x + i * width - 1.5 * width, vals, width, label=sched)
    ax.set_xticks(x)
    ax.set_xticklabels(sla_classes)
    ax.set_ylabel("p95 latency (us)")
    ax.set_title("p95 latency by SLA class")
    ax.set_yscale("log")
    ax.legend(fontsize=8, loc="upper left")
    ax.grid(axis="y", alpha=0.3)

    # ----- Panel 2: deadline miss rate per SLA class -----
    ax = axs[0, 1]
    for i, sched in enumerate(schedulers):
        vals = []
        for cls in sla_classes:
            row = next((r for r in summaries[sched] if r.sla_class == cls), None)
            vals.append(row.deadline_miss_rate if row else 0.0)
        ax.bar(x + i * width - 1.5 * width, vals, width, label=sched)
    ax.set_xticks(x)
    ax.set_xticklabels(sla_classes)
    ax.set_ylabel("deadline miss rate")
    ax.set_title("Deadline miss rate by SLA class")
    ax.set_ylim(0, 1.05)
    ax.legend(fontsize=8, loc="upper right")
    ax.grid(axis="y", alpha=0.3)

    # ----- Panel 3: latency CDF for premium tenants -----
    ax = axs[1, 0]
    for sched in schedulers:
        lats = []
        for row in summaries[sched]:
            if row.sla_class == "premium":
                # synthesize a sortable view from saved records via a side-channel
                pass
        # We need the raw records for a CDF, fetch from the saved CSV file.
        recs_path = out_path.parent.parent / "records" / _slug(sched + ".csv")
        if recs_path.exists():
            with recs_path.open() as f:
                rdr = csv.DictReader(f)
                premium_lats = [
                    float(r["latency_us"])
                    for r in rdr
                    if r["sla_class"] == "premium"
                ]
            if premium_lats:
                xs = np.sort(premium_lats)
                ys = np.arange(1, len(xs) + 1) / len(xs)
                ax.plot(xs, ys, label=sched, linewidth=1.5)
    ax.set_xscale("log")
    ax.set_xlabel("latency (us)")
    ax.set_ylabel("CDF")
    ax.set_title("Premium-tenant latency CDF (lower-left is better)")
    ax.legend(fontsize=8, loc="lower right")
    ax.grid(alpha=0.3)

    # ----- Panel 4: throughput across schedulers -----
    ax = axs[1, 1]
    throughputs = []
    labels = []
    for sched in schedulers:
        row = next((r for r in summaries[sched] if r.sla_class == "__all__"), None)
        if row is not None:
            throughputs.append(row.throughput_per_us * 1e6)  # req/sec
            labels.append(sched)
    bars = ax.bar(range(len(labels)), throughputs, color=["#888", "#888", "#888", "#2a7"])
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=15, ha="right", fontsize=8)
    ax.set_ylabel("throughput (req/s)")
    ax.set_title("Overall throughput")
    for bar, val in zip(bars, throughputs):
        ax.text(bar.get_x() + bar.get_width() / 2, val, f"{val:,.0f}",
                ha="center", va="bottom", fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def _slug(name: str) -> str:
    return (
        name.replace(" ", "_")
            .replace("+", "plus")
            .replace("/", "_")
    )


def make_fairness_per_tenant_plot(
    workload: WorkloadSpec,
    per_tenant_rows: List[TenantMetricRow],
    out_path: Path,
) -> None:
    """Per-tenant p95/p99 latency bars across schedulers.

    Layout: one subplot per scheduler. Within each subplot, tenants are
    grouped along the x-axis and two bars per tenant show p95 and p99.
    Bar colors encode SLA class so the eye can immediately see whether
    standard-class tenants are being served similarly to each other.
    """
    schedulers = sorted({r.scheduler for r in per_tenant_rows})
    tenants = sorted({r.tenant_id for r in per_tenant_rows})
    class_color = {
        "premium": "#1f77b4",
        "standard": "#2ca02c",
        "best_effort": "#d62728",
    }

    fig, axs = plt.subplots(
        1, len(schedulers), figsize=(4 * len(schedulers), 5), sharey=True
    )
    if len(schedulers) == 1:
        axs = [axs]

    for ax, sched in zip(axs, schedulers):
        sched_rows = {r.tenant_id: r for r in per_tenant_rows if r.scheduler == sched}
        x = np.arange(len(tenants))
        p95 = [sched_rows[t].p95_latency_us if t in sched_rows else 0 for t in tenants]
        p99 = [sched_rows[t].p99_latency_us if t in sched_rows else 0 for t in tenants]
        colors = [class_color.get(workload.tenant_classes.get(t, ""), "#888")
                  for t in tenants]
        ax.bar(x - 0.2, p95, 0.4, color=colors, label="p95", alpha=0.85)
        ax.bar(x + 0.2, p99, 0.4, color=colors, label="p99",
               edgecolor="black", linewidth=1, hatch="//")
        ax.set_xticks(x)
        ax.set_xticklabels(
            [f"t{t}\n({workload.tenant_classes.get(t, '?')})" for t in tenants],
            fontsize=8,
        )
        ax.set_title(sched, fontsize=10)
        ax.set_yscale("log")
        ax.grid(axis="y", alpha=0.3)
    axs[0].set_ylabel("latency (us)")

    # Legend: one entry per SLA class plus p95/p99 markers
    handles = [
        plt.Rectangle((0, 0), 1, 1, color=class_color[c]) for c in class_color
    ]
    handles.append(plt.Rectangle((0, 0), 1, 1, fill=False, edgecolor="black", hatch="//"))
    labels = list(class_color.keys()) + ["p99 (hatched)"]
    fig.legend(handles, labels, loc="upper center", ncol=len(labels),
               fontsize=8, bbox_to_anchor=(0.5, 1.02))

    fig.suptitle(f"{workload.name} - per-tenant p95/p99 latency", y=1.06)
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def make_jain_index_plot(
    workload: WorkloadSpec,
    fairness_rows: List[FairnessRow],
    out_path: Path,
) -> None:
    """Grouped bar chart of Jain's fairness index per scheduler per scope.

    Each scope (all, standard, best_effort, premium) renders one bar per
    scheduler. A horizontal line at J=1.0 marks perfect fairness; the y-axis
    is clamped to [0, 1.05]. The plot makes immediately visible which
    schedulers starve which class.
    """
    schedulers = sorted({r.scheduler for r in fairness_rows})
    scopes = []
    for r in fairness_rows:
        if r.scope not in scopes:
            scopes.append(r.scope)
    # Stable order: 'all' first, then everything else alphabetical
    scopes = (["all"] if "all" in scopes else []) + sorted(
        s for s in scopes if s != "all"
    )

    width = 0.8 / max(1, len(schedulers))
    x = np.arange(len(scopes))

    fig, ax = plt.subplots(figsize=(8, 5))
    for i, sched in enumerate(schedulers):
        vals = []
        for scope in scopes:
            row = next(
                (r for r in fairness_rows if r.scheduler == sched and r.scope == scope),
                None,
            )
            vals.append(row.jain_index if row and not np.isnan(row.jain_index) else 0.0)
        ax.bar(x + i * width - (len(schedulers) - 1) * width / 2, vals, width, label=sched)

    ax.axhline(y=1.0, color="black", linewidth=0.8, linestyle="--", alpha=0.4)
    ax.set_xticks(x)
    ax.set_xticklabels(scopes)
    ax.set_ylabel("Jain's fairness index")
    ax.set_ylim(0, 1.08)
    ax.set_title(
        f"{workload.name} - Jain's fairness index "
        "(1.0 = perfectly equal completion share)"
    )
    ax.grid(axis="y", alpha=0.3)
    ax.legend(loc="lower right", fontsize=8)
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="Phase 0 W4 benchmark driver")
    ap.add_argument("--horizon-us", type=float, default=10_000.0)
    ap.add_argument("--seed", type=int, default=0xC0DE)
    ap.add_argument("--quick", action="store_true",
                    help="Smaller horizon for smoke tests")
    ap.add_argument("--output-dir", type=Path,
                    default=Path("results"))
    args = ap.parse_args()

    horizon = 3_000.0 if args.quick else args.horizon_us

    print(f"==> Generating W4 workload (horizon_us={horizon}, seed=0x{args.seed:x})")
    workload = generate_w4_combined(seed=args.seed, horizon_us=horizon)
    print(f"    {len(workload.requests)} requests across "
          f"{len(workload.tenant_classes)} tenants "
          f"({sorted(set(workload.tenant_classes.values()))})")

    records_dir = args.output_dir / "records"
    summary_path = args.output_dir / "adversarial_w4_summary.csv"
    per_tenant_path = args.output_dir / "adversarial_w4_per_tenant.csv"
    fairness_path = args.output_dir / "adversarial_w4_fairness.csv"
    plot_path = args.output_dir / "plots" / "adversarial_w4_baseline_comparison.png"
    per_tenant_plot = args.output_dir / "plots" / "w4_fairness_per_tenant.png"
    jain_plot = args.output_dir / "plots" / "w4_jains_index.png"

    arrival_counts: Dict[int, int] = {}
    for r in workload.requests:
        arrival_counts[r.tenant_id] = arrival_counts.get(r.tenant_id, 0) + 1

    all_summary: List[MetricRow] = []
    per_sched_summary: Dict[str, List[MetricRow]] = {}
    all_per_tenant: List[TenantMetricRow] = []
    all_fairness: List[FairnessRow] = []

    for name, cls in SCHEDULER_FACTORIES:
        print(f"==> Running {name}")
        sched = cls()
        result = sched.run(workload.requests, workload.tenant_classes)
        rows = summarize(result)
        per_sched_summary[name] = rows
        all_summary.extend(rows)
        all_per_tenant.extend(summarize_per_tenant(result))
        all_fairness.extend(fairness(result, arrival_counts))

        record_path = records_dir / f"{_slug(name)}.csv"
        write_records_csv(result, record_path)

        # Quick console summary
        for r in rows:
            if r.sla_class != "__all__":
                continue
            print(f"    overall: n={r.n_requests} p95={r.p95_latency_us:.1f}us "
                  f"miss={r.deadline_miss_rate:.2%} "
                  f"thpt={r.throughput_per_us*1e6:.0f} req/s")

    write_summary_csv(all_summary, summary_path)
    write_per_tenant_csv(all_per_tenant, per_tenant_path)
    write_fairness_csv(all_fairness, fairness_path)
    print(f"==> Summary CSV:    {summary_path}")
    print(f"==> Per-tenant CSV: {per_tenant_path}")
    print(f"==> Fairness CSV:   {fairness_path}")

    make_comparison_plot(workload, per_sched_summary, plot_path)
    make_fairness_per_tenant_plot(workload, all_per_tenant, per_tenant_plot)
    make_jain_index_plot(workload, all_fairness, jain_plot)
    print(f"==> Plot (baseline):     {plot_path}")
    print(f"==> Plot (per-tenant):   {per_tenant_plot}")
    print(f"==> Plot (Jain's index): {jain_plot}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
