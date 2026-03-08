# NNFX Trading Bot — Project Rules

## Project Goal
Build an automated trading bot implementing the No Nonsense Forex (NNFX) strategy for MetaTrader 5 (MT5). The bot is written in MQL5.

## Platform
- **Primary:** MetaTrader 5 (MQL5)
- **Fallback:** MetaTrader 4 (MQL4) if needed
- **Language:** MQL5 (.mq5 files, compiled to .ex5)
- **Testing:** MT5 Strategy Tester (visual + optimization modes)

## NNFX Strategy Rules

### Indicators (all configurable via input parameters)
1. **Baseline** — determines trend direction. Only take trades in baseline direction.
   - Price must be within 1x ATR of baseline to enter
   - Default: Ichimoku Kinko Hyo (Tenkan-sen), KAMA, or HMA
2. **C1 (Primary Confirmation)** — must agree with baseline direction to open trade
3. **C2 (Secondary Confirmation)** — must agree with C1 on entry candle (or previous candle — configurable)
4. **Volume Indicator** — trade only when volume confirms (e.g., WAE, Waddah Attar Explosion)
5. **Exit Indicator** — used to close trades early (optional, configurable)
6. **ATR** — all risk calculations based on ATR(14) by default

### Entry Rules
- All 5 conditions must align: Baseline + C1 + C2 + Volume + ATR proximity
- Enter at open of next candle after signal candle
- No trades if price is more than 1x ATR from baseline
- One trade per pair at a time

### Risk Management
- **Stop Loss:** 1.5x ATR from entry price
- **Take Profit:** 1x ATR (for first half), let second half run
- **Position Sizing:** Risk fixed % of account balance per trade (default 2%)
- **Lot Size:** Calculated dynamically from ATR stop and account risk %

### Trade Management
- Split position into 2 halves
  - Half 1: Close at 1x ATR profit
  - Half 2: Move SL to breakeven after Half 1 closes, trail or use exit indicator
- Opposite signal on open trade = close immediately

### Filters
- **Continuation trade:** If baseline flip occurs mid-trend, re-enter if all signals align
- **No news trading:** Avoid entries within configurable hours of high-impact news (optional)
- **Session filter:** Configurable trading hours (default: London + NY overlap)

## Code Structure

```
nnfx/
├── CLAUDE.md               ← this file
├── README.md
├── Experts/
│   └── NNFX_Bot.mq5        ← main EA file
├── Indicators/
│   └── (custom indicator wrappers if needed)
├── Include/
│   ├── NNFX_Core.mqh       ← strategy logic
│   ├── RiskManager.mqh     ← position sizing, SL/TP calc
│   ├── TradeManager.mqh    ← open/close/modify orders
│   └── IndicatorManager.mqh← indicator signal interface
├── Scripts/
│   └── (utility scripts)
└── Backtest/
    └── (results and notes)
```

## Coding Standards
- All indicator inputs must be configurable via EA input parameters
- No hardcoded magic numbers — use named constants or enums
- Each module (risk, trade, indicator) in its own .mqh include file
- Log all trade decisions to the MT5 journal with timestamps
- Handle errors from OrderSend, PositionModify etc. explicitly
- Use `CTrade` class from MQL5 standard library for order management

## Indicator Abstraction
Each indicator slot (Baseline, C1, C2, Volume, Exit) should use an enum to select which indicator to use, so the user can switch indicators without changing code:
```mql5
enum ENUM_BASELINE { BASE_ICHIMOKU, BASE_KAMA, BASE_HMA, BASE_EMA };
enum ENUM_CONFIRM  { CONF_MACD, CONF_RSI, CONF_STOCH, CONF_SSL };
```

## Backtesting Requirements
- Must pass 10+ years of data on major pairs (EURUSD, GBPUSD, USDJPY)
- Minimum targets: Profit Factor > 1.5, Max Drawdown < 20%, Win Rate > 40%
- Optimize ATR period, risk %, indicator parameters

## Out of Scope (for now)
- Live broker connection / VPS deployment
- Multi-currency portfolio management
- News feed API integration
