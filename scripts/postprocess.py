"""
Post-process pre-aggregated query output into visualization formats.

USAGE:
  python3 scripts/postprocess.py \
    --input data/capital_flows_raw.json \
    --format b \
    --top-n 0 \
    --positions data/positions_by_ticker.json \
    --output data/capital_flows_viz.json

The aggregated SQL groups by building pair + trade_date. This script:
- Format B: collapses across trade_dates, creates daily arrays for timelapse, optionally applies top-N per district

Options:
  --positions FILE              Filter out rows where either building lacks AUM
  --top-n 0                     No cap (0 = keep all pairs)
  --min-pairs-per-district 50   Backfill districts below this count from top dropped pairs
  --max-file-mb 200             Strip daily arrays from lowest-traffic pairs to stay under cap
  --date-range START END        Only keep daily entries within this date range (YYYY-MM-DD)
"""

import argparse
import json
import os
import sys
import time
from collections import defaultdict
from typing import Iterator

import ijson


def log(msg):
    print(msg, file=sys.stderr)


def safe_float(val):
    try:
        return float(val)
    except (ValueError, TypeError):
        return 0.0


def safe_int(val):
    try:
        return int(val)
    except (ValueError, TypeError):
        return 0


def stream_json_array(path: str, report_every: int = 500_000) -> Iterator[dict]:
    file_size = os.path.getsize(path)
    log(f"Streaming {path} ({file_size / 1e9:.2f} GB) ...")
    t_start = time.time()
    count = 0
    with open(path, "rb") as f:
        for item in ijson.items(f, "item"):
            yield item
            count += 1
            if count % report_every == 0:
                elapsed = time.time() - t_start
                rate = count / elapsed if elapsed > 0 else 0
                log(f"  {count:>12,} rows streamed | {rate:,.0f} rows/s | {elapsed:.0f}s")
    elapsed = time.time() - t_start
    log(f"  Streamed {count:,} rows in {elapsed:.1f}s")


def build_aum_lookup(positions_path):
    with open(positions_path) as f:
        positions = json.load(f)
    lookup = {}
    for p in positions:
        aum = safe_float(p.get("total_settled_market_value_usd", 0))
        if p.get("symbol"):
            lookup[p["symbol"]] = lookup.get(p["symbol"], 0) + aum
        elif p.get("asset_id"):
            key = str(p["asset_id"])
            lookup[key] = lookup.get(key, 0) + aum
    log(f"  AUM lookup: {len(lookup):,} entries")
    return lookup


def filter_by_aum(rows, aum_lookup):
    kept = []
    skipped = 0
    for r in rows:
        from_bid = r["from_building"]
        to_bid = r["to_building"]
        if aum_lookup.get(from_bid, 0) > 0 and aum_lookup.get(to_bid, 0) > 0:
            kept.append(r)
        else:
            skipped += 1
    log(f"  AUM filter: kept {len(kept):,}, skipped {skipped:,}")
    return kept


def serialize_json_with_progress(records: list[dict], path: str) -> int:
    """Write records as a JSON array, logging progress every 10k records."""
    total = len(records)
    log(f"  Serializing {total:,} records to {path} ...")
    t0 = time.time()
    written = 0
    with open(path, "w") as f:
        f.write("[")
        for i, r in enumerate(records):
            if i > 0:
                f.write(",")
            json.dump(r, f, separators=(",", ":"))
            written += 1
            if written % 10_000 == 0:
                elapsed = time.time() - t0
                pct = written / total * 100
                rate = written / elapsed if elapsed > 0 else 0
                eta = (total - written) / rate if rate > 0 else 0
                log(f"    {written:>10,} / {total:,} ({pct:.0f}%) | {rate:,.0f} rec/s | ETA {eta:.0f}s")
        f.write("]")
    elapsed = time.time() - t0
    size_bytes = os.path.getsize(path)
    log(f"  Wrote {size_bytes / 1048576:.1f} MB in {elapsed:.1f}s")
    return size_bytes


def enforce_file_cap(records: list[dict], max_mb: int, path: str) -> None:
    # Quick size estimate via in-memory serialize of first record
    if max_mb > 0 and len(records) > 0:
        sample = len(json.dumps(records[0], separators=(",", ":")))
        est_mb = sample * len(records) / 1048576
        if est_mb > max_mb * 1.5:
            log(f"  Estimated output ~{est_mb:.0f} MB exceeds {max_mb} MB cap — trimming daily arrays ...")
            daily_sizes = []
            for i, r in enumerate(records):
                if "daily" in r:
                    daily_bytes = len(json.dumps(r["daily"], separators=(",", ":"))) + len(',"daily":')
                    daily_sizes.append((i, int(r["flow_count"]), daily_bytes))
            daily_sizes.sort(key=lambda x: x[1])

            target_reclaim = int((est_mb - max_mb) * 1048576)
            reclaimed = 0
            stripped = 0
            for i, fc, db in daily_sizes:
                if "daily" in records[i]:
                    del records[i]["daily"]
                reclaimed += db
                stripped += 1
                if reclaimed >= target_reclaim:
                    break
            log(f"  Stripped daily from {stripped:,} lowest-traffic pairs")

    serialize_json_with_progress(records, path)


def generate_format_b(rows: Iterator[dict], top_n: int = 200, min_flows: int = 0, min_pairs_per_district: int = 0, aum_lookup: dict | None = None, date_range: tuple[str, str] | None = None) -> list[dict]:
    log("Generating Format B (collapse across trade dates) ...")
    if date_range:
        log(f"  Date range filter: {date_range[0]} to {date_range[1]}")
    agg = {}
    input_count = 0
    skipped_aum = 0
    for r in rows:
        if aum_lookup is not None:
            if aum_lookup.get(r["from_building"], 0) <= 0 or aum_lookup.get(r["to_building"], 0) <= 0:
                skipped_aum += 1
                continue
        input_count += 1
        key = (
            r["from_building"], r["from_neighborhood"], r["from_district"],
            r["to_building"], r["to_neighborhood"], r["to_district"],
        )
        if key not in agg:
            agg[key] = {
                "flow_count": 0,
                "total_sell_amount": 0.0,
                "total_buy_amount": 0.0,
                "peak_daily_accounts": 0,
                "avg_hours_in_cash_weighted": 0.0,
                "from_building_label": r.get("from_building_label", ""),
                "to_building_label": r.get("to_building_label", ""),
                "first_flow_date": "",
                "last_flow_date": "",
                "daily_flows": defaultdict(lambda: {"flow_count": 0, "sell_amount": 0.0, "buy_amount": 0.0}),
            }
        rec = agg[key]
        fc = safe_int(r.get("flow_count", 0))
        rec["flow_count"] += fc
        rec["total_sell_amount"] += safe_float(r.get("total_sell_amount", 0))
        rec["total_buy_amount"] += safe_float(r.get("total_buy_amount", 0))
        rec["peak_daily_accounts"] = max(rec["peak_daily_accounts"], safe_int(r.get("unique_accounts", 0)))
        rec["avg_hours_in_cash_weighted"] += safe_float(r.get("avg_hours_in_cash", 0)) * fc
        td = r.get("trade_date", "") or r.get("first_flow_date", "")
        if td and not (date_range and (td < date_range[0] or td > date_range[1])):
            if not rec["first_flow_date"] or td < rec["first_flow_date"]:
                rec["first_flow_date"] = td
            if not rec["last_flow_date"] or td > rec["last_flow_date"]:
                rec["last_flow_date"] = td
            day = rec["daily_flows"][td]
            day["flow_count"] += fc
            day["sell_amount"] += safe_float(r.get("total_sell_amount", 0))
            day["buy_amount"] += safe_float(r.get("total_buy_amount", 0))

    log(f"  Collapsed to {len(agg):,} building pairs (from {input_count:,} daily rows)")
    if skipped_aum:
        log(f"  AUM filter: skipped {skipped_aum:,} rows")

    exempt_districts = {'Futures', 'Mutual Funds', 'Mutual Fund', 'Options'}
    if min_flows > 0:
        before = len(agg)
        above = {k: v for k, v in agg.items()
                 if v["flow_count"] >= min_flows or k[2] in exempt_districts or k[5] in exempt_districts}
        below = {k: v for k, v in agg.items() if k not in above}
        exempt_count = sum(1 for k in above if (k[2] in exempt_districts or k[5] in exempt_districts) and agg[k]["flow_count"] < min_flows)
        log(f"  Min-flows filter (>= {min_flows}): {len(above):,} pairs (dropped {before - len(above):,}, {exempt_count:,} exempt)")
    else:
        above = agg
        below = {}

    if min_pairs_per_district > 0 and below:
        src_counts = defaultdict(int)
        for k in above:
            src_counts[k[2]] += 1

        all_districts = set()
        for k in {**above, **below}:
            all_districts.add(k[2])

        for district in sorted(all_districts):
            current = src_counts.get(district, 0)
            if current < min_pairs_per_district:
                needed = min_pairs_per_district - current
                candidates = [(k, v) for k, v in below.items()
                              if k[2] == district and k not in above]
                candidates.sort(key=lambda x: x[1]["flow_count"], reverse=True)
                added = 0
                for k, v in candidates[:needed]:
                    above[k] = v
                    added += 1
                if added:
                    log(f"  Backfilled {added} pairs for {district} (had {current}, now {current + added})")

    agg = above

    district_groups = defaultdict(list)
    for key, rec in agg.items():
        district_groups[key[2]].append((key, rec))

    kept = []
    for district in sorted(district_groups.keys()):
        pairs = district_groups[district]
        pairs.sort(key=lambda x: x[1]["flow_count"], reverse=True)
        selected = pairs if top_n == 0 else pairs[:top_n]
        log(f"    {district}: kept {len(selected)} of {len(pairs)} pairs")

        for key, rec in selected:
            fc = rec["flow_count"]
            avg_cash = rec["avg_hours_in_cash_weighted"] / fc if fc > 0 else 0.0
            row = {
                "from_building": key[0],
                "from_neighborhood": key[1],
                "from_district": key[2],
                "from_building_label": rec["from_building_label"],
                "to_building": key[3],
                "to_neighborhood": key[4],
                "to_district": key[5],
                "to_building_label": rec["to_building_label"],
                "flow_count": str(fc),
                "total_sell_amount": f"{rec['total_sell_amount']:.2f}",
                "total_buy_amount": f"{rec['total_buy_amount']:.2f}",
                "peak_daily_accounts": str(rec["peak_daily_accounts"]),
                "avg_hours_in_cash": f"{avg_cash:.1f}",
            }
            if rec["first_flow_date"]:
                row["first_flow_date"] = rec["first_flow_date"]
            if rec["last_flow_date"]:
                row["last_flow_date"] = rec["last_flow_date"]
            if rec["daily_flows"]:
                row["daily"] = [
                    [d, df["flow_count"], round(df["sell_amount"], 2), round(df["buy_amount"], 2)]
                    for d, df in sorted(rec["daily_flows"].items())
                ]
            kept.append(row)

    log(f"  Final Format B rows: {len(kept):,}")
    return kept


def main():
    parser = argparse.ArgumentParser(description="Post-process pre-aggregated v3 output")
    parser.add_argument("--input", required=True)
    parser.add_argument("--format", choices=["b"], default="b")
    parser.add_argument("--top-n", type=int, default=200, help="Top N pairs per district (0 = no cap)")
    parser.add_argument("--min-flows", type=int, default=0, help="Minimum flow count per pair (post-collapse)")
    parser.add_argument("--min-pairs-per-district", type=int, default=50, help="Backfill districts below this pair count (0 = disabled)")
    parser.add_argument("--max-file-mb", type=int, default=200, help="Strip daily arrays from lowest-traffic pairs to stay under this cap (0 = no cap)")
    parser.add_argument("--positions", default=None, help="Positions JSON for AUM filtering")
    parser.add_argument("--date-range", nargs=2, metavar=("START", "END"), default=None, help="Only keep daily entries within YYYY-MM-DD range")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    aum_lookup = None
    if args.positions:
        log(f"Loading positions from {args.positions} ...")
        aum_lookup = build_aum_lookup(args.positions)

    if args.format == "b":
        rows = stream_json_array(args.input)
        date_range = tuple(args.date_range) if args.date_range else None
        b = generate_format_b(rows, top_n=args.top_n, min_flows=args.min_flows,
                              min_pairs_per_district=args.min_pairs_per_district, aum_lookup=aum_lookup,
                              date_range=date_range)

        out_b = args.output or "data/capital_flows_viz.json"
        enforce_file_cap(b, args.max_file_mb, out_b)

    log("Done.")


if __name__ == "__main__":
    main()
