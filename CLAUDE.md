# NNFX Trading Bot — Project Rules

## Project Goal
Automated trading bots implementing the No Nonsense Forex (NNFX) strategy for MetaTrader 4 (MT4).

## Platform
- **Primary:** MetaTrader 4 (MQL4) via OANDA broker
- **Language:** MQL4 (.mq4 files, compiled to .ex4)
- **Compiler:** MetaEditor at `C:\Program Files (x86)\OANDA - MetaTrader 4\metaeditor.exe`
- **Data directory:** `C:\Users\river\AppData\Roaming\MetaQuotes\Terminal\7E6C4A6F67D435CAE80890D8C1401332\`
- **Testing:** Scripts run directly on charts (MT4 Strategy Tester has limitations on OANDA build)

## Active EAs
| EA | Timeframe | Pairs | Magic | Strategy |
|----|-----------|-------|-------|----------|
| NNFX_Combined.mq4 | D1 | EURUSD, GBPUSD, USDJPY, NZDUSD | 77702 | V1 KAMA/V2 Kijun auto-detect |
| NNFX_Combined_H1.mq4 | H1 | USDJPY only | 77703 | V3 MTF custom indicators |

## H1 V3 Strategy (Current Focus)
- H4 McGinley Dynamic(14) — trend direction filter
- H1 Keltner Channel(20) — midline flip entry trigger
- H1 RangeFilter(30, 2.5) — confirmation
- H1 HalfTrend(3) — exit signal
- 3% risk with compounding, split into 2 orders (TP at 1xATR + runner)
- Object prefix: "NNFXH1_" (D1 uses "NNFX_")

## Compilation Notes
- MetaEditor CLI: `/compile:"path.mq4" /log:"path.log"`
- Log files are UTF-16LE encoded — use `tr -d '\0'` or `iconv` to read
- Must wait 5+ seconds between sequential compiles or .ex4 files won't generate
- After compile, copy .ex4 to the MT4 data directory (MQL4/Experts/ or MQL4/Scripts/)

## Custom Indicators (all non-repainting)
All use closed-bar data only. Signal buffers use +1 (bull) / -1 (bear) convention.
- McGinley_Dynamic, KeltnerChannel, RangeFilter, HalfTrend
- Supertrend, Ehlers_MAMA, DonchianChannel, T3_MA, JMA, SqueezeMomentum

## Coding Standards
- All indicator inputs configurable via EA input parameters
- No hardcoded magic numbers — use named constants
- Log trade decisions to MT4 journal
- Handle OrderSend errors explicitly
- Use OrderSelect/OrderClose for order management (MQL4 style, not CTrade)

## Risk Management
- Stop Loss: 1.5x ATR from entry
- Take Profit: 1x ATR (order 1), runner (order 2)
- Position sizing: Risk % of balance / (SL pips × tick value)
- After Order 1 TP → runner SL moves to breakeven
- Exit indicator flip or HTF flip against trade → close all
