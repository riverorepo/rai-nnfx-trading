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

## H1 V3 Strategy (Live — USDJPY only)
- H4 McGinley Dynamic(14) — trend direction filter
- H1 Keltner Channel(20) — midline flip entry trigger
- H1 RangeFilter(30, 2.5) — confirmation
- H1 HalfTrend(3) — exit signal
- 3% risk with compounding, split into 2 orders (TP at 1xATR + runner)
- Object prefix: "NNFXH1_" (D1 uses "NNFX_")

## H1 V4 Optimization (Current Focus — DO NOT BUILD EA YET)

### Phase 2 Winner (2026-03-12, post-bugfix, full dataset 2020–2025)
- H4 McGinley Dynamic(8, factor=0.65) — trend filter
- H1 Keltner Channel(22, ATR=14, mult=1.00) — entry (midline cross signal only)
- H1 T3(3, factor=0.90) — confirmation
- H1 RangeFilter(17, mult=2.00) — exit
- SL=1.50x ATR, TP=2.15x ATR, 5% risk
- Aggregate PF: 3.14 | Avg WR: 61.1% | Worst DD: 25.7%
- ALL 8 pairs profitable (USDJPY 7.14, EURJPY 3.43, EURUSD 2.77, USDCAD 2.66, USDCHF 2.58, AUDUSD 2.38, NZDUSD 2.17, GBPUSD 2.00)
- Results file: `MQL4/Files/NNFX_H1_ParamOpt_Phase2.csv`

### Bugs Fixed (2026-03-12)
1. **KeltnerChannel signal ignores ATR period/multiplier** — Signal buffer only checks `Close > MiddleLine` (EMA). ATR period and multiplier only affect bands (upper/lower) which are unused in signal. Sweeping these params was wasted compute. Fix: pinned in optimizer.
2. **RangeFilter exit multiplier hardcoded to 0** — ParamOptimizer set `exP2=0` for all exits, only handling HalfTrend/Supertrend special cases. With mult=0, RangeFilter smooth range is zero → exit never triggers. Fix: BuildExitRanges now returns and sweeps p2 for RangeFilter and Supertrend exits.

### Before Building V4 EA — Must Do:
1. ~~**Investigate identical results bug**~~ — FIXED. See bugs above.
2. **Walk-forward validation** — IN PROGRESS. Phase 3 added to ParamOptimizer: optimizes on IS (2020–2023), tests top 20 on OOS (2024–present). Output: `MQL4/Files/NNFX_H1_WalkForward.csv` with IS/OOS PF side-by-side and PF Decay %.
3. **Test lower risk levels** — 5% risk with 25.7% DD. Test at 3% and 2% to see drawdown impact.
4. **Test missing pairs** — GBPJPY, EURGBP, AUDJPY showed 0.00 PF (not tested or no data). EURJPY scored 3.43 so JPY crosses may be strong.
5. **Verify spread assumptions** — Confirm what spread mode the sweep used (live snapshot vs typical averages).

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

## Risk Management (V3 Live)
- Stop Loss: 1.5x ATR from entry
- Take Profit: 1x ATR (order 1), runner (order 2)
- Position sizing: Risk % of balance / (SL pips × tick value)
- After Order 1 TP → runner SL moves to breakeven
- Exit indicator flip or HTF flip against trade → close all

## Key Optimization Changes (V3 → V4 candidate)
| Parameter | V3 (live) | V4 (candidate) |
|-----------|-----------|----------------|
| McGinley period | 14 | 8 |
| McGinley factor | — | 0.65 |
| Keltner MA period | 20 | 22 |
| Keltner ATR/mult | 20 / 1.5 | 14 / 1.00 (pinned — signal uses midline only) |
| Confirmation | RangeFilter(30, 2.5) | T3(3, 0.90) |
| Exit | HalfTrend(3) | RangeFilter(17, 2.00) |
| SL | 1.5x ATR | 1.50x ATR |
| TP | 1.0x ATR | 2.15x ATR |
| Risk | 3% | 5% (test at 2-3% too) |
| Viable pairs | USDJPY only | All 8 majors |
