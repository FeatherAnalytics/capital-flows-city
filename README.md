# Capital Flow Cityscape

[**Live Demo**](https://www.featheranalytics.dev/capital-flows-city/)

A 3D cityscape where buildings represent securities, districts represent asset classes, and animated flows of capital between them become visible paths through a living city. All data is synthetically generated — each page load produces a unique city.

## What It Shows

- **Districts** = Asset classes (Stocks, ETFs, Bonds, Mutual Funds, Options, Futures, Cash)
- **Neighborhoods** = Sub-types (Common Stock, Bond ETF, ADR, REIT, etc.)
- **Buildings** = Individual tickers with procedurally generated names

Building height encodes flow volume (log-scaled). Window lighting encodes net flow direction and ownership concentration. Hovering a building reveals curved arcs connecting it to every ticker it exchanged capital with — thicker arcs for larger flows, with animated dots during timelapse playback.

## Running Locally

Serve the directory with any static HTTP server:

```bash
python3 -m http.server
# or
npx -y http-server -p 8000
```

Open [http://localhost:8000](http://localhost:8000). The visualization generates synthetic data automatically — no data files needed.

### Shareable Seeds

Append `?seed=N` to the URL to pin the random seed. Same seed produces the same city every time, so you can share a specific cityscape with someone else:

```
http://localhost:8000/?seed=42
```

Without a seed parameter, each page load generates a fresh city.

### Controls

- **Click and drag** to rotate the cityscape
- **Scroll** to zoom in/out
- **Hover** a building to see ticker details and flow connections
- **Timeline scrubber** to navigate through the trading day
- **Play/pause** for timelapse playback with speed control (0.25x–5x)
- **Light/dark mode** toggle in the top-right stats panel

## Using Your Own Data

To visualize real capital flow data, place your data files in the `data/` directory. When data files are present, the visualization loads them instead of generating synthetic data.

### Data Files

**`data/flows.json`** (required) — Aggregated building-to-building flows. Accepts two formats:

**Plain array** (simplest — just an array of flow objects):

```json
[
  {
    "from_district": "Stocks",
    "to_district": "ETFs",
    "from_neighborhood": "Technology",
    "to_neighborhood": "Equity ETF",
    "from_building": "AAPL",
    "to_building": "SPY",
    "from_building_label": "Apple Inc",
    "to_building_label": "SPDR S&P 500",
    "trade_date": "2026-05-12",
    "flow_count": 25,
    "unique_accounts": 12,
    "total_sell_amount": 500000.00,
    "total_buy_amount": 495000.00,
    "avg_hours_in_cash": 0.5
  },
  ...
]
```

**Compressed format** (for large datasets — uses lookup tables for smaller file size):

```json
{
  "lookups": {
    "fd": ["Stocks", "ETFs", ...],
    "td": ["Stocks", "ETFs", ...],
    "fn": ["Technology", "Equity ETF", ...],
    "tn": ["Technology", "Equity ETF", ...],
    "fb": ["AAPL", "SPY", ...],
    "tb": ["AAPL", "SPY", ...],
    "fl": ["Apple Inc", "SPDR S&P 500", ...],
    "tl": ["Apple Inc", "SPDR S&P 500", ...],
    "dt": ["2026-05-12"]
  },
  "fields": ["from_district", "to_district", "from_neighborhood", "to_neighborhood",
             "from_building", "to_building", "from_building_label", "to_building_label",
             "trade_date", "flow_count", "unique_accounts",
             "total_sell_amount", "total_buy_amount", "avg_hours_in_cash"],
  "rows": [[0, 1, 0, 1, 0, 1, 0, 1, 0, 25, 12, 500000.00, 495000.00, 0.5], ...]
}
```

Valid districts: `Stocks`, `ETFs`, `Bonds`, `Options`, `Mutual Funds`, `Futures`, `Cash`.

**`data/timeline.json`** (optional) — Defines the timelapse time range and bucket files. If omitted, the timelapse defaults to standard market hours (9:30 AM – 4:00 PM ET) with synthetic flows. Bucket files go in `data/buckets/`. See the Python pipeline scripts for the expected format.

### Pipeline Scripts

The `sql/` and Python scripts (`bq_export.py`, `postprocess.py`, `compress_viz_data.py`) can produce these files from BigQuery data. The compression step is optional — the visualization accepts both plain and compressed formats.

## Tech Stack

| Layer | Technology |
|---|---|
| Visualization | Three.js r160 (CDN), vanilla JS/CSS |
| Data generation | `synth.js` (client-side ES module) |
| Pipeline (optional) | Python + BigQuery for real data |

## Features

- **Synthetic data generation** — unique city on every page load, shareable via seed URLs
- **Light/dark mode** — toggle with the theme button; persists via localStorage
- **Timelapse playback** — watch capital flows animate through a trading day
- **District-based layout** — each asset class occupies its own city district with neighborhood sub-zones
- **Flow visualization** — curved arcs with thickness proportional to flow size, animated dots during playback
- **Hover details** — building tooltips with volume, flow count, unique accounts, and time-in-cash metrics
- **Filters** — filter by ticker, minimum volume, and district
- **Custom data support** — drop your own data files in `data/` to override the generator
