-- Capital Flows Cityscape
-- Template query — replace table references with your own data warehouse tables.
-- See README.md for required schema documentation.
--
-- =============================================================
-- 3-day sell-off window: Oct 27-29, 2025
--
-- Day 1 (Oct 27): Normal baseline — sell/buy ratio 0.805
-- Day 2 (Oct 28): High sell-off — ratio 0.830, $5.3B sells
-- Day 3 (Oct 29): Buying surge — ratio 0.631, $7.3B buys
--
-- Filters relaxed vs production query:
--   - frequent building threshold: 3 sessions (was 10)
--   - pair_count threshold: 3 (was 10)
--   - session amount threshold: $500 (was $1000)
-- =============================================================

WITH

-- ---------------------------------------------------------------
-- Lookup CTEs
-- ---------------------------------------------------------------

equities AS (
  SELECT UPPER(symbol) AS symbol, type, subtype, symbol_description, sic_code,
         SAFE_CAST(sic_code AS INT64) AS sic_code_int
  FROM equities
  WHERE is_current
  QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(symbol) ORDER BY id DESC) = 1
),

account_master AS (
  SELECT account_number, classification_code
  FROM account_master
),

-- ---------------------------------------------------------------
-- Source 1: Equities & ETFs from trades
-- ---------------------------------------------------------------

order_level AS (
  SELECT
    ft.order_natural_key,
    ft.account_key,
    ft.security_key,
    ft.side_key,
    SUM(ft.execution_value) AS trade_value,
    MIN(ft.execution_timestamp) AS first_execution_time,
    MAX(ft.trade_date_key) AS trade_date_key,
    MAX(ft.source_system) AS source_system,
    ANY_VALUE(ds.symbol) AS ds_symbol,
    ANY_VALUE(ds.security_name) AS ds_security_name,
    ANY_VALUE(ds.description) AS ds_description,
    ANY_VALUE(ds.asset_subtype) AS ds_asset_subtype
  FROM trades ft
  JOIN securities ds
    ON ft.security_key = ds.security_key AND ds.is_current
  WHERE ft.trade_date_key BETWEEN 20251027 AND 20251029
    AND ft.order_natural_key IS NOT NULL
    AND ds.asset_type = 'EQUITY'
  GROUP BY ft.order_natural_key, ft.account_key, ft.security_key,
           ft.side_key
),

etf_overrides AS (
  SELECT symbol, neighborhood FROM UNNEST([
    STRUCT('SPY' AS symbol, 'Broad Market ETF' AS neighborhood),
    STRUCT('QQQ', 'Broad Market ETF'),
    STRUCT('IWM', 'Broad Market ETF'),
    STRUCT('VTI', 'Broad Market ETF'),
    STRUCT('VOO', 'Broad Market ETF'),
    STRUCT('DIA', 'Broad Market ETF'),
    STRUCT('ARKK', 'Technology ETF'),
    STRUCT('XLF', 'Financial ETF'),
    STRUCT('XLE', 'Energy ETF'),
    STRUCT('XLK', 'Technology ETF'),
    STRUCT('XLV', 'Healthcare ETF'),
    STRUCT('XLP', 'Consumer ETF'),
    STRUCT('XLI', 'Industrial ETF'),
    STRUCT('XLU', 'Utilities ETF'),
    STRUCT('XLB', 'Materials ETF'),
    STRUCT('GLD', 'Commodity ETF'),
    STRUCT('SLV', 'Commodity ETF'),
    STRUCT('USO', 'Commodity ETF'),
    STRUCT('TLT', 'Bond ETF'),
    STRUCT('BND', 'Bond ETF'),
    STRUCT('AGG', 'Bond ETF'),
    STRUCT('HYG', 'Bond ETF'),
    STRUCT('LQD', 'Bond ETF'),
    STRUCT('VNQ', 'Real Estate ETF'),
    STRUCT('EEM', 'International ETF'),
    STRUCT('EFA', 'International ETF'),
    STRUCT('VWO', 'International ETF'),
    STRUCT('SQQQ', 'Inverse ETF'),
    STRUCT('SPXS', 'Inverse ETF'),
    STRUCT('SH', 'Inverse ETF'),
    STRUCT('PSQ', 'Inverse ETF'),
    STRUCT('TQQQ', 'Leveraged ETF'),
    STRUCT('SPXL', 'Leveraged ETF'),
    STRUCT('UVXY', 'Leveraged ETF'),
    STRUCT('UPRO', 'Leveraged ETF'),
    STRUCT('BITO', 'Crypto ETF'),
    STRUCT('IBIT', 'Crypto ETF'),
    STRUCT('SCHD', 'Dividend/Income ETF'),
    STRUCT('VIG', 'Dividend/Income ETF'),
    STRUCT('DVY', 'Dividend/Income ETF'),
    STRUCT('MJ', 'Vice ETF'),
    STRUCT('YOLO', 'Vice ETF'),
    STRUCT('BETZ', 'Vice ETF'),
    STRUCT('BJK', 'Vice ETF')
  ])
),

classified_equities AS (
  SELECT
    da.account_natural_key AS account_id,
    ds_side.side_code AS side,
    CASE
      WHEN eq.type = 'ETF' THEN 'ETFs'
      ELSE 'Stocks'
    END AS district,
    COALESCE(eo.neighborhood, CASE
      WHEN eq.type = 'ETF' AND COALESCE(eq.subtype, ol.ds_asset_subtype) = 'DEBT_BACKED' THEN 'Bond ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'COMMODITY|GOLD|SILVER|OIL|NATURAL GAS|METAL|PALLADIUM|PLATINUM|AGRICULTURE|WHEAT|CORN|SUGAR') THEN 'Commodity ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'INVERSE|SHORT|PROSHARES SHORT|DIREXION.*BEAR|BEAR\s') THEN 'Inverse ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'LEVERAG|ULTRA|2X|3X|DIREXION|PROSHARES ULTRA') THEN 'Leveraged ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'INTERNATIONAL|GLOBAL|EMERGING|FOREIGN|WORLD|DEVELOPED|CHINA|JAPAN|EUROPE|ASIA|INDIA|BRAZIL|LATIN|FRONTIER') THEN 'International ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'DIVIDEND|INCOME|YIELD|HIGH DIV') THEN 'Dividend/Income ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'CRYPTO|BITCOIN|ETHEREUM|BLOCKCHAIN|DIGITAL ASSET') THEN 'Crypto ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'REAL ESTATE|REIT|PROPERTY|MORTGAGE') THEN 'Real Estate ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'HEALTH|BIOTECH|PHARMA|GENOMIC|MEDICAL') THEN 'Healthcare ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'TECH|SEMI|CYBER|SOFTWARE|CLOUD|ARTIFICIAL|ROBOT|INNOVAT') THEN 'Technology ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'ENERGY|CLEAN|SOLAR|CARBON|URANIUM|LITHIUM') THEN 'Energy ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'FINANC|BANK|INSURANCE') THEN 'Financial ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'CONSUMER|RETAIL|FOOD|STAPLE') THEN 'Consumer ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'INDUSTR|DEFENS|AERO|INFRASTRUCTURE|TRANSPORT') THEN 'Industrial ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'UTILIT|WATER') THEN 'Utilities ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'MATERIAL|TIMBER|STEEL|MINING') THEN 'Materials ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'CANNABIS|MARIJUANA|GAMING|GAMBLING|BETTING|CASINO|ALCOHOL|BEER|WINE|SPIRITS|DISTILL') THEN 'Vice ETF'
      WHEN eq.type = 'ETF' AND REGEXP_CONTAINS(UPPER(COALESCE(eq.symbol_description, '')), r'S&P 500|RUSSELL|NASDAQ|TOTAL MARKET|TOTAL STOCK|BROAD|DOW JONES|LARGE.CAP|MID.CAP|SMALL.CAP|ALL.CAP|GROWTH|VALUE|MSCI USA') THEN 'Broad Market ETF'
      WHEN eq.type = 'ETF' THEN 'Equity ETF'
      WHEN eq.type = 'ADR' THEN 'ADR'
      WHEN ol.ds_asset_subtype = 'REAL_ESTATE_INVESTMENT_TRUST' THEN 'REIT'
      WHEN eq.type = 'PREFERRED_STOCK' THEN 'Preferred Stock'
      WHEN eq.sic_code_int BETWEEN 1000 AND 1499 THEN 'Energy & Mining'
      WHEN eq.sic_code_int BETWEEN 1500 AND 1799 THEN 'Construction'
      WHEN eq.sic_code_int BETWEEN 2000 AND 3999 THEN 'Manufacturing'
      WHEN eq.sic_code_int BETWEEN 4000 AND 4899 THEN 'Transportation'
      WHEN eq.sic_code_int BETWEEN 4900 AND 4999 THEN 'Utilities'
      WHEN eq.sic_code_int BETWEEN 5000 AND 5199 THEN 'Wholesale'
      WHEN eq.sic_code_int BETWEEN 5200 AND 5999 THEN 'Retail'
      WHEN eq.sic_code_int BETWEEN 6000 AND 6499 THEN 'Finance'
      WHEN eq.sic_code_int BETWEEN 6500 AND 6799 THEN 'Real Estate'
      WHEN eq.sic_code_int BETWEEN 7000 AND 8999 THEN 'Services'
      ELSE 'Common Stock'
    END) AS neighborhood,
    COALESCE(ol.ds_symbol, 'UNKNOWN') AS building,
    COALESCE(ol.ds_security_name, ol.ds_description, ol.ds_symbol, 'Unknown') AS building_label,
    ol.trade_value AS amount,
    ol.first_execution_time AS execution_timestamp,
    ol.trade_date_key,
    ol.source_system
  FROM order_level ol
  JOIN trade_sides ds_side
    ON ol.side_key = ds_side.side_key
  JOIN accounts da
    ON ol.account_key = da.account_key AND da.is_current
  LEFT JOIN equities eq
    ON UPPER(ol.ds_symbol) = eq.symbol
  LEFT JOIN etf_overrides eo
    ON UPPER(ol.ds_symbol) = eo.symbol
  LEFT JOIN account_master am
    ON da.account_number = am.account_number
  WHERE ds_side.side_code IN ('BUY', 'SELL')
),

-- ---------------------------------------------------------------
-- Source 2-4: Classic trades consolidated scan
-- ---------------------------------------------------------------

classic_trades AS (
  SELECT
    td.account_number AS account_id,
    CASE td.buy_sell_code WHEN 'B' THEN 'BUY' WHEN 'S' THEN 'SELL' END AS side,
    td.security_type_code,
    td.cusip,
    dims.description AS security_description,
    dims.bond_type,
    ABS(td.net_amount) AS amount,
    COALESCE(
      SAFE.TIMESTAMP(
        DATETIME_ADD(
          CAST(td.trade_date AS DATETIME),
          INTERVAL SAFE_CAST(LEFT(td.execution_time, 2) AS INT64) * 60
                + SAFE_CAST(RIGHT(td.execution_time, 2) AS INT64) MINUTE
        )
      ),
      TIMESTAMP(td.trade_date)
    ) AS execution_timestamp,
    CAST(FORMAT_DATE('%Y%m%d', CAST(td.trade_date AS DATE)) AS INT64) AS trade_date_key
  FROM trades td
  LEFT JOIN account_master am
    ON td.account_number = am.account_number
  LEFT JOIN securities dims
    ON td.cusip = dims.cusip AND dims.is_current
  WHERE td.process_date BETWEEN '2025-10-27' AND '2025-10-29'
    AND td.security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q', '5', '6', '&')
    AND td.buy_sell_code IN ('B', 'S')
),

classic_bond_mf AS (
  SELECT
    account_id, side,
    'Bonds' AS district,
    CASE
      WHEN security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q') AND bond_type = 'TREASURY' THEN 'Government Bond'
      WHEN security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q') AND bond_type = 'AGENCY' THEN 'Agency Bond'
      WHEN security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q') AND bond_type = 'CORPORATE' THEN 'Corporate Bond'
      WHEN security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q') AND bond_type = 'CD' THEN 'Certificate of Deposit'
      WHEN security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q') AND bond_type = 'FOREIGN_GOVERNMENT' THEN 'Foreign Government Bond'
      WHEN security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q') AND bond_type = 'EURO_BOND' THEN 'Euro Bond'
      WHEN security_type_code = 'B' THEN 'Corporate Bond'
      WHEN security_type_code = '4' THEN 'Government Bond'
      WHEN security_type_code = '3' THEN 'Municipal Bond'
      WHEN security_type_code = 'G' THEN 'Agency Bond'
      WHEN security_type_code = 'M' THEN 'Mortgage-Backed'
      WHEN security_type_code = 'J' THEN 'Corporate Bond'
      WHEN security_type_code = 'P' THEN 'Government Bond'
      WHEN security_type_code = 'Q' THEN 'Government Bond'
    END AS neighborhood,
    cusip AS building,
    COALESCE(security_description, cusip) AS building_label,
    amount, execution_timestamp, trade_date_key,
    'Classic' AS source_system
  FROM classic_trades
  WHERE security_type_code IN ('B', '4', '3', 'G', 'M', 'J', 'P', 'Q')
),

classic_options AS (
  SELECT
    account_id, side,
    'Options' AS district,
    'Equity Options' AS neighborhood,
    COALESCE(REGEXP_EXTRACT(cusip, r'^([A-Z]+)'), cusip) AS building,
    COALESCE(REGEXP_EXTRACT(cusip, r'^([A-Z]+)'), security_description, cusip) AS building_label,
    amount, execution_timestamp, trade_date_key,
    'Classic' AS source_system
  FROM classic_trades
  WHERE security_type_code IN ('5', '6')
),

classic_futures AS (
  SELECT
    account_id, side,
    'Futures' AS district,
    CASE
      WHEN REGEXP_CONTAINS(cusip, r'^\[|^\]') THEN 'Futures Options'
      ELSE 'Index/Commodity Futures'
    END AS neighborhood,
    REGEXP_EXTRACT(cusip, r'^[&\]\[]*([A-Z]+)') AS building,
    COALESCE(security_description, cusip) AS building_label,
    amount, execution_timestamp, trade_date_key,
    'Classic' AS source_system
  FROM classic_trades
  WHERE security_type_code = '&'
),

-- ---------------------------------------------------------------
-- Account cross-reference
-- ---------------------------------------------------------------

ascend_account_xref AS (
  SELECT account_id, account_number
  FROM accounts
  WHERE process_date BETWEEN '2025-10-27' AND '2025-10-29'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY process_date DESC) = 1
),

-- ---------------------------------------------------------------
-- Bonds and mutual funds
-- ---------------------------------------------------------------

bond_mf_activities AS (
  SELECT
    a.account_id, a.side,
    CASE
      WHEN a.asset_type = 'FIXED_INCOME' THEN 'Bonds'
      WHEN a.asset_type = 'MUTUAL_FUND' THEN 'Mutual Funds'
    END AS district,
    CASE
      WHEN a.asset_type = 'FIXED_INCOME' AND dims.bond_type = 'TREASURY' THEN 'Government Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND dims.bond_type = 'AGENCY' THEN 'Agency Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND dims.bond_type = 'CORPORATE' THEN 'Corporate Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND dims.bond_type = 'CD' THEN 'Certificate of Deposit'
      WHEN a.asset_type = 'FIXED_INCOME' AND dims.bond_type = 'FOREIGN_GOVERNMENT' THEN 'Foreign Government Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND dims.bond_type = 'EURO_BOND' THEN 'Euro Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND REGEXP_CONTAINS(UPPER(COALESCE(a.asset_description, '')), r'TREASURY|T-NOTE|T-BOND|US\s*GOVT|UNITED\s*STATES') THEN 'Government Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND REGEXP_CONTAINS(UPPER(COALESCE(a.asset_description, '')), r'FNMA|FHLMC|GNMA|FEDERAL\s*HOME|FEDERAL\s*NATL|GOVT\s*NATL') THEN 'Agency Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND REGEXP_CONTAINS(UPPER(COALESCE(a.asset_description, '')), r'MUNICIPAL|MUNI\b|STATE\s*OF|CITY\s*OF|COUNTY\s*OF') THEN 'Municipal Bond'
      WHEN a.asset_type = 'FIXED_INCOME' AND REGEXP_CONTAINS(UPPER(COALESCE(a.asset_description, '')), r'MORTGAGE|MBS|CMO|COLLATERAL') THEN 'Mortgage-Backed'
      WHEN a.asset_type = 'FIXED_INCOME' THEN 'Corporate Bond'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'MONEY\s*MARKET|CASH\s*RESERVE|TREASURY\s*OBLIGATION|GOVERNMENT\s*OBLIGATION|PRIME\s*OBLIGATION') THEN 'Money Market Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'MUNICIPAL|MUNI|TAX.FREE|TAX.EXEMPT') THEN 'Municipal Bond Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'BOND|FIXED\s*INCOME|INCOME\s*FUND|DEBT|CREDIT|HIGH\s*YIELD|INVESTMENT\s*GRADE|INTERMEDIATE.TERM|SHORT.TERM|LONG.TERM|AGGREGATE\s*BOND') THEN 'Bond Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'INTERNATIONAL|GLOBAL|EMERGING|FOREIGN|WORLD|OVERSEAS') THEN 'International Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'BALANCED|TARGET\s*DATE|TARGET\s*RETIRE|LIFECYCLE|ALLOCATION|MODERATE|CONSERVATIVE|AGGRESSIVE') THEN 'Balanced/Target Date Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'INDEX|S&P\s*500|RUSSELL|NASDAQ|TOTAL\s*MARKET|TOTAL\s*STOCK') THEN 'Index Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'HEALTH|BIOTECH|PHARMA|GENOMIC|MEDICAL') THEN 'Healthcare Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'TECH|SEMI|CYBER|SOFTWARE|CLOUD|ARTIFICIAL|ROBOT|INNOVAT') THEN 'Technology Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'ENERGY|CLEAN|SOLAR|CARBON|URANIUM|LITHIUM') THEN 'Energy Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'FINANC|BANK|INSURANCE') THEN 'Financial Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'REAL\s*ESTATE|REIT') THEN 'Real Estate Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' AND REGEXP_CONTAINS(UPPER(COALESCE(dims.description, a.asset_description, '')), r'EQUITY|STOCK|GROWTH|VALUE|CAPITAL\s*APPRECIATION|LARGE.CAP|MID.CAP|SMALL.CAP|BLUE\s*CHIP') THEN 'Equity Fund'
      WHEN a.asset_type = 'MUTUAL_FUND' THEN 'Mutual Fund'
    END AS neighborhood,
    CASE
      WHEN a.asset_type = 'FIXED_INCOME' THEN COALESCE(CAST(a.asset_id AS STRING), 'UNKNOWN')
      ELSE COALESCE(a.symbol, 'UNKNOWN')
    END AS building,
    COALESCE(a.asset_description, a.symbol, 'Unknown') AS building_label,
    ABS(a.net_amount) AS amount,
    a.activity_time AS execution_timestamp,
    CAST(FORMAT_DATE('%Y%m%d', a.activity_date) AS INT64) AS trade_date_key,
    'Ascend' AS source_system
  FROM activities a
  LEFT JOIN ascend_account_xref acct
    ON a.account_id = acct.account_id
  LEFT JOIN account_master am
    ON acct.account_number = am.account_number
  LEFT JOIN securities dims
    ON a.symbol = dims.symbol AND dims.is_current
  WHERE a.type = 'TRADE'
    AND a.sub_type IN ('TRADE', 'ALLOCATION')
    AND a.state = 'CURRENT'
    AND a.side IN ('BUY', 'SELL')
    AND a.asset_type IN ('FIXED_INCOME', 'MUTUAL_FUND')
    AND a.activity_date BETWEEN '2025-10-27' AND '2025-10-29'
),

-- ---------------------------------------------------------------
-- Bonds and mutual funds continued
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- Combine all trade sources
-- ---------------------------------------------------------------

unified_trades AS (
  SELECT * FROM classified_equities
  UNION ALL
  SELECT * FROM classic_bond_mf
  UNION ALL
  SELECT * FROM classic_options
  UNION ALL
  SELECT * FROM classic_futures
  UNION ALL
  SELECT * FROM bond_mf_activities
),

-- ---------------------------------------------------------------
-- Session assignment: 5-minute gap-based window within calendar day
-- ---------------------------------------------------------------

ordered_trades AS (
  SELECT
    *,
    PARSE_DATE('%Y%m%d', CAST(trade_date_key AS STRING)) AS trade_date,
    LAG(execution_timestamp) OVER (
      PARTITION BY account_id, trade_date_key
      ORDER BY execution_timestamp
    ) AS prev_ts
  FROM unified_trades
),

session_breaks AS (
  SELECT *,
    CASE
      WHEN prev_ts IS NULL THEN 1
      WHEN TIMESTAMP_DIFF(execution_timestamp, prev_ts, SECOND) > 300 THEN 1
      ELSE 0
    END AS new_session
  FROM ordered_trades
),

session_assigned AS (
  SELECT *,
    CONCAT(
      account_id, '_',
      CAST(trade_date_key AS STRING), '_',
      CAST(SUM(new_session) OVER (
        PARTITION BY account_id, trade_date_key
        ORDER BY execution_timestamp
      ) AS STRING)
    ) AS session_id
  FROM session_breaks
),

-- ---------------------------------------------------------------
-- Aggregate sells and buys per building within each session
-- Relaxed threshold: $500 min (was $1000)
-- ---------------------------------------------------------------

session_sells AS (
  SELECT
    session_id, account_id, trade_date,
    building, building_label, district, neighborhood,
    SUM(amount) AS sell_total,
    MIN(execution_timestamp) AS first_sell_ts,
    COUNT(*) AS sell_trade_count
  FROM session_assigned
  WHERE side = 'SELL'
  GROUP BY session_id, account_id, trade_date,
           building, building_label, district, neighborhood
  HAVING SUM(amount) >= 500
),

session_buys AS (
  SELECT
    session_id, account_id, trade_date,
    building, building_label, district, neighborhood,
    SUM(amount) AS buy_total,
    MAX(execution_timestamp) AS last_buy_ts,
    COUNT(*) AS buy_trade_count
  FROM session_assigned
  WHERE side = 'BUY'
  GROUP BY session_id, account_id, trade_date,
           building, building_label, district, neighborhood
  HAVING SUM(amount) >= 500
),

-- Relaxed threshold: 3 sessions (was 10)
frequent_sell_buildings AS (
  SELECT building
  FROM session_sells
  GROUP BY building
  HAVING COUNT(DISTINCT session_id) >= 3
),

frequent_buy_buildings AS (
  SELECT building
  FROM session_buys
  GROUP BY building
  HAVING COUNT(DISTINCT session_id) >= 3
),

filtered_sells AS (
  SELECT s.*
  FROM session_sells s
  LEFT JOIN frequent_sell_buildings fsb ON s.building = fsb.building
  WHERE fsb.building IS NOT NULL
     OR s.district IN ('Futures', 'Mutual Funds', 'Mutual Fund', 'Options')
),

filtered_buys AS (
  SELECT b.*
  FROM session_buys b
  LEFT JOIN frequent_buy_buildings fbb ON b.building = fbb.building
  WHERE fbb.building IS NOT NULL
     OR b.district IN ('Futures', 'Mutual Funds', 'Mutual Fund', 'Options')
),

session_buy_totals AS (
  SELECT session_id, SUM(buy_total) AS session_buy_total
  FROM filtered_buys
  GROUP BY session_id
),

sell_buy_pairs AS (
  SELECT
    s.account_id,

    s.district           AS from_district,
    s.neighborhood       AS from_neighborhood,
    s.building           AS from_building,
    s.building_label     AS from_building_label,
    s.sell_total * (b.buy_total / bt.session_buy_total) AS sell_amount,

    b.district           AS to_district,
    b.neighborhood       AS to_neighborhood,
    b.building           AS to_building,
    b.building_label     AS to_building_label,
    b.buy_total * (s.sell_total / bt.session_buy_total) AS buy_amount,

    TIMESTAMP_DIFF(b.last_buy_ts, s.first_sell_ts, HOUR) AS hours_in_cash,
    s.trade_date

  FROM filtered_sells s
  JOIN filtered_buys b
    ON s.session_id = b.session_id
  JOIN session_buy_totals bt
    ON s.session_id = bt.session_id
  WHERE bt.session_buy_total > 0
)

-- ---------------------------------------------------------------
-- Final aggregation: relaxed pair_count >= 3 (was 10)
-- ---------------------------------------------------------------

SELECT
  from_district,
  from_neighborhood,
  from_building,
  from_building_label,
  to_district,
  to_neighborhood,
  to_building,
  to_building_label,
  CAST(trade_date AS STRING)       AS trade_date,

  COUNT(*)                            AS flow_count,
  APPROX_COUNT_DISTINCT(account_id) AS unique_accounts,
  ROUND(SUM(sell_amount), 2)        AS total_sell_amount,
  ROUND(SUM(buy_amount), 2)        AS total_buy_amount,
  ROUND(AVG(sell_amount), 2)        AS avg_sell_amount,
  ROUND(AVG(buy_amount), 2)        AS avg_buy_amount,
  ROUND(AVG(hours_in_cash), 1)      AS avg_hours_in_cash

FROM (
  SELECT
    sbp.*,
    COUNT(*) OVER (PARTITION BY sbp.from_building, sbp.to_building) AS pair_count
  FROM sell_buy_pairs sbp
)
WHERE pair_count >= 3
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
ORDER BY flow_count DESC;
