# RAI NNFX Trading Bot

Automated No Nonsense Forex (NNFX) Expert Advisor for MetaTrader 4, built for Oanda.

## Strategy Overview

NNFX is a structured algorithmic forex trading methodology that requires all indicator conditions to align before entering a trade.

### D1 Strategy (V1/V2)
Classic NNFX 5-condition system on the Daily timeframe: Baseline + C1 + C2 + Volume + Exit.

### H1 Strategy (V3) — USDJPY Only
Multi-timeframe system using custom non-repainting indicators:
- **H4 McGinley Dynamic(14)** — trend filter (direction only)
- **H1 Keltner Channel(20)** — midline flip as entry trigger
- **H1 RangeFilter(30, 2.5)** — confirmation
- **H1 HalfTrend(3)** — exit signal
- **3% risk with compounding** — $10K → $79,344 (+693%) over 5 years in backtesting
- PF 1.66 | 67% win rate | 22.8% max drawdown

## Files

### Expert Advisors
| File | Description |
|------|-------------|
| `Experts/NNFX_Bot.mq4` | V1 live trading EA — KAMA baseline + WAE volume (best on USDJPY, GBPUSD) |
| `Experts/NNFX_Combined.mq4` | Combined V1+V2 EA — auto-detects pair, runs best strategy per pair (magic 77702) |
| `Experts/NNFX_Combined_H1.mq4` | V3 H1 live trading EA — MTF custom indicators, USDJPY only, 3% risk (magic 77703) |
| `Experts/NNFX_RepaintCheck.mq4` | Repaint detector — run in Strategy Tester (Every Tick) to verify indicators don't repaint |
| `Experts/nnfxautotrade.mq4` | Semi-manual trade panel — BUY/SELL buttons with NNFX position sizing (by Alex Cercos) |

### Scripts
| File | Description |
|------|-------------|
| `Scripts/NNFX_MultiBacktest.mq4` | V1 multi-pair backtester — bypasses MT4 Strategy Tester, runs as a Script on any chart |
| `Scripts/NNFX_MultiBacktest_V2.mq4` | V2 multi-pair backtester — Ichimoku Kijun baseline + Momentum Magnitude volume |
| `Scripts/NNFX_Optimizer.mq4` | Parameter sweep optimizer — tests SSL lengths, Stoch K, ATR period, KAMA vs HMA, continuation on/off |
| `Scripts/NNFX_IndicatorTester.mq4` | Generic indicator test harness — swap any indicator into any slot with 8 signal methods |
| `Scripts/NNFX_MegaSweep.mq4` | Bulk indicator sweep — tests 104 built-in MT4 indicator combos across all slots and 7 pairs |
| `Scripts/NNFX_H1_Sweep_V3.mq4` | H1 V3 sweep — tests 75 custom indicator combos with MTF architecture across 7 pairs |
| `Scripts/NNFX_H1_Focused_BT.mq4` | H1 focused backtest — trade-by-trade log at 3% risk with compounding per pair |

### Custom Indicators
| File | Role | Source | Non-repainting |
|------|------|--------|----------------|
| `Indicators/KAMA.mq4` | Baseline | [mql5.com/en/code/9167](https://www.mql5.com/en/code/9167) | ✅ |
| `Indicators/HMA.mq4` | Baseline (alt) | [mql5.com/en/code/25629](https://www.mql5.com/en/code/25629) | ✅ |
| `Indicators/SSL_Channel.mq4` | C1 / C2 / Exit | [mql5.com/en/code/39878](https://www.mql5.com/en/code/39878) | ✅ |
| `Indicators/Waddah_Attar_Explosion.mq4` | Volume | [mql5.com/en/code/7051](https://www.mql5.com/en/code/7051) | ✅ |
| `Indicators/McGinley_Dynamic.mq4` | H4 Trend Filter (H1 V3) | Custom | ✅ |
| `Indicators/KeltnerChannel.mq4` | Entry (H1 V3) | Custom | ✅ |
| `Indicators/RangeFilter.mq4` | Confirmation (H1 V3) | Custom | ✅ |
| `Indicators/HalfTrend.mq4` | Exit (H1 V3) | Custom | ✅ |
| `Indicators/Supertrend.mq4` | Alt trend | Custom | ✅ |
| `Indicators/Ehlers_MAMA.mq4` | Alt trend (DSP) | Custom | ✅ |
| `Indicators/DonchianChannel.mq4` | Alt channel | Custom | ✅ |
| `Indicators/T3_MA.mq4` | Alt MA (Tillson) | Custom | ✅ |
| `Indicators/JMA.mq4` | Alt MA (Jurik) | Custom | ✅ |
| `Indicators/SqueezeMomentum.mq4` | Alt volume | Custom | ✅ |

### Utilities
| File | Description |
|------|-------------|
| `run_backtests.ps1` | PowerShell script for automated MT4 Strategy Tester runs (pair-by-pair) |
| `parse_log.ps1` | PowerShell helper to parse tester logs and count signal rejections by condition |

ATR is built into MT4 (no download needed).

## NNFX_Bot — How It Works

### The 5 Conditions (all must align on completed bar)

1. **Baseline** — KAMA or HMA (selectable). Fresh price cross required (or C1 flip for continuation trades). Price must be within 1x ATR of baseline.
2. **C1 (SSL Channel)** — Direction (Hlv1 buffer: +1/-1) must agree with baseline.
3. **C2 (MACD or Stochastic)** — Must confirm on current or previous bar.
4. **Volume (WAE)** — Explosion line > dead zone + trend histogram matches direction + trend growing.
5. **Exit (SSL Channel)** — Separate instance. Color flip against trade closes the runner.

### Continuation Trades (optional, `InpAllowContinuation`)
When enabled, the bot can re-enter trades without a fresh baseline cross:
- Price must already be on the correct side of baseline
- A fresh **C1 SSL direction change** serves as the entry trigger instead
- All other conditions (C2, Volume, ATR proximity) still required
- Useful for catching trends after the initial baseline cross entry closes

### Entry & Order Management
- Enters at next bar open after signal bar
- Splits into **2 orders** (half lots each):
  - **Order 1:** TP at 1x ATR, SL at 1.5x ATR
  - **Order 2 (runner):** No TP, SL at 1.5x ATR
- After Order 1 TP hit → runner SL moves to breakeven
- Exit SSL flip → closes runner early
- Opposite baseline cross → closes everything immediately

### Risk Management
- Configurable % risk per trade (default 2%)
- Dynamic lot sizing from ATR stop + tick value
- Enforces broker min/max lot and lot step
- Configured for Oanda (5-digit broker)

## Installation

1. Copy `Experts/*.mq4` → `MT4/MQL4/Experts/`
2. Copy `Indicators/*.mq4` → `MT4/MQL4/Indicators/`
3. Open MetaEditor → compile all files (F7)
4. In MT4 Navigator → drag `NNFX_Bot` onto a D1 chart
5. Enable "Allow live trading" in EA settings

**Always test on a demo account first.**

## Backtesting

### Option A: Multi-Pair Script (Recommended)

`Scripts/NNFX_MultiBacktest.mq4` runs as a **Script** on any chart and backtests 5 pairs (EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD) in one pass. This bypasses MT4's Strategy Tester, which doesn't support command-line automation on Oanda's MT4 build.

**Setup:**
1. Copy `Scripts/NNFX_MultiBacktest.mq4` → `MT4/MQL4/Scripts/`
2. Compile in MetaEditor (F7)
3. Drag onto any D1 chart → configure inputs → OK
4. Results written to `MQL4/Files/NNFX_Backtest_Results.csv` and `NNFX_Backtest_Summary.txt`

**Spread modes** (input `InpSpreadMode`):
| Mode | Description |
|------|-------------|
| 0 | Current live spread (snapshot at run time) |
| **1** | **Typical Oanda averages per pair (default, recommended)** |
| 2 | Custom fixed spread (set `InpCustomSpread` in points) |

MQL4 does not store historical per-bar spread data (`iSpread` is MQL5-only), so mode 1 uses published Oanda average spreads: EURUSD 1.4, GBPUSD 1.8, USDJPY 1.4, USDCHF 1.7, AUDUSD 1.4 pips.

### Option B: MT4 Strategy Tester (Single Pair)

In MT4 Strategy Tester (Ctrl+R):
- EA: `NNFX_Bot`
- Symbol: `EURUSD` (or any major)
- Period: `D1`
- Model: `Open prices only` (correct for D1 bar-open EA)
- Dates: 2015–2025

### Option C: Parameter Optimizer (Find Best Settings)

`Scripts/NNFX_Optimizer.mq4` sweeps parameter combinations and ranks them by aggregate profit factor across all 5 pairs.

**Setup:**
1. Copy `Scripts/NNFX_Optimizer.mq4` → `MT4/MQL4/Scripts/`
2. Compile in MetaEditor (F7)
3. Drag onto any D1 chart → configure sweep ranges → OK
4. Results saved to `MQL4/Files/NNFX_Optimizer_Results.csv`

**Parameters swept:**
| Parameter | Default Range | Step |
|-----------|--------------|------|
| SSL C1 Length | 5–30 | 5 |
| SSL Exit Length | 5–30 | 5 |
| Stochastic %K | 5–21 | 3 |
| ATR Period | 7–21 | 7 |
| Baseline | KAMA vs HMA | — |
| Continuation | On vs Off | — |

Default sweep = 2,304 combinations × 5 pairs. Adjust step sizes to narrow or widen the search.

### Key Metrics to Watch
| Metric | Target |
|--------|--------|
| Profit Factor | > 1.5 |
| Max Drawdown | < 20% |
| Win Rate | > 40% |
| Total Trades | > 100 (statistical significance) |

## iCustom Buffer Reference

| Indicator | Buffer | Value |
|-----------|--------|-------|
| KAMA | 0 | KAMA line |
| HMA | 0 | Hull main line |
| SSL_Channel | 0 | Hlv1 (+1 bullish / -1 bearish) |
| SSL_Channel | 1 | sslUp line |
| SSL_Channel | 2 | sslDown line |
| WAE | 0 | Green histogram (bull trend) |
| WAE | 1 | Red histogram (bear trend) |
| WAE | 2 | Explosion line (BB width) |
| WAE | 3 | Dead zone line |
| McGinley_Dynamic | 2 | Signal (+1 bull / -1 bear) |
| McGinley_Dynamic | 3 | MD value |
| KeltnerChannel | 0 | Upper band |
| KeltnerChannel | 1 | Middle (EMA) |
| KeltnerChannel | 2 | Lower band |
| KeltnerChannel | 3 | Signal (+1 bull / -1 bear) |
| RangeFilter | 2 | Signal (+1 bull / -1 bear) |
| HalfTrend | 2 | Signal (+1 bull / -1 bear) |
| Supertrend | 2 | Signal (+1 bull / -1 bear) |
| Ehlers_MAMA | 0 | MAMA line |
| Ehlers_MAMA | 1 | FAMA line |
| Ehlers_MAMA | 2 | Signal (+1 bull / -1 bear) |
| DonchianChannel | 3 | Signal (+1 bull / -1 bear) |
| T3_MA | 2 | Signal (+1 bull / -1 bear) |
| JMA | 2 | Signal (+1 bull / -1 bear) |
| SqueezeMomentum | 4 | Signal (+1 bull / -1 bear) |

## Backtest Results (2015–2025, D1, 2% risk, $10k start)

### Optimized: Stoch C2 | SSL C1=25, Exit=5 | ATR=7 | Spread: Typical Oanda

All 7 major pairs tested. Ranked by profit factor:

| Rank | Pair | Signals | Orders | WR% | Long WR | Short WR | Net Profit | PF | MaxDD% |
|------|------|---------|--------|------|---------|----------|------------|------|--------|
| 1 | USDJPY | 72 | 144 | 61.1% | 60.9% | 61.5% | +$897 | 1.24 | 9.2% |
| 2 | EURUSD | 84 | 168 | 50.0% | 51.3% | 48.9% | +$515 | 1.13 | 6.5% |
| 3 | GBPUSD | 65 | 130 | 58.5% | 54.3% | 63.3% | +$331 | 1.13 | 4.3% |
| 4 | AUDUSD | 71 | 142 | 53.5% | 70.4% | 43.2% | -$56 | 0.98 | 7.4% |
| 5 | USDCHF | 80 | 160 | 48.8% | 45.3% | 55.6% | -$175 | 0.95 | 6.0% |
| 6 | USDCAD | 96 | 192 | 46.9% | 50.0% | 43.5% | -$1,019 | 0.79 | 16.4% |
| 7 | NZDUSD | 95 | 190 | 42.1% | 50.0% | 36.8% | -$2,027 | 0.58 | 22.0% |

**V1 recommended pairs: USDJPY, GBPUSD** (see V2 below for EURUSD, NZDUSD)

**Optimizer findings:**
- KAMA dominates HMA across all parameter combos — HMA didn't make top 50
- Longer SSL C1 (25–30) filters noise better than shorter (10–20)
- Short SSL Exit (5) locks in runner profits faster
- Shorter ATR (7) reacts to volatility changes faster than ATR(14)
- Continuation trades did not improve results — strict baseline cross is better

### V2 Strategy: Ichimoku Kijun + Momentum Magnitude (2015–2025, D1, 2% risk, $10k)

MegaSweep tested 104 built-in MT4 indicator combos across all 5 slots. Key findings:
- **Baseline:** Ichimoku Kijun-sen(20) outperformed KAMA on EURUSD/NZDUSD
- **Volume:** Momentum Magnitude(14) outperformed WAE across most pairs

V2 uses: Kijun(20) baseline + SSL C1=25 + Stoch C2 + Momentum Magnitude(14) volume + SSL Exit=5

| Rank | Pair | Signals | Orders | WR% | Net Profit | PF | MaxDD% |
|------|------|---------|--------|------|------------|------|--------|
| 1 | EURUSD | 91 | 182 | 53.8% | +$1,160 | 1.58 | 5.8% |
| 2 | NZDUSD | 85 | 170 | 47.1% | +$579 | 1.32 | 11.2% |

V2 improves EURUSD from PF 1.13 → 1.58 and turns NZDUSD from -$2,027 → +$579.

### Combined Portfolio (V1 + V2)

The **NNFX_Combined.mq4** EA auto-detects the pair and applies the best strategy:

| Pair | Strategy | Net Profit | PF |
|------|----------|------------|------|
| USDJPY | V1 (KAMA + WAE) | +$897 | 1.24 |
| GBPUSD | V1 (KAMA + WAE) | +$331 | 1.13 |
| EURUSD | V2 (Kijun + MomMag) | +$1,160 | 1.58 |
| NZDUSD | V2 (Kijun + MomMag) | +$579 | 1.32 |
| **Total** | | **+$2,967** | |

Magic numbers: V1 standalone = 77701, Combined D1 EA = 77702, H1 EA = 77703

### H1 V3: Custom Indicators + MTF (2020–2025, H1, 3% risk, $10k, compounding)

V3 sweep tested 75 custom indicator combos with H4 trend filter + H1 entry/confirm/exit. Winner: H4 McGinley(14) + Keltner(20) entry + RangeFilter(30,2.5) confirm + HalfTrend(3) exit.

| Pair | Trades | WR% | Net Profit | PF | MaxDD% | Final Balance |
|------|--------|------|------------|------|--------|---------------|
| **USDJPY** | **679** | **67.0%** | **+$69,344** | **1.66** | **22.8%** | **$79,344** |
| GBPUSD | 672 | 53.1% | +$2,369 | 1.03 | 37.9% | $12,369 |
| AUDUSD | 665 | 53.5% | +$1,184 | 1.03 | 29.4% | $11,184 |
| EURUSD | 668 | 49.3% | -$6,021 | 0.87 | 60.2% | $3,979 |
| USDCAD | 673 | 47.5% | -$6,896 | 0.82 | 69.0% | $3,104 |

**H1 V3 recommended pair: USDJPY only.** At 3% risk with compounding, drawdowns on weaker pairs destroy accounts.

### Pre-Optimization: Stoch C2 | SSL=20 | Spread: Current Live

| Pair | Signals | Orders | WR% | Long WR | Short WR | Net Profit | PF | MaxDD% |
|------|---------|--------|------|---------|----------|------------|------|--------|
| EURUSD | 95 | 190 | 43.2% | 43.2% | 43.1% | -$1,691 | 0.68 | 19.3% |
| GBPUSD | 75 | 150 | 46.7% | 47.4% | 45.9% | -$799 | 0.79 | 13.0% |
| USDJPY | 87 | 174 | 54.0% | 50.9% | 60.0% | -$17 | 1.00 | 12.4% |
| USDCHF | 102 | 204 | 43.1% | 40.6% | 47.4% | -$1,730 | 0.66 | 19.2% |
| AUDUSD | 90 | 180 | 42.2% | 48.6% | 37.7% | -$1,672 | 0.67 | 21.4% |

### MACD C2 | SSL=10 | Manual MT4 Strategy Tester (validation)
- EURUSD: 110 trades, +$21.70, PF 1.01, DD 9.49%, Long WR 60%, Short WR 30%
- Confirmed severe long/short asymmetry with MACD — Stochastic is preferred C2

## Backtest Config

See `ini/` directory for MT4 Strategy Tester config files per pair, or use `run_backtests.ps1` for automated runs.

## Roadmap
- [x] Backtest EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD (10 years)
- [x] Test Stochastic vs MACD for C2
- [x] Custom multi-pair backtester script (bypasses MT4 Strategy Tester limitations)
- [x] Optimize indicator parameters (SSL lengths, Stochastic settings, ATR period)
- [x] Add continuation trade logic
- [x] Test HMA vs KAMA baseline
- [x] Run optimizer and analyze results
- [x] Expand to all 7 major pairs
- [x] MegaSweep: test 104 built-in indicator combos across all slots
- [x] Build V2 strategy (Ichimoku Kijun + Momentum Magnitude)
- [x] Build combined V1+V2 EA with per-pair strategy auto-detection
- [x] Repaint checker EA for validating custom indicators
- [x] Generic indicator test harness (IndicatorTester)
- [x] Test custom (non-built-in) indicators at scale (10 custom indicators, V3 sweep)
- [x] Build H1 MTF strategy with custom indicators (V3: McGinley + Keltner + RangeFilter + HalfTrend)
- [x] Focused backtest with compounding (USDJPY: $10K → $79K at 3% risk)
- [x] Build H1 live EA (NNFX_Combined_H1.mq4, magic 77703)
- [ ] Walk-forward analysis / out-of-sample validation
- [ ] VPS deployment for live trading
