# Capital Flow Cityscape

I wanted to see if complex financial data — the kind that lives in Excel spreadsheets and BI dashboards — could be visualized in a way that reveals patterns you can't see in flat tables. This project is the result: a 3D cityscape where buildings represent securities, districts represent asset classes, and the flows of capital between them become visible paths through a living city.

All values are randomized. This is a proof-of-concept project and should not be used as-is out-of-the-box.

## What It Shows

The cityscape covers two periods of trading activity during a period of market volatility. The first is the lead up to and the aftermath of the initiation of the Iran conflict in February 2026. The second is a period of high selling in October 2025. Each record is a directional sell-to-buy pair showing capital flowing from one security to another. This is at the aggregated level, showing connections between two assets.

- **Districts** = Asset classes (Stocks, ETFs, Bonds, Mutual Funds, Options, Futures)
- **Neighborhoods** = Sub-types (Common Stock, Bond ETF, ADR, REIT, Money Market, etc.)
- **Buildings** = Individual tickers (QQQ, AAPL, SPY, etc.)

Building height encodes ending AUM (log-scaled), with trade volume as a fallback. Window lighting encodes net flow direction and ownership concentration. Hovering a building reveals curved arcs connecting it to every ticker it exchanged capital with — thicker arcs for larger flows, with animated dots during timelapse playback.

## Architecture

```
BigQuery tables ──→ bq_export.py ──→ capital_flows_raw.json
                                          │
                                     postprocess.py
                                          │
                                     capital_flows_viz.json
                                          │
                                     compress_viz_data.py
                                          │
                                     capital_flows_viz.min.json ──→ index.html (Three.js)
```

1. **SQL query** (BigQuery) defines session-based capital flow pairs with proportional allocation
2. **`bq_export.py`** streams the query results to raw JSON with stall detection and resume
3. **`postprocess.py`** collapses daily rows to pair-level aggregates, applies filters, builds time series
4. **`compress_viz_data.py`** applies lookup-table compression (~50-70% size reduction)
5. **Browser** loads the minified JSON and renders a Three.js cityscape

## Tech Stack

| Layer | Technology |
|---|---|
| Visualization | Three.js r160 (CDN), vanilla JS/CSS, single HTML file |
| Data warehouse | BigQuery (Google Cloud) |
| Pipeline scripts | Python (`bq_export.py`, `postprocess.py`, `compress_viz_data.py`) |
| Python deps | `google-cloud-bigquery`, `ijson` |

## Running Locally

The data files are included in the repo. Just serve the directory:

```bash
# Python
python3 -m http.server

# Or Node.js
npx -y http-server -p 8000
```

Open [http://localhost:8000](http://localhost:8000).

### Controls

- **Click and drag** to rotate the cityscape
- **Scroll** to zoom in/out
- **Hover** a building to see ticker details and flow connections
- **Timeline scrubber** to navigate through dates
- **Play/pause** for timelapse playback with speed control (0.25x–2x)

## Using Your Own Data

To visualize your own capital flow data:

1. Adapt the SQL templates in `sql/` for your BigQuery project and tables
2. Run the pipeline: `bq_export.py` → `postprocess.py` → `compress_viz_data.py`
3. The compressed JSON drops into the project root, and the viz picks it up on reload

The pipeline expects sell-to-buy pair data with fields like `from_district`, `to_district`, `from_building`, `to_building`, dollar amounts, and daily time series. See `sql/capital_flows.sql` for the full schema.

## Features

- **Light/dark mode** — toggle with the theme button; persists via localStorage
- **Timelapse playback** — watch capital flows animate day by day
- **District-based layout** — each asset class occupies its own city district with neighborhood sub-zones
- **Flow visualization** — curved arcs with thickness proportional to flow size, animated dots during playback
- **Hover details** — building tooltips with volume, flow count, unique accounts, and time-in-cash metrics
- **Filters** — filter by ticker, minimum volume, and district
