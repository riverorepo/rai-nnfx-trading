//+------------------------------------------------------------------+
//|                                         NNFX_H1_AccurateBT.mq4  |
//|  High-accuracy validation: M15 sub-bar SL/TP resolution,        |
//|  time-of-day spread modeling, slippage, OOS split                |
//|  Outputs: Trades CSV, Summary CSV, Equity CSV                    |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property strict
#property show_inputs

//+------------------------------------------------------------------+
//| BASE INDICATOR ENUM                                              |
//+------------------------------------------------------------------+
enum ENUM_BASE_IND
{
   BASE_SUPERTREND  = 0,
   BASE_RANGEFILTER = 1,
   BASE_HALFTREND   = 2,
   BASE_MAMA        = 3,
   BASE_DONCHIAN    = 4,
   BASE_KELTNER     = 5,
   BASE_T3          = 6,
   BASE_MCGINLEY    = 7,
   BASE_JMA         = 8,
   BASE_SQUEEZE     = 9,
   BASE_NONE        = 10
};

enum ENUM_SPREAD_MODE
{
   SPREAD_FIXED        = 0,  // Fixed (typical spread)
   SPREAD_TIME_ADJ     = 1,  // Time-of-day adjusted
   SPREAD_WORST_CASE   = 2   // Worst case (2x typical)
};

enum ENUM_SUB_TF
{
   SUB_M15 = 0,  // M15 (4x resolution)
   SUB_M5  = 1   // M5 (12x resolution)
};

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
// Strategy slots — set from ParamOptimizer winner
input ENUM_BASE_IND InpHTF      = BASE_MCGINLEY;    // Slot 1: HTF Filter
input ENUM_BASE_IND InpEntry    = BASE_KELTNER;     // Slot 2: Entry Trigger
input ENUM_BASE_IND InpConfirm  = BASE_T3;           // Slot 3: Confirmation (ComboSweep winner)
input ENUM_BASE_IND InpVolume   = BASE_NONE;         // Slot 4: Volume
input ENUM_BASE_IND InpExit     = BASE_RANGEFILTER;  // Slot 5: Exit (ComboSweep winner)

// HTF params
input double InpHTF_P1    = 14;     // HTF Param 1
input double InpHTF_P2    = 0.6;    // HTF Param 2
input double InpHTF_P3    = 0;      // HTF Param 3
// Entry params
input double InpEnt_P1    = 20;     // Entry Param 1
input double InpEnt_P2    = 20;     // Entry Param 2
input double InpEnt_P3    = 1.5;    // Entry Param 3
// Confirm params (T3: Period, VolumeFactor)
input double InpConf_P1   = 8;      // Confirm Param 1 (T3 Period)
input double InpConf_P2   = 0.7;    // Confirm Param 2 (T3 VolFactor)
input double InpConf_P3   = 0;      // Confirm Param 3
input double InpConf_P4   = 0;      // Confirm Param 4
// Exit params (RangeFilter: Period, Multiplier)
input double InpEx_P1     = 20;     // Exit Param 1 (RangeFilter Period)
input double InpEx_P2     = 2.0;    // Exit Param 2 (RangeFilter Mult)
input double InpEx_P3     = 0;      // Exit Param 3

// Trade management
input double InpSLMult       = 1.0;    // Stop Loss (x ATR)
input double InpTP1Mult      = 1.5;    // Take Profit (x ATR)
input double InpRiskPct      = 5.0;    // Risk % per trade
input double InpStartBalance = 10000;  // Starting Balance ($)
input int    InpATRPeriod    = 14;     // ATR Period

// Accuracy settings
input ENUM_SPREAD_MODE InpSpreadMode = SPREAD_TIME_ADJ; // Spread Model
input int    InpSlippage     = 2;      // Slippage (points): 0=ideal, 2=typical, 5=stress
input ENUM_SUB_TF InpSubTF   = SUB_M15; // Sub-bar timeframe
input double InpOOSPct       = 20.0;   // Out-of-sample % (last N% of data)

// Pairs
input string InpPairs = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,NZDUSD,USDCAD,EURJPY,GBPJPY,EURGBP,AUDJPY";

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define IND_SUPERTREND   "Supertrend"
#define IND_RANGEFILTER  "RangeFilter"
#define IND_HALFTREND    "HalfTrend"
#define IND_MAMA         "Ehlers_MAMA"
#define IND_DONCHIAN     "DonchianChannel"
#define IND_KELTNER      "KeltnerChannel"
#define IND_T3           "T3_MA"
#define IND_MCGINLEY     "McGinley_Dynamic"
#define IND_JMA_NAME     "JMA"
#define IND_SQUEEZE      "SqueezeMomentum"

//+------------------------------------------------------------------+
//| STRUCTS                                                           |
//+------------------------------------------------------------------+
struct VTrade
{
   int      dir;
   double   entry, sl, tp1, lots1, lots2;
   bool     o1Open, o2Open, movedBE;
   double   pnl;
   datetime openTime;
   double   rawSpread;     // spread at entry
};

struct TradeRecord
{
   datetime openTime, closeTime;
   string   pair;
   int      dir;
   double   entry, exitPrice, pnl, balAfter;
   double   spreadUsed, slipUsed;
   bool     ambiguous;     // both SL+TP in range on same sub-bar
   string   closeReason;   // "TP1","SL","HTF_FLIP","EXIT_FLIP","SL_BE","END"
};

struct PairStats
{
   int    trades, wins, losses;
   double gp, gl, pf, wr;
   double maxDD, maxDDPct;
   double endBal;
   int    ambiguousCount;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string       g_pairs[];
int          g_pairCount;
TradeRecord  g_trades[];
int          g_tradeCount;

int GetTypicalSpreadPips(string s)
{
   if(s=="EURUSD") return 14; if(s=="GBPUSD") return 18; if(s=="USDJPY") return 14;
   if(s=="USDCHF") return 17; if(s=="AUDUSD") return 14; if(s=="NZDUSD") return 20;
   if(s=="USDCAD") return 20; if(s=="EURJPY") return 22; if(s=="GBPJPY") return 30;
   if(s=="EURGBP") return 18; if(s=="AUDJPY") return 22; return 20;
}

// Time-of-day spread multiplier (GMT hour)
double SpreadMultiplier(int gmtHour)
{
   if(gmtHour >= 23 || gmtHour == 0) return 2.0;   // Rollover
   if(gmtHour >= 1 && gmtHour <= 6)  return 1.5;   // Asian early
   if(gmtHour >= 7 && gmtHour <= 11) return 0.8;   // London
   if(gmtHour >= 12 && gmtHour <= 16) return 0.7;  // NY overlap
   if(gmtHour >= 17 && gmtHour <= 22) return 1.2;  // NY afternoon
   return 1.0;
}

double GetSpread(string sym, datetime barTime)
{
   double pointVal = MarketInfo(sym, MODE_POINT);
   int basePips = GetTypicalSpreadPips(sym);
   double baseSpread = basePips * pointVal;

   switch(InpSpreadMode)
   {
      case SPREAD_FIXED:
         return baseSpread;
      case SPREAD_TIME_ADJ:
      {
         int hour = TimeHour(barTime);
         return baseSpread * SpreadMultiplier(hour);
      }
      case SPREAD_WORST_CASE:
         return baseSpread * 2.0;
      default:
         return baseSpread;
   }
}

double GetSlippage(string sym)
{
   return InpSlippage * MarketInfo(sym, MODE_POINT);
}

void ParsePairs()
{
   string temp = InpPairs;
   g_pairCount = 0;
   ArrayResize(g_pairs, 20);
   int pos;
   while((pos = StringFind(temp, ",")) >= 0)
   {
      string p = StringTrimLeft(StringTrimRight(StringSubstr(temp, 0, pos)));
      if(StringLen(p) > 0) { g_pairs[g_pairCount] = p; g_pairCount++; }
      temp = StringSubstr(temp, pos + 1);
   }
   temp = StringTrimLeft(StringTrimRight(temp));
   if(StringLen(temp) > 0) { g_pairs[g_pairCount] = temp; g_pairCount++; }
   ArrayResize(g_pairs, g_pairCount);
}

string BaseIndName(ENUM_BASE_IND ind)
{
   switch(ind)
   {
      case BASE_SUPERTREND:  return "Supertrend";
      case BASE_RANGEFILTER: return "RangeFilter";
      case BASE_HALFTREND:   return "HalfTrend";
      case BASE_MAMA:        return "MAMA";
      case BASE_DONCHIAN:    return "Donchian";
      case BASE_KELTNER:     return "Keltner";
      case BASE_T3:          return "T3";
      case BASE_MCGINLEY:    return "McGinley";
      case BASE_JMA:         return "JMA";
      case BASE_SQUEEZE:     return "Squeeze";
      case BASE_NONE:        return "NONE";
      default:               return "?";
   }
}

//+------------------------------------------------------------------+
//| INDICATOR SIGNAL HELPERS                                          |
//+------------------------------------------------------------------+
int GetSupertrendDir(string sym, int tf, int atrPer, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_SUPERTREND, atrPer, mult, PRICE_CLOSE, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetRangeFilterDir(string sym, int tf, int period, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_RANGEFILTER, period, mult, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetHalfTrendDir(string sym, int tf, int amp, int chDev, int atrPer, int shift)
{
   double sig = iCustom(sym, tf, IND_HALFTREND, amp, chDev, atrPer, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetT3Dir(string sym, int tf, int period, double vfactor, int shift)
{
   double sig = iCustom(sym, tf, IND_T3, period, vfactor, PRICE_CLOSE, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetMcGinleyDir(string sym, int tf, int period, double k, int shift)
{
   double sig = iCustom(sym, tf, IND_MCGINLEY, period, k, PRICE_CLOSE, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetJMADir(string sym, int tf, int length, int phase, int shift)
{
   double sig = iCustom(sym, tf, IND_JMA_NAME, length, phase, PRICE_CLOSE, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetMAMADir(string sym, int tf, double fast, double slow, int shift)
{
   double sig = iCustom(sym, tf, IND_MAMA, fast, slow, PRICE_MEDIAN, 2, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetDonchianDir(string sym, int tf, int period, int shift)
{
   double sig = iCustom(sym, tf, IND_DONCHIAN, period, true, 3, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetKeltnerDir(string sym, int tf, int maPer, int atrPer, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 3, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
int GetSqueezeDir(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double sig = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 4, shift);
   if(sig > 0.5) return 1; if(sig < -0.5) return -1; return 0;
}
bool SqueezeFiring(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double sqzOff = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 3, shift);
   return (sqzOff != EMPTY_VALUE && sqzOff != -1e308);
}
bool SqueezeMomGrowing(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double momPos  = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 0, shift);
   double momNeg  = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 1, shift);
   double momPosP = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 0, shift+1);
   double momNegP = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 1, shift+1);
   return (MathAbs(momPos)+MathAbs(momNeg) > MathAbs(momPosP)+MathAbs(momNegP));
}

int GetDirection(string sym, int tf, ENUM_BASE_IND ind, double p1, double p2, double p3, double p4, int shift)
{
   switch(ind)
   {
      case BASE_SUPERTREND:  return GetSupertrendDir(sym, tf, (int)p1, p2, shift);
      case BASE_RANGEFILTER: return GetRangeFilterDir(sym, tf, (int)p1, p2, shift);
      case BASE_HALFTREND:   return GetHalfTrendDir(sym, tf, (int)p1, (int)p2, (int)p3, shift);
      case BASE_T3:          return GetT3Dir(sym, tf, (int)p1, p2, shift);
      case BASE_MCGINLEY:    return GetMcGinleyDir(sym, tf, (int)p1, p2, shift);
      case BASE_JMA:         return GetJMADir(sym, tf, (int)p1, (int)p2, shift);
      case BASE_MAMA:        return GetMAMADir(sym, tf, p1, p2, shift);
      case BASE_DONCHIAN:    return GetDonchianDir(sym, tf, (int)p1, shift);
      case BASE_KELTNER:     return GetKeltnerDir(sym, tf, (int)p1, (int)p2, p3, shift);
      case BASE_SQUEEZE:     return GetSqueezeDir(sym, tf, (int)p1, p2, (int)p3, p4, (int)p1, shift);
      case BASE_NONE:        return 0;
      default:               return 0;
   }
}

//+------------------------------------------------------------------+
//| SLOT SIGNAL FUNCTIONS                                             |
//+------------------------------------------------------------------+
int GetHTFDir(string sym, int h1Bar)
{
   datetime barTime = iTime(sym, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(sym, PERIOD_H4, barTime, false);
   if(htfBar < 1) return 0;
   return GetDirection(sym, PERIOD_H4, InpHTF, InpHTF_P1, InpHTF_P2, InpHTF_P3, 0, htfBar);
}

bool HTFFlippedAgainst(string sym, int h1Bar, int tradeDir)
{
   int dirNow  = GetHTFDir(sym, h1Bar);
   int dirPrev = GetHTFDir(sym, h1Bar+1);
   if(tradeDir == 1  && dirNow == -1 && dirPrev != -1) return true;
   if(tradeDir == -1 && dirNow == 1  && dirPrev != 1)  return true;
   return false;
}

bool EntryFlipOccurred(string sym, int bar, int htfDir)
{
   int dirCurr = GetDirection(sym, PERIOD_H1, InpEntry, InpEnt_P1, InpEnt_P2, InpEnt_P3, 0, bar);
   int dirPrev = GetDirection(sym, PERIOD_H1, InpEntry, InpEnt_P1, InpEnt_P2, InpEnt_P3, 0, bar+1);
   return (dirCurr == htfDir && dirPrev != htfDir);
}

bool ConfirmAgrees(string sym, int bar, int htfDir)
{
   if(InpConfirm == BASE_NONE) return true;
   for(int i=0; i<=2; i++)
   {
      int dir = GetDirection(sym, PERIOD_H1, InpConfirm, InpConf_P1, InpConf_P2, InpConf_P3, InpConf_P4, bar+i);
      if(dir == htfDir) return true;
   }
   return false;
}

bool CheckVolume(string sym, int shift, int direction)
{
   if(InpVolume == BASE_NONE) return true;
   int bbLen=20; double bbMult=2.0; int kcLen=20; double kcMult=1.5; int momLen=20;
   if(!SqueezeFiring(sym, PERIOD_H1, bbLen, bbMult, kcLen, kcMult, momLen, shift)) return false;
   int momDir = GetSqueezeDir(sym, PERIOD_H1, bbLen, bbMult, kcLen, kcMult, momLen, shift);
   if(momDir != direction) return false;
   return SqueezeMomGrowing(sym, PERIOD_H1, bbLen, bbMult, kcLen, kcMult, momLen, shift);
}

bool CheckExit(string sym, int shift, int tradeDir)
{
   int dir = GetDirection(sym, PERIOD_H1, InpExit, InpEx_P1, InpEx_P2, InpEx_P3, 0, shift);
   if(tradeDir == 1  && dir == -1) return true;
   if(tradeDir == -1 && dir ==  1) return true;
   return false;
}

int EvalEntry(string sym, int bar)
{
   int htfDir = GetHTFDir(sym, bar);
   if(htfDir == 0) return 0;
   if(!EntryFlipOccurred(sym, bar, htfDir)) return 0;
   if(!ConfirmAgrees(sym, bar, htfDir)) return 0;
   if(!CheckVolume(sym, bar, htfDir)) return 0;
   return htfDir;
}

//+------------------------------------------------------------------+
//| M15 SUB-BAR SL/TP RESOLUTION                                     |
//| Returns: 0=neither hit, 1=TP hit, -1=SL hit                     |
//| Sets ambiguous=true if both in range on same sub-bar             |
//+------------------------------------------------------------------+
int CheckSubBar(string sym, int h1Bar, VTrade &t, double spread, bool &ambiguous)
{
   ambiguous = false;
   int subTF = (InpSubTF == SUB_M15) ? PERIOD_M15 : PERIOD_M5;
   int subsPerH1 = (InpSubTF == SUB_M15) ? 4 : 12;

   datetime h1Time = iTime(sym, PERIOD_H1, h1Bar);

   for(int s=0; s<subsPerH1; s++)
   {
      // Find the sub-bar corresponding to this time offset
      datetime subTime = h1Time + s * (subTF * 60);
      int subBar = iBarShift(sym, subTF, subTime, false);
      if(subBar < 0) continue;

      double subHi = iHigh(sym, subTF, subBar);
      double subLo = iLow(sym, subTF, subBar);

      // Apply spread for shorts
      double aSubHi = subHi + spread;
      double aSubLo = subLo + spread;

      bool tpHit = false, slHit = false;

      if(t.dir == 1)
      {
         tpHit = (subHi >= t.tp1);
         slHit = (subLo <= t.sl);
      }
      else
      {
         tpHit = (aSubLo <= t.tp1);
         slHit = (aSubHi >= t.sl);
      }

      if(tpHit && slHit)
      {
         ambiguous = true;
         return -1; // Pessimistic: assume SL hit first
      }
      if(slHit) return -1;
      if(tpHit) return 1;
   }
   return 0; // Neither hit
}

//+------------------------------------------------------------------+
//| RECORD TRADE                                                      |
//+------------------------------------------------------------------+
void RecordTrade(datetime openT, datetime closeT, string pair, int dir,
                 double entryP, double exitP, double pnl, double balAfter,
                 double spreadUsed, double slipUsed, bool ambig, string reason)
{
   int idx = g_tradeCount;
   g_tradeCount++;
   if(g_tradeCount > ArraySize(g_trades))
      ArrayResize(g_trades, g_tradeCount + 200);

   g_trades[idx].openTime    = openT;
   g_trades[idx].closeTime   = closeT;
   g_trades[idx].pair        = pair;
   g_trades[idx].dir         = dir;
   g_trades[idx].entry       = entryP;
   g_trades[idx].exitPrice   = exitP;
   g_trades[idx].pnl         = pnl;
   g_trades[idx].balAfter    = balAfter;
   g_trades[idx].spreadUsed  = spreadUsed;
   g_trades[idx].slipUsed    = slipUsed;
   g_trades[idx].ambiguous   = ambig;
   g_trades[idx].closeReason = reason;
}

//+------------------------------------------------------------------+
//| OnStart                                                           |
//+------------------------------------------------------------------+
void OnStart()
{
   ParsePairs();

   datetime startDate = D'2020.01.01';
   datetime endDate   = D'2025.01.01';

   Print("=== NNFX H1 Accurate Backtest ===");
   Print("Strategy: HTF=", BaseIndName(InpHTF), "(", InpHTF_P1, ",", InpHTF_P2, ")",
         " Entry=", BaseIndName(InpEntry), "(", InpEnt_P1, ",", InpEnt_P2, ",", InpEnt_P3, ")",
         " Confirm=", BaseIndName(InpConfirm), "(", InpConf_P1, ",", InpConf_P2, ")",
         " Exit=", BaseIndName(InpExit), "(", InpEx_P1, ")");
   Print("SL=", InpSLMult, "x | TP=", InpTP1Mult, "x | Risk=", InpRiskPct, "%");
   Print("Spread: ", EnumToString(InpSpreadMode), " | Slippage: ", InpSlippage, " pts");
   Print("Sub-bar: ", (InpSubTF==SUB_M15)?"M15":"M5", " | OOS: last ", InpOOSPct, "%");

   g_tradeCount = 0;
   ArrayResize(g_trades, 1000);

   // Per-pair stats arrays
   PairStats isStats[];   // In-sample
   PairStats oosStats[];  // Out-of-sample
   ArrayResize(isStats, g_pairCount);
   ArrayResize(oosStats, g_pairCount);

   // Equity curve data
   int eqCount = 0;
   datetime eqDates[];
   double   eqBalance[];
   double   eqDrawdown[];
   ArrayResize(eqDates, 50000);
   ArrayResize(eqBalance, 50000);
   ArrayResize(eqDrawdown, 50000);

   double grandBalance = InpStartBalance;
   double grandPeak    = InpStartBalance;

   for(int p = 0; p < g_pairCount; p++)
   {
      string sym = g_pairs[p];
      int startBar = iBarShift(sym, PERIOD_H1, startDate, false);
      int endBar   = iBarShift(sym, PERIOD_H1, endDate, false);
      if(endBar < 0) endBar = 0;
      if(startBar < 0) startBar = iBars(sym, PERIOD_H1) - 1;

      double tickVal  = MarketInfo(sym, MODE_TICKVALUE);
      double tickSz   = MarketInfo(sym, MODE_TICKSIZE);
      double pointVal = MarketInfo(sym, MODE_POINT);
      double slippage = GetSlippage(sym);

      if(tickVal <= 0 || tickSz <= 0) { Print(sym, ": invalid market info, skipping"); continue; }

      // OOS split bar
      int totalBars = startBar - endBar;
      int oosBar = startBar - (int)(totalBars * (100.0 - InpOOSPct) / 100.0);

      double balance = InpStartBalance;
      double peak    = InpStartBalance;

      // Initialize per-pair stats
      isStats[p].trades=0; isStats[p].wins=0; isStats[p].losses=0;
      isStats[p].gp=0; isStats[p].gl=0; isStats[p].maxDD=0; isStats[p].maxDDPct=0;
      isStats[p].ambiguousCount=0;
      oosStats[p].trades=0; oosStats[p].wins=0; oosStats[p].losses=0;
      oosStats[p].gp=0; oosStats[p].gl=0; oosStats[p].maxDD=0; oosStats[p].maxDDPct=0;
      oosStats[p].ambiguousCount=0;

      VTrade trade;
      trade.o1Open=false; trade.o2Open=false; trade.movedBE=false; trade.pnl=0;
      trade.dir=0; trade.entry=0; trade.sl=0; trade.tp1=0;
      trade.lots1=0; trade.lots2=0; trade.openTime=0; trade.rawSpread=0;

      for(int bar = startBar - 1; bar > endBar; bar--)
      {
         datetime barTime = iTime(sym, PERIOD_H1, bar);
         double spread = GetSpread(sym, barTime);
         bool isOOS = (bar < oosBar);

         // Manage open trades with M15 sub-bar resolution
         if(trade.o1Open || trade.o2Open)
         {
            double hi  = iHigh(sym, PERIOD_H1, bar);
            double lo  = iLow(sym, PERIOD_H1, bar);
            double cl  = iClose(sym, PERIOD_H1, bar);
            double aHi = hi + spread;
            double aCl = cl + spread;

            // HTF flip against — close all at close price
            if(HTFFlippedAgainst(sym, bar, trade.dir))
            {
               double ep = (trade.dir==1) ? cl : aCl;
               ep += (trade.dir==1) ? -slippage : slippage; // slippage against us
               double totalPnl = 0;
               if(trade.o1Open)
               {
                  double pnl1 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots1
                                                : (trade.entry-ep)/tickSz*tickVal*trade.lots1;
                  balance += pnl1; trade.pnl += pnl1; totalPnl += pnl1;
                  if(pnl1>0) { if(isOOS) oosStats[p].gp+=pnl1; else isStats[p].gp+=pnl1; }
                  else       { if(isOOS) oosStats[p].gl+=pnl1; else isStats[p].gl+=pnl1; }
                  trade.o1Open = false;
               }
               if(trade.o2Open)
               {
                  double pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                                : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
                  balance += pnl2; trade.pnl += pnl2; totalPnl += pnl2;
                  if(pnl2>0) { if(isOOS) oosStats[p].gp+=pnl2; else isStats[p].gp+=pnl2; }
                  else       { if(isOOS) oosStats[p].gl+=pnl2; else isStats[p].gl+=pnl2; }
                  trade.o2Open = false;
               }
               if(trade.pnl>=0) { if(isOOS) oosStats[p].wins++; else isStats[p].wins++; }
               else             { if(isOOS) oosStats[p].losses++; else isStats[p].losses++; }
               if(isOOS) oosStats[p].trades++; else isStats[p].trades++;
               RecordTrade(trade.openTime, barTime, sym, trade.dir, trade.entry, ep,
                           trade.pnl, balance, trade.rawSpread, slippage, false, "HTF_FLIP");
               if(balance>peak) peak=balance;
               double dd=peak-balance;
               if(isOOS) { if(dd>oosStats[p].maxDD){oosStats[p].maxDD=dd; oosStats[p].maxDDPct=(dd/peak)*100.0;} }
               else      { if(dd>isStats[p].maxDD){isStats[p].maxDD=dd; isStats[p].maxDDPct=(dd/peak)*100.0;} }

               // Equity curve
               if(eqCount < ArraySize(eqDates))
               {
                  eqDates[eqCount]=barTime; eqBalance[eqCount]=balance;
                  eqDrawdown[eqCount]=(peak>0)?(peak-balance)/peak*100.0:0;
                  eqCount++;
               }
               continue;
            }

            // Order 1: Use M15 sub-bar for SL/TP resolution
            if(trade.o1Open)
            {
               bool ambig = false;
               int subResult = CheckSubBar(sym, bar, trade, spread, ambig);

               if(subResult != 0)
               {
                  double pnl1 = 0;
                  if(subResult == 1) // TP hit
                  {
                     pnl1 = (trade.dir==1) ? (trade.tp1-trade.entry)/tickSz*tickVal*trade.lots1
                                            : (trade.entry-trade.tp1)/tickSz*tickVal*trade.lots1;
                     if(trade.o2Open) { trade.sl = trade.entry; trade.movedBE = true; }
                  }
                  else // SL hit
                  {
                     pnl1 = (trade.dir==1) ? (trade.sl-trade.entry)/tickSz*tickVal*trade.lots1
                                            : (trade.entry-trade.sl)/tickSz*tickVal*trade.lots1;
                  }
                  balance += pnl1; trade.pnl += pnl1;
                  if(pnl1>0) { if(isOOS) oosStats[p].gp+=pnl1; else isStats[p].gp+=pnl1; }
                  else       { if(isOOS) oosStats[p].gl+=pnl1; else isStats[p].gl+=pnl1; }
                  trade.o1Open = false;
                  if(ambig) { if(isOOS) oosStats[p].ambiguousCount++; else isStats[p].ambiguousCount++; }
               }
            }

            // Order 2 (runner): SL or exit signal
            if(trade.o2Open)
            {
               // Check SL via sub-bar
               bool ambig2 = false;
               // For runner, only check SL (no TP on runner)
               bool slHit = false;
               int subTF = (InpSubTF == SUB_M15) ? PERIOD_M15 : PERIOD_M5;
               int subsPerH1 = (InpSubTF == SUB_M15) ? 4 : 12;
               datetime h1Time = iTime(sym, PERIOD_H1, bar);

               for(int s=0; s<subsPerH1; s++)
               {
                  datetime subTime = h1Time + s * (subTF * 60);
                  int subBar = iBarShift(sym, subTF, subTime, false);
                  if(subBar < 0) continue;
                  double subHi = iHigh(sym, subTF, subBar) + spread;
                  double subLo = iLow(sym, subTF, subBar);
                  if(trade.dir==1  && subLo<=trade.sl)  { slHit=true; break; }
                  if(trade.dir==-1 && subHi>=trade.sl) { slHit=true; break; }
               }

               bool exitFlip = CheckExit(sym, bar, trade.dir);

               double pnl2 = 0;
               string reason = "";
               if(slHit)
               {
                  double ep = trade.sl + ((trade.dir==1) ? -slippage : slippage);
                  pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                        : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
                  reason = trade.movedBE ? "SL_BE" : "SL";
               }
               else if(exitFlip)
               {
                  double ep = (trade.dir==1) ? cl-slippage : aCl+slippage;
                  pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                        : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
                  reason = "EXIT_FLIP";
               }

               if(slHit || exitFlip)
               {
                  balance += pnl2; trade.pnl += pnl2;
                  if(pnl2>0) { if(isOOS) oosStats[p].gp+=pnl2; else isStats[p].gp+=pnl2; }
                  else       { if(isOOS) oosStats[p].gl+=pnl2; else isStats[p].gl+=pnl2; }
                  trade.o2Open = false;
               }
            }

            // Both orders closed — record full trade
            if(!trade.o1Open && !trade.o2Open)
            {
               if(trade.pnl>=0) { if(isOOS) oosStats[p].wins++; else isStats[p].wins++; }
               else             { if(isOOS) oosStats[p].losses++; else isStats[p].losses++; }
               if(isOOS) oosStats[p].trades++; else isStats[p].trades++;
               RecordTrade(trade.openTime, barTime, sym, trade.dir, trade.entry, cl,
                           trade.pnl, balance, trade.rawSpread, slippage, false, "NORMAL");
            }

            if(balance>peak) peak=balance;
            double dd2=peak-balance;
            if(isOOS) { if(dd2>oosStats[p].maxDD){oosStats[p].maxDD=dd2; oosStats[p].maxDDPct=(dd2/peak)*100.0;} }
            else      { if(dd2>isStats[p].maxDD){isStats[p].maxDD=dd2; isStats[p].maxDDPct=(dd2/peak)*100.0;} }

            if(trade.o1Open || trade.o2Open) continue;
         }

         // Evaluate entry (still on H1 closed bars)
         int signal = EvalEntry(sym, bar);
         if(signal == 0) continue;

         double atr = iATR(sym, PERIOD_H1, InpATRPeriod, bar);
         if(atr <= 0) continue;

         double openNext = iOpen(sym, PERIOD_H1, bar - 1);
         if(openNext <= 0) continue;

         double entrySpread = GetSpread(sym, barTime);
         double entry = (signal==1) ? openNext + entrySpread + slippage
                                     : openNext - slippage;
         double slDist  = InpSLMult * atr;
         double tp1Dist = InpTP1Mult * atr;

         double risk    = balance * (InpRiskPct / 100.0);
         double slTicks = slDist / tickSz;
         double rpl     = slTicks * tickVal;
         if(rpl <= 0) continue;

         double half = MathFloor((risk / rpl) / 2.0 * 100.0) / 100.0;
         if(half < 0.01) half = 0.01;

         trade.dir    = signal;
         trade.entry  = entry;
         trade.lots1  = half;
         trade.lots2  = half;
         trade.o1Open = true;
         trade.o2Open = true;
         trade.movedBE= false;
         trade.pnl    = 0;
         trade.openTime = barTime;
         trade.rawSpread = entrySpread;

         if(signal == 1) { trade.sl = entry - slDist; trade.tp1 = entry + tp1Dist; }
         else            { trade.sl = entry + slDist; trade.tp1 = entry - tp1Dist; }

         // Equity curve snapshot
         if(eqCount < ArraySize(eqDates))
         {
            eqDates[eqCount]=barTime; eqBalance[eqCount]=balance;
            eqDrawdown[eqCount]=(peak>0)?(peak-balance)/peak*100.0:0;
            eqCount++;
         }
      }

      // Close remaining open trade
      if(trade.o1Open || trade.o2Open)
      {
         double lc = iClose(sym, PERIOD_H1, endBar);
         double lastSpread = GetSpread(sym, iTime(sym, PERIOD_H1, endBar));
         double ep = (trade.dir==1) ? lc-slippage : lc+lastSpread+slippage;
         double totalPnl = 0;
         if(trade.o1Open)
         {
            double pnl1 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots1
                                          : (trade.entry-ep)/tickSz*tickVal*trade.lots1;
            balance += pnl1; trade.pnl += pnl1;
            trade.o1Open = false;
         }
         if(trade.o2Open)
         {
            double pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                          : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
            balance += pnl2; trade.pnl += pnl2;
            trade.o2Open = false;
         }
         RecordTrade(trade.openTime, iTime(sym,PERIOD_H1,endBar), sym, trade.dir,
                     trade.entry, ep, trade.pnl, balance, trade.rawSpread, slippage, false, "END");
      }

      isStats[p].endBal = balance;
      isStats[p].pf = (isStats[p].gl!=0) ? MathAbs(isStats[p].gp/isStats[p].gl) : 0;
      isStats[p].wr = (isStats[p].trades>0) ? ((double)isStats[p].wins/isStats[p].trades*100.0) : 0;
      oosStats[p].endBal = balance;
      oosStats[p].pf = (oosStats[p].gl!=0) ? MathAbs(oosStats[p].gp/oosStats[p].gl) : 0;
      oosStats[p].wr = (oosStats[p].trades>0) ? ((double)oosStats[p].wins/oosStats[p].trades*100.0) : 0;

      Print("--- ", sym, " ---");
      Print("  IS: Trades=", isStats[p].trades, " WR=", DoubleToStr(isStats[p].wr,1),
            "% PF=", DoubleToStr(isStats[p].pf,2), " DD=", DoubleToStr(isStats[p].maxDDPct,1),
            "% Ambig=", isStats[p].ambiguousCount);
      Print("  OOS: Trades=", oosStats[p].trades, " WR=", DoubleToStr(oosStats[p].wr,1),
            "% PF=", DoubleToStr(oosStats[p].pf,2), " DD=", DoubleToStr(oosStats[p].maxDDPct,1),
            "% Ambig=", oosStats[p].ambiguousCount);
      Print("  Final Balance: $", DoubleToStr(balance, 2));
   }

   // Write all output files
   WriteTradesCSV();
   WriteSummaryCSV(isStats, oosStats);
   WriteEquityCSV(eqDates, eqBalance, eqDrawdown, eqCount);

   Print("=== Accurate Backtest Complete ===");
   Alert("NNFX H1 AccurateBT done! Check MQL4/Files/NNFX_H1_AccurateBT_*.csv");
}

//+------------------------------------------------------------------+
//| WRITE TRADES CSV                                                  |
//+------------------------------------------------------------------+
void WriteTradesCSV()
{
   string fn = "NNFX_H1_AccurateBT_Trades.csv";
   int h = FileOpen(fn, FILE_WRITE | FILE_CSV, ',');
   if(h < 0) { Print("ERROR: Cannot open ", fn); return; }

   FileWrite(h, "Open_Time","Close_Time","Pair","Direction","Entry","Exit",
             "PnL","Balance_After","Spread","Slippage","Ambiguous","Close_Reason");

   for(int i=0; i<g_tradeCount; i++)
   {
      FileWrite(h,
         TimeToStr(g_trades[i].openTime, TIME_DATE|TIME_MINUTES),
         TimeToStr(g_trades[i].closeTime, TIME_DATE|TIME_MINUTES),
         g_trades[i].pair,
         (g_trades[i].dir==1) ? "LONG" : "SHORT",
         DoubleToStr(g_trades[i].entry, 5),
         DoubleToStr(g_trades[i].exitPrice, 5),
         DoubleToStr(g_trades[i].pnl, 2),
         DoubleToStr(g_trades[i].balAfter, 2),
         DoubleToStr(g_trades[i].spreadUsed, 5),
         DoubleToStr(g_trades[i].slipUsed, 5),
         g_trades[i].ambiguous ? "YES" : "NO",
         g_trades[i].closeReason);
   }
   FileClose(h);
   Print("Trades saved: MQL4/Files/", fn, " (", g_tradeCount, " trades)");
}

//+------------------------------------------------------------------+
//| WRITE SUMMARY CSV (IS vs OOS)                                     |
//+------------------------------------------------------------------+
void WriteSummaryCSV(PairStats &isS[], PairStats &oosS[])
{
   string fn = "NNFX_H1_AccurateBT_Summary.csv";
   int h = FileOpen(fn, FILE_WRITE | FILE_CSV, ',');
   if(h < 0) { Print("ERROR: Cannot open ", fn); return; }

   FileWrite(h, "Pair","Sample","Trades","Wins","Losses","WR%","PF",
             "Gross_Profit","Gross_Loss","Net","Max_DD%","Ambiguous_Bars","End_Balance");

   double isGP=0, isGL=0, oosGP=0, oosGL=0;
   int isT=0, isW=0, oosT=0, oosW=0, isAmb=0, oosAmb=0;

   for(int p=0; p<g_pairCount; p++)
   {
      string sym = g_pairs[p];
      double isNet = isS[p].gp + isS[p].gl;
      double oosNet = oosS[p].gp + oosS[p].gl;

      FileWrite(h, sym, "IN_SAMPLE", isS[p].trades, isS[p].wins, isS[p].losses,
                DoubleToStr(isS[p].wr,1), DoubleToStr(isS[p].pf,2),
                DoubleToStr(isS[p].gp,2), DoubleToStr(isS[p].gl,2), DoubleToStr(isNet,2),
                DoubleToStr(isS[p].maxDDPct,1), isS[p].ambiguousCount,
                DoubleToStr(isS[p].endBal,2));

      FileWrite(h, sym, "OUT_OF_SAMPLE", oosS[p].trades, oosS[p].wins, oosS[p].losses,
                DoubleToStr(oosS[p].wr,1), DoubleToStr(oosS[p].pf,2),
                DoubleToStr(oosS[p].gp,2), DoubleToStr(oosS[p].gl,2), DoubleToStr(oosNet,2),
                DoubleToStr(oosS[p].maxDDPct,1), oosS[p].ambiguousCount,
                DoubleToStr(oosS[p].endBal,2));

      isGP+=isS[p].gp; isGL+=isS[p].gl; isT+=isS[p].trades; isW+=isS[p].wins; isAmb+=isS[p].ambiguousCount;
      oosGP+=oosS[p].gp; oosGL+=oosS[p].gl; oosT+=oosS[p].trades; oosW+=oosS[p].wins; oosAmb+=oosS[p].ambiguousCount;
   }

   // Aggregate rows
   double isAggPF = (isGL!=0) ? MathAbs(isGP/isGL) : 0;
   double isAggWR = (isT>0) ? ((double)isW/isT*100.0) : 0;
   double oosAggPF = (oosGL!=0) ? MathAbs(oosGP/oosGL) : 0;
   double oosAggWR = (oosT>0) ? ((double)oosW/oosT*100.0) : 0;

   FileWrite(h, "AGGREGATE","IN_SAMPLE", isT, isW, isT-isW,
             DoubleToStr(isAggWR,1), DoubleToStr(isAggPF,2),
             DoubleToStr(isGP,2), DoubleToStr(isGL,2), DoubleToStr(isGP+isGL,2),
             "", isAmb, "");
   FileWrite(h, "AGGREGATE","OUT_OF_SAMPLE", oosT, oosW, oosT-oosW,
             DoubleToStr(oosAggWR,1), DoubleToStr(oosAggPF,2),
             DoubleToStr(oosGP,2), DoubleToStr(oosGL,2), DoubleToStr(oosGP+oosGL,2),
             "", oosAmb, "");

   FileClose(h);
   Print("Summary saved: MQL4/Files/", fn);

   // Print summary
   Print("========================================");
   Print("IN-SAMPLE: Trades=", isT, " WR=", DoubleToStr(isAggWR,1), "% PF=", DoubleToStr(isAggPF,2),
         " Net=$", DoubleToStr(isGP+isGL,2), " Ambig=", isAmb);
   Print("OUT-OF-SAMPLE: Trades=", oosT, " WR=", DoubleToStr(oosAggWR,1), "% PF=", DoubleToStr(oosAggPF,2),
         " Net=$", DoubleToStr(oosGP+oosGL,2), " Ambig=", oosAmb);
   Print("========================================");
}

//+------------------------------------------------------------------+
//| WRITE EQUITY CURVE CSV                                            |
//+------------------------------------------------------------------+
void WriteEquityCSV(datetime &dates[], double &bal[], double &dd[], int count)
{
   string fn = "NNFX_H1_AccurateBT_Equity.csv";
   int h = FileOpen(fn, FILE_WRITE | FILE_CSV, ',');
   if(h < 0) { Print("ERROR: Cannot open ", fn); return; }

   FileWrite(h, "Date", "Balance", "Drawdown_Pct");
   for(int i=0; i<count; i++)
   {
      FileWrite(h,
         TimeToStr(dates[i], TIME_DATE|TIME_MINUTES),
         DoubleToStr(bal[i], 2),
         DoubleToStr(dd[i], 2));
   }
   FileClose(h);
   Print("Equity curve saved: MQL4/Files/", fn, " (", count, " points)");
}
//+------------------------------------------------------------------+
