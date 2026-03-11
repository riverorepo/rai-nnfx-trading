//+------------------------------------------------------------------+
//|                                          NNFX_H1_Sweep_V3.mq4   |
//|  H1 intraday sweep — custom non-repainting indicators:          |
//|    Supertrend, RangeFilter, HalfTrend, Ehlers MAMA, Donchian,   |
//|    Keltner, T3, McGinley Dynamic, JMA, Squeeze Momentum         |
//|  Same MTF architecture as V2:                                    |
//|    Slot 1: HTF Trend Filter (H4/D1) — direction only            |
//|    Slot 2: H1 Entry Trigger — indicator FLIP in HTF direction   |
//|    Slot 3: H1 Confirmation — direction must agree               |
//|    Slot 4: H1 Volume/Strength — momentum/volatility filter      |
//|    Slot 5: H1 Exit — fast flip against trade closes runner      |
//|  Locked defaults = V2 slot winners (best stock indicators)      |
//|  ~100 configs x 7 pairs. 2020-2025.                             |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "1.00"
#property strict
#property show_inputs

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_SWEEP_SLOT
{
   SWEEP_ALL    = 0,  // All Slots (run sequentially)
   SWEEP_HTF    = 1,  // HTF Trend Filter only
   SWEEP_ENTRY  = 2,  // Entry Trigger only
   SWEEP_CONFIRM= 3,  // Confirmation only
   SWEEP_VOLUME = 4,  // Volume only
   SWEEP_EXIT   = 5   // Exit only
};

enum ENUM_IND_TYPE
{
   // HTF Trend (slot 1) — custom indicators on H4
   IND_HTF_SUPERTREND,
   IND_HTF_RANGEFILTER,
   IND_HTF_T3,
   IND_HTF_MCGINLEY,
   IND_HTF_JMA,
   IND_HTF_MAMA,
   IND_HTF_HALFTREND,
   IND_HTF_KAMA,        // V2 winner — kept as reference
   IND_HTF_EMA,         // Stock — reference

   // Entry Trigger (slot 2) — flip detection on H1
   IND_ENTRY_SUPERTREND,
   IND_ENTRY_RANGEFILTER,
   IND_ENTRY_HALFTREND,
   IND_ENTRY_T3,
   IND_ENTRY_MCGINLEY,
   IND_ENTRY_JMA,
   IND_ENTRY_MAMA,
   IND_ENTRY_DONCHIAN,
   IND_ENTRY_KELTNER,
   IND_ENTRY_EMA_PRICE,  // V2 winner — reference

   // Confirmation (slot 3)
   IND_CONF_SUPERTREND,
   IND_CONF_HALFTREND,
   IND_CONF_RANGEFILTER,
   IND_CONF_SQUEEZE,
   IND_CONF_KELTNER,
   IND_CONF_DONCHIAN,
   IND_CONF_MAMA,
   IND_CONF_T3,
   IND_CONF_STOCH,       // V2 winner — reference

   // Volume (slot 4)
   IND_VOL_SQUEEZE,
   IND_VOL_KELTNER_EXP,
   IND_VOL_DONCHIAN_EXP,
   IND_VOL_BB_WIDTH,     // V2 winner — reference
   IND_VOL_NONE,

   // Exit (slot 5) — flip against trade
   IND_EXIT_SUPERTREND,
   IND_EXIT_HALFTREND,
   IND_EXIT_RANGEFILTER,
   IND_EXIT_T3,
   IND_EXIT_MCGINLEY,
   IND_EXIT_JMA,
   IND_EXIT_MAMA,
   IND_EXIT_DONCHIAN,
   IND_EXIT_RSI          // V2 winner — reference
};

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input ENUM_SWEEP_SLOT InpSweepSlot   = SWEEP_ALL; // Which Slot(s) to Sweep
input int             InpMaxResults  = 50;         // Max results to display
input int             InpSessionStart= 7;          // Session Start (GMT)
input int             InpSessionEnd  = 20;         // Session End (GMT)
input bool            InpUseSession  = true;       // Enable Session Filter

//+------------------------------------------------------------------+
//| LOCKED DEFAULTS — V2 slot winners                                |
//+------------------------------------------------------------------+
// HTF: H4 KAMA(10) — best HTF from V2
#define LOCKED_HTF_TF       PERIOD_H4

// Entry: EMA(50) x Price — best entry from V2
#define LOCKED_ENTRY_EMA_PER 50

// Confirm: Stoch(8) > 50 — best confirm from V2
#define LOCKED_CONF_STOCH_K  8
#define LOCKED_CONF_STOCH_D  3
#define LOCKED_CONF_STOCH_SL 3

// Volume: BBwidth(20) expanding — best volume from V2
#define LOCKED_VOL_BB_PER   20
#define LOCKED_VOL_BB_DEV   2.0

// Exit: RSI(14) cross 50 — best exit from V2
#define LOCKED_EXIT_RSI_PER  14

// Trade management
#define LOCKED_ATR          14
#define LOCKED_SL           1.5
#define LOCKED_TP1          1.0
#define LOCKED_RISK         1.0
#define LOCKED_BAL          10000.0

// Custom indicator names
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
#define IND_KAMA         "KAMA"
#define IND_SSL          "SSL_Channel"

//+------------------------------------------------------------------+
//| STRUCTS                                                           |
//+------------------------------------------------------------------+
struct SweepConfig
{
   int            slot;
   ENUM_IND_TYPE  indType;
   double         p1, p2, p3, p4; // p4: for HTF slot = timeframe (240=H4, 1440=D1)
   string         label;
};

struct SweepResult
{
   string label;
   int    slot;
   double aggNet;
   double aggPF;
   double avgWR;
   double worstDD;
   int    totalSig;
   double pairPF[7];
   double pairNet[7];
};

struct VTrade
{
   int    dir;
   double entry, sl, tp1, lots1, lots2;
   bool   o1Open, o2Open, movedBE;
   double pnl;
};

struct PStats
{
   int    sig, wins, losses;
   double gp, gl, maxDD, maxDDPct, bal;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string g_pairs[7];
int    g_startBar[7], g_endBar[7];
double g_tickVal[7], g_tickSz[7], g_pointVal[7], g_spread[7];

int GetTypicalSpread(string s)
{
   if(s=="EURUSD") return 14; if(s=="GBPUSD") return 18; if(s=="USDJPY") return 14;
   if(s=="USDCHF") return 17; if(s=="AUDUSD") return 14; if(s=="NZDUSD") return 20;
   if(s=="USDCAD") return 20; return 20;
}

bool InSession(datetime barTime)
{
   if(!InpUseSession) return true;
   int hour = TimeHour(barTime);
   if(InpSessionStart < InpSessionEnd)
      return (hour >= InpSessionStart && hour < InpSessionEnd);
   else
      return (hour >= InpSessionStart || hour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| CUSTOM INDICATOR SIGNAL HELPERS                                   |
//| All return +1 (bullish), -1 (bearish), or 0                     |
//+------------------------------------------------------------------+

// Generic: indicators with Signal at buffer 2 (Supertrend, RangeFilter, HalfTrend, T3, McGinley, JMA)
int GetCustomSig2(string sym, int tf, string indName, double p1, double p2, double p3, int shift)
{
   double sig = iCustom(sym, tf, indName, p1, p2, p3, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// Supertrend: params are ATRPeriod, Multiplier, PriceType(0=PRICE_CLOSE)
int GetSupertrendDir(string sym, int tf, int atrPer, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_SUPERTREND, atrPer, mult, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// RangeFilter: params are Period, Multiplier
int GetRangeFilterDir(string sym, int tf, int period, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_RANGEFILTER, period, mult, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// HalfTrend: params are Amplitude, ChannelDev, ATRPeriod
int GetHalfTrendDir(string sym, int tf, int amp, int chDev, int atrPer, int shift)
{
   double sig = iCustom(sym, tf, IND_HALFTREND, amp, chDev, atrPer, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// T3: params are Period, VolumeFactor, PriceType
int GetT3Dir(string sym, int tf, int period, double vfactor, int shift)
{
   double sig = iCustom(sym, tf, IND_T3, period, vfactor, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// McGinley: params are Period, Constant, PriceType
int GetMcGinleyDir(string sym, int tf, int period, double k, int shift)
{
   double sig = iCustom(sym, tf, IND_MCGINLEY, period, k, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// JMA: params are Length, Phase, PriceType
int GetJMADir(string sym, int tf, int length, int phase, int shift)
{
   double sig = iCustom(sym, tf, IND_JMA_NAME, length, phase, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// Ehlers MAMA: params are FastLimit, SlowLimit, PriceType
int GetMAMADir(string sym, int tf, double fast, double slow, int shift)
{
   double sig = iCustom(sym, tf, IND_MAMA, fast, slow, PRICE_MEDIAN, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// Donchian: params are Period, ShiftBars. Signal at buffer 3
int GetDonchianDir(string sym, int tf, int period, int shift)
{
   double sig = iCustom(sym, tf, IND_DONCHIAN, period, true, 3, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// Keltner: params are MAPeriod, ATRPeriod, Multiplier, MAMethod, PriceType. Signal at buffer 3
int GetKeltnerDir(string sym, int tf, int maPer, int atrPer, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 3, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// Squeeze Momentum: Signal at buffer 4 (1=bullish momentum, -1=bearish)
int GetSqueezeDir(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double sig = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 4, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// Squeeze: is squeeze OFF? (BB outside KC = volatility breakout)
// Buffer 3 = SqzOff dots (not EMPTY_VALUE when squeeze is off)
bool SqueezeFiring(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double sqzOff = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 3, shift);
   return (sqzOff != EMPTY_VALUE && sqzOff != -1e308);
}

// Squeeze: momentum magnitude growing
bool SqueezeMomGrowing(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double momPos  = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 0, shift);
   double momNeg  = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 1, shift);
   double momPosP = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 0, shift+1);
   double momNegP = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 1, shift+1);
   double absMom  = MathAbs(momPos) + MathAbs(momNeg);
   double absMomP = MathAbs(momPosP) + MathAbs(momNegP);
   return (absMom > absMomP);
}

// KAMA: buffer 0 = KAMA value
int GetKAMADir(string sym, int tf, int period, double fast, double slow, int shift)
{
   double val   = iCustom(sym, tf, IND_KAMA, period, fast, slow, 0, shift);
   double close = iClose(sym, tf, shift);
   if(close > val) return 1;
   if(close < val) return -1;
   return 0;
}

// Keltner band width expanding
bool KeltnerExpanding(string sym, int tf, int maPer, int atrPer, double mult, int shift)
{
   double upper  = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 0, shift);
   double lower  = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 2, shift);
   double mid    = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 1, shift);
   double upperP = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 0, shift+1);
   double lowerP = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 2, shift+1);
   double midP   = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 1, shift+1);
   if(mid==0||midP==0) return false;
   double w  = (upper - lower) / mid;
   double wP = (upperP - lowerP) / midP;
   return (w > wP);
}

// Donchian band width expanding
bool DonchianExpanding(string sym, int tf, int period, int shift)
{
   double upper  = iCustom(sym, tf, IND_DONCHIAN, period, true, 0, shift);
   double lower  = iCustom(sym, tf, IND_DONCHIAN, period, true, 2, shift);
   double upperP = iCustom(sym, tf, IND_DONCHIAN, period, true, 0, shift+1);
   double lowerP = iCustom(sym, tf, IND_DONCHIAN, period, true, 2, shift+1);
   double mid  = (upper + lower) / 2.0;
   double midP = (upperP + lowerP) / 2.0;
   if(mid==0||midP==0) return false;
   double w  = (upper - lower) / mid;
   double wP = (upperP - lowerP) / midP;
   return (w > wP);
}

//+------------------------------------------------------------------+
//| OnStart                                                           |
//+------------------------------------------------------------------+
void OnStart()
{
   g_pairs[0]="EURUSD"; g_pairs[1]="GBPUSD"; g_pairs[2]="USDJPY";
   g_pairs[3]="USDCHF"; g_pairs[4]="AUDUSD"; g_pairs[5]="NZDUSD"; g_pairs[6]="USDCAD";

   datetime startDate = D'2020.01.01';
   datetime endDate   = D'2025.01.01';

   for(int p=0; p<7; p++)
   {
      g_startBar[p] = iBarShift(g_pairs[p], PERIOD_H1, startDate, false);
      g_endBar[p]   = iBarShift(g_pairs[p], PERIOD_H1, endDate, false);
      if(g_endBar[p]<0)    g_endBar[p]=0;
      if(g_startBar[p]<0)  g_startBar[p]=iBars(g_pairs[p],PERIOD_H1)-1;
      g_tickVal[p]  = MarketInfo(g_pairs[p], MODE_TICKVALUE);
      g_tickSz[p]   = MarketInfo(g_pairs[p], MODE_TICKSIZE);
      g_pointVal[p] = MarketInfo(g_pairs[p], MODE_POINT);
      g_spread[p]   = GetTypicalSpread(g_pairs[p]) * g_pointVal[p];
      Print(g_pairs[p], " H1 bars: ", g_startBar[p]-g_endBar[p]);
   }

   Print("=== NNFX H1 Sweep V3 — Custom Indicators ===");
   Print("Locked defaults: H4 KAMA(10) | EMA(50)xPrice | Stoch(8)>50 | BBwidth(20) | RSI(14)");
   Print("Testing: Supertrend, RangeFilter, HalfTrend, MAMA, Donchian, Keltner, T3, McGinley, JMA, Squeeze");

   SweepConfig configs[];
   BuildConfigs(configs);
   int total = ArraySize(configs);
   Print("Total configs: ", total);

   SweepResult results[];
   ArrayResize(results, total);
   int resultCount = 0;
   uint startTick = GetTickCount();

   for(int c=0; c<total; c++)
   {
      if(IsStopped()) { Print("CANCELLED by user."); break; }

      if((c+1) % 3 == 0)
      {
         uint elapsed = GetTickCount() - startTick;
         double pct = (double)(c+1)/total*100.0;
         double estTotal = (pct > 0) ? elapsed / pct * 100.0 : 0;
         double remaining = (estTotal - elapsed) / 1000.0;
         Print("Progress: ", c+1, "/", total, " (", DoubleToStr(pct,1), "%) ~",
               DoubleToStr(remaining,0), "s remaining");
      }

      SweepResult res;
      res.label    = configs[c].label;
      res.slot     = configs[c].slot;
      res.aggNet   = 0;
      res.totalSig = 0;
      res.worstDD  = 0;
      double totalGP=0, totalGL=0, totalWR=0;

      for(int p=0; p<7; p++)
      {
         if(g_tickVal[p]<=0 || g_tickSz[p]<=0) continue;
         PStats ps;
         RunBacktest(g_pairs[p], g_startBar[p], g_endBar[p], g_spread[p],
                     g_tickVal[p], g_tickSz[p], configs[c], ps);

         double net = ps.gp + ps.gl;
         res.aggNet += net;
         totalGP    += ps.gp;
         totalGL    += ps.gl;
         res.totalSig += ps.sig;
         if(ps.maxDDPct > res.worstDD) res.worstDD = ps.maxDDPct;
         res.pairPF[p]  = (ps.gl!=0) ? MathAbs(ps.gp/ps.gl) : 0;
         res.pairNet[p] = net;
         double wr = (ps.sig>0) ? ((double)ps.wins/ps.sig*100.0) : 0;
         totalWR += wr;
      }
      res.aggPF = (totalGL!=0) ? MathAbs(totalGP/totalGL) : 0;
      res.avgWR = totalWR / 7.0;

      results[resultCount] = res;
      resultCount++;
   }

   SortResults(results, resultCount);
   WriteCSV(results, resultCount);
   PrintTop(results, MathMin(resultCount, InpMaxResults));

   uint totalTime = (GetTickCount() - startTick) / 1000;
   Print("=== H1 Sweep V3 Complete in ", totalTime, "s ===");
   Alert("NNFX H1 Sweep V3 done! Check MQL4/Files/NNFX_H1_SweepV3_Results.csv");
}

//+------------------------------------------------------------------+
//| BUILD CONFIGS                                                     |
//+------------------------------------------------------------------+
void AddCfg(SweepConfig &arr[], int &n, int slot, ENUM_IND_TYPE type,
            double p1, double p2, double p3, double p4, string lbl)
{
   if(n >= ArraySize(arr)) ArrayResize(arr, n+50);
   arr[n].slot    = slot;
   arr[n].indType = type;
   arr[n].p1=p1; arr[n].p2=p2; arr[n].p3=p3; arr[n].p4=p4;
   arr[n].label   = lbl;
   n++;
}

void BuildConfigs(SweepConfig &configs[])
{
   int n = 0;
   ArrayResize(configs, 200);

   //--- SLOT 1: HTF Trend Filter — custom indicators on H4
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_HTF)
   {
      // Supertrend on H4: ATRPeriod, Multiplier
      AddCfg(configs,n, 1, IND_HTF_SUPERTREND, 10,2.0,0,240, "HTF:H4_Supertrend(10,2.0)");
      AddCfg(configs,n, 1, IND_HTF_SUPERTREND, 10,3.0,0,240, "HTF:H4_Supertrend(10,3.0)");
      AddCfg(configs,n, 1, IND_HTF_SUPERTREND, 14,2.0,0,240, "HTF:H4_Supertrend(14,2.0)");
      // RangeFilter on H4
      AddCfg(configs,n, 1, IND_HTF_RANGEFILTER, 30,2.5,0,240, "HTF:H4_RngFilt(30,2.5)");
      AddCfg(configs,n, 1, IND_HTF_RANGEFILTER, 50,3.0,0,240, "HTF:H4_RngFilt(50,3.0)");
      // T3 on H4
      AddCfg(configs,n, 1, IND_HTF_T3, 5,0.7,0,240, "HTF:H4_T3(5)");
      AddCfg(configs,n, 1, IND_HTF_T3, 8,0.7,0,240, "HTF:H4_T3(8)");
      // McGinley on H4
      AddCfg(configs,n, 1, IND_HTF_MCGINLEY, 10,0.6,0,240, "HTF:H4_McGinley(10)");
      AddCfg(configs,n, 1, IND_HTF_MCGINLEY, 14,0.6,0,240, "HTF:H4_McGinley(14)");
      // JMA on H4
      AddCfg(configs,n, 1, IND_HTF_JMA, 10,0,0,240, "HTF:H4_JMA(10)");
      AddCfg(configs,n, 1, IND_HTF_JMA, 14,0,0,240, "HTF:H4_JMA(14)");
      // MAMA on H4
      AddCfg(configs,n, 1, IND_HTF_MAMA, 0.5,0.05,0,240, "HTF:H4_MAMA(0.5/0.05)");
      AddCfg(configs,n, 1, IND_HTF_MAMA, 0.4,0.04,0,240, "HTF:H4_MAMA(0.4/0.04)");
      // HalfTrend on H4
      AddCfg(configs,n, 1, IND_HTF_HALFTREND, 2,2,100,240, "HTF:H4_HalfTrend(2)");
      AddCfg(configs,n, 1, IND_HTF_HALFTREND, 3,2,100,240, "HTF:H4_HalfTrend(3)");
      // V2 winner: H4 KAMA(10) — reference
      AddCfg(configs,n, 1, IND_HTF_KAMA, 10,2,30,240, "HTF:H4_KAMA(10)");
      // H4 EMA — reference
      AddCfg(configs,n, 1, IND_HTF_EMA, 50,0,0,240, "HTF:H4_EMA(50)");
   }

   //--- SLOT 2: H1 Entry Trigger — FLIP detection with custom indicators
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_ENTRY)
   {
      // Supertrend flip
      AddCfg(configs,n, 2, IND_ENTRY_SUPERTREND, 7,2.0,0,0, "ENTRY:Supertrend(7,2.0)flip");
      AddCfg(configs,n, 2, IND_ENTRY_SUPERTREND, 10,2.0,0,0, "ENTRY:Supertrend(10,2.0)flip");
      AddCfg(configs,n, 2, IND_ENTRY_SUPERTREND, 10,3.0,0,0, "ENTRY:Supertrend(10,3.0)flip");
      AddCfg(configs,n, 2, IND_ENTRY_SUPERTREND, 14,2.0,0,0, "ENTRY:Supertrend(14,2.0)flip");
      // RangeFilter flip
      AddCfg(configs,n, 2, IND_ENTRY_RANGEFILTER, 30,2.5,0,0, "ENTRY:RngFilt(30,2.5)flip");
      AddCfg(configs,n, 2, IND_ENTRY_RANGEFILTER, 50,3.0,0,0, "ENTRY:RngFilt(50,3.0)flip");
      AddCfg(configs,n, 2, IND_ENTRY_RANGEFILTER, 20,2.0,0,0, "ENTRY:RngFilt(20,2.0)flip");
      // HalfTrend flip
      AddCfg(configs,n, 2, IND_ENTRY_HALFTREND, 2,2,100,0, "ENTRY:HalfTrend(2)flip");
      AddCfg(configs,n, 2, IND_ENTRY_HALFTREND, 3,2,100,0, "ENTRY:HalfTrend(3)flip");
      // T3 direction change
      AddCfg(configs,n, 2, IND_ENTRY_T3, 5,0.7,0,0, "ENTRY:T3(5)flip");
      AddCfg(configs,n, 2, IND_ENTRY_T3, 8,0.7,0,0, "ENTRY:T3(8)flip");
      // McGinley direction change
      AddCfg(configs,n, 2, IND_ENTRY_MCGINLEY, 10,0.6,0,0, "ENTRY:McGinley(10)flip");
      AddCfg(configs,n, 2, IND_ENTRY_MCGINLEY, 14,0.6,0,0, "ENTRY:McGinley(14)flip");
      // JMA direction change
      AddCfg(configs,n, 2, IND_ENTRY_JMA, 10,0,0,0, "ENTRY:JMA(10)flip");
      AddCfg(configs,n, 2, IND_ENTRY_JMA, 14,0,0,0, "ENTRY:JMA(14)flip");
      AddCfg(configs,n, 2, IND_ENTRY_JMA, 7,0,0,0, "ENTRY:JMA(7)flip");
      // MAMA cross
      AddCfg(configs,n, 2, IND_ENTRY_MAMA, 0.5,0.05,0,0, "ENTRY:MAMA(0.5/0.05)flip");
      // Donchian midline cross
      AddCfg(configs,n, 2, IND_ENTRY_DONCHIAN, 15,0,0,0, "ENTRY:Donchian(15)flip");
      AddCfg(configs,n, 2, IND_ENTRY_DONCHIAN, 20,0,0,0, "ENTRY:Donchian(20)flip");
      // Keltner midline cross
      AddCfg(configs,n, 2, IND_ENTRY_KELTNER, 20,20,1.5,0, "ENTRY:Keltner(20)flip");
      // V2 winner: EMA(50)xPrice — reference
      AddCfg(configs,n, 2, IND_ENTRY_EMA_PRICE, 50,0,0,0, "ENTRY:EMA(50)xPrice");
   }

   //--- SLOT 3: H1 Confirmation
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_CONFIRM)
   {
      // Supertrend direction
      AddCfg(configs,n, 3, IND_CONF_SUPERTREND, 10,2.0,0,0, "CONF:Supertrend(10,2.0)");
      AddCfg(configs,n, 3, IND_CONF_SUPERTREND, 10,3.0,0,0, "CONF:Supertrend(10,3.0)");
      AddCfg(configs,n, 3, IND_CONF_SUPERTREND, 14,2.0,0,0, "CONF:Supertrend(14,2.0)");
      // HalfTrend direction
      AddCfg(configs,n, 3, IND_CONF_HALFTREND, 2,2,100,0, "CONF:HalfTrend(2)");
      AddCfg(configs,n, 3, IND_CONF_HALFTREND, 3,2,100,0, "CONF:HalfTrend(3)");
      // RangeFilter direction
      AddCfg(configs,n, 3, IND_CONF_RANGEFILTER, 30,2.5,0,0, "CONF:RngFilt(30,2.5)");
      AddCfg(configs,n, 3, IND_CONF_RANGEFILTER, 50,3.0,0,0, "CONF:RngFilt(50,3.0)");
      // Squeeze direction
      AddCfg(configs,n, 3, IND_CONF_SQUEEZE, 20,2.0,20,1.5, "CONF:SqzMom(20)");
      // Keltner direction
      AddCfg(configs,n, 3, IND_CONF_KELTNER, 20,20,1.5,0, "CONF:Keltner(20)");
      // Donchian direction
      AddCfg(configs,n, 3, IND_CONF_DONCHIAN, 20,0,0,0, "CONF:Donchian(20)");
      // MAMA direction
      AddCfg(configs,n, 3, IND_CONF_MAMA, 0.5,0.05,0,0, "CONF:MAMA(0.5/0.05)");
      // T3 direction
      AddCfg(configs,n, 3, IND_CONF_T3, 8,0.7,0,0, "CONF:T3(8)");
      // V2 winner: Stoch(8)
      AddCfg(configs,n, 3, IND_CONF_STOCH, 8,3,3,0, "CONF:Stoch(8)");
   }

   //--- SLOT 4: H1 Volume/Strength
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_VOLUME)
   {
      // Squeeze: squeeze OFF + momentum growing + direction matching
      AddCfg(configs,n, 4, IND_VOL_SQUEEZE, 20,2.0,20,1.5, "VOL:Squeeze(20/20)");
      AddCfg(configs,n, 4, IND_VOL_SQUEEZE, 20,2.0,20,2.0, "VOL:Squeeze(20/20)KC2.0");
      // Keltner bands expanding
      AddCfg(configs,n, 4, IND_VOL_KELTNER_EXP, 20,20,1.5,0, "VOL:KeltnerExp(20)");
      // Donchian bands expanding
      AddCfg(configs,n, 4, IND_VOL_DONCHIAN_EXP, 20,0,0,0, "VOL:DonchianExp(20)");
      AddCfg(configs,n, 4, IND_VOL_DONCHIAN_EXP, 15,0,0,0, "VOL:DonchianExp(15)");
      // V2 winner: BBwidth(20)
      AddCfg(configs,n, 4, IND_VOL_BB_WIDTH, 20,2.0,0,0, "VOL:BBwidth(20)");
      // No filter
      AddCfg(configs,n, 4, IND_VOL_NONE, 0,0,0,0, "VOL:NoFilter");
   }

   //--- SLOT 5: H1 Exit — flip against trade direction
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_EXIT)
   {
      // Supertrend flip
      AddCfg(configs,n, 5, IND_EXIT_SUPERTREND, 7,2.0,0,0, "EXIT:Supertrend(7,2.0)");
      AddCfg(configs,n, 5, IND_EXIT_SUPERTREND, 10,2.0,0,0, "EXIT:Supertrend(10,2.0)");
      AddCfg(configs,n, 5, IND_EXIT_SUPERTREND, 10,3.0,0,0, "EXIT:Supertrend(10,3.0)");
      // HalfTrend flip
      AddCfg(configs,n, 5, IND_EXIT_HALFTREND, 2,2,100,0, "EXIT:HalfTrend(2)");
      AddCfg(configs,n, 5, IND_EXIT_HALFTREND, 3,2,100,0, "EXIT:HalfTrend(3)");
      // RangeFilter flip
      AddCfg(configs,n, 5, IND_EXIT_RANGEFILTER, 20,2.0,0,0, "EXIT:RngFilt(20,2.0)");
      AddCfg(configs,n, 5, IND_EXIT_RANGEFILTER, 30,2.5,0,0, "EXIT:RngFilt(30,2.5)");
      // T3 direction change
      AddCfg(configs,n, 5, IND_EXIT_T3, 5,0.7,0,0, "EXIT:T3(5)");
      AddCfg(configs,n, 5, IND_EXIT_T3, 8,0.7,0,0, "EXIT:T3(8)");
      // McGinley direction change
      AddCfg(configs,n, 5, IND_EXIT_MCGINLEY, 8,0.6,0,0, "EXIT:McGinley(8)");
      AddCfg(configs,n, 5, IND_EXIT_MCGINLEY, 10,0.6,0,0, "EXIT:McGinley(10)");
      // JMA direction change
      AddCfg(configs,n, 5, IND_EXIT_JMA, 7,0,0,0, "EXIT:JMA(7)");
      AddCfg(configs,n, 5, IND_EXIT_JMA, 10,0,0,0, "EXIT:JMA(10)");
      // MAMA cross
      AddCfg(configs,n, 5, IND_EXIT_MAMA, 0.5,0.05,0,0, "EXIT:MAMA(0.5/0.05)");
      // Donchian midline cross
      AddCfg(configs,n, 5, IND_EXIT_DONCHIAN, 10,0,0,0, "EXIT:Donchian(10)");
      AddCfg(configs,n, 5, IND_EXIT_DONCHIAN, 15,0,0,0, "EXIT:Donchian(15)");
      // V2 winner: RSI(14)
      AddCfg(configs,n, 5, IND_EXIT_RSI, 14,0,0,0, "EXIT:RSI(14)");
   }

   ArrayResize(configs, n);
}

//+------------------------------------------------------------------+
//| HTF TREND FILTER (Slot 1)                                        |
//| Returns +1 (longs only) / -1 (shorts only) / 0 (no trade)       |
//+------------------------------------------------------------------+
int GetHTFDir(string sym, int h1Bar, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType;
   double p1, p2, p3;
   int htfTF;

   if(cfg.slot == 1)
   {
      iType = cfg.indType;
      p1 = cfg.p1; p2 = cfg.p2; p3 = cfg.p3;
      htfTF = (cfg.p4 >= 1440) ? PERIOD_D1 : PERIOD_H4;
   }
   else
   {
      // Locked: H4 KAMA(10)
      iType = IND_HTF_KAMA;
      p1 = 10; p2 = 2; p3 = 30;
      htfTF = PERIOD_H4;
   }

   // Map H1 bar time to HTF bar index
   datetime barTime = iTime(sym, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(sym, htfTF, barTime, false);
   if(htfBar < 1) return 0;

   switch(iType)
   {
      case IND_HTF_SUPERTREND:
         return GetSupertrendDir(sym, htfTF, (int)p1, p2, htfBar);
      case IND_HTF_RANGEFILTER:
         return GetRangeFilterDir(sym, htfTF, (int)p1, p2, htfBar);
      case IND_HTF_T3:
         return GetT3Dir(sym, htfTF, (int)p1, p2, htfBar);
      case IND_HTF_MCGINLEY:
         return GetMcGinleyDir(sym, htfTF, (int)p1, p2, htfBar);
      case IND_HTF_JMA:
         return GetJMADir(sym, htfTF, (int)p1, (int)p2, htfBar);
      case IND_HTF_MAMA:
         return GetMAMADir(sym, htfTF, p1, p2, htfBar);
      case IND_HTF_HALFTREND:
         return GetHalfTrendDir(sym, htfTF, (int)p1, (int)p2, (int)p3, htfBar);
      case IND_HTF_KAMA:
         return GetKAMADir(sym, htfTF, (int)p1, p2, p3, htfBar);
      case IND_HTF_EMA:
      {
         double ema   = iMA(sym, htfTF, (int)p1, 0, MODE_EMA, PRICE_CLOSE, htfBar);
         double close = iClose(sym, htfTF, htfBar);
         if(close > ema) return 1;
         if(close < ema) return -1;
         return 0;
      }
      default: return 0;
   }
}

// HTF flip detection for closing trades
bool HTFFlippedAgainst(string sym, int h1Bar, int tradeDir, SweepConfig &cfg)
{
   int dirNow  = GetHTFDir(sym, h1Bar,   cfg);
   int dirPrev = GetHTFDir(sym, h1Bar+1, cfg);
   if(tradeDir == 1  && dirNow == -1 && dirPrev != -1) return true;
   if(tradeDir == -1 && dirNow == 1  && dirPrev != 1)  return true;
   return false;
}

//+------------------------------------------------------------------+
//| ENTRY TRIGGER (Slot 2) — direction on H1                         |
//+------------------------------------------------------------------+
int GetEntryDir(string sym, int shift, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType;
   double p1, p2, p3;

   if(cfg.slot == 2)
   {
      iType = cfg.indType; p1 = cfg.p1; p2 = cfg.p2; p3 = cfg.p3;
   }
   else
   {
      // Locked: EMA(50) x Price
      iType = IND_ENTRY_EMA_PRICE;
      p1 = LOCKED_ENTRY_EMA_PER; p2 = 0; p3 = 0;
   }

   switch(iType)
   {
      case IND_ENTRY_SUPERTREND:
         return GetSupertrendDir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_ENTRY_RANGEFILTER:
         return GetRangeFilterDir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_ENTRY_HALFTREND:
         return GetHalfTrendDir(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3, shift);
      case IND_ENTRY_T3:
         return GetT3Dir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_ENTRY_MCGINLEY:
         return GetMcGinleyDir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_ENTRY_JMA:
         return GetJMADir(sym, PERIOD_H1, (int)p1, (int)p2, shift);
      case IND_ENTRY_MAMA:
         return GetMAMADir(sym, PERIOD_H1, p1, p2, shift);
      case IND_ENTRY_DONCHIAN:
         return GetDonchianDir(sym, PERIOD_H1, (int)p1, shift);
      case IND_ENTRY_KELTNER:
         return GetKeltnerDir(sym, PERIOD_H1, (int)p1, (int)p2, p3, shift);
      case IND_ENTRY_EMA_PRICE:
      {
         double ema   = iMA(sym, PERIOD_H1, (int)p1, 0, MODE_EMA, PRICE_CLOSE, shift);
         double close = iClose(sym, PERIOD_H1, shift);
         if(close > ema) return 1;
         if(close < ema) return -1;
         return 0;
      }
      default: return 0;
   }
}

bool EntryFlipOccurred(string sym, int bar, int htfDir, SweepConfig &cfg)
{
   int dirCurr = GetEntryDir(sym, bar,   cfg);
   int dirPrev = GetEntryDir(sym, bar+1, cfg);
   return (dirCurr == htfDir && dirPrev != htfDir);
}

//+------------------------------------------------------------------+
//| CONFIRMATION (Slot 3)                                             |
//+------------------------------------------------------------------+
int GetConfirmDir(string sym, int shift, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType;
   double p1, p2, p3, p4;

   if(cfg.slot == 3)
   {
      iType = cfg.indType; p1 = cfg.p1; p2 = cfg.p2; p3 = cfg.p3; p4 = cfg.p4;
   }
   else
   {
      // Locked: Stoch(8)
      iType = IND_CONF_STOCH;
      p1 = LOCKED_CONF_STOCH_K; p2 = LOCKED_CONF_STOCH_D; p3 = LOCKED_CONF_STOCH_SL; p4 = 0;
   }

   switch(iType)
   {
      case IND_CONF_SUPERTREND:
         return GetSupertrendDir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_CONF_HALFTREND:
         return GetHalfTrendDir(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3, shift);
      case IND_CONF_RANGEFILTER:
         return GetRangeFilterDir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_CONF_SQUEEZE:
         return GetSqueezeDir(sym, PERIOD_H1, (int)p1, p2, (int)p3, p4, (int)p1, shift);
      case IND_CONF_KELTNER:
         return GetKeltnerDir(sym, PERIOD_H1, (int)p1, (int)p2, p3, shift);
      case IND_CONF_DONCHIAN:
         return GetDonchianDir(sym, PERIOD_H1, (int)p1, shift);
      case IND_CONF_MAMA:
         return GetMAMADir(sym, PERIOD_H1, p1, p2, shift);
      case IND_CONF_T3:
         return GetT3Dir(sym, PERIOD_H1, (int)p1, p2, shift);
      case IND_CONF_STOCH:
      {
         double val = iStochastic(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                                   MODE_SMA, 0, MODE_MAIN, shift);
         if(val > 50) return 1;
         if(val < 50) return -1;
         return 0;
      }
      default: return 0;
   }
}

//+------------------------------------------------------------------+
//| VOLUME (Slot 4)                                                   |
//+------------------------------------------------------------------+
bool CheckVolume(string sym, int shift, int direction, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType;
   double p1, p2, p3, p4;

   if(cfg.slot == 4)
   {
      iType = cfg.indType; p1 = cfg.p1; p2 = cfg.p2; p3 = cfg.p3; p4 = cfg.p4;
   }
   else
   {
      // Locked: BBwidth(20) expanding
      iType = IND_VOL_BB_WIDTH;
      p1 = LOCKED_VOL_BB_PER; p2 = LOCKED_VOL_BB_DEV; p3 = 0; p4 = 0;
   }

   switch(iType)
   {
      case IND_VOL_SQUEEZE:
      {
         // Squeeze must be OFF (volatility breakout) AND momentum must agree with direction AND growing
         int bbLen = (int)p1; int kcLen = (int)p3; int momLen = bbLen;
         if(!SqueezeFiring(sym, PERIOD_H1, bbLen, p2, kcLen, p4, momLen, shift))
            return false;
         int momDir = GetSqueezeDir(sym, PERIOD_H1, bbLen, p2, kcLen, p4, momLen, shift);
         if(momDir != direction) return false;
         return SqueezeMomGrowing(sym, PERIOD_H1, bbLen, p2, kcLen, p4, momLen, shift);
      }
      case IND_VOL_KELTNER_EXP:
         return KeltnerExpanding(sym, PERIOD_H1, (int)p1, (int)p2, p3, shift);
      case IND_VOL_DONCHIAN_EXP:
         return DonchianExpanding(sym, PERIOD_H1, (int)p1, shift);
      case IND_VOL_BB_WIDTH:
      {
         double upper  = iBands(sym, PERIOD_H1, (int)p1, p2, 0, PRICE_CLOSE, MODE_UPPER, shift);
         double lower  = iBands(sym, PERIOD_H1, (int)p1, p2, 0, PRICE_CLOSE, MODE_LOWER, shift);
         double mid    = iBands(sym, PERIOD_H1, (int)p1, p2, 0, PRICE_CLOSE, MODE_MAIN,  shift);
         double upperP = iBands(sym, PERIOD_H1, (int)p1, p2, 0, PRICE_CLOSE, MODE_UPPER, shift+1);
         double lowerP = iBands(sym, PERIOD_H1, (int)p1, p2, 0, PRICE_CLOSE, MODE_LOWER, shift+1);
         double midP   = iBands(sym, PERIOD_H1, (int)p1, p2, 0, PRICE_CLOSE, MODE_MAIN,  shift+1);
         if(mid==0 || midP==0) return false;
         double width     = (upper - lower) / mid;
         double widthPrev = (upperP - lowerP) / midP;
         return (width > widthPrev);
      }
      case IND_VOL_NONE:
         return true;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| EXIT (Slot 5) — flip against trade direction                     |
//+------------------------------------------------------------------+
bool CheckExit(string sym, int shift, int tradeDir, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType;
   double p1, p2, p3;

   if(cfg.slot == 5)
   {
      iType = cfg.indType; p1 = cfg.p1; p2 = cfg.p2; p3 = cfg.p3;
   }
   else
   {
      // Locked: RSI(14) cross 50
      iType = IND_EXIT_RSI;
      p1 = LOCKED_EXIT_RSI_PER; p2 = 0; p3 = 0;
   }

   int dir = 0;
   switch(iType)
   {
      case IND_EXIT_SUPERTREND:
         dir = GetSupertrendDir(sym, PERIOD_H1, (int)p1, p2, shift);
         break;
      case IND_EXIT_HALFTREND:
         dir = GetHalfTrendDir(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3, shift);
         break;
      case IND_EXIT_RANGEFILTER:
         dir = GetRangeFilterDir(sym, PERIOD_H1, (int)p1, p2, shift);
         break;
      case IND_EXIT_T3:
         dir = GetT3Dir(sym, PERIOD_H1, (int)p1, p2, shift);
         break;
      case IND_EXIT_MCGINLEY:
         dir = GetMcGinleyDir(sym, PERIOD_H1, (int)p1, p2, shift);
         break;
      case IND_EXIT_JMA:
         dir = GetJMADir(sym, PERIOD_H1, (int)p1, (int)p2, shift);
         break;
      case IND_EXIT_MAMA:
         dir = GetMAMADir(sym, PERIOD_H1, p1, p2, shift);
         break;
      case IND_EXIT_DONCHIAN:
         dir = GetDonchianDir(sym, PERIOD_H1, (int)p1, shift);
         break;
      case IND_EXIT_RSI:
      {
         double rsi = iRSI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(rsi > 50) dir = 1;
         else if(rsi < 50) dir = -1;
         break;
      }
      default: return false;
   }

   // Exit when indicator direction is AGAINST trade
   if(tradeDir == 1  && dir == -1) return true;
   if(tradeDir == -1 && dir ==  1) return true;
   return false;
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                  |
//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar, SweepConfig &cfg)
{
   // 1. HTF Trend Filter
   int htfDir = GetHTFDir(sym, bar, cfg);
   if(htfDir == 0) return 0;

   // 2. Entry Trigger — must be a FLIP in the HTF direction
   if(!EntryFlipOccurred(sym, bar, htfDir, cfg)) return 0;

   // 3. Confirmation — current or previous bar must agree
   int confCurr = GetConfirmDir(sym, bar,   cfg);
   int confPrev = GetConfirmDir(sym, bar+1, cfg);
   if(confCurr != htfDir && confPrev != htfDir) return 0;

   // 4. Volume
   if(!CheckVolume(sym, bar, htfDir, cfg)) return 0;

   return htfDir;
}

//+------------------------------------------------------------------+
//| BACKTEST ENGINE (identical to V2)                                 |
//+------------------------------------------------------------------+
void RunBacktest(string sym, int startBar, int endBar, double spread,
                  double tickVal, double tickSz, SweepConfig &cfg, PStats &stats)
{
   stats.sig=0; stats.wins=0; stats.losses=0;
   stats.gp=0; stats.gl=0; stats.maxDD=0; stats.maxDDPct=0;
   stats.bal=LOCKED_BAL;

   double balance=LOCKED_BAL, peak=LOCKED_BAL;
   VTrade trade;
   trade.o1Open=false; trade.o2Open=false;
   trade.movedBE=false; trade.pnl=0;
   trade.dir=0; trade.entry=0; trade.sl=0; trade.tp1=0;
   trade.lots1=0; trade.lots2=0;

   for(int bar=startBar-1; bar>endBar; bar--)
   {
      if(trade.o1Open || trade.o2Open)
         Manage(sym, bar, spread, trade, balance, peak, stats, tickVal, tickSz, cfg);
      if(trade.o1Open || trade.o2Open) continue;

      datetime barTime = iTime(sym, PERIOD_H1, bar);
      if(!InSession(barTime)) continue;

      int signal = EvalEntry(sym, bar, cfg);
      if(signal == 0) continue;
      stats.sig++;

      double atr = iATR(sym, PERIOD_H1, LOCKED_ATR, bar);
      if(atr <= 0) continue;

      double openNext = iOpen(sym, PERIOD_H1, bar-1);
      if(openNext <= 0) continue;

      double entry   = (signal==1) ? openNext + spread : openNext;
      double slDist  = LOCKED_SL  * atr;
      double tp1Dist = LOCKED_TP1 * atr;

      double risk    = balance * (LOCKED_RISK / 100.0);
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

      if(signal == 1)
      {
         trade.sl  = entry - slDist;
         trade.tp1 = entry + tp1Dist;
      }
      else
      {
         trade.sl  = entry + slDist;
         trade.tp1 = entry - tp1Dist;
      }
   }

   if(trade.o1Open || trade.o2Open)
   {
      double lc = iClose(sym, PERIOD_H1, endBar);
      double ep = (trade.dir==1) ? lc : lc + spread;
      FClose(trade, ep, balance, peak, stats, tickVal, tickSz);
   }
   stats.bal = balance;
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void Manage(string sym, int bar, double spread, VTrade &t,
             double &bal, double &peak, PStats &s, double tv, double ts, SweepConfig &cfg)
{
   double hi  = iHigh (sym, PERIOD_H1, bar);
   double lo  = iLow  (sym, PERIOD_H1, bar);
   double cl  = iClose(sym, PERIOD_H1, bar);
   double aHi = hi + spread;
   double aLo = lo + spread;
   double aCl = cl + spread;

   if(HTFFlippedAgainst(sym, bar, t.dir, cfg))
   {
      double ep = (t.dir==1) ? cl : aCl;
      FClose(t, ep, bal, peak, s, tv, ts);
      return;
   }

   if(t.o1Open)
   {
      bool tp=false, sl=false;
      double pnl=0;
      if(t.dir == 1)
      {
         if(hi >= t.tp1)  { tp=true; pnl=(t.tp1-t.entry)/ts*tv*t.lots1; }
         else if(lo<=t.sl){ sl=true; pnl=(t.sl -t.entry)/ts*tv*t.lots1; }
      }
      else
      {
         if(aLo<=t.tp1)   { tp=true; pnl=(t.entry-t.tp1)/ts*tv*t.lots1; }
         else if(aHi>=t.sl){ sl=true; pnl=(t.entry-t.sl )/ts*tv*t.lots1; }
      }
      if(tp || sl)
      {
         bal    += pnl;
         t.pnl  += pnl;
         if(pnl > 0) s.gp += pnl; else s.gl += pnl;
         t.o1Open = false;
         if(tp && t.o2Open)
         {
            t.sl      = t.entry;
            t.movedBE = true;
         }
      }
   }

   if(t.o2Open)
   {
      bool slHit = false;
      if(t.dir ==  1 && lo  <= t.sl) slHit = true;
      if(t.dir == -1 && aHi >= t.sl) slHit = true;

      bool exitFlip = CheckExit(sym, bar, t.dir, cfg);

      double pnl=0;
      if(slHit)
      {
         pnl = (t.dir==1) ? (t.sl-t.entry)/ts*tv*t.lots2 : (t.entry-t.sl)/ts*tv*t.lots2;
         bal    += pnl;
         t.pnl  += pnl;
         if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
         t.o2Open = false;
      }
      else if(exitFlip)
      {
         double ep = (t.dir==1) ? cl : aCl;
         pnl = (t.dir==1) ? (ep-t.entry)/ts*tv*t.lots2 : (t.entry-ep)/ts*tv*t.lots2;
         bal    += pnl;
         t.pnl  += pnl;
         if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
         t.o2Open = false;
      }
   }

   if(!t.o1Open && !t.o2Open)
   {
      if(t.pnl >= 0) s.wins++; else s.losses++;
   }

   if(bal > peak) peak = bal;
   double dd = peak - bal;
   if(dd > s.maxDD)
   {
      s.maxDD    = dd;
      s.maxDDPct = (dd / peak) * 100.0;
   }
}

//+------------------------------------------------------------------+
//| FORCE CLOSE                                                       |
//+------------------------------------------------------------------+
void FClose(VTrade &t, double ep, double &bal, double &peak, PStats &s, double tv, double ts)
{
   if(t.o1Open)
   {
      double pnl = (t.dir==1) ? (ep-t.entry)/ts*tv*t.lots1 : (t.entry-ep)/ts*tv*t.lots1;
      bal   += pnl;
      t.pnl += pnl;
      if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
      t.o1Open = false;
   }
   if(t.o2Open)
   {
      double pnl = (t.dir==1) ? (ep-t.entry)/ts*tv*t.lots2 : (t.entry-ep)/ts*tv*t.lots2;
      bal   += pnl;
      t.pnl += pnl;
      if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
      t.o2Open = false;
   }
   if(t.pnl >= 0) s.wins++; else s.losses++;
   if(bal > peak) peak = bal;
   double dd = peak - bal;
   if(dd > s.maxDD)
   {
      s.maxDD    = dd;
      s.maxDDPct = (dd / peak) * 100.0;
   }
}

//+------------------------------------------------------------------+
//| SORT & OUTPUT                                                     |
//+------------------------------------------------------------------+
void SortResults(SweepResult &arr[], int count)
{
   for(int i=0; i<count-1; i++)
      for(int j=0; j<count-i-1; j++)
         if(arr[j].aggPF < arr[j+1].aggPF)
         {
            SweepResult tmp = arr[j];
            arr[j]   = arr[j+1];
            arr[j+1] = tmp;
         }
}

void PrintTop(SweepResult &res[], int count)
{
   Print("===== TOP ", count, " H1 V3 CUSTOM INDICATOR CONFIGS (by Aggregate PF) =====");
   for(int i=0; i<count; i++)
   {
      Print(StringFormat("#%d %s | Net=$%.2f PF=%.2f WR=%.1f%% DD=%.1f%% Sig=%d",
            i+1, res[i].label, res[i].aggNet, res[i].aggPF,
            res[i].avgWR, res[i].worstDD, res[i].totalSig));
   }
}

void WriteCSV(SweepResult &res[], int count)
{
   string filename = "NNFX_H1_SweepV3_Results.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle,
             "Rank", "Indicator", "Slot",
             "EURUSD_PF","GBPUSD_PF","USDJPY_PF","USDCHF_PF","AUDUSD_PF","NZDUSD_PF","USDCAD_PF",
             "EURUSD_Net","GBPUSD_Net","USDJPY_Net","USDCHF_Net","AUDUSD_Net","NZDUSD_Net","USDCAD_Net",
             "Agg_NetProfit","Agg_PF","Avg_WR%","Worst_DD%","Total_Signals");

   for(int i=0; i<count; i++)
   {
      SweepResult r = res[i];
      string slotName = "";
      if(r.slot==1) slotName="HTF_Trend";
      if(r.slot==2) slotName="Entry_Trigger";
      if(r.slot==3) slotName="Confirmation";
      if(r.slot==4) slotName="Volume";
      if(r.slot==5) slotName="Exit";

      FileWrite(handle,
                i+1, r.label, slotName,
                DoubleToStr(r.pairPF[0],2), DoubleToStr(r.pairPF[1],2), DoubleToStr(r.pairPF[2],2),
                DoubleToStr(r.pairPF[3],2), DoubleToStr(r.pairPF[4],2), DoubleToStr(r.pairPF[5],2),
                DoubleToStr(r.pairPF[6],2),
                DoubleToStr(r.pairNet[0],2), DoubleToStr(r.pairNet[1],2), DoubleToStr(r.pairNet[2],2),
                DoubleToStr(r.pairNet[3],2), DoubleToStr(r.pairNet[4],2), DoubleToStr(r.pairNet[5],2),
                DoubleToStr(r.pairNet[6],2),
                DoubleToStr(r.aggNet,2), DoubleToStr(r.aggPF,2),
                DoubleToStr(r.avgWR,1),  DoubleToStr(r.worstDD,1),
                r.totalSig);
   }

   FileClose(handle);
   Print("Results saved to: MQL4/Files/", filename);
}
//+------------------------------------------------------------------+
