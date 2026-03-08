//+------------------------------------------------------------------+
//|                                          NNFX_IndicatorTester.mq4|
//|         Test any indicator in any NNFX slot against all 7 majors |
//|         Winning strategy params are LOCKED — only the tested     |
//|         slot is swapped. Results appended to CSV for comparison.  |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "1.00"
#property strict
#property show_inputs

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_TEST_SLOT
{
   SLOT_BASELINE = 0,  // Baseline (replaces KAMA)
   SLOT_C1       = 1,  // C1 Confirmation (replaces SSL C1)
   SLOT_C2       = 2,  // C2 Confirmation (replaces Stochastic)
   SLOT_VOLUME   = 3,  // Volume (replaces WAE)
   SLOT_EXIT     = 4   // Exit (replaces SSL Exit)
};

enum ENUM_SIGNAL_METHOD
{
   SIG_PRICE_VS_LINE     = 0,  // Price vs Line (baselines)
   SIG_ABOVE_BELOW_ZERO  = 1,  // Above/Below Zero
   SIG_ABOVE_BELOW_LEVEL = 2,  // Above/Below Level (set InpSignalLevel)
   SIG_DIRECTION_BUFFER  = 3,  // Direction Buffer (+1/-1)
   SIG_RISING_FALLING    = 4,  // Rising=Bull, Falling=Bear
   SIG_TWO_BUFFERS       = 5,  // Buffer1 > Buffer2 = Bull
   SIG_VOL_THRESHOLD     = 6,  // Volume: Value > Threshold = Confirmed
   SIG_VOL_DIRECTIONAL   = 7   // Volume: Value > 0 in direction + > Threshold
};

//+------------------------------------------------------------------+
//| TEST INDICATOR INPUTS                                             |
//+------------------------------------------------------------------+
input string           _test_sep_       = "=== Indicator To Test ===";    // ---
input string           InpIndicatorName = "";          // Indicator Name (e.g. "RSI_Custom")
input ENUM_TEST_SLOT   InpTestSlot      = SLOT_C1;     // Slot To Test
input ENUM_SIGNAL_METHOD InpSignalMethod = SIG_ABOVE_BELOW_ZERO; // Signal Method
input int              InpSignalBuffer  = 0;           // Signal Buffer Index
input int              InpSignalBuffer2 = 1;           // Buffer 2 (for TWO_BUFFERS method)
input double           InpSignalLevel   = 50.0;        // Signal Level (for ABOVE_BELOW_LEVEL)
input double           InpVolThreshold  = 0.0;         // Volume Threshold (for VOL methods)
input string           _params_sep_     = "=== Indicator Parameters ==="; // ---
input int              InpParamCount    = 0;           // Number of Params to Pass (0-8)
input double           InpParam1        = 0;  // Param 1
input double           InpParam2        = 0;  // Param 2
input double           InpParam3        = 0;  // Param 3
input double           InpParam4        = 0;  // Param 4
input double           InpParam5        = 0;  // Param 5
input double           InpParam6        = 0;  // Param 6
input double           InpParam7        = 0;  // Param 7
input double           InpParam8        = 0;  // Param 8

//+------------------------------------------------------------------+
//| LOCKED STRATEGY PARAMETERS (do not change)                        |
//+------------------------------------------------------------------+
// Baseline: KAMA
#define LOCKED_KAMA_PERIOD     10
#define LOCKED_KAMA_FAST       2.0
#define LOCKED_KAMA_SLOW       30.0
// C1: SSL Channel length 25
#define LOCKED_SSL_C1_LEN      25
// C2: Stochastic K=14, D=3, Slowing=3
#define LOCKED_STOCH_K         14
#define LOCKED_STOCH_D         3
#define LOCKED_STOCH_SLOWING   3
// Volume: WAE 150/30/15/15
#define LOCKED_WAE_SENSITIVE   150
#define LOCKED_WAE_DEADZONE    30
#define LOCKED_WAE_EXPLPOWER   15
#define LOCKED_WAE_TRENDPWR    15
// Exit: SSL Channel length 5
#define LOCKED_SSL_EXIT_LEN    5
// ATR / Risk
#define LOCKED_ATR_PERIOD      7
#define LOCKED_SL_MULT         1.5
#define LOCKED_TP1_MULT        1.0
#define LOCKED_MAX_ATR_DIST    1.0
#define LOCKED_RISK_PCT        2.0
#define LOCKED_START_BAL       10000.0

#define IND_KAMA "KAMA"
#define IND_SSL  "SSL_Channel"
#define IND_WAE  "Waddah_Attar_Explosion"

//--- Trade tracking
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
   string symbol;
   int    signals;
   int    wins;
   int    losses;
   int    longSignals;
   int    longWins;
   int    shortSignals;
   int    shortWins;
   double grossProfit;
   double grossLoss;
   double maxDD;
   double maxDDPct;
   double finalBalance;
};

//--- Spread helper
int GetTypicalSpread(string sym)
{
   if(sym == "EURUSD") return 14;
   if(sym == "GBPUSD") return 18;
   if(sym == "USDJPY") return 14;
   if(sym == "USDCHF") return 17;
   if(sym == "AUDUSD") return 14;
   if(sym == "NZDUSD") return 20;
   if(sym == "USDCAD") return 20;
   return 20;
}

//+------------------------------------------------------------------+
void OnStart()
{
   if(StringLen(InpIndicatorName) == 0)
   {
      Print("ERROR: No indicator name specified. Set InpIndicatorName.");
      Alert("Set InpIndicatorName before running.");
      return;
   }

   string pairs[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD", "USDCAD"};
   int numPairs = ArraySize(pairs);

   string slotName = "";
   switch(InpTestSlot)
   {
      case SLOT_BASELINE: slotName = "Baseline"; break;
      case SLOT_C1:       slotName = "C1";       break;
      case SLOT_C2:       slotName = "C2";       break;
      case SLOT_VOLUME:   slotName = "Volume";   break;
      case SLOT_EXIT:     slotName = "Exit";     break;
   }

   Print("=== NNFX Indicator Tester ===");
   Print("Testing: ", InpIndicatorName, " in ", slotName, " slot");
   Print("Signal method: ", EnumToString(InpSignalMethod), " | Buffer: ", InpSignalBuffer);
   Print("Pairs: 7 majors | Period: 2015-2025 D1");

   PairStats results[];
   ArrayResize(results, numPairs);

   datetime startDate = D'2015.01.01';
   datetime endDate   = D'2025.01.01';

   for(int p = 0; p < numPairs; p++)
   {
      string sym = pairs[p];
      results[p].symbol = sym;

      double tickVal  = MarketInfo(sym, MODE_TICKVALUE);
      double tickSz   = MarketInfo(sym, MODE_TICKSIZE);
      double pointVal = MarketInfo(sym, MODE_POINT);
      int spreadPts   = GetTypicalSpread(sym);
      double spread   = spreadPts * pointVal;

      if(tickVal <= 0 || tickSz <= 0 || pointVal <= 0)
      {
         Print("WARNING: Cannot get market info for ", sym, ". Skipping.");
         continue;
      }

      int startBar = iBarShift(sym, PERIOD_D1, startDate, false);
      int endBar   = iBarShift(sym, PERIOD_D1, endDate, false);
      if(endBar < 0) endBar = 0;
      if(startBar < 0) startBar = iBars(sym, PERIOD_D1) - 1;

      Print("--- ", sym, " (bars ", startBar, " to ", endBar, ") ---");
      RunBacktest(sym, startBar, endBar, spread, tickVal, tickSz, results[p]);
      PrintPairResult(results[p]);
   }

   // Aggregate
   double totalNet = 0, totalGP = 0, totalGL = 0;
   int totalSig = 0, totalWins = 0;
   double worstDD = 0;
   for(int i = 0; i < numPairs; i++)
   {
      totalNet += (results[i].grossProfit + results[i].grossLoss);
      totalGP  += results[i].grossProfit;
      totalGL  += results[i].grossLoss;
      totalSig += results[i].signals;
      totalWins+= results[i].wins;
      if(results[i].maxDDPct > worstDD) worstDD = results[i].maxDDPct;
   }
   double aggPF = (totalGL != 0) ? MathAbs(totalGP / totalGL) : 0;
   double avgWR = (totalSig > 0) ? ((double)totalWins / totalSig * 100.0) : 0;

   Print("===== AGGREGATE =====");
   Print("Net: $", DoubleToStr(totalNet, 2), " | PF: ", DoubleToStr(aggPF, 2),
         " | WR: ", DoubleToStr(avgWR, 1), "% | Worst DD: ", DoubleToStr(worstDD, 1), "%");

   // Append to CSV log
   AppendToCSV(results, numPairs, slotName, totalNet, aggPF, avgWR, worstDD, totalSig);

   Print("=== Test Complete ===");
   Alert("NNFX Indicator Test done! Results in NNFX_Indicator_Tests.csv");
}

//+------------------------------------------------------------------+
void RunBacktest(string sym, int startBar, int endBar, double spread,
                  double tickVal, double tickSz, PairStats &stats)
{
   stats.signals = 0; stats.wins = 0; stats.losses = 0;
   stats.longSignals = 0; stats.longWins = 0;
   stats.shortSignals = 0; stats.shortWins = 0;
   stats.grossProfit = 0; stats.grossLoss = 0;
   stats.maxDD = 0; stats.maxDDPct = 0;
   stats.finalBalance = LOCKED_START_BAL;

   double balance = LOCKED_START_BAL;
   double peak    = LOCKED_START_BAL;

   VTrade trade;
   trade.order1Open = false;
   trade.order2Open = false;

   for(int bar = startBar - 1; bar > endBar; bar--)
   {
      if(trade.order1Open || trade.order2Open)
         ManageTrade(sym, bar, spread, trade, balance, peak, stats, tickVal, tickSz);

      if(trade.order1Open || trade.order2Open)
         continue;

      int signal = EvaluateEntry(sym, bar);
      if(signal == 0) continue;

      stats.signals++;
      if(signal == 1) stats.longSignals++;
      else stats.shortSignals++;

      double atr = iATR(sym, PERIOD_D1, LOCKED_ATR_PERIOD, bar);
      if(atr <= 0) continue;

      double openNext = iOpen(sym, PERIOD_D1, bar - 1);
      double entryPrice = (signal == 1) ? openNext + spread : openNext;
      double slDist  = LOCKED_SL_MULT * atr;
      double tp1Dist = LOCKED_TP1_MULT * atr;

      double riskAmount = balance * (LOCKED_RISK_PCT / 100.0);
      double slTicks = slDist / tickSz;
      double riskPerLot = slTicks * tickVal;
      if(riskPerLot <= 0) continue;
      double halfLot = MathFloor((riskAmount / riskPerLot) / 2.0 * 100) / 100.0;
      if(halfLot < 0.01) halfLot = 0.01;

      trade.direction  = signal;
      trade.entryPrice = entryPrice;
      trade.lots1 = halfLot; trade.lots2 = halfLot;
      trade.order1Open = true; trade.order2Open = true;
      trade.movedToBE = false; trade.signalPnl = 0;

      if(signal == 1)
      { trade.sl = entryPrice - slDist; trade.tp1 = entryPrice + tp1Dist; }
      else
      { trade.sl = entryPrice + slDist; trade.tp1 = entryPrice - tp1Dist; }
   }

   // Close remaining
   if(trade.order1Open || trade.order2Open)
   {
      double lastClose = iClose(sym, PERIOD_D1, endBar);
      double exitPrice = (trade.direction == 1) ? lastClose : lastClose + spread;
      ForceClose(trade, exitPrice, balance, peak, stats, tickVal, tickSz);
   }
   stats.finalBalance = balance;
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION — uses locked indicators + test indicator        |
//+------------------------------------------------------------------+
int EvaluateEntry(string sym, int bar)
{
   // 1. Baseline direction + cross
   double blCurr, blPrev;
   if(InpTestSlot == SLOT_BASELINE)
   {
      blCurr = GetTestIndicatorValue(sym, bar);
      blPrev = GetTestIndicatorValue(sym, bar + 1);
   }
   else
   {
      blCurr = iCustom(sym, PERIOD_D1, IND_KAMA, LOCKED_KAMA_PERIOD, LOCKED_KAMA_FAST, LOCKED_KAMA_SLOW, 0, bar);
      blPrev = iCustom(sym, PERIOD_D1, IND_KAMA, LOCKED_KAMA_PERIOD, LOCKED_KAMA_FAST, LOCKED_KAMA_SLOW, 0, bar + 1);
   }
   if(blCurr == 0 || blPrev == 0) return 0;

   double closeCurr = iClose(sym, PERIOD_D1, bar);
   double closePrev = iClose(sym, PERIOD_D1, bar + 1);

   int baselineDir = 0;
   if(closeCurr > blCurr) baselineDir = 1;
   else if(closeCurr < blCurr) baselineDir = -1;
   if(baselineDir == 0) return 0;

   // For baseline slot with non-line methods, interpret direction differently
   if(InpTestSlot == SLOT_BASELINE && InpSignalMethod != SIG_PRICE_VS_LINE)
      baselineDir = InterpretDirection(sym, bar);

   bool cross = false;
   if(InpTestSlot == SLOT_BASELINE && InpSignalMethod != SIG_PRICE_VS_LINE)
   {
      // For non-line baselines, cross = direction changed
      int dirPrev = InterpretDirection(sym, bar + 1);
      cross = (baselineDir != 0 && baselineDir != dirPrev);
   }
   else
   {
      if(baselineDir == 1 && closePrev <= blPrev) cross = true;
      if(baselineDir == -1 && closePrev >= blPrev) cross = true;
   }
   if(!cross) return 0;

   // 2. ATR filter
   double atr = iATR(sym, PERIOD_D1, LOCKED_ATR_PERIOD, bar);
   if(InpTestSlot == SLOT_BASELINE && InpSignalMethod == SIG_PRICE_VS_LINE)
   {
      double dist = MathAbs(closeCurr - blCurr);
      if(dist > LOCKED_MAX_ATR_DIST * atr) return 0;
   }

   // 3. C1
   int c1Dir;
   if(InpTestSlot == SLOT_C1)
      c1Dir = InterpretDirection(sym, bar);
   else
      c1Dir = GetLockedSSL_C1(sym, bar);
   if(c1Dir != baselineDir) return 0;

   // 4. C2
   bool c2ok = false;
   if(InpTestSlot == SLOT_C2)
   {
      int c2Curr = InterpretDirection(sym, bar);
      int c2Prev = InterpretDirection(sym, bar + 1);
      c2ok = (c2Curr == baselineDir || c2Prev == baselineDir);
   }
   else
   {
      int c2Curr = GetLockedStoch(sym, bar);
      int c2Prev = GetLockedStoch(sym, bar + 1);
      c2ok = (c2Curr == baselineDir || c2Prev == baselineDir);
   }
   if(!c2ok) return 0;

   // 5. Volume
   bool volOK = false;
   if(InpTestSlot == SLOT_VOLUME)
      volOK = InterpretVolume(sym, bar, baselineDir);
   else
      volOK = GetLockedWAE(sym, bar, baselineDir);
   if(!volOK) return 0;

   return baselineDir;
}

//+------------------------------------------------------------------+
//| GET TEST INDICATOR VALUE (generic iCustom with N params)          |
//+------------------------------------------------------------------+
double GetTestIndicatorValue(string sym, int shift)
{
   return GetCustom(sym, InpIndicatorName, InpSignalBuffer, shift);
}

double GetTestIndicatorValue2(string sym, int shift)
{
   return GetCustom(sym, InpIndicatorName, InpSignalBuffer2, shift);
}

double GetCustom(string sym, string name, int buf, int shift)
{
   switch(InpParamCount)
   {
      case 0:  return iCustom(sym, PERIOD_D1, name, buf, shift);
      case 1:  return iCustom(sym, PERIOD_D1, name, InpParam1, buf, shift);
      case 2:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, buf, shift);
      case 3:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, InpParam3, buf, shift);
      case 4:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, InpParam3, InpParam4, buf, shift);
      case 5:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, buf, shift);
      case 6:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpParam6, buf, shift);
      case 7:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpParam6, InpParam7, buf, shift);
      case 8:  return iCustom(sym, PERIOD_D1, name, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpParam6, InpParam7, InpParam8, buf, shift);
      default: return iCustom(sym, PERIOD_D1, name, buf, shift);
   }
}

//+------------------------------------------------------------------+
//| INTERPRET DIRECTION from test indicator based on signal method    |
//| Returns: +1 bull, -1 bear, 0 neutral                             |
//+------------------------------------------------------------------+
int InterpretDirection(string sym, int shift)
{
   double val = GetTestIndicatorValue(sym, shift);

   switch(InpSignalMethod)
   {
      case SIG_PRICE_VS_LINE:
      {
         double close = iClose(sym, PERIOD_D1, shift);
         if(close > val) return 1;
         if(close < val) return -1;
         return 0;
      }
      case SIG_ABOVE_BELOW_ZERO:
         if(val > 0) return 1;
         if(val < 0) return -1;
         return 0;

      case SIG_ABOVE_BELOW_LEVEL:
         if(val > InpSignalLevel) return 1;
         if(val < InpSignalLevel) return -1;
         return 0;

      case SIG_DIRECTION_BUFFER:
         if(val > 0.5)  return 1;
         if(val < -0.5) return -1;
         return 0;

      case SIG_RISING_FALLING:
      {
         double prev = GetTestIndicatorValue(sym, shift + 1);
         if(val > prev) return 1;
         if(val < prev) return -1;
         return 0;
      }
      case SIG_TWO_BUFFERS:
      {
         double val2 = GetTestIndicatorValue2(sym, shift);
         if(val > val2) return 1;
         if(val < val2) return -1;
         return 0;
      }
      default:
         return 0;
   }
}

//+------------------------------------------------------------------+
//| INTERPRET VOLUME from test indicator                              |
//| Returns: true if volume confirms                                  |
//+------------------------------------------------------------------+
bool InterpretVolume(string sym, int shift, int direction)
{
   double val = GetTestIndicatorValue(sym, shift);
   double valPrev = GetTestIndicatorValue(sym, shift + 1);

   switch(InpSignalMethod)
   {
      case SIG_VOL_THRESHOLD:
         // Simple: value above threshold = volume confirmed (direction-agnostic)
         return (val > InpVolThreshold && val > valPrev);

      case SIG_VOL_DIRECTIONAL:
      {
         // Value > threshold + matches direction
         // Positive = bullish volume, Negative = bearish volume
         if(direction == 1 && val > InpVolThreshold && val > valPrev) return true;
         if(direction == -1 && val < -InpVolThreshold && val < valPrev) return true;
         return false;
      }
      case SIG_ABOVE_BELOW_ZERO:
         // Treat as: |value| > threshold and direction matches sign
         if(direction == 1 && val > InpVolThreshold) return true;
         if(direction == -1 && val < -InpVolThreshold) return true;
         return false;

      default:
         // Fallback: any positive value = confirmed
         return (val > InpVolThreshold);
   }
}

//+------------------------------------------------------------------+
//| LOCKED INDICATOR FUNCTIONS (winning strategy)                     |
//+------------------------------------------------------------------+
int GetLockedSSL_C1(string sym, int shift)
{
   double hlv = iCustom(sym, PERIOD_D1, IND_SSL,
                          false, 0, 2, LOCKED_SSL_C1_LEN, 0, 3, LOCKED_SSL_C1_LEN, 0, shift);
   if(hlv > 0.5)  return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

int GetLockedSSL_Exit(string sym, int shift)
{
   double hlv = iCustom(sym, PERIOD_D1, IND_SSL,
                          false, 0, 2, LOCKED_SSL_EXIT_LEN, 0, 3, LOCKED_SSL_EXIT_LEN, 0, shift);
   if(hlv > 0.5)  return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

int GetLockedStoch(string sym, int shift)
{
   double stoch = iStochastic(sym, PERIOD_D1, LOCKED_STOCH_K, LOCKED_STOCH_D,
                               LOCKED_STOCH_SLOWING, MODE_SMA, 0, MODE_MAIN, shift);
   if(stoch > 50.0) return 1;
   if(stoch < 50.0) return -1;
   return 0;
}

bool GetLockedWAE(string sym, int shift, int direction)
{
   double green     = iCustom(sym, PERIOD_D1, IND_WAE, LOCKED_WAE_SENSITIVE,
                               LOCKED_WAE_DEADZONE, LOCKED_WAE_EXPLPOWER, LOCKED_WAE_TRENDPWR,
                               true, 500, true, true, true, true, 0, shift);
   double red       = iCustom(sym, PERIOD_D1, IND_WAE, LOCKED_WAE_SENSITIVE,
                               LOCKED_WAE_DEADZONE, LOCKED_WAE_EXPLPOWER, LOCKED_WAE_TRENDPWR,
                               true, 500, true, true, true, true, 1, shift);
   double explosion = iCustom(sym, PERIOD_D1, IND_WAE, LOCKED_WAE_SENSITIVE,
                               LOCKED_WAE_DEADZONE, LOCKED_WAE_EXPLPOWER, LOCKED_WAE_TRENDPWR,
                               true, 500, true, true, true, true, 2, shift);
   double deadZone  = iCustom(sym, PERIOD_D1, IND_WAE, LOCKED_WAE_SENSITIVE,
                               LOCKED_WAE_DEADZONE, LOCKED_WAE_EXPLPOWER, LOCKED_WAE_TRENDPWR,
                               true, 500, true, true, true, true, 3, shift);
   double greenPrev = iCustom(sym, PERIOD_D1, IND_WAE, LOCKED_WAE_SENSITIVE,
                               LOCKED_WAE_DEADZONE, LOCKED_WAE_EXPLPOWER, LOCKED_WAE_TRENDPWR,
                               true, 500, true, true, true, true, 0, shift + 1);
   double redPrev   = iCustom(sym, PERIOD_D1, IND_WAE, LOCKED_WAE_SENSITIVE,
                               LOCKED_WAE_DEADZONE, LOCKED_WAE_EXPLPOWER, LOCKED_WAE_TRENDPWR,
                               true, 500, true, true, true, true, 1, shift + 1);

   if(explosion <= deadZone) return false;
   bool trendMatch = false;
   bool trendGrow  = false;
   if(direction == 1 && green > 0)  { trendMatch = true; trendGrow = (green > greenPrev); }
   if(direction == -1 && red > 0)   { trendMatch = true; trendGrow = (red > redPrev); }
   return (trendMatch && trendGrow);
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (identical to multi-backtester)                  |
//+------------------------------------------------------------------+
void ManageTrade(string sym, int bar, double spread, VTrade &trade,
                  double &balance, double &peak, PairStats &stats,
                  double tickVal, double tickSz)
{
   double high  = iHigh(sym, PERIOD_D1, bar);
   double low   = iLow(sym, PERIOD_D1, bar);
   double close = iClose(sym, PERIOD_D1, bar);
   double askHigh = high + spread, askLow = low + spread, askClose = close + spread;

   // Opposite baseline cross -> close all
   double blCurr, blPrev;
   if(InpTestSlot == SLOT_BASELINE)
   {
      blCurr = GetTestIndicatorValue(sym, bar);
      blPrev = GetTestIndicatorValue(sym, bar + 1);
   }
   else
   {
      blCurr = iCustom(sym, PERIOD_D1, IND_KAMA, LOCKED_KAMA_PERIOD, LOCKED_KAMA_FAST, LOCKED_KAMA_SLOW, 0, bar);
      blPrev = iCustom(sym, PERIOD_D1, IND_KAMA, LOCKED_KAMA_PERIOD, LOCKED_KAMA_FAST, LOCKED_KAMA_SLOW, 0, bar + 1);
   }
   double closePrev = iClose(sym, PERIOD_D1, bar + 1);

   bool oppCross = false;
   if(InpTestSlot == SLOT_BASELINE && InpSignalMethod != SIG_PRICE_VS_LINE)
   {
      int dirNow  = InterpretDirection(sym, bar);
      int dirPrev = InterpretDirection(sym, bar + 1);
      if(trade.direction == 1 && dirNow == -1 && dirPrev != -1) oppCross = true;
      if(trade.direction == -1 && dirNow == 1 && dirPrev != 1) oppCross = true;
   }
   else
   {
      if(trade.direction == 1 && close < blCurr && closePrev >= blPrev) oppCross = true;
      if(trade.direction == -1 && close > blCurr && closePrev <= blPrev) oppCross = true;
   }

   if(oppCross)
   {
      double exitPrice = (trade.direction == 1) ? close : askClose;
      ForceClose(trade, exitPrice, balance, peak, stats, tickVal, tickSz);
      return;
   }

   // Order 1: TP/SL
   if(trade.order1Open)
   {
      bool tp1Hit = false, sl1Hit = false;
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
         balance += pnl1; trade.signalPnl += pnl1;
         if(pnl1 > 0) stats.grossProfit += pnl1; else stats.grossLoss += pnl1;
         trade.order1Open = false;
         if(tp1Hit && trade.order2Open) { trade.sl = trade.entryPrice; trade.movedToBE = true; }
      }
   }

   // Order 2: Runner
   if(trade.order2Open)
   {
      bool slHit2 = false;
      if(trade.direction == 1 && low <= trade.sl) slHit2 = true;
      if(trade.direction == -1 && askHigh >= trade.sl) slHit2 = true;

      // Exit signal
      int exitDir;
      if(InpTestSlot == SLOT_EXIT)
         exitDir = InterpretDirection(sym, bar);
      else
         exitDir = GetLockedSSL_Exit(sym, bar);

      bool exitFlip = false;
      if(trade.direction == 1 && exitDir == -1) exitFlip = true;
      if(trade.direction == -1 && exitDir == 1) exitFlip = true;

      double pnl2 = 0;
      if(slHit2)
      {
         if(trade.direction == 1) pnl2 = (trade.sl - trade.entryPrice) / tickSz * tickVal * trade.lots2;
         else pnl2 = (trade.entryPrice - trade.sl) / tickSz * tickVal * trade.lots2;
         balance += pnl2; trade.signalPnl += pnl2;
         if(pnl2 > 0) stats.grossProfit += pnl2; else stats.grossLoss += pnl2;
         trade.order2Open = false;
      }
      else if(exitFlip)
      {
         double exitPrice = (trade.direction == 1) ? close : askClose;
         if(trade.direction == 1) pnl2 = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots2;
         else pnl2 = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots2;
         balance += pnl2; trade.signalPnl += pnl2;
         if(pnl2 > 0) stats.grossProfit += pnl2; else stats.grossLoss += pnl2;
         trade.order2Open = false;
      }
   }

   // Both closed
   if(!trade.order1Open && !trade.order2Open)
   {
      if(trade.signalPnl >= 0)
      { stats.wins++; if(trade.direction == 1) stats.longWins++; else stats.shortWins++; }
      else stats.losses++;
   }

   // Drawdown
   if(balance > peak) peak = balance;
   double dd = peak - balance;
   if(dd > stats.maxDD) { stats.maxDD = dd; stats.maxDDPct = (dd / peak) * 100.0; }
}

//+------------------------------------------------------------------+
void ForceClose(VTrade &trade, double exitPrice,
                 double &balance, double &peak, PairStats &stats,
                 double tickVal, double tickSz)
{
   if(trade.order1Open)
   {
      double pnl;
      if(trade.direction == 1) pnl = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots1;
      else pnl = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots1;
      balance += pnl; trade.signalPnl += pnl;
      if(pnl > 0) stats.grossProfit += pnl; else stats.grossLoss += pnl;
      trade.order1Open = false;
   }
   if(trade.order2Open)
   {
      double pnl;
      if(trade.direction == 1) pnl = (exitPrice - trade.entryPrice) / tickSz * tickVal * trade.lots2;
      else pnl = (trade.entryPrice - exitPrice) / tickSz * tickVal * trade.lots2;
      balance += pnl; trade.signalPnl += pnl;
      if(pnl > 0) stats.grossProfit += pnl; else stats.grossLoss += pnl;
      trade.order2Open = false;
   }
   if(trade.signalPnl >= 0)
   { stats.wins++; if(trade.direction == 1) stats.longWins++; else stats.shortWins++; }
   else stats.losses++;

   if(balance > peak) peak = balance;
   double dd = peak - balance;
   if(dd > stats.maxDD) { stats.maxDD = dd; stats.maxDDPct = (dd / peak) * 100.0; }
}

//+------------------------------------------------------------------+
void PrintPairResult(PairStats &r)
{
   double pf = (r.grossLoss != 0) ? MathAbs(r.grossProfit / r.grossLoss) : 0;
   double net = r.grossProfit + r.grossLoss;
   double wr = (r.signals > 0) ? ((double)r.wins / r.signals * 100.0) : 0;
   double lwr = (r.longSignals > 0) ? ((double)r.longWins / r.longSignals * 100.0) : 0;
   double swr = (r.shortSignals > 0) ? ((double)r.shortWins / r.shortSignals * 100.0) : 0;

   Print(r.symbol, ": Sig=", r.signals, " WR=", DoubleToStr(wr, 1), "%",
         " (L:", DoubleToStr(lwr, 1), "% S:", DoubleToStr(swr, 1), "%)",
         " Net=$", DoubleToStr(net, 2), " PF=", DoubleToStr(pf, 2),
         " DD=", DoubleToStr(r.maxDDPct, 1), "%");
}

//+------------------------------------------------------------------+
void AppendToCSV(PairStats &results[], int numPairs, string slotName,
                  double totalNet, double aggPF, double avgWR, double worstDD, int totalSig)
{
   string filename = "NNFX_Indicator_Tests.csv";
   bool fileExists = false;

   // Check if file exists by trying to open for read
   int testHandle = FileOpen(filename, FILE_READ | FILE_CSV);
   if(testHandle >= 0) { fileExists = true; FileClose(testHandle); }

   int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   // Write header if new file
   if(!fileExists)
   {
      FileWrite(handle, "Date", "Indicator", "Slot", "SignalMethod", "Buffer", "Params",
                "EURUSD_PF", "GBPUSD_PF", "USDJPY_PF", "USDCHF_PF", "AUDUSD_PF", "NZDUSD_PF", "USDCAD_PF",
                "Agg_NetProfit", "Agg_PF", "Avg_WR%", "Worst_DD%", "Total_Signals");
   }

   // Seek to end
   FileSeek(handle, 0, SEEK_END);

   // Build params string
   string paramStr = "";
   for(int i = 1; i <= InpParamCount; i++)
   {
      double pv = 0;
      switch(i)
      {
         case 1: pv = InpParam1; break; case 2: pv = InpParam2; break;
         case 3: pv = InpParam3; break; case 4: pv = InpParam4; break;
         case 5: pv = InpParam5; break; case 6: pv = InpParam6; break;
         case 7: pv = InpParam7; break; case 8: pv = InpParam8; break;
      }
      if(i > 1) paramStr += "/";
      paramStr += DoubleToStr(pv, 2);
   }
   if(InpParamCount == 0) paramStr = "default";

   // Per-pair PFs
   string pairPFs = "";
   double pfArr[];
   ArrayResize(pfArr, numPairs);
   for(int i = 0; i < numPairs; i++)
      pfArr[i] = (results[i].grossLoss != 0) ? MathAbs(results[i].grossProfit / results[i].grossLoss) : 0;

   FileWrite(handle, TimeToStr(TimeCurrent(), TIME_DATE),
             InpIndicatorName, slotName, EnumToString(InpSignalMethod),
             InpSignalBuffer, paramStr,
             DoubleToStr(pfArr[0], 2), DoubleToStr(pfArr[1], 2), DoubleToStr(pfArr[2], 2),
             DoubleToStr(pfArr[3], 2), DoubleToStr(pfArr[4], 2), DoubleToStr(pfArr[5], 2),
             DoubleToStr(pfArr[6], 2),
             DoubleToStr(totalNet, 2), DoubleToStr(aggPF, 2),
             DoubleToStr(avgWR, 1), DoubleToStr(worstDD, 1), totalSig);

   FileClose(handle);
   Print("Results appended to: MQL4/Files/", filename);
}
//+------------------------------------------------------------------+
