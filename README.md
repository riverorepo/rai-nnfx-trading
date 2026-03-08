# RAI NNFX Trading Bot

Automated No Nonsense Forex (NNFX) Expert Advisor for MetaTrader 4, built for Oanda.

## Strategy Overview

NNFX is a structured algorithmic forex trading methodology that requires all 5 indicator conditions to align before entering a trade. Trades only on the **Daily (D1)** timeframe.

## Files

### Expert Advisors
| File | Description |
|------|-------------|
| `Experts/NNFX_Bot.mq4` | Fully automated NNFX EA — evaluates all 5 conditions, splits orders, manages trades |
| `Experts/nnfxautotrade.mq4` | Semi-manual trade panel — BUY/SELL buttons with NNFX position sizing (by Alex Cercos) |

### Scripts
| File | Description |
|------|-------------|
| `Scripts/NNFX_MultiBacktest.mq4` | Custom multi-pair backtester (v3.0) — bypasses MT4 Strategy Tester, runs as a Script on any chart |

### Custom Indicators
| File | Role | Source | Non-repainting |
|------|------|--------|----------------|
| `Indicators/KAMA.mq4` | Baseline | [mql5.com/en/code/9167](https://www.mql5.com/en/code/9167) | ✅ |
| `Indicators/HMA.mq4` | Baseline (alt) | [mql5.com/en/code/25629](https://www.mql5.com/en/code/25629) | ✅ |
| `Indicators/SSL_Channel.mq4` | C1 / C2 / Exit | [mql5.com/en/code/39878](https://www.mql5.com/en/code/39878) | ✅ |
| `Indicators/Waddah_Attar_Explosion.mq4` | Volume | [mql5.com/en/code/7051](https://www.mql5.com/en/code/7051) | ✅ |

### Utilities
| File | Description |
|------|-------------|
| `run_backtests.ps1` | PowerShell script for automated MT4 Strategy Tester runs (pair-by-pair) |
| `parse_log.ps1` | PowerShell helper to parse tester logs and count signal rejections by condition |

ATR is built into MT4 (no download needed).

## NNFX_Bot — How It Works

### The 5 Conditions (all must align on completed bar)

1. **Baseline** — KAMA or HMA (selectable). Fresh price cross required. Price must be within 1x ATR of baseline.
2. **C1 (SSL Channel)** — Direction (Hlv1 buffer: +1/-1) must agree with baseline.
3. **C2 (MACD or Stochastic)** — Must confirm on current or previous bar.
4. **Volume (WAE)** — Explosion line > dead zone + trend histogram matches direction + trend growing.
5. **Exit (SSL Channel)** — Separate instance. Color flip against trade closes the runner.

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

## Backtest Results (2015–2025, D1, 2% risk, $10k start)

### Stochastic C2 | SSL=20 | Spread: Current Live

| Pair | Signals | Orders | WR% | Long WR | Short WR | Net Profit | PF | MaxDD% |
|------|---------|--------|------|---------|----------|------------|------|--------|
| EURUSD | 95 | 190 | 43.2% | 43.2% | 43.1% | -$1,691 | 0.68 | 19.3% |
| GBPUSD | 75 | 150 | 46.7% | 47.4% | 45.9% | -$799 | 0.79 | 13.0% |
| USDJPY | 87 | 174 | 54.0% | 50.9% | 60.0% | -$17 | 1.00 | 12.4% |
| USDCHF | 102 | 204 | 43.1% | 40.6% | 47.4% | -$1,730 | 0.66 | 19.2% |
| AUDUSD | 90 | 180 | 42.2% | 48.6% | 37.7% | -$1,672 | 0.67 | 21.4% |

**Key findings:**
- Stochastic C2 fixes the long/short directional bias that MACD had (MACD showed 60% long vs 30% short WR on EURUSD)
- USDJPY is the strongest pair (PF 1.00, 54% WR, lowest drawdown)
- Strategy needs parameter optimization before going live

### MACD C2 | SSL=10 | Manual MT4 Strategy Tester (validation)
- EURUSD: 110 trades, +$21.70, PF 1.01, DD 9.49%, Long WR 60%, Short WR 30%
- Confirmed severe long/short asymmetry with MACD — Stochastic is preferred C2

## Backtest Config

See `ini/` directory for MT4 Strategy Tester config files per pair, or use `run_backtests.ps1` for automated runs.

## Roadmap
- [x] Backtest EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD (10 years)
- [x] Test Stochastic vs MACD for C2
- [x] Custom multi-pair backtester script (bypasses MT4 Strategy Tester limitations)
- [ ] Optimize indicator parameters (SSL lengths, Stochastic settings, ATR period)
- [ ] Add continuation trade logic
- [ ] Test HMA vs KAMA baseline
- [ ] VPS deployment for live trading
