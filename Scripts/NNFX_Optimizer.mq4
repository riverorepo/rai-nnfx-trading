//+------------------------------------------------------------------+
//|                                              NNFX_Optimizer.mq4  |
//|         Parameter sweep optimizer for NNFX strategy               |
//|         Tests: SSL lengths, Stoch settings, ATR period,           |
//|         KAMA vs HMA baseline, continuation on/off                 |
//|         Runs as a Script on any chart.                            |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "1.00"
#property strict
#property show_inputs

//--- Sweep range inputs
input string   _sweep_sep_     = "=== Parameter Sweep Ranges ===";       // ---
input int      InpSSL_C1_Min   = 5;       // SSL C1 Length: Min
input int      InpSSL_C1_Max   = 30;      // SSL C1 Length: Max
input int      InpSSL_C1_Step  = 5;       // SSL C1 Length: Step
input int      InpSSL_Exit_Min = 5;       // SSL Exit Length: Min
input int      InpSSL_Exit_Max = 30;      // SSL Exit Length: Max
input int      InpSSL_Exit_Step= 5;       // SSL Exit Length: Step
input string   _stoch_sep_     = "=== Stochastic Sweep ===";             // ---
input int      InpStochK_Min   = 5;       // Stoch %K: Min
input int      InpStochK_Max   = 21;      // Stoch %K: Max
input int      InpStochK_Step  = 3;       // Stoch %K: Step (5,8,11,14,17,20)
input string   _atr_sep_       = "=== ATR Sweep ===";                    // ---
input int      InpATR_Min      = 7;       // ATR Period: Min
input int      InpATR_Max      = 21;      // ATR Period: Max
input int      InpATR_Step     = 7;       // ATR Period: Step (7,14,21)
input string   _bl_sep_        = "=== Baseline & Continuation ===";      // ---
input bool     InpTestBothBaselines = true;  // Test both KAMA and HMA
input bool     InpTestContinuation  = true;  // Test continuation on/off

//--- Fixed parameters (not swept)
input string   _fixed_sep_     = "=== Fixed Parameters ===";             // ---
input int      InpKamaPeriod   = 10;      // KAMA Period
input double   InpKamaFastMA   = 2.0;     // KAMA Fast
input double   InpKamaSlowMA   = 30.0;    // KAMA Slow
input int      InpHmaPeriod    = 20;      // HMA Period
input double   InpHmaDivisor   = 2.0;     // HMA Divisor
input int      InpStochD       = 3;       // Stoch %D (fixed)
input int      InpStochSlowing = 3;       // Stoch Slowing (fixed)
input int      InpWAE_Sensitive= 150;     // WAE Sensitivity
input int      InpWAE_DeadZone = 30;      // WAE Dead Zone
input int      InpWAE_ExplPower= 15;      // WAE Explosion Power
input int      InpWAE_TrendPwr = 15;      // WAE Trend Power
input double   InpSLMultiplier = 1.5;     // SL Multiplier (ATR x)
input double   InpTP1Multiplier= 1.0;     // TP1 Multiplier (ATR x)
input double   InpMaxATRDist   = 1.0;     // Max Baseline Distance (ATR x)
input double   InpRiskPercent  = 2.0;     // Risk %
input double   InpStartBalance= 10000.0;  // Starting Balance
input int      InpSpreadMode   = 1;       // Spread: 0=Current, 1=Typical, 2=Custom
input int      InpCustomSpread = 15;      // Custom Spread (points)
input int      InpMaxResults   = 50;      // Max results to save (top N by PF)

#define IND_KAMA "KAMA"
#define IND_SSL  "SSL_Channel"
#define IND_WAE  "Waddah_Attar_Explosion"

//--- Optimization result
struct OptResult
{
   int    baselineType;    // 0=KAMA, 1=HMA
   int    sslC1Len;
   int    sslExitLen;
   int    stochK;
   int    atrPeriod;
   bool   continuation;
   double aggNetProfit;    // sum across all pairs
   double aggPF;           // aggregate profit factor
   double avgWinRate;
   double worstDD;         // worst drawdown across pairs
   int    totalSignals;
};

//--- Virtual trade tracking (same as multi-backtester)
struct VTrade
{
   int    direction;
   double entryPrice;
   double sl;
   double tp1;
   double lots1;
   double lots2;
   bool   order1Open;
   bool   order2Open;
   bool   movedToBE;
   double signalPnl;
};

struct PairStats
{
   int    signals;
   int    wins;
   int    losses;
   double grossProfit;
   double grossLoss;
   double maxDD;
   double maxDDPct;
   double finalBalance;
};

//--- Typical Oanda spreads
int GetTypicalSpread(string sym)
{
   if(sym == "EURUSD") return 14;
   if(sym == "GBPUSD") return 18;
   if(sym == "USDJPY") return 14;
   if(sym == "USDCHF") return 17;
   if(sym == "AUDUSD") return 14;
   if(sym == "NZDUSD") return 20;
   if(sym == "USDCAD") return 20;
   if(sym == "EURJPY") return 18;
   if(sym == "GBPJPY") return 28;
   if(sym == "EURGBP") return 15;
   return 20;
}

//+------------------------------------------------------------------+
void OnStart()
{
   string pairs[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD"};
   int numPairs = ArraySize(pairs);

   // Count total combinations
   int sslC1Steps  = (InpSSL_C1_Max - InpSSL_C1_Min) / InpSSL_C1_Step + 1;
   int sslExSteps  = (InpSSL_Exit_Max - InpSSL_Exit_Min) / InpSSL_Exit_Step + 1;
   int stochSteps  = (InpStochK_Max - InpStochK_Min) / InpStochK_Step + 1;
   int atrSteps    = (InpATR_Max - InpATR_Min) / InpATR_Step + 1;
   int blSteps     = InpTestBothBaselines ? 2 : 1;
   int contSteps   = InpTestContinuation ? 2 : 1;
   int totalCombos = sslC1Steps * sslExSteps * stochSteps * atrSteps * blSteps * contSteps;

   Print("=== NNFX Parameter Optimizer v1.0 ===");
   Print("Total parameter combinations: ", totalCombos);
   Print("Pairs: ", numPairs, " | Bars per pair: ~2500 (10yr D1)");
   Print("Estimated runs: ", totalCombos * numPairs);

   // Pre-compute bar ranges for each pair
   int startBars[], endBars[];
   ArrayResize(startBars, numPairs);
   ArrayResize(endBars, numPairs);
   double tickValues[], tickSizes[], pointValues[];
   int spreadPtsArr[];
   ArrayResize(tickValues, numPairs);
   ArrayResize(tickSizes, numPairs);
   ArrayResize(pointValues, numPairs);
   ArrayResize(spreadPtsArr, numPairs);

   datetime startDate = D'2015.01.01';
   datetime endDate   = D'2025.01.01';

   for(int p = 0; p < numPairs; p++)
   {
      startBars[p] = iBarShift(pairs[p], PERIOD_D1, startDate, false);
      endBars[p]   = iBarShift(pairs[p], PERIOD_D1, endDate, false);
      if(endBars[p] < 0) endBars[p] = 0;
      if(startBars[p] < 0) startBars[p] = iBars(pairs[p], PERIOD_D1) - 1;
      tickValues[p] = MarketInfo(pairs[p], MODE_TICKVALUE);
      tickSizes[p]  = MarketInfo(pairs[p], MODE_TICKSIZE);
      pointValues[p]= MarketInfo(pairs[p], MODE_POINT);
      if(InpSpreadMode == 1)
         spreadPtsArr[p] = GetTypicalSpread(pairs[p]);
      else if(InpSpreadMode == 2)
         spreadPtsArr[p] = InpCustomSpread;
      else
         spreadPtsArr[p] = (int)MarketInfo(pairs[p], MODE_SPREAD);

      Print(pairs[p], ": bars ", startBars[p], " to ", endBars[p],
            " | tickVal=", DoubleToStr(tickValues[p], 5),
            " | spread=", spreadPtsArr[p], "pts");
   }

   // Allocate results array
   OptResult allResults[];
   ArrayResize(allResults, totalCombos);
   int resultCount = 0;
   int comboNum = 0;

   // === SWEEP LOOP ===
   for(int bl = 0; bl < blSteps; bl++)
   {
      int baselineType = bl;  // 0=KAMA, 1=HMA

      for(int sc1 = InpSSL_C1_Min; sc1 <= InpSSL_C1_Max; sc1 += InpSSL_C1_Step)
      {
         for(int sex = InpSSL_Exit_Min; sex <= InpSSL_Exit_Max; sex += InpSSL_Exit_Step)
         {
            for(int sk = InpStochK_Min; sk <= InpStochK_Max; sk += InpStochK_Step)
            {
               for(int atr = InpATR_Min; atr <= InpATR_Max; atr += InpATR_Step)
               {
                  for(int cont = 0; cont < contSteps; cont++)
                  {
                     bool allowCont = (cont == 1);
                     comboNum++;

                     // Progress every 100 combos
                     if(comboNum % 100 == 0)
                        Print("Progress: ", comboNum, "/", totalCombos,
                              " (", DoubleToStr((double)comboNum/totalCombos*100, 1), "%)");

                     // Check for user cancel
                     if(IsStopped()) { Print("CANCELLED by user."); break; }

                     OptResult res;
                     res.baselineType  = baselineType;
                     res.sslC1Len      = sc1;
                     res.sslExitLen    = sex;
                     res.stochK        = sk;
                     res.atrPeriod     = atr;
                     res.continuation  = allowCont;
                     res.aggNetProfit  = 0;
                     res.aggPF         = 0;
                     res.avgWinRate    = 0;
                     res.worstDD       = 0;
                     res.totalSignals  = 0;

                     double totalGrossProfit = 0;
                     double totalGrossLoss   = 0;
                     double totalWR          = 0;

                     // Run across all pairs
                     for(int p = 0; p < numPairs; p++)
                     {
                        if(tickValues[p] <= 0 || tickSizes[p] <= 0) continue;

                        PairStats ps;
                        double spread = spreadPtsArr[p] * pointValues[p];

                        RunSingleBacktest(pairs[p], startBars[p], endBars[p],
                                          baselineType, sc1, sex, sk, atr, allowCont,
                                          spread, tickValues[p], tickSizes[p], ps);

                        double net = ps.grossProfit + ps.grossLoss;
                        res.aggNetProfit += net;
                        totalGrossProfit += ps.grossProfit;
                        totalGrossLoss   += ps.grossLoss;
                        res.totalSignals += ps.signals;
                        if(ps.maxDDPct > res.worstDD)
                           res.worstDD = ps.maxDDPct;
                        double wr = (ps.signals > 0) ? ((double)ps.wins / ps.signals * 100.0) : 0;
                        totalWR += wr;
                     }

                     res.aggPF = (totalGrossLoss != 0) ? MathAbs(totalGrossProfit / totalGrossLoss) : 0;
                     res.avgWinRate = totalWR / numPairs;

                     allResults[resultCount] = res;
                     resultCount++;
                  }
                  if(IsStopped()) break;
               }
               if(IsStopped()) break;
            }
            if(IsStopped()) break;
         }
         if(IsStopped()) break;
      }
      if(IsStopped()) break;
   }

   Print("Sweep complete. Total results: ", resultCount);

   // Sort by aggregate profit factor (descending)
   SortResultsByPF(allResults, resultCount);

   // Output top N
   int outputCount = MathMin(resultCount, InpMaxResults);
   WriteOptimizerCSV(allResults, outputCount);
   PrintTopResults(allResults, outputCount);

   Print("=== Optimization Complete ===");
   Alert("NNFX Optimizer done! Check Experts tab and MQL4/Files/NNFX_Optimizer_Results.csv");
}

//+------------------------------------------------------------------+
void RunSingleBacktest(string sym, int startBar, int endBar,
                        int baselineType, int sslC1Len, int sslExitLen,
                        int stochK, int atrPeriod, bool allowCont,
                        double spread, double tickVal, double tickSz,
                        PairStats &stats)
{
   stats.signals     = 0;
   stats.wins        = 0;
   stats.losses      = 0;
   stats.grossProfit = 0;
   stats.grossLoss   = 0;
   stats.maxDD       = 0;
   stats.maxDDPct    = 0;
   stats.finalBalance= InpStartBalance;

   double balance     = InpStartBalance;
   double peakBalance = InpStartBalance;

   VTrade trade;
   trade.order1Open = false;
   trade.order2Open = false;

   for(int bar = startBar - 1; bar > endBar; bar--)
   {
      // Manage existing trades
      if(trade.order1Open || trade.order2Open)
      {
         ManageTrade(sym, bar, spread, trade, balance, peakBalance, stats,
                     tickVal, tickSz, baselineType, sslExitLen);
      }

      if(trade.order1Open || trade.order2Open)
         continue;

      // Evaluate entry
      int signal = EvalEntry(sym, bar, baselineType, sslC1Len, stochK, atrPeriod, allowCont);
      if(signal == 0)
         continue;

      stats.signals++;
      double atr = iATR(sym, PERIOD_D1, atrPeriod, bar);
      if(atr <= 0) continue;

      double openNext = iOpen(sym, PERIOD_D1, bar - 1);
      double entryPrice;
      if(signal == 1)
         entryPrice = openNext + spread;
      else
         entryPrice = openNext;

      double slDist  = InpSLMultiplier * atr;
      double tp1Dist = InpTP1Multiplier * atr;

      double riskAmount = balance * (InpRiskPercent / 100.0);
      double slTicks = slDist / tickSz;
      double riskPerLot = slTicks * tickVal;
      if(riskPerLot <= 0) continue;
      double totalLots = riskAmount / riskPerLot;
      double halfLot = MathFloor(totalLots / 2.0 * 100) / 100.0;
      if(halfLot < 0.01) halfLot = 0.01;

      trade.direction  = signal;
      trade.entryPrice = entryPrice;
      trade.lots1      = halfLot;
      trade.lots2      = halfLot;
      trade.order1Open = true;
      trade.order2Open = true;
      trade.movedToBE  = false;
      trade.signalPnl  = 0;

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
   }

   // Close remaining at end
   if(trade.order1Open || trade.order2Open)
   {
      double lastClose = iClose(sym, PERIOD_D1, endBar);
      double exitPrice;
      if(trade.direction == 1) exitPrice = lastClose;
      else                     exitPrice = lastClose + spread;
      CloseAll(trade, exitPrice, balance, peakBalance, stats, tickVal, tickSz);
   }

   stats.finalBalance = balance;
}

//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar, int baselineType, int sslC1Len,
              int stochK, int atrPeriod, bool allowCont)
{
   double blCurr = GetBL(sym, bar, baselineType);
   double blPrev = GetBL(sym, bar + 1, baselineType);
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
      if(!allowCont) return 0;
      // Continuation: require fresh C1 SSL direction change
      int c1Now  = GetSSL(sym, bar, sslC1Len);
      int c1Prev = GetSSL(sym, bar + 1, sslC1Len);
      if(!(c1Now != c1Prev && c1Now == baselineDir))
         return 0;
   }

   // ATR filter
   double atr = iATR(sym, PERIOD_D1, atrPeriod, bar);
   double dist = MathAbs(closeCurr - blCurr);
   if(dist > InpMaxATRDist * atr) return 0;

   // C1 SSL
   int c1Dir = GetSSL(sym, bar, sslC1Len);
   if(c1Dir != baselineDir) return 0;

   // C2 Stochastic (optimizer only uses stoch since it was proven better)
   int c2Curr = GetStochDir(sym, bar, stochK);
   int c2Prev = GetStochDir(sym, bar + 1, stochK);
   if(c2Curr != baselineDir && c2Prev != baselineDir) return 0;

   // WAE
   if(!CheckWAE(sym, bar, baselineDir)) return 0;

   return baselineDir;
}

//+------------------------------------------------------------------+
double GetBL(string sym, int shift, int blType)
{
   if(blType == 0)
      return iCustom(sym, PERIOD_D1, IND_KAMA, InpKamaPeriod, InpKamaFastMA, InpKamaSlowMA, 0, shift);
   else
      return iCustom(sym, PERIOD_D1, "HMA", InpHmaPeriod, InpHmaDivisor, PRICE_CLOSE, 0, shift);
}

//+------------------------------------------------------------------+
int GetSSL(string sym, int shift, int len)
{
   double hlv = iCustom(sym, PERIOD_D1, IND_SSL,
                          false, 0, 2, len, 0, 3, len, 0, shift);
   if(hlv > 0.5)  return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

//+------------------------------------------------------------------+
int GetSSLExit(string sym, int shift, int len)
{
   double hlv = iCustom(sym, PERIOD_D1, IND_SSL,
                          false, 0, 2, len, 0, 3, len, 0, shift);
   if(hlv > 0.5)  return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

//+------------------------------------------------------------------+
int GetStochDir(string sym, int shift, int kPeriod)
{
   double stoch = iStochastic(sym, PERIOD_D1, kPeriod, InpStochD,
                               InpStochSlowing, MODE_SMA, 0, MODE_MAIN, shift);
   if(stoch > 50.0) return 1;
   if(stoch < 50.0) return -1;
   return 0;
}

//+------------------------------------------------------------------+
bool CheckWAE(string sym, int bar, int direction)
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
void ManageTrade(string sym, int bar, double spread, VTrade &trade,
                  double &balance, double &peakBalance, PairStats &stats,
                  double tickVal, double tickSz, int baselineType, int sslExitLen)
{
   double high  = iHigh(sym, PERIOD_D1, bar);
   double low   = iLow(sym, PERIOD_D1, bar);
   double close = iClose(sym, PERIOD_D1, bar);
   double askHigh  = high + spread;
   double askLow   = low + spread;
   double askClose = close + spread;

   // Opposite baseline cross -> close everything
   double blCurr = GetBL(sym, bar, baselineType);
   double blPrev = GetBL(sym, bar + 1, baselineType);
   double closePrev = iClose(sym, PERIOD_D1, bar + 1);
   bool oppCross = false;
   if(trade.direction == 1 && close < blCurr && closePrev >= blPrev) oppCross = true;
   if(trade.direction == -1 && close > blCurr && closePrev <= blPrev) oppCross = true;

   if(oppCross)
   {
      double exitPrice;
      if(trade.direction == 1) exitPrice = close;
      else                     exitPrice = askClose;
      CloseAll(trade, exitPrice, balance, peakBalance, stats, tickVal, tickSz);
      return;
   }

   // Order 1: TP/SL
   if(trade.order1Open)
   {
      bool tp1Hit = false;
      bool sl1Hit = false;
      double pnl1 = 0;

      if(trade.direction == 1)
      {
         if(high >= trade.tp1) { tp1Hit = true; pnl1 = (trade.tp1 - trade.entryPrice) / tickSz * tickVal * trade.lots1; }
         else if(low <= trade.sl) { sl1Hit = true; pnl1 = (trade.sl - trade.entryPrice) / tickSz * tickVal * trade.lots1; }
      }
      else
      {
         if(askLow <= trade.tp1) { tp1Hit = true; pnl1 = (trade.entryPrice - trade.tp1) / tickSz * tickVal * trade.lots1; }
         else if(askHigh >= trade.sl) { sl1Hit = true; pnl1 = (trade.entryPrice - trade.sl) / tickSz * tickVal * trade.lots1; }
      }

      if(tp1Hit || sl1Hit)
      {
         balance += pnl1;
         trade.signalPnl += pnl1;
         if(pnl1 > 0) stats.grossProfit += pnl1;
         else stats.grossLoss += pnl1;
         trade.order1Open = false;

         if(tp1Hit && trade.order2Open)
         {
            trade.sl = trade.entryPrice;
            trade.movedToBE = true;
         }
      }
   }

   // Order 2: Runner - SL or exit SSL
   if(trade.order2Open)
   {
      bool slHit2 = false;
      if(trade.direction == 1 && low <= trade.sl) slHit2 = true;
      if(trade.direction == -1 && askHigh >= trade.sl) slHit2 = true;

      int exitDir = GetSSLExit(sym, bar, sslExitLen);
      bool exitFlip = false;
      if(trade.direction == 1 && exitDir == -1) exitFlip = true;
      if(trade.direction == -1 && exitDir == 1) exitFlip = true;

      double pnl2 = 0;
      if(slHit2)
      {
         if(trade.direction == 1)
            pnl2 = (trade.sl - trade.entryPrice) / tickSz * tickVal * trade.lots2;
         else
            pnl2 = (trade.entryPrice - trade.sl) / tickSz * tickVal * trade.lots2;
         balance += pnl2;
         trade.signalPnl += pnl2;
         if(pnl2 > 0) stats.grossProfit += pnl2; else stats.grossLoss += pnl2;
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
         if(pnl2 > 0) stats.grossProfit += pnl2; else stats.grossLoss += pnl2;
         trade.order2Open = false;
      }
   }

   // Both closed -> count win/loss
   if(!trade.order1Open && !trade.order2Open)
   {
      if(trade.signalPnl >= 0) stats.wins++;
      else stats.losses++;
   }

   // Drawdown
   if(balance > peakBalance) peakBalance = balance;
   double dd = peakBalance - balance;
   if(dd > stats.maxDD)
   {
      stats.maxDD = dd;
      stats.maxDDPct = (dd / peakBalance) * 100.0;
   }
}

//+------------------------------------------------------------------+
void CloseAll(VTrade &trade, double exitPrice,
               double &balance, double &peakBalance, PairStats &stats,
               double tickVal, double tickSz)
{
   if(trade.order1Open)
   {
      double pnl;
      if(trade.direction == 1) pnl = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots1;
      else                     pnl = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots1;
      balance += pnl; trade.signalPnl += pnl;
      if(pnl > 0) stats.grossProfit += pnl; else stats.grossLoss += pnl;
      trade.order1Open = false;
   }
   if(trade.order2Open)
   {
      double pnl;
      if(trade.direction == 1) pnl = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots2;
      else                     pnl = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots2;
      balance += pnl; trade.signalPnl += pnl;
      if(pnl > 0) stats.grossProfit += pnl; else stats.grossLoss += pnl;
      trade.order2Open = false;
   }
   if(trade.signalPnl >= 0) stats.wins++; else stats.losses++;
   if(balance > peakBalance) peakBalance = balance;
   double dd = peakBalance - balance;
   if(dd > stats.maxDD) { stats.maxDD = dd; stats.maxDDPct = (dd / peakBalance) * 100.0; }
}

//+------------------------------------------------------------------+
// Simple bubble sort by aggregate PF descending
void SortResultsByPF(OptResult &arr[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = 0; j < count - i - 1; j++)
      {
         if(arr[j].aggPF < arr[j + 1].aggPF)
         {
            OptResult tmp = arr[j];
            arr[j] = arr[j + 1];
            arr[j + 1] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
void PrintTopResults(OptResult &results[], int count)
{
   Print("===== TOP ", count, " PARAMETER SETS (by Aggregate PF) =====");
   Print(StringFormat("%4s | %4s | %5s | %5s | %3s | %3s | %4s | %10s | %5s | %5s | %6s",
         "Rank", "BL", "SSL_C1", "SSL_Ex", "StK", "ATR", "Cont", "NetProfit", "PF", "WR%", "MaxDD%"));
   Print("-----|------|--------|--------|-----|-----|------|------------|-------|-------|-------");

   for(int i = 0; i < count; i++)
   {
      OptResult r = results[i];
      string blName = (r.baselineType == 0) ? "KAMA" : "HMA";
      string contStr = r.continuation ? "YES" : "NO";

      Print(StringFormat("%4d | %4s | %6d | %6d | %3d | %3d | %4s | $%9.2f | %5.2f | %5.1f | %5.1f%%",
            i + 1, blName, r.sslC1Len, r.sslExitLen, r.stochK, r.atrPeriod, contStr,
            r.aggNetProfit, r.aggPF, r.avgWinRate, r.worstDD));
   }
}

//+------------------------------------------------------------------+
void WriteOptimizerCSV(OptResult &results[], int count)
{
   string filename = "NNFX_Optimizer_Results.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle, "Rank", "Baseline", "SSL_C1_Len", "SSL_Exit_Len",
             "Stoch_K", "ATR_Period", "Continuation",
             "Agg_NetProfit", "Agg_PF", "Avg_WinRate%", "Worst_MaxDD%", "Total_Signals");

   for(int i = 0; i < count; i++)
   {
      OptResult r = results[i];
      string blName = (r.baselineType == 0) ? "KAMA" : "HMA";
      string contStr = r.continuation ? "YES" : "NO";

      FileWrite(handle, i + 1, blName, r.sslC1Len, r.sslExitLen,
                r.stochK, r.atrPeriod, contStr,
                DoubleToStr(r.aggNetProfit, 2), DoubleToStr(r.aggPF, 2),
                DoubleToStr(r.avgWinRate, 1), DoubleToStr(r.worstDD, 1),
                r.totalSignals);
   }

   FileClose(handle);
   Print("Optimizer results saved to: MQL4/Files/", filename);
}
//+------------------------------------------------------------------+
