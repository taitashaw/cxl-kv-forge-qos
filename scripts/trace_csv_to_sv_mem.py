#!/usr/bin/env python3
"""
trace_csv_to_sv_mem.py

Convert a Phase 0 benchmark CSV trace into a SystemVerilog $readmemh-compatible
memory file. Each row of the CSV becomes one 256-bit request packet matching
the kvq_pkg.sv bitfield layout:

  [255:248] opcode                       (8)
  [247:232] request_id                   (16)
  [231:216] tenant_id                    (16)
  [215:200] session_id                   (16)
  [199:192] layer_id                     (8)
  [191:184] head_id                      (8)
  [183:152] token_id                     (32)
  [151:88]  kv_address                   (64)
  [87:72]   payload_length               (16)
  [71:68]   priority                     (4)
  [67:36]   deadline_cycles              (32)
  [35:28]   flags                        (8)
  [27:0]    reserved_or_inline_payload   (28)

Usage:
  python3 trace_csv_to_sv_mem.py INPUT.csv OUTPUT.mem
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

OPCODES = {
    "READ":             0x01,
    "WRITE":            0x02,
    "PREFETCH":         0x03,
    "EVICT":            0x04,
    "INVALIDATE":       0x05,
    "QUERY_STATS":      0x06,
    "RESET_STATS":      0x07,
    "PROGRAM_CONTRACT": 0x08,
    "RESET_CONTRACT":   0x09,
}

COLUMNS = [
    "cycle",
    "opcode",
    "request_id",
    "tenant_id",
    "session_id",
    "layer_id",
    "head_id",
    "token_id",
    "kv_address",
    "payload_length",
    "priority",
    "deadline_cycles",
    "flags",
]


def _opcode_value(raw: str) -> int:
    raw = (raw or "").strip()
    if not raw:
        return OPCODES["READ"]
    if raw.upper() in OPCODES:
        return OPCODES[raw.upper()]
    # numeric forms: 0xNN, NN
    return int(raw, 0) & 0xFF


def _int(raw: str, default: int = 0) -> int:
    raw = (raw or "").strip()
    if not raw:
        return default
    return int(raw, 0)


def _pack(row: dict) -> int:
    opcode    = _opcode_value(row.get("opcode", "READ"))             & 0xFF
    req_id    = _int(row.get("request_id", "0"))                      & 0xFFFF
    tenant_id = _int(row.get("tenant_id", "0"))                       & 0xFFFF
    session   = _int(row.get("session_id", "0"))                      & 0xFFFF
    layer     = _int(row.get("layer_id", "0"))                        & 0xFF
    head      = _int(row.get("head_id", "0"))                         & 0xFF
    token     = _int(row.get("token_id", "0"))                        & 0xFFFFFFFF
    addr      = _int(row.get("kv_address", "0"))                      & 0xFFFFFFFFFFFFFFFF
    paylen    = _int(row.get("payload_length", "0"))                  & 0xFFFF
    prio      = _int(row.get("priority", "0"))                        & 0xF
    deadline  = _int(row.get("deadline_cycles", "0"))                 & 0xFFFFFFFF
    flags     = _int(row.get("flags", "0"))                           & 0xFF
    reserved  = 0

    word  = 0
    word |= (opcode    & 0xFF)               << 248
    word |= (req_id    & 0xFFFF)             << 232
    word |= (tenant_id & 0xFFFF)             << 216
    word |= (session   & 0xFFFF)             << 200
    word |= (layer     & 0xFF)               << 192
    word |= (head      & 0xFF)               << 184
    word |= (token     & 0xFFFFFFFF)         << 152
    word |= (addr      & 0xFFFFFFFFFFFFFFFF) <<  88
    word |= (paylen    & 0xFFFF)             <<  72
    word |= (prio      & 0xF)                <<  68
    word |= (deadline  & 0xFFFFFFFF)         <<  36
    word |= (flags     & 0xFF)               <<  28
    word |= (reserved  & 0xFFFFFFF)          <<   0
    return word


def convert(in_path: Path, out_path: Path) -> int:
    rows_written = 0
    with in_path.open() as fin, out_path.open("w") as fout:
        reader = csv.DictReader(fin)
        missing = [c for c in COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            print(f"warn: missing columns in {in_path.name}: {missing} (using defaults)")
        fout.write(f"// auto-generated from {in_path.name} - 256-bit request packets\n")
        for row in reader:
            word = _pack(row)
            fout.write(f"{word:064x}\n")
            rows_written += 1
    return rows_written


def main() -> int:
    ap = argparse.ArgumentParser(description="CSV -> 256-bit SV mem converter")
    ap.add_argument("input",  type=Path, help="input CSV trace")
    ap.add_argument("output", type=Path, help="output .mem path")
    args = ap.parse_args()

    if not args.input.exists():
        print(f"error: {args.input} not found", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    n = convert(args.input, args.output)
    print(f"wrote {n} packets to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
