// Synthetic data generator for Capital Flow Cityscape
// Produces randomized financial flow data on each page load.
// Seed via URL param: index.html?seed=42 for reproducible cities.

const DISTRICTS = ['Stocks', 'ETFs', 'Options', 'Bonds', 'Mutual Funds', 'Futures', 'Cash'];

const DISTRICT_NEIGHBORHOODS = {
  'Stocks': ['Common Stock', 'ADR', 'Preferred Stock', 'REIT', 'Finance', 'Manufacturing', 'Energy & Mining', 'Services', 'Retail', 'Construction', 'Transportation', 'Utilities', 'Wholesale', 'Real Estate'],
  'ETFs': ['Equity ETF', 'Bond ETF', 'Broad Market ETF', 'Technology ETF', 'Healthcare ETF', 'International ETF', 'Dividend/Income ETF', 'Energy ETF', 'Financial ETF', 'Consumer ETF', 'Industrial ETF', 'Leveraged ETF', 'Commodity ETF', 'Real Estate ETF', 'Inverse ETF', 'Crypto ETF', 'Materials ETF', 'Utilities ETF', 'Vice ETF'],
  'Options': ['Equity Options', 'ADR', 'Finance', 'Manufacturing', 'Energy & Mining', 'Services', 'Retail', 'Construction', 'Transportation', 'Utilities', 'Wholesale', 'Real Estate', 'Technology ETF', 'Healthcare ETF', 'Bond ETF', 'Broad Market ETF', 'Equity ETF', 'Energy ETF', 'Financial ETF', 'Consumer ETF', 'Leveraged ETF', 'Commodity ETF', 'Real Estate ETF', 'Inverse ETF', 'Industrial ETF', 'International ETF', 'Dividend/Income ETF', 'Crypto ETF', 'Utilities ETF', 'Vice ETF'],
  'Bonds': ['Government Bond', 'Corporate Bond', 'Municipal Bond', 'Agency Bond', 'Certificate of Deposit', 'Foreign Government Bond'],
  'Mutual Funds': ['Equity Fund', 'Bond Fund', 'Balanced/Target Date Fund', 'International Fund', 'Mutual Fund', 'Technology Fund', 'Energy Fund'],
  'Futures': ['Futures Options'],
  'Cash': ['Available Balance', 'Uninvested'],
};

const DISTRICT_BUILDING_COUNTS = {
  'Stocks': [150, 200],
  'ETFs': [120, 180],
  'Options': [100, 160],
  'Bonds': [80, 120],
  'Mutual Funds': [40, 75],
  'Futures': [20, 30],
  'Cash': [1, 1],
};

const CONSONANTS = 'BCDFGHJKLMNPQRSTVWXYZ';
const VOWELS = 'AEIOU';
const ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

function createPRNG(seed) {
  let s = seed | 0;
  if (s === 0) s = 1;
  return function () {
    s = (s * 16807 + 0) % 2147483647;
    return s / 2147483647;
  };
}

function randInt(rng, min, max) {
  return min + Math.floor(rng() * (max - min + 1));
}

function pick(rng, arr) {
  return arr[Math.floor(rng() * arr.length)];
}

function logNormal(rng, mu, sigma) {
  const u1 = rng();
  const u2 = rng();
  const z = Math.sqrt(-2 * Math.log(u1 + 1e-10)) * Math.cos(2 * Math.PI * u2);
  return Math.exp(mu + sigma * z);
}

function exponential(rng, lambda) {
  return -Math.log(rng() + 1e-10) / lambda;
}

function generateTicker(rng, length) {
  let t = '';
  for (let i = 0; i < length; i++) {
    t += i % 2 === 0 ? pick(rng, CONSONANTS) : pick(rng, VOWELS);
  }
  return t;
}

function generateBondLabel(rng, ticker) {
  const names = ['ACME CORP', 'GLOBAL INDUSTRIES', 'NATIONAL FINANCE', 'PREMIER HOLDINGS', 'UNITED SERVICES', 'PACIFIC RESOURCES', 'ATLANTIC CAPITAL', 'WESTERN ENERGY', 'NORTHERN TRUST', 'EASTERN UTILITIES', 'CENTRAL SYSTEMS', 'METRO GROUP', 'SUMMIT PARTNERS', 'COASTAL VENTURES', 'MOUNTAIN CAPITAL'];
  const rate = (rng() * 8 + 0.5).toFixed(2);
  const yr = 2025 + randInt(rng, 1, 10);
  const mo = String(randInt(rng, 1, 12)).padStart(2, '0');
  const dy = String(randInt(rng, 1, 28)).padStart(2, '0');
  return `${pick(rng, names)} ${rate}%, ${mo}/${dy}/${yr}`;
}

function generateCUSIP(rng) {
  let c = '';
  for (let i = 0; i < 6; i++) c += String(randInt(rng, 0, 9));
  c += pick(rng, ALPHA);
  c += pick(rng, ALPHA);
  c += String(randInt(rng, 0, 9));
  return c;
}

function getMostRecentTradingDay() {
  const now = new Date();
  const holidays = [
    '01-01', '01-20', '02-17', '04-18', '05-26', '06-19',
    '07-04', '09-01', '11-27', '12-25',
  ];
  const d = new Date(now);
  for (let i = 0; i < 10; i++) {
    d.setDate(d.getDate() - (i === 0 ? 0 : 1));
    const day = d.getDay();
    if (day === 0 || day === 6) continue;
    const mmdd = `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    if (holidays.includes(mmdd)) continue;
    if (d.getHours() < 16 && i === 0) {
      d.setDate(d.getDate() - 1);
      continue;
    }
    return d;
  }
  return now;
}

function formatDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function groupByDistrict(buildingRegistry) {
  const keys = Object.keys(buildingRegistry);
  const byDistrict = {};
  for (const key of keys) {
    const d = buildingRegistry[key].district;
    if (!byDistrict[d]) byDistrict[d] = [];
    byDistrict[d].push(key);
  }
  return { keys, byDistrict };
}

function pickFlowPair(rng, buildingRegistry, buildingKeys, districtKeys, crossDistrictRatio) {
  const crossDistrict = rng() < crossDistrictRatio;
  const fromKey = pick(rng, buildingKeys);
  const fromEntry = buildingRegistry[fromKey];

  let toKey;
  if (crossDistrict) {
    const otherDistricts = DISTRICTS.filter(d => d !== fromEntry.district && districtKeys[d]?.length);
    if (otherDistricts.length > 0) {
      toKey = pick(rng, districtKeys[pick(rng, otherDistricts)]);
    } else {
      toKey = pick(rng, buildingKeys);
    }
  } else {
    const same = districtKeys[fromEntry.district];
    toKey = same.length > 1 ? pick(rng, same.filter(k => k !== fromKey)) : pick(rng, buildingKeys);
  }
  return { fromEntry, toEntry: buildingRegistry[toKey] };
}

function parseSeed() {
  try {
    const params = new URLSearchParams(window.location.search);
    const s = params.get('seed');
    if (s !== null && s !== '') {
      const n = parseInt(s, 10);
      if (!isNaN(n)) return { seed: n, explicit: true };
    }
  } catch (e) { /* ignore */ }
  return { seed: Date.now() & 0x7FFFFFFF, explicit: false };
}

export function generateCityData() {
  const { seed, explicit: seedExplicit } = parseSeed();
  const rng = createPRNG(seed);
  const tradeDate = formatDate(getMostRecentTradingDay());
  const buildingRegistry = {};
  const usedTickers = new Set();

  for (const district of DISTRICTS) {
    const [minB, maxB] = DISTRICT_BUILDING_COUNTS[district];
    const count = randInt(rng, minB, maxB);
    const neighborhoods = DISTRICT_NEIGHBORHOODS[district];

    for (let i = 0; i < count; i++) {
      let ticker, label;
      if (district === 'Cash') {
        ticker = 'CASH';
        label = 'Available Cash';
      } else if (district === 'Bonds') {
        ticker = generateCUSIP(rng);
        while (usedTickers.has(ticker)) ticker = generateCUSIP(rng);
        label = generateBondLabel(rng, ticker);
      } else {
        const len = randInt(rng, 3, 4);
        ticker = generateTicker(rng, len);
        while (usedTickers.has(ticker)) ticker = generateTicker(rng, randInt(rng, 3, 5));
        label = ticker;
      }
      usedTickers.add(ticker);

      const neighborhood = pick(rng, neighborhoods);
      const key = `${district}|${neighborhood}|${ticker}`;
      buildingRegistry[key] = { district, neighborhood, ticker, label };
    }
  }

  const { keys: buildingKeys, byDistrict: districtKeys } = groupByDistrict(buildingRegistry);

  const rows = [];
  const targetRows = randInt(rng, 8000, 15000);
  const crossDistrictRatio = 0.35 + rng() * 0.1;

  for (let i = 0; i < targetRows; i++) {
    const { fromEntry, toEntry } = pickFlowPair(rng, buildingRegistry, buildingKeys, districtKeys, crossDistrictRatio);

    const sellAmount = logNormal(rng, 7.8, 3.0);
    const buyAmount = sellAmount * (0.95 + rng() * 0.1);
    const flowCount = Math.max(1, Math.round(logNormal(rng, 0.7, 1.5)));
    const uniqueAccounts = Math.max(1, Math.ceil(flowCount * (0.1 + rng() * 0.5)));
    const avgHoursInCash = exponential(rng, 1.4);

    rows.push({
      from_district: fromEntry.district,
      to_district: toEntry.district,
      from_neighborhood: fromEntry.neighborhood,
      to_neighborhood: toEntry.neighborhood,
      from_building: fromEntry.ticker,
      to_building: toEntry.ticker,
      from_building_label: fromEntry.label,
      to_building_label: toEntry.label,
      trade_date: tradeDate,
      flow_count: flowCount,
      unique_accounts: uniqueAccounts,
      total_sell_amount: Math.round(sellAmount * 100) / 100,
      total_buy_amount: Math.round(buyAmount * 100) / 100,
      avg_hours_in_cash: Math.round(avgHoursInCash * 100) / 100,
    });
  }

  console.log(`Synthetic city: seed=${seed}${seedExplicit ? ' (from URL)' : ''}, ${buildingKeys.length} buildings, ${rows.length} flows`);

  return { rows, buildingRegistry, tradeDate, seed, seedExplicit };
}

function marketActivityCurve(minute) {
  if (minute < 180) return 0.05 + (minute / 180) * 0.05;
  if (minute < 540) return 0.1 + ((minute - 180) / 360) * 0.4;
  if (minute < 570) return 0.8 + ((minute - 540) / 30) * 0.2;
  if (minute < 960) return 0.7 + Math.sin((minute - 570) / 390 * Math.PI) * 0.3;
  if (minute < 1020) return 0.5 - ((minute - 960) / 60) * 0.3;
  return 0.05 + ((1440 - minute) / 420) * 0.1;
}

export function generateBucketFlows(startMinute, buildingRegistry, seed) {
  const bucketSeed = ((seed || 1) * 31 + startMinute * 7919) & 0x7FFFFFFF;
  const rng = createPRNG(bucketSeed);

  const { keys: buildingKeys, byDistrict: districtKeys } = groupByDistrict(buildingRegistry);
  if (buildingKeys.length === 0) return { flows: [], totalRows: 0 };

  const activity = marketActivityCurve(startMinute);
  const flowCount = Math.round(50 + activity * 450);
  const totalRows = Math.round(flowCount * (5 + rng() * 25));

  const flows = [];
  for (let i = 0; i < flowCount; i++) {
    const { fromEntry, toEntry } = pickFlowPair(rng, buildingRegistry, buildingKeys, districtKeys, 0.38);

    const sellAmount = logNormal(rng, 7.4, 2.5);
    const buyAmount = sellAmount * (0.95 + rng() * 0.1);
    const minutesInCash = exponential(rng, 0.025);
    const firstSellMinutes = startMinute + rng() * 5;
    const accountId = `SYN${String(bucketSeed + i).padStart(8, '0')}`;

    flows.push({
      account_id: accountId,
      from_building: fromEntry.ticker,
      to_building: toEntry.ticker,
      from_district: fromEntry.district,
      to_district: toEntry.district,
      from_building_label: fromEntry.label,
      to_building_label: toEntry.label,
      from_neighborhood: fromEntry.neighborhood,
      to_neighborhood: toEntry.neighborhood,
      sell_amount: Math.round(sellAmount * 100) / 100,
      buy_amount: Math.round(buyAmount * 100) / 100,
      minutes_in_cash: Math.round(Math.min(minutesInCash, 1440) * 100) / 100,
      first_sell_minutes: Math.round(firstSellMinutes * 100) / 100,
      from_trade_count: randInt(rng, 1, 8),
      to_trade_count: randInt(rng, 1, 8),
    });
  }

  return { flows, totalRows };
}
