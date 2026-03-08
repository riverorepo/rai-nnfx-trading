//+------------------------------------------------------------------+
//|                                           NNFX_MultiBacktest.mq4 |
//|         Custom multi-pair backtester - bypasses Strategy Tester   |
//|         Runs as a Script on any chart. Simulates NNFX trades     |
//|         with typical per-pair spread, win/loss counting, CSV.     |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "3.00"
#property strict
#property show_inputs

//--- Settings
input int      InpBaselineType    = 0;       // Baseline: 0=KAMA, 1=HMA
input int      InpKamaPeriod      = 10;      // KAMA Period
input double   InpKamaFastMA      = 2.0;     // KAMA Fast
input double   InpKamaSlowMA      = 30.0;    // KAMA Slow
input bool     InpSSL_C1_Wicks    = false;   // C1 SSL Wicks
input int      InpSSL_C1_MA1Type  = 0;       // C1 SSL MA1 Type
input int      InpSSL_C1_MA1Src   = 2;       // C1 SSL MA1 Src (PRICE_HIGH)
input int      InpSSL_C1_MA1Len   = 25;      // C1 SSL MA1 Length
input int      InpSSL_C1_MA2Type  = 0;       // C1 SSL MA2 Type
input int      InpSSL_C1_MA2Src   = 3;       // C1 SSL MA2 Src (PRICE_LOW)
input int      InpSSL_C1_MA2Len   = 25;      // C1 SSL MA2 Length
input int      InpC2Type          = 1;       // C2: 0=MACD, 1=Stochastic
input int      InpStochK          = 14;      // Stoch %K
input int      InpStochD          = 3;       // Stoch %D
input int      InpStochSlowing    = 3;       // Stoch Slowing
input int      InpMacdFast        = 12;      // MACD Fast
input int      InpMacdSlow        = 26;      // MACD Slow
input int      InpMacdSignal      = 9;       // MACD Signal
input int      InpWAE_Sensitive   = 150;     // WAE Sensitivity
input int      InpWAE_DeadZone    = 30;      // WAE Dead Zone
input int      InpWAE_ExplPower   = 15;      // WAE Explosion Power
input int      InpWAE_TrendPwr    = 15;      // WAE Trend Power
input bool     InpSSL_Exit_Wicks  = false;   // Exit SSL Wicks
input int      InpSSL_Exit_MA1Type= 0;       // Exit SSL MA1 Type
input int      InpSSL_Exit_MA1Src = 2;       // Exit SSL MA1 Src
input int      InpSSL_Exit_MA1Len = 5;       // Exit SSL MA1 Length
input int      InpSSL_Exit_MA2Type= 0;       // Exit SSL MA2 Type
input int      InpSSL_Exit_MA2Src = 3;       // Exit SSL MA2 Src
input int      InpSSL_Exit_MA2Len = 5;       // Exit SSL MA2 Length
input int      InpATRPeriod       = 7;       // ATR Period
input double   InpSLMultiplier    = 1.5;     // SL Multiplier (ATR x)
input double   InpTP1Multiplier   = 1.0;     // TP1 Multiplier (ATR x)
input double   InpMaxATRDist      = 1.0;     // Max Baseline Distance (ATR x)
input double   InpRiskPercent     = 2.0;     // Risk % per trade
input double   InpStartBalance    = 10000.0; // Starting Balance
input int      InpSpreadMode      = 1;       // Spread: 0=Current, 1=Typical, 2=Custom(pts)
input int      InpCustomSpread     = 15;      // Custom Spread (points, if mode=2)
input bool     InpAllowContinuation = false;  // Allow Continuation Trades
input int      InpHmaPeriod       = 20;      // HMA Period
input double   InpHmaDivisor      = 2.0;     // HMA Divisor

#define IND_KAMA "KAMA"
#define IND_SSL  "SSL_Channel"
#define IND_WAE  "Waddah_Attar_Explosion"

//--- Trade tracking
struct VirtualTrade
{
   int    direction;     // 1=buy, -1=sell
   double entryPrice;    // actual entry (with spread for buys)
   double sl;
   double tp1;           // for order 1
   double lots1;
   double lots2;
   bool   order1Open;
   bool   order2Open;
   bool   movedToBE;
   datetime entryTime;
   double signalPnl;     // accumulated P&L for this signal
};

//--- Results per pair
struct PairResult
{
   string symbol;
   int    totalSignals;
   int    totalOrders;     // = signals * 2 (to match MT4 trade count)
   int    wins;            // profitable signals (both orders combined)
   int    losses;
   double grossProfit;
   double grossLoss;
   double maxDrawdown;
   double maxDrawdownPct;
   double finalBalance;
   int    longSignals;
   int    longWins;
   int    shortSignals;
   int    shortWins;
};

//+------------------------------------------------------------------+
// Typical Oanda spreads in points (5-digit). Source: Oanda published averages.
// These represent normal market hours. Actual varies by session/volatility.
int GetTypicalSpread(string sym)
{
   if(sym == "EURUSD") return 14;   // ~1.4 pips
   if(sym == "GBPUSD") return 18;   // ~1.8 pips
   if(sym == "USDJPY") return 14;   // ~1.4 pips
   if(sym == "USDCHF") return 17;   // ~1.7 pips
   if(sym == "AUDUSD") return 14;   // ~1.4 pips
   if(sym == "NZDUSD") return 20;   // ~2.0 pips
   if(sym == "USDCAD") return 20;   // ~2.0 pips
   if(sym == "EURJPY") return 18;   // ~1.8 pips
   if(sym == "GBPJPY") return 28;   // ~2.8 pips
   if(sym == "EURGBP") return 15;   // ~1.5 pips
   return 20; // default fallback
}

//+------------------------------------------------------------------+
void OnStart()
{
   string pairs[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD", "USDCAD"};
   int numPairs = ArraySize(pairs);
   PairResult results[];
   ArrayResize(results, numPairs);

   string c2name = (InpC2Type == 1) ? "Stochastic" : "MACD";
   string spreadMode = "Current";
   if(InpSpreadMode == 1) spreadMode = "Typical (Oanda avg)";
   if(InpSpreadMode == 2) spreadMode = "Custom (" + IntegerToString(InpCustomSpread) + " pts)";

   Print("=== NNFX Multi-Pair Backtest v3.0 ===");
   Print("C2: ", c2name, " | SSL C1 Len: ", InpSSL_C1_MA1Len, " | SSL Exit Len: ", InpSSL_Exit_MA1Len);
   Print("Spread mode: ", spreadMode);

   for(int p = 0; p < numPairs; p++)
   {
      string sym = pairs[p];
      Print("--- Processing ", sym, " ---");

      int totalBars = iBars(sym, PERIOD_D1);
      if(totalBars < 100)
      {
         Print("WARNING: ", sym, " only has ", totalBars, " D1 bars. Skipping.");
         results[p].symbol = sym;
         results[p].totalSignals = 0;
         continue;
      }

      RunBacktest(sym, results[p]);
      PrintResult(results[p]);
   }

   WriteResultsCSV(results);
   WriteResultsSummary(results);

   Print("=== NNFX Multi-Pair Backtest Complete ===");
   Alert("NNFX Backtest finished! Check Experts tab and MQL4/Files/ for results.");
}

//+------------------------------------------------------------------+
void RunBacktest(string sym, PairResult &result)
{
   result.symbol = sym;
   result.totalSignals = 0;
   result.totalOrders = 0;
   result.wins = 0;
   result.losses = 0;
   result.grossProfit = 0;
   result.grossLoss = 0;
   result.maxDrawdown = 0;
   result.maxDrawdownPct = 0;
   result.finalBalance = InpStartBalance;
   result.longSignals = 0;
   result.longWins = 0;
   result.shortSignals = 0;
   result.shortWins = 0;

   double balance = InpStartBalance;
   double peakBalance = InpStartBalance;
   double tickValue = MarketInfo(sym, MODE_TICKVALUE);
   double tickSize  = MarketInfo(sym, MODE_TICKSIZE);
   double pointVal  = MarketInfo(sym, MODE_POINT);
   // Spread calculation based on selected mode
   int spreadPts;
   if(InpSpreadMode == 1)
      spreadPts = GetTypicalSpread(sym);
   else if(InpSpreadMode == 2)
      spreadPts = InpCustomSpread;
   else
      spreadPts = (int)MarketInfo(sym, MODE_SPREAD);

   double spread = spreadPts * pointVal;

   if(tickValue <= 0 || tickSize <= 0 || pointVal <= 0)
   {
      Print("ERROR: Cannot get market info for ", sym);
      return;
   }

   Print(sym, " spread: ", spreadPts, " points (", DoubleToString(spread, 5), " price)");

   int totalBars = iBars(sym, PERIOD_D1);
   datetime startDate = D'2015.01.01';
   datetime endDate   = D'2025.01.01';
   int startBar = iBarShift(sym, PERIOD_D1, startDate, false);
   int endBar   = iBarShift(sym, PERIOD_D1, endDate, false);
   if(endBar < 0) endBar = 0;
   if(startBar < 0) startBar = totalBars - 1;

   Print(sym, ": Bars from ", startBar, " to ", endBar, " (", startBar - endBar, " bars)");

   VirtualTrade trade;
   trade.order1Open = false;
   trade.order2Open = false;

   for(int bar = startBar - 1; bar > endBar; bar--)
   {
      double openNext = iOpen(sym, PERIOD_D1, bar - 1);

      // --- Manage existing trades ---
      if(trade.order1Open || trade.order2Open)
      {
         ManageVirtualTrade(sym, bar, spread, trade, balance, peakBalance, result, tickValue, tickSize);
      }

      // --- Skip if position open ---
      if(trade.order1Open || trade.order2Open)
         continue;

      // --- Evaluate entry ---
      int signal = EvaluateEntryForPair(sym, bar);
      if(signal == 0)
         continue;

      // --- Open virtual trade ---
      result.totalSignals++;
      result.totalOrders += 2;  // 2 orders per signal, matching MT4

      double atr = iATR(sym, PERIOD_D1, InpATRPeriod, bar);
      if(atr <= 0) continue;

      // Entry price with spread (MT4 bar data = Bid prices)
      // Buy: entry at Ask = Open + spread
      // Sell: entry at Bid = Open
      double entryPrice;
      if(signal == 1)
         entryPrice = openNext + spread;  // Buy at Ask
      else
         entryPrice = openNext;            // Sell at Bid

      double slDist  = InpSLMultiplier * atr;
      double tp1Dist = InpTP1Multiplier * atr;

      // Lot sizing
      double riskAmount = balance * (InpRiskPercent / 100.0);
      double slTicks = slDist / tickSize;
      double riskPerLot = slTicks * tickValue;
      if(riskPerLot <= 0) continue;
      double totalLots = riskAmount / riskPerLot;
      double halfLot = MathFloor(totalLots / 2.0 * 100) / 100.0;  // round to 0.01
      if(halfLot < 0.01) halfLot = 0.01;

      trade.direction = signal;
      trade.entryPrice = entryPrice;
      trade.entryTime = iTime(sym, PERIOD_D1, bar - 1);
      trade.lots1 = halfLot;
      trade.lots2 = halfLot;
      trade.order1Open = true;
      trade.order2Open = true;
      trade.movedToBE = false;
      trade.signalPnl = 0;

      if(signal == 1)
      {
         trade.sl  = entryPrice - slDist;
         trade.tp1 = entryPrice + tp1Dist;
      }
      else
      {
         trade.sl  = entryPrice + slDist;
         trade.tp1 = entryPrice - tp1Dist;
      }

      if(signal == 1) result.longSignals++;
      else result.shortSignals++;
   }

   // Close remaining
   if(trade.order1Open || trade.order2Open)
   {
      double lastClose = iClose(sym, PERIOD_D1, endBar);
      double exitPrice;
      if(trade.direction == 1) exitPrice = lastClose;           // Buy closes at Bid
      else                     exitPrice = lastClose + spread;  // Sell closes at Ask
      ForceCloseAll(trade, exitPrice, balance, peakBalance, result, tickValue, tickSize);
   }

   result.finalBalance = balance;
}

//+------------------------------------------------------------------+
int EvaluateEntryForPair(string sym, int bar)
{
   double blCurr = GetBaselineForPair(sym, bar);
   double blPrev = GetBaselineForPair(sym, bar + 1);
   if(blCurr == 0 || blPrev == 0) return 0;

   double closeCurr = iClose(sym, PERIOD_D1, bar);
   double closePrev = iClose(sym, PERIOD_D1, bar + 1);

   int baselineDir = 0;
   if(closeCurr > blCurr) baselineDir = 1;
   else if(closeCurr < blCurr) baselineDir = -1;
   if(baselineDir == 0) return 0;

   bool baselineCross = false;
   if(baselineDir == 1 && closePrev <= blPrev) baselineCross = true;
   if(baselineDir == -1 && closePrev >= blPrev) baselineCross = true;
   if(!baselineCross)
   {
      if(!InpAllowContinuation) return 0;
      // Continuation: require fresh C1 SSL direction change as trigger
      int c1Now  = GetSSL_C1_ForPair(sym, bar);
      int c1Prev2 = GetSSL_C1_ForPair(sym, bar + 1);
      if(c1Now != c1Prev2 && c1Now == baselineDir)
      { /* continuation trigger — proceed */ }
      else
         return 0;
   }

   double atr = iATR(sym, PERIOD_D1, InpATRPeriod, bar);
   double dist = MathAbs(closeCurr - blCurr);
   if(dist > InpMaxATRDist * atr) return 0;

   int c1Dir = GetSSL_C1_ForPair(sym, bar);
   if(c1Dir != baselineDir) return 0;

   bool c2ok = false;
   int c2Curr = GetC2ForPair(sym, bar);
   int c2Prev = GetC2ForPair(sym, bar + 1);
   if(c2Curr == baselineDir || c2Prev == baselineDir) c2ok = true;
   if(!c2ok) return 0;

   if(!CheckWAE_ForPair(sym, bar, baselineDir)) return 0;

   return baselineDir;
}

//+------------------------------------------------------------------+
double GetBaselineForPair(string sym, int shift)
{
   if(InpBaselineType == 0)
      return iCustom(sym, PERIOD_D1, IND_KAMA, InpKamaPeriod, InpKamaFastMA, InpKamaSlowMA, 0, shift);
   else
      return iCustom(sym, PERIOD_D1, "HMA", InpHmaPeriod, InpHmaDivisor, PRICE_CLOSE, 0, shift);
}

//+------------------------------------------------------------------+
int GetSSL_C1_ForPair(string sym, int shift)
{
   double hlv = iCustom(sym, PERIOD_D1, IND_SSL,
                          InpSSL_C1_Wicks, InpSSL_C1_MA1Type,
                          InpSSL_C1_MA1Src, InpSSL_C1_MA1Len,
                          InpSSL_C1_MA2Type, InpSSL_C1_MA2Src,
                          InpSSL_C1_MA2Len, 0, shift);
   if(hlv > 0.5)  return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

//+------------------------------------------------------------------+
int GetSSL_Exit_ForPair(string sym, int shift)
{
   double hlv = iCustom(sym, PERIOD_D1, IND_SSL,
                          InpSSL_Exit_Wicks, InpSSL_Exit_MA1Type,
                          InpSSL_Exit_MA1Src, InpSSL_Exit_MA1Len,
                          InpSSL_Exit_MA2Type, InpSSL_Exit_MA2Src,
                          InpSSL_Exit_MA2Len, 0, shift);
   if(hlv > 0.5)  return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

//+------------------------------------------------------------------+
int GetC2ForPair(string sym, int shift)
{
   if(InpC2Type == 0)
   {
      double macd = iMACD(sym, PERIOD_D1, InpMacdFast, InpMacdSlow,
                           InpMacdSignal, PRICE_CLOSE, MODE_MAIN, shift);
      if(macd > 0) return 1;
      if(macd < 0) return -1;
      return 0;
   }
   else
   {
      double stoch = iStochastic(sym, PERIOD_D1, InpStochK, InpStochD,
                                  InpStochSlowing, MODE_SMA, 0, MODE_MAIN, shift);
      if(stoch > 50.0) return 1;
      if(stoch < 50.0) return -1;
      return 0;
   }
}

//+------------------------------------------------------------------+
bool CheckWAE_ForPair(string sym, int bar, int direction)
{
   double green     = iCustom(sym, PERIOD_D1, IND_WAE, InpWAE_Sensitive,
                               InpWAE_DeadZone, InpWAE_ExplPower, InpWAE_TrendPwr,
                               true, 500, true, true, true, true, 0, bar);
   double red       = iCustom(sym, PERIOD_D1, IND_WAE, InpWAE_Sensitive,
                               InpWAE_DeadZone, InpWAE_ExplPower, InpWAE_TrendPwr,
                               true, 500, true, true, true, true, 1, bar);
   double explosion = iCustom(sym, PERIOD_D1, IND_WAE, InpWAE_Sensitive,
                               InpWAE_DeadZone, InpWAE_ExplPower, InpWAE_TrendPwr,
                               true, 500, true, true, true, true, 2, bar);
   double deadZone  = iCustom(sym, PERIOD_D1, IND_WAE, InpWAE_Sensitive,
                               InpWAE_DeadZone, InpWAE_ExplPower, InpWAE_TrendPwr,
                               true, 500, true, true, true, true, 3, bar);
   double greenPrev = iCustom(sym, PERIOD_D1, IND_WAE, InpWAE_Sensitive,
                               InpWAE_DeadZone, InpWAE_ExplPower, InpWAE_TrendPwr,
                               true, 500, true, true, true, true, 0, bar + 1);
   double redPrev   = iCustom(sym, PERIOD_D1, IND_WAE, InpWAE_Sensitive,
                               InpWAE_DeadZone, InpWAE_ExplPower, InpWAE_TrendPwr,
                               true, 500, true, true, true, true, 1, bar + 1);

   if(explosion <= deadZone) return false;

   bool trendMatch = false;
   bool trendGrow  = false;
   if(direction == 1 && green > 0)  { trendMatch = true; trendGrow = (green > greenPrev); }
   if(direction == -1 && red > 0)   { trendMatch = true; trendGrow = (red > redPrev); }

   return (trendMatch && trendGrow);
}

//+------------------------------------------------------------------+
void ManageVirtualTrade(string sym, int bar, double spread, VirtualTrade &trade,
                         double &balance, double &peakBalance, PairResult &result,
                         double tickVal, double tickSz)
{
   double high  = iHigh(sym, PERIOD_D1, bar);
   double low   = iLow(sym, PERIOD_D1, bar);
   double close = iClose(sym, PERIOD_D1, bar);

   // Bar data is Bid. For sells, SL/TP checked against Ask = price + spread
   double askHigh  = high + spread;
   double askLow   = low + spread;
   double askClose = close + spread;

   // --- Opposite baseline cross -> close everything ---
   double blCurr = GetBaselineForPair(sym, bar);
   double blPrev = GetBaselineForPair(sym, bar + 1);
   double closePrev = iClose(sym, PERIOD_D1, bar + 1);

   bool oppCross = false;
   if(trade.direction == 1 && close < blCurr && closePrev >= blPrev)
      oppCross = true;
   if(trade.direction == -1 && close > blCurr && closePrev <= blPrev)
      oppCross = true;

   if(oppCross)
   {
      double exitPrice;
      if(trade.direction == 1) exitPrice = close;       // Buy closes at Bid
      else                     exitPrice = askClose;     // Sell closes at Ask
      ForceCloseAll(trade, exitPrice, balance, peakBalance, result, tickVal, tickSz);
      return;
   }

   // --- Order 1: TP/SL check ---
   if(trade.order1Open)
   {
      bool tp1Hit = false;
      bool sl1Hit = false;
      double pnl1 = 0;

      if(trade.direction == 1)
      {
         // Buy: checked against Bid prices (bar data)
         if(high >= trade.tp1)
         {
            tp1Hit = true;
            pnl1 = (trade.tp1 - trade.entryPrice) / tickSz * tickVal * trade.lots1;
         }
         else if(low <= trade.sl)
         {
            sl1Hit = true;
            pnl1 = (trade.sl - trade.entryPrice) / tickSz * tickVal * trade.lots1;
         }
      }
      else
      {
         // Sell: checked against Ask prices
         if(askLow <= trade.tp1)
         {
            tp1Hit = true;
            pnl1 = (trade.entryPrice - trade.tp1) / tickSz * tickVal * trade.lots1;
         }
         else if(askHigh >= trade.sl)
         {
            sl1Hit = true;
            pnl1 = (trade.entryPrice - trade.sl) / tickSz * tickVal * trade.lots1;
         }
      }

      if(tp1Hit || sl1Hit)
      {
         balance += pnl1;
         trade.signalPnl += pnl1;
         if(pnl1 > 0) result.grossProfit += pnl1;
         else result.grossLoss += pnl1;
         trade.order1Open = false;

         // TP1 hit -> move runner to breakeven
         if(tp1Hit && trade.order2Open)
         {
            trade.sl = trade.entryPrice;
            trade.movedToBE = true;
         }
      }
   }

   // --- Order 2: Runner - SL or Exit SSL ---
   if(trade.order2Open)
   {
      bool slHit2 = false;
      if(trade.direction == 1 && low <= trade.sl) slHit2 = true;
      if(trade.direction == -1 && askHigh >= trade.sl) slHit2 = true;

      int exitSSL = GetSSL_Exit_ForPair(sym, bar);
      bool exitFlip = false;
      if(trade.direction == 1 && exitSSL == -1) exitFlip = true;
      if(trade.direction == -1 && exitSSL == 1) exitFlip = true;

      double pnl2 = 0;

      if(slHit2)
      {
         if(trade.direction == 1)
            pnl2 = (trade.sl - trade.entryPrice) / tickSz * tickVal * trade.lots2;
         else
            pnl2 = (trade.entryPrice - trade.sl) / tickSz * tickVal * trade.lots2;

         balance += pnl2;
         trade.signalPnl += pnl2;
         if(pnl2 > 0) result.grossProfit += pnl2;
         else result.grossLoss += pnl2;
         trade.order2Open = false;
      }
      else if(exitFlip)
      {
         double exitPrice;
         if(trade.direction == 1) exitPrice = close;
         else                     exitPrice = askClose;

         if(trade.direction == 1)
            pnl2 = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots2;
         else
            pnl2 = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots2;

         balance += pnl2;
         trade.signalPnl += pnl2;
         if(pnl2 > 0) result.grossProfit += pnl2;
         else result.grossLoss += pnl2;
         trade.order2Open = false;
      }
   }

   // --- Both orders closed? Count win/loss for this signal ---
   if(!trade.order1Open && !trade.order2Open)
   {
      if(trade.signalPnl >= 0)
      {
         result.wins++;
         if(trade.direction == 1) result.longWins++;
         else result.shortWins++;
      }
      else
      {
         result.losses++;
      }
   }

   // --- Drawdown tracking ---
   if(balance > peakBalance) peakBalance = balance;
   double dd = peakBalance - balance;
   if(dd > result.maxDrawdown)
   {
      result.maxDrawdown = dd;
      result.maxDrawdownPct = (dd / peakBalance) * 100.0;
   }
}

//+------------------------------------------------------------------+
void ForceCloseAll(VirtualTrade &trade, double exitPrice,
                    double &balance, double &peakBalance, PairResult &result,
                    double tickVal, double tickSz)
{
   if(trade.order1Open)
   {
      double pnl;
      if(trade.direction == 1)
         pnl = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots1;
      else
         pnl = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots1;

      balance += pnl;
      trade.signalPnl += pnl;
      if(pnl > 0) result.grossProfit += pnl;
      else result.grossLoss += pnl;
      trade.order1Open = false;
   }

   if(trade.order2Open)
   {
      double pnl;
      if(trade.direction == 1)
         pnl = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots2;
      else
         pnl = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots2;

      balance += pnl;
      trade.signalPnl += pnl;
      if(pnl > 0) result.grossProfit += pnl;
      else result.grossLoss += pnl;
      trade.order2Open = false;
   }

   // Count win/loss
   if(trade.signalPnl >= 0)
   {
      result.wins++;
      if(trade.direction == 1) result.longWins++;
      else result.shortWins++;
   }
   else
   {
      result.losses++;
   }

   // Drawdown
   if(balance > peakBalance) peakBalance = balance;
   double dd = peakBalance - balance;
   if(dd > result.maxDrawdown)
   {
      result.maxDrawdown = dd;
      result.maxDrawdownPct = (dd / peakBalance) * 100.0;
   }
}

//+------------------------------------------------------------------+
void PrintResult(PairResult &r)
{
   double pf = (r.grossLoss != 0) ? MathAbs(r.grossProfit / r.grossLoss) : 0;
   double netProfit = r.grossProfit + r.grossLoss;
   double winRate = (r.totalSignals > 0) ? ((double)r.wins / r.totalSignals * 100.0) : 0;
   double longWR = (r.longSignals > 0) ? ((double)r.longWins / r.longSignals * 100.0) : 0;
   double shortWR = (r.shortSignals > 0) ? ((double)r.shortWins / r.shortSignals * 100.0) : 0;

   Print("===== ", r.symbol, " RESULTS =====");
   Print("Signals: ", r.totalSignals, " | Orders: ", r.totalOrders, " (MT4-equivalent trades)");
   Print("Wins: ", r.wins, " | Losses: ", r.losses, " | Win Rate: ", DoubleToStr(winRate, 1), "%");
   Print("Long: ", r.longSignals, " (", DoubleToStr(longWR, 1), "% win) | Short: ", r.shortSignals, " (", DoubleToStr(shortWR, 1), "% win)");
   Print("Net Profit: $", DoubleToStr(netProfit, 2));
   Print("Profit Factor: ", DoubleToStr(pf, 2));
   Print("Max Drawdown: $", DoubleToStr(r.maxDrawdown, 2), " (", DoubleToStr(r.maxDrawdownPct, 1), "%)");
   Print("Final Balance: $", DoubleToStr(r.finalBalance, 2));
}

//+------------------------------------------------------------------+
void WriteResultsCSV(PairResult &results[])
{
   string filename = "NNFX_Backtest_Results.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle, "Symbol", "Signals", "Orders", "Wins", "Losses", "WinRate%",
             "LongSignals", "LongWR%", "ShortSignals", "ShortWR%",
             "NetProfit", "GrossProfit", "GrossLoss", "ProfitFactor",
             "MaxDD$", "MaxDD%", "FinalBalance");

   for(int i = 0; i < ArraySize(results); i++)
   {
      PairResult r = results[i];
      double pf = (r.grossLoss != 0) ? MathAbs(r.grossProfit / r.grossLoss) : 0;
      double net = r.grossProfit + r.grossLoss;
      double wr = (r.totalSignals > 0) ? ((double)r.wins / r.totalSignals * 100.0) : 0;
      double lwr = (r.longSignals > 0) ? ((double)r.longWins / r.longSignals * 100.0) : 0;
      double swr = (r.shortSignals > 0) ? ((double)r.shortWins / r.shortSignals * 100.0) : 0;

      FileWrite(handle, r.symbol, r.totalSignals, r.totalOrders,
                r.wins, r.losses, DoubleToStr(wr, 1),
                r.longSignals, DoubleToStr(lwr, 1),
                r.shortSignals, DoubleToStr(swr, 1),
                DoubleToStr(net, 2), DoubleToStr(r.grossProfit, 2),
                DoubleToStr(r.grossLoss, 2), DoubleToStr(pf, 2),
                DoubleToStr(r.maxDrawdown, 2), DoubleToStr(r.maxDrawdownPct, 1),
                DoubleToStr(r.finalBalance, 2));
   }
   FileClose(handle);
   Print("CSV saved to: MQL4/Files/", filename);
}

//+------------------------------------------------------------------+
void WriteResultsSummary(PairResult &results[])
{
   string filename = "NNFX_Backtest_Summary.txt";
   int handle = FileOpen(filename, FILE_WRITE | FILE_TXT);
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   string c2name = (InpC2Type == 1) ? "Stochastic" : "MACD";
   FileWriteString(handle, "NNFX Multi-Pair Backtest Results (v3.0 - historical spread)\r\n");
   FileWriteString(handle, "Config: C2=" + c2name + " | SSL_C1=" + IntegerToString(InpSSL_C1_MA1Len) +
                            " | SSL_Exit=" + IntegerToString(InpSSL_Exit_MA1Len) + "\r\n");
   string spMode = "Current";
   if(InpSpreadMode == 1) spMode = "Typical (Oanda)";
   if(InpSpreadMode == 2) spMode = "Custom (" + IntegerToString(InpCustomSpread) + "pts)";
   FileWriteString(handle, "Period: 2015-2025 | D1 | Risk: " + DoubleToStr(InpRiskPercent, 1) + "% | Spread: " + spMode + "\r\n\r\n");

   FileWriteString(handle, StringFormat("%-8s | %4s | %6s | %5s | %6s | %7s | %7s | %10s | %5s | %7s\r\n",
                   "Pair", "Sig", "Orders", "Wins", "WR%", "LongWR%", "ShrtWR%", "Net Profit", "PF", "MaxDD%"));
   FileWriteString(handle, "---------|------|--------|-------|--------|---------|---------|------------|-------|--------\r\n");

   for(int i = 0; i < ArraySize(results); i++)
   {
      PairResult r = results[i];
      double pf = (r.grossLoss != 0) ? MathAbs(r.grossProfit / r.grossLoss) : 0;
      double net = r.grossProfit + r.grossLoss;
      double wr = (r.totalSignals > 0) ? ((double)r.wins / r.totalSignals * 100.0) : 0;
      double lwr = (r.longSignals > 0) ? ((double)r.longWins / r.longSignals * 100.0) : 0;
      double swr = (r.shortSignals > 0) ? ((double)r.shortWins / r.shortSignals * 100.0) : 0;

      FileWriteString(handle, StringFormat("%-8s | %4d | %6d | %5d | %5.1f%% | %6.1f%% | %6.1f%% | $%9.2f | %5.2f | %6.1f%%\r\n",
                      r.symbol, r.totalSignals, r.totalOrders, r.wins, wr, lwr, swr, net, pf, r.maxDrawdownPct));
   }

   FileWriteString(handle, "\r\nMax Drawdowns:\r\n");
   for(int i = 0; i < ArraySize(results); i++)
   {
      FileWriteString(handle, StringFormat("  %s: $%.2f (%.1f%%)\r\n",
                      results[i].symbol, results[i].maxDrawdown, results[i].maxDrawdownPct));
   }

   FileClose(handle);
   Print("Summary saved to: MQL4/Files/", filename);
}
//+------------------------------------------------------------------+
