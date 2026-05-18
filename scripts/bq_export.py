"""
USAGE: bq_export.py --sql-file FILE --output FILE [--project PROJECT] [--page-size N]
       bq_export.py --resume JOB_ID --output FILE [--project PROJECT] [--page-size N]

Stream BigQuery query results to a local JSON file, page by page.
Avoids the bq CLI's memory buffering issue with large result sets.

Auto-detects stalls (no progress for 5 minutes) and resumes from the
last written row using BQ's cached query results (valid for 24 hours).

Output format matches `bq query --format=json`: a JSON array of objects
where all values are strings.

Examples:
  .venv/bin/python scripts/bq_export.py \\
    --sql-file sql/capital_flows.sql \\
    --output data/capital_flows_raw.json

  # Resume a stalled export from an existing job:
  .venv/bin/python scripts/bq_export.py \\
    --resume a433b9b3-79d7-4a18-84d5-d4e924790dc7 \\
    --output data/capital_flows_raw.json
"""

import argparse
import json
import os
import sys
import threading
import time
from datetime import date, datetime
from decimal import Decimal

from google.cloud import bigquery


STALL_TIMEOUT_S = 300
WATCHDOG_CHECK_S = 60
MAX_RETRIES = 5


def to_string(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    return str(value)


class StallDetected(Exception):
    pass


def watchdog(row_counter: list[int], stop_event: threading.Event) -> None:
    last_count = row_counter[0]
    last_progress_time = time.time()
    while not stop_event.is_set():
        stop_event.wait(WATCHDOG_CHECK_S)
        if stop_event.is_set():
            return
        current = row_counter[0]
        if current > last_count:
            last_count = current
            last_progress_time = time.time()
        elif time.time() - last_progress_time > STALL_TIMEOUT_S:
            print(
                f"\n*** STALL DETECTED: no progress for {STALL_TIMEOUT_S}s "
                f"(stuck at row {current:,}). Interrupting download. ***",
                file=sys.stderr,
            )
            os.kill(os.getpid(), 2)  # SIGINT to unblock the iterator
            return


def download_rows(
    client: bigquery.Client,
    job_id: str,
    page_size: int,
    out_path: str,
    skip_rows: int = 0,
) -> int:
    """Download rows from a completed BQ job. Returns total rows written."""
    job = client.get_job(job_id)
    result = job.result(page_size=page_size)
    total_rows = result.total_rows or 0
    schema_fields = [field.name for field in result.schema]

    if skip_rows == 0:
        print(f"Schema: {', '.join(schema_fields)}")

    print(
        f"Downloading from row {skip_rows:,} of {total_rows:,} "
        f"({skip_rows / total_rows * 100:.1f}% already written)"
    )

    row_counter = [0]
    stop_event = threading.Event()
    watcher = threading.Thread(target=watchdog, args=(row_counter, stop_event), daemon=True)
    watcher.start()

    tmp_path = out_path + ".tmp"
    mode = "a" if skip_rows > 0 else "w"
    row_count = skip_rows
    t_write_start = time.time()

    try:
        with open(tmp_path, mode) as out:
            if skip_rows == 0:
                out.write("[")

            for row in result:
                if row_counter[0] < skip_rows:
                    row_counter[0] += 1
                    if row_counter[0] % (page_size * 10) == 0:
                        print(f"  Skipping... {row_counter[0]:,} / {skip_rows:,}")
                    continue

                obj = {field: to_string(row[field]) for field in schema_fields}

                if row_count > 0:
                    out.write(",")
                json.dump(obj, out, separators=(",", ":"))
                row_count += 1
                row_counter[0] = row_count

                if row_count % page_size == 0:
                    out.flush()
                    elapsed = time.time() - t_write_start
                    file_size = os.path.getsize(tmp_path)
                    rate = (row_count - skip_rows) / elapsed if elapsed > 0 else 0
                    pct = (row_count / total_rows * 100) if total_rows else 0
                    print(
                        f"  {row_count:>12,} / {total_rows:,} rows "
                        f"({pct:5.1f}%) | "
                        f"{file_size / 1e9:.2f} GB | "
                        f"{rate:,.0f} rows/s | "
                        f"{elapsed:.0f}s elapsed"
                    )

            out.write("]")

    except KeyboardInterrupt:
        stop_event.set()
        raise StallDetected(f"Stalled at row {row_count:,}")
    finally:
        stop_event.set()

    os.rename(tmp_path, out_path)
    return row_count


def count_rows_in_tmp(tmp_path: str) -> int:
    """Count rows already written to the .tmp file by counting top-level JSON commas."""
    if not os.path.exists(tmp_path):
        return 0
    size = os.path.getsize(tmp_path)
    if size < 2:
        return 0
    print(f"Counting rows in existing {tmp_path} ({size / 1e9:.2f} GB)...")
    count = 0
    depth = 0
    in_string = False
    escape = False
    with open(tmp_path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            for byte in chunk:
                if escape:
                    escape = False
                    continue
                ch = chr(byte)
                if ch == "\\":
                    escape = True
                    continue
                if ch == '"':
                    in_string = not in_string
                    continue
                if in_string:
                    continue
                if ch == "{":
                    if depth == 1:
                        count += 1
                    depth += 1
                elif ch == "}":
                    depth -= 1
    print(f"  Found {count:,} complete rows")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stream BigQuery query results to a local JSON file."
    )
    parser.add_argument("--sql-file", default=None, help="Path to SQL file")
    parser.add_argument("--resume", default=None, help="Resume from existing BQ job ID")
    parser.add_argument("--output", required=True, help="Output JSON file path")
    parser.add_argument(
        "--project",
        default="your-gcp-project-id",
        help="BigQuery project ID (default: your-gcp-project-id)",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=10000,
        help="Rows per page (default: 10000)",
    )
    args = parser.parse_args()

    if not args.sql_file and not args.resume:
        parser.error("Either --sql-file or --resume is required")

    client = bigquery.Client(project=args.project)

    if args.resume:
        job_id = args.resume
        print(f"Resuming from job: {job_id}")
    else:
        with open(args.sql_file, "r") as f:
            sql = f.read()

        print(f"SQL file: {args.sql_file} ({len(sql)} chars)")
        print(f"Output:   {args.output}")
        print(f"Project:  {args.project}")
        print(f"Page size: {args.page_size}")
        print()

        print("Submitting query to BigQuery...")
        t_start = time.time()
        query_job = client.query(sql)
        job_id = query_job.job_id
        print(f"Job ID: {job_id}")
        print("Waiting for query to complete...")
        result = query_job.result(page_size=args.page_size)
        t_query = time.time() - t_start
        total_rows = result.total_rows or 0
        print(f"Query completed in {t_query:.1f}s. Total rows: {total_rows:,}")
        print()

    tmp_path = args.output + ".tmp"
    skip_rows = count_rows_in_tmp(tmp_path) if os.path.exists(tmp_path) else 0

    t_start = time.time()
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            print(f"\n--- Attempt {attempt}/{MAX_RETRIES} ---")
            row_count = download_rows(client, job_id, args.page_size, args.output, skip_rows)
            break
        except StallDetected as e:
            print(f"\n{e}", file=sys.stderr)
            if attempt < MAX_RETRIES:
                skip_rows = count_rows_in_tmp(tmp_path)
                print(f"Will resume from row {skip_rows:,} on next attempt...")
                time.sleep(5)
            else:
                print(f"Failed after {MAX_RETRIES} attempts.", file=sys.stderr)
                print(f"To resume manually:\n  .venv/bin/python scripts/bq_export.py --resume {job_id} --output {args.output}")
                sys.exit(1)

    t_total = time.time() - t_start
    file_size = os.path.getsize(args.output)
    print()
    print(f"Done. {row_count:,} rows written to {args.output}")
    print(f"File size: {file_size / 1e9:.2f} GB")
    print(f"Total time: {t_total:.1f}s")
    print(f"Job ID (for resume): {job_id}")


if __name__ == "__main__":
    main()
