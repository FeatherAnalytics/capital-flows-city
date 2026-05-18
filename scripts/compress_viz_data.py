"""
Lossless compression of capital_flows_viz.json using lookup tables and positional arrays.

USAGE:
    .venv/bin/python scripts/compress_viz_data.py [--input FILE] [--output FILE]

Defaults:
    --input  data/capital_flows_viz.json
    --output data/capital_flows_viz.min.json
"""

import argparse
import json
import os


LOOKUP_FIELDS = [
    "from_district", "to_district",
    "from_neighborhood", "to_neighborhood",
    "from_building", "to_building",
    "from_building_label", "to_building_label",
    "first_flow_date", "last_flow_date",
    "avg_hours_in_cash",
]

NUMERIC_FIELDS = [
    "flow_count",
]

OPTIONAL_NUMERIC_FIELDS = [
    "unique_accounts", "peak_daily_accounts",
]

PASSTHROUGH_FIELDS = [
    "total_sell_amount", "total_buy_amount",
]

OPTIONAL_PASSTHROUGH_FIELDS = [
    "daily",
]

FIELD_ORDER = (
    LOOKUP_FIELDS + NUMERIC_FIELDS + OPTIONAL_NUMERIC_FIELDS
    + PASSTHROUGH_FIELDS + OPTIONAL_PASSTHROUGH_FIELDS
)

LOOKUP_KEYS = {
    "from_district": "fd",
    "to_district": "td",
    "from_neighborhood": "fn",
    "to_neighborhood": "tn",
    "from_building": "fb",
    "to_building": "tb",
    "from_building_label": "fl",
    "to_building_label": "tl",
    "first_flow_date": "df",
    "last_flow_date": "dl",
    "avg_hours_in_cash": "ah",
}


def build_lookups(data):
    lookups = {}
    for field in LOOKUP_FIELDS:
        values = sorted(set(str(row[field]) for row in data))
        lkey = LOOKUP_KEYS[field]
        lookups[lkey] = values
    return lookups


def compress(data, lookups):
    index_maps = {}
    for field in LOOKUP_FIELDS:
        lkey = LOOKUP_KEYS[field]
        index_maps[field] = {v: i for i, v in enumerate(lookups[lkey])}

    optional_fields = set(OPTIONAL_NUMERIC_FIELDS + OPTIONAL_PASSTHROUGH_FIELDS)
    numeric_set = set(NUMERIC_FIELDS + OPTIONAL_NUMERIC_FIELDS)

    rows = []
    for row in data:
        compressed_row = []
        for field in FIELD_ORDER:
            val = row.get(field)
            if val is None and field in optional_fields:
                compressed_row.append(None)
            elif field in index_maps:
                compressed_row.append(index_maps[field][str(val)])
            elif field in numeric_set:
                compressed_row.append(int(val) if str(val).isdigit() else float(val))
            else:
                compressed_row.append(val)
        rows.append(compressed_row)

    return {
        "lookups": lookups,
        "fields": FIELD_ORDER,
        "rows": rows,
    }


def main():
    parser = argparse.ArgumentParser(description="Compress capital_flows_viz.json losslessly")
    parser.add_argument("--input", default="data/capital_flows_viz.json")
    parser.add_argument("--output", default="data/capital_flows_viz.min.json")
    args = parser.parse_args()

    print(f"Reading {args.input}...")
    with open(args.input) as f:
        data = json.load(f)
    input_size = os.path.getsize(args.input)
    print(f"  {len(data):,} rows, {input_size:,} bytes ({input_size / 1024 / 1024:.1f} MB)")

    print("Building lookup tables...")
    lookups = build_lookups(data)
    for lkey, values in lookups.items():
        print(f"  {lkey}: {len(values)} unique values")

    print("Compressing rows...")
    compressed = compress(data, lookups)

    print(f"Writing {args.output}...")
    with open(args.output, "w") as f:
        json.dump(compressed, f, separators=(",", ":"))
    output_size = os.path.getsize(args.output)

    print(f"\nResults:")
    print(f"  Input:  {input_size:>14,} bytes ({input_size / 1024 / 1024:.1f} MB)")
    print(f"  Output: {output_size:>14,} bytes ({output_size / 1024 / 1024:.1f} MB)")
    print(f"  Saved:  {input_size - output_size:>14,} bytes ({(1 - output_size / input_size) * 100:.1f}%)")


if __name__ == "__main__":
    main()
