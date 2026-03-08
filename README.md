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

### Custom Indicators
| File | Role | Source | Non-repainting |
|------|------|--------|----------------|
| `Indicators/KAMA.mq4` | Baseline | [mql5.com/en/code/9167](https://www.mql5.com/en/code/9167) | ✅ |
| `Indicators/HMA.mq4` | Baseline (alt) | [mql5.com/en/code/25629](https://www.mql5.com/en/code/25629) | ✅ |
| `Indicators/SSL_Channel.mq4` | C1 / C2 / Exit | [mql5.com/en/code/39878](https://www.mql5.com/en/code/39878) | ✅ |
| `Indicators/Waddah_Attar_Explosion.mq4` | Volume | [mql5.com/en/code/7051](https://www.mql5.com/en/code/7051) | ✅ |

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

## Backtest Config

See `backtest_EURUSD.ini` — run via MT4 Strategy Tester or command line.

## Roadmap
- [ ] Backtest EURUSD, GBPUSD, USDJPY (10 years)
- [ ] Optimize indicator parameters
- [ ] Add continuation trade logic
- [ ] Test HMA vs KAMA baseline
- [ ] Test Stochastic vs MACD for C2
- [ ] VPS deployment for live trading
