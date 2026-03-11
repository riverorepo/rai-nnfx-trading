//+------------------------------------------------------------------+
//|                                        NNFX_H1_ComboSweep.mq4   |
//|  Mass combo sweep: 5-slot indicator combinations × 11 pairs      |
//|  HTF(6) × Entry(7) × Confirm(11) × Volume(2) × Exit(7)         |
//|  = 6,468 combos × 11 pairs = ~71K backtests                     |
//|  Aggressive settings: 5% risk, 1.0× SL, 1.5× TP, no session    |
//|  Composite score = aggPF × sqrt(totalSignals)                    |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property strict
#property show_inputs

//+------------------------------------------------------------------+
//| BASE INDICATOR ENUM (shared across slots)                        |
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

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input int    InpMaxResults  = 200;      // Max results to save
input bool   InpPartialSave = true;     // Save partial results every 500 combos

//+------------------------------------------------------------------+
//| AGGRESSIVE HARDCODED SETTINGS                                     |
//+------------------------------------------------------------------+
#define RISK_PCT         5.0
#define SL_MULT          1.0
#define TP1_MULT         1.5
#define ATR_PERIOD       14
#define START_BALANCE    10000.0

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

#define NUM_PAIRS        11

//+------------------------------------------------------------------+
//| STRUCTS                                                           |
//+------------------------------------------------------------------+
struct ComboConfig
{
   ENUM_BASE_IND htfInd;
   ENUM_BASE_IND entryInd;
   ENUM_BASE_IND confirmInd;
   ENUM_BASE_IND volumeInd;
   ENUM_BASE_IND exitInd;
   // Default params per indicator (one set per slot)
   double htfP1, htfP2, htfP3;
   double entP1, entP2, entP3;
   double confP1, confP2, confP3, confP4;
   double volP1, volP2, volP3, volP4;
   double exP1, exP2, exP3;
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

struct ComboResult
{
   string htfName, entName, confName, volName, exName;
   double pairPF[NUM_PAIRS];
   double pairNet[NUM_PAIRS];
   double aggPF, aggNet;
   double avgWR, worstDD;
   int    totalSig;
   double compositeScore;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string g_pairs[NUM_PAIRS];
int    g_startBar[NUM_PAIRS], g_endBar[NUM_PAIRS];
double g_tickVal[NUM_PAIRS], g_tickSz[NUM_PAIRS], g_pointVal[NUM_PAIRS], g_spread[NUM_PAIRS];

int GetTypicalSpread(string s)
{
   if(s=="EURUSD") return 14; if(s=="GBPUSD") return 18; if(s=="USDJPY") return 14;
   if(s=="USDCHF") return 17; if(s=="AUDUSD") return 14; if(s=="NZDUSD") return 20;
   if(s=="USDCAD") return 20; if(s=="EURJPY") return 22; if(s=="GBPJPY") return 30;
   if(s=="EURGBP") return 18; if(s=="AUDJPY") return 22; return 20;
}

//+------------------------------------------------------------------+
//| INDICATOR NAME HELPERS                                            |
//+------------------------------------------------------------------+
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
//| CUSTOM INDICATOR SIGNAL HELPERS                                   |
//| All return +1 (bullish), -1 (bearish), or 0                     |
//+------------------------------------------------------------------+

int GetSupertrendDir(string sym, int tf, int atrPer, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_SUPERTREND, atrPer, mult, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetRangeFilterDir(string sym, int tf, int period, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_RANGEFILTER, period, mult, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetHalfTrendDir(string sym, int tf, int amp, int chDev, int atrPer, int shift)
{
   double sig = iCustom(sym, tf, IND_HALFTREND, amp, chDev, atrPer, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetT3Dir(string sym, int tf, int period, double vfactor, int shift)
{
   double sig = iCustom(sym, tf, IND_T3, period, vfactor, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetMcGinleyDir(string sym, int tf, int period, double k, int shift)
{
   double sig = iCustom(sym, tf, IND_MCGINLEY, period, k, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetJMADir(string sym, int tf, int length, int phase, int shift)
{
   double sig = iCustom(sym, tf, IND_JMA_NAME, length, phase, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetMAMADir(string sym, int tf, double fast, double slow, int shift)
{
   double sig = iCustom(sym, tf, IND_MAMA, fast, slow, PRICE_MEDIAN, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetDonchianDir(string sym, int tf, int period, int shift)
{
   double sig = iCustom(sym, tf, IND_DONCHIAN, period, true, 3, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetKeltnerDir(string sym, int tf, int maPer, int atrPer, double mult, int shift)
{
   double sig = iCustom(sym, tf, IND_KELTNER, maPer, atrPer, mult, MODE_EMA, PRICE_CLOSE, 3, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetSqueezeDir(string sym, int tf, int bbLen, double bbMult, int kcLen, double kcMult, int momLen, int shift)
{
   double sig = iCustom(sym, tf, IND_SQUEEZE, bbLen, bbMult, kcLen, kcMult, momLen, 4, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
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
   double absMom  = MathAbs(momPos) + MathAbs(momNeg);
   double absMomP = MathAbs(momPosP) + MathAbs(momNegP);
   return (absMom > absMomP);
}

//+------------------------------------------------------------------+
//| GENERIC SIGNAL DISPATCH — read direction from any base indicator  |
//| on any timeframe with default params per slot                     |
//+------------------------------------------------------------------+
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
//| SLOT-SPECIFIC SIGNAL FUNCTIONS                                    |
//+------------------------------------------------------------------+

// Slot 1: HTF Filter — direction on H4
int GetHTFDir(string sym, int h1Bar, ComboConfig &cfg)
{
   datetime barTime = iTime(sym, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(sym, PERIOD_H4, barTime, false);
   if(htfBar < 1) return 0;
   return GetDirection(sym, PERIOD_H4, cfg.htfInd, cfg.htfP1, cfg.htfP2, cfg.htfP3, 0, htfBar);
}

bool HTFFlippedAgainst(string sym, int h1Bar, int tradeDir, ComboConfig &cfg)
{
   int dirNow  = GetHTFDir(sym, h1Bar,   cfg);
   int dirPrev = GetHTFDir(sym, h1Bar+1, cfg);
   if(tradeDir == 1  && dirNow == -1 && dirPrev != -1) return true;
   if(tradeDir == -1 && dirNow == 1  && dirPrev != 1)  return true;
   return false;
}

// Slot 2: Entry — flip detection on H1
int GetEntryDir(string sym, int shift, ComboConfig &cfg)
{
   return GetDirection(sym, PERIOD_H1, cfg.entryInd, cfg.entP1, cfg.entP2, cfg.entP3, 0, shift);
}

bool EntryFlipOccurred(string sym, int bar, int htfDir, ComboConfig &cfg)
{
   int dirCurr = GetEntryDir(sym, bar,   cfg);
   int dirPrev = GetEntryDir(sym, bar+1, cfg);
   return (dirCurr == htfDir && dirPrev != htfDir);
}

// Slot 3: Confirmation — direction agrees (relaxed: current or prev 2 bars)
bool ConfirmAgrees(string sym, int bar, int htfDir, ComboConfig &cfg)
{
   if(cfg.confirmInd == BASE_NONE) return true;
   int dir0 = GetDirection(sym, PERIOD_H1, cfg.confirmInd, cfg.confP1, cfg.confP2, cfg.confP3, cfg.confP4, bar);
   if(dir0 == htfDir) return true;
   int dir1 = GetDirection(sym, PERIOD_H1, cfg.confirmInd, cfg.confP1, cfg.confP2, cfg.confP3, cfg.confP4, bar+1);
   if(dir1 == htfDir) return true;
   int dir2 = GetDirection(sym, PERIOD_H1, cfg.confirmInd, cfg.confP1, cfg.confP2, cfg.confP3, cfg.confP4, bar+2);
   if(dir2 == htfDir) return true;
   return false;
}

// Slot 4: Volume — momentum filter
bool CheckVolume(string sym, int shift, int direction, ComboConfig &cfg)
{
   if(cfg.volumeInd == BASE_NONE) return true;
   // Squeeze: squeeze OFF + momentum direction match + growing
   int bbLen = (int)cfg.volP1; int kcLen = (int)cfg.volP3; int momLen = bbLen;
   if(!SqueezeFiring(sym, PERIOD_H1, bbLen, cfg.volP2, kcLen, cfg.volP4, momLen, shift))
      return false;
   int momDir = GetSqueezeDir(sym, PERIOD_H1, bbLen, cfg.volP2, kcLen, cfg.volP4, momLen, shift);
   if(momDir != direction) return false;
   return SqueezeMomGrowing(sym, PERIOD_H1, bbLen, cfg.volP2, kcLen, cfg.volP4, momLen, shift);
}

// Slot 5: Exit — flip against trade direction
bool CheckExit(string sym, int shift, int tradeDir, ComboConfig &cfg)
{
   int dir = GetDirection(sym, PERIOD_H1, cfg.exitInd, cfg.exP1, cfg.exP2, cfg.exP3, 0, shift);
   if(tradeDir == 1  && dir == -1) return true;
   if(tradeDir == -1 && dir ==  1) return true;
   return false;
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                  |
//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar, ComboConfig &cfg)
{
   int htfDir = GetHTFDir(sym, bar, cfg);
   if(htfDir == 0) return 0;
   if(!EntryFlipOccurred(sym, bar, htfDir, cfg)) return 0;
   if(!ConfirmAgrees(sym, bar, htfDir, cfg)) return 0;
   if(!CheckVolume(sym, bar, htfDir, cfg)) return 0;
   return htfDir;
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
   if(dd > s.maxDD) { s.maxDD = dd; s.maxDDPct = (dd/peak)*100.0; }
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void Manage(string sym, int bar, double spread, VTrade &t,
            double &bal, double &peak, PStats &s, double tv, double ts, ComboConfig &cfg)
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
         if(tp && t.o2Open) { t.sl = t.entry; t.movedBE = true; }
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
         bal += pnl; t.pnl += pnl;
         if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
         t.o2Open = false;
      }
      else if(exitFlip)
      {
         double ep = (t.dir==1) ? cl : aCl;
         pnl = (t.dir==1) ? (ep-t.entry)/ts*tv*t.lots2 : (t.entry-ep)/ts*tv*t.lots2;
         bal += pnl; t.pnl += pnl;
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
   if(dd > s.maxDD) { s.maxDD = dd; s.maxDDPct = (dd/peak)*100.0; }
}

//+------------------------------------------------------------------+
//| BACKTEST ENGINE                                                   |
//+------------------------------------------------------------------+
void RunBacktest(string sym, int startBar, int endBar, double spread,
                 double tickVal, double tickSz, ComboConfig &cfg, PStats &stats)
{
   stats.sig=0; stats.wins=0; stats.losses=0;
   stats.gp=0; stats.gl=0; stats.maxDD=0; stats.maxDDPct=0;
   stats.bal=START_BALANCE;

   double balance=START_BALANCE, peak=START_BALANCE;
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

      // No session filter — aggressive: trade all hours

      int signal = EvalEntry(sym, bar, cfg);
      if(signal == 0) continue;
      stats.sig++;

      double atr = iATR(sym, PERIOD_H1, ATR_PERIOD, bar);
      if(atr <= 0) continue;

      double openNext = iOpen(sym, PERIOD_H1, bar-1);
      if(openNext <= 0) continue;

      double entry   = (signal==1) ? openNext + spread : openNext;
      double slDist  = SL_MULT  * atr;
      double tp1Dist = TP1_MULT * atr;

      // Compounding: risk % of current balance
      double risk    = balance * (RISK_PCT / 100.0);
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

      if(signal == 1) { trade.sl = entry - slDist; trade.tp1 = entry + tp1Dist; }
      else            { trade.sl = entry + slDist; trade.tp1 = entry - tp1Dist; }
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
//| DEFAULT PARAMS PER BASE INDICATOR                                 |
//+------------------------------------------------------------------+
void GetDefaultHTFParams(ENUM_BASE_IND ind, double &p1, double &p2, double &p3)
{
   p1=0; p2=0; p3=0;
   switch(ind)
   {
      case BASE_MCGINLEY:    p1=14; p2=0.6; break;
      case BASE_SUPERTREND:  p1=10; p2=3.0; break;
      case BASE_MAMA:        p1=0.5; p2=0.05; break;
      case BASE_T3:          p1=8; p2=0.7; break;
      case BASE_JMA:         p1=14; p2=0; break;
      case BASE_RANGEFILTER: p1=30; p2=2.5; break;
      default: break;
   }
}

void GetDefaultEntryParams(ENUM_BASE_IND ind, double &p1, double &p2, double &p3)
{
   p1=0; p2=0; p3=0;
   switch(ind)
   {
      case BASE_KELTNER:     p1=20; p2=20; p3=1.5; break;
      case BASE_DONCHIAN:    p1=20; break;
      case BASE_RANGEFILTER: p1=30; p2=2.5; break;
      case BASE_SUPERTREND:  p1=10; p2=2.0; break;
      case BASE_HALFTREND:   p1=3; p2=2; p3=100; break;
      case BASE_T3:          p1=5; p2=0.7; break;
      case BASE_JMA:         p1=10; p2=0; break;
      default: break;
   }
}

void GetDefaultConfirmParams(ENUM_BASE_IND ind, double &p1, double &p2, double &p3, double &p4)
{
   p1=0; p2=0; p3=0; p4=0;
   switch(ind)
   {
      case BASE_SUPERTREND:  p1=10; p2=2.0; break;
      case BASE_RANGEFILTER: p1=30; p2=2.5; break;
      case BASE_HALFTREND:   p1=3; p2=2; p3=100; break;
      case BASE_MAMA:        p1=0.5; p2=0.05; break;
      case BASE_DONCHIAN:    p1=20; break;
      case BASE_KELTNER:     p1=20; p2=20; p3=1.5; break;
      case BASE_T3:          p1=8; p2=0.7; break;
      case BASE_MCGINLEY:    p1=14; p2=0.6; break;
      case BASE_JMA:         p1=14; p2=0; break;
      case BASE_SQUEEZE:     p1=20; p2=2.0; p3=20; p4=1.5; break;
      case BASE_NONE:        break;
      default: break;
   }
}

void GetDefaultExitParams(ENUM_BASE_IND ind, double &p1, double &p2, double &p3)
{
   p1=0; p2=0; p3=0;
   switch(ind)
   {
      case BASE_HALFTREND:   p1=3; p2=2; p3=100; break;
      case BASE_SUPERTREND:  p1=10; p2=2.0; break;
      case BASE_MAMA:        p1=0.5; p2=0.05; break;
      case BASE_T3:          p1=5; p2=0.7; break;
      case BASE_JMA:         p1=7; p2=0; break;
      case BASE_RANGEFILTER: p1=20; p2=2.0; break;
      case BASE_MCGINLEY:    p1=10; p2=0.6; break;
      default: break;
   }
}

//+------------------------------------------------------------------+
//| CSV OUTPUT                                                        |
//+------------------------------------------------------------------+
void WriteCSV(ComboResult &res[], int count, string filename)
{
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle,
      "Rank", "HTF_Ind", "Entry_Ind", "Confirm_Ind", "Volume_Ind", "Exit_Ind",
      "EURUSD_PF","GBPUSD_PF","USDJPY_PF","USDCHF_PF","AUDUSD_PF","NZDUSD_PF","USDCAD_PF",
      "EURJPY_PF","GBPJPY_PF","EURGBP_PF","AUDJPY_PF",
      "EURUSD_Net","GBPUSD_Net","USDJPY_Net","USDCHF_Net","AUDUSD_Net","NZDUSD_Net","USDCAD_Net",
      "EURJPY_Net","GBPJPY_Net","EURGBP_Net","AUDJPY_Net",
      "Agg_PF","Agg_Net","Avg_WR%","Worst_DD%","Total_Signals","Composite_Score");

   int toWrite = MathMin(count, InpMaxResults);
   for(int i=0; i<toWrite; i++)
   {
      FileWrite(handle,
         i+1, res[i].htfName, res[i].entName, res[i].confName, res[i].volName, res[i].exName,
         DoubleToStr(res[i].pairPF[0],2), DoubleToStr(res[i].pairPF[1],2), DoubleToStr(res[i].pairPF[2],2),
         DoubleToStr(res[i].pairPF[3],2), DoubleToStr(res[i].pairPF[4],2), DoubleToStr(res[i].pairPF[5],2),
         DoubleToStr(res[i].pairPF[6],2), DoubleToStr(res[i].pairPF[7],2), DoubleToStr(res[i].pairPF[8],2),
         DoubleToStr(res[i].pairPF[9],2), DoubleToStr(res[i].pairPF[10],2),
         DoubleToStr(res[i].pairNet[0],2), DoubleToStr(res[i].pairNet[1],2), DoubleToStr(res[i].pairNet[2],2),
         DoubleToStr(res[i].pairNet[3],2), DoubleToStr(res[i].pairNet[4],2), DoubleToStr(res[i].pairNet[5],2),
         DoubleToStr(res[i].pairNet[6],2), DoubleToStr(res[i].pairNet[7],2), DoubleToStr(res[i].pairNet[8],2),
         DoubleToStr(res[i].pairNet[9],2), DoubleToStr(res[i].pairNet[10],2),
         DoubleToStr(res[i].aggPF,2), DoubleToStr(res[i].aggNet,2),
         DoubleToStr(res[i].avgWR,1), DoubleToStr(res[i].worstDD,1),
         res[i].totalSig, DoubleToStr(res[i].compositeScore,2));
   }
   FileClose(handle);
   Print("Results saved: MQL4/Files/", filename);
}

//+------------------------------------------------------------------+
//| SORT by composite score (descending)                              |
//+------------------------------------------------------------------+
void SortResults(ComboResult &arr[], int count)
{
   for(int i=0; i<count-1; i++)
      for(int j=0; j<count-i-1; j++)
         if(arr[j].compositeScore < arr[j+1].compositeScore)
         {
            ComboResult tmp = arr[j];
            arr[j]   = arr[j+1];
            arr[j+1] = tmp;
         }
}

//+------------------------------------------------------------------+
//| INSERT INTO TOP-N BUFFER (keeps only best N results in memory)    |
//+------------------------------------------------------------------+
void InsertResult(ComboResult &arr[], int &count, int maxKeep, ComboResult &newRes)
{
   if(count < maxKeep)
   {
      arr[count] = newRes;
      count++;
      return;
   }
   // Find minimum score in buffer
   int minIdx = 0;
   double minScore = arr[0].compositeScore;
   for(int i=1; i<count; i++)
   {
      if(arr[i].compositeScore < minScore)
      {
         minScore = arr[i].compositeScore;
         minIdx = i;
      }
   }
   if(newRes.compositeScore > minScore)
      arr[minIdx] = newRes;
}

//+------------------------------------------------------------------+
//| OnStart — MAIN COMBO SWEEP                                        |
//+------------------------------------------------------------------+
void OnStart()
{
   // Initialize pairs
   g_pairs[0]="EURUSD"; g_pairs[1]="GBPUSD"; g_pairs[2]="USDJPY";
   g_pairs[3]="USDCHF"; g_pairs[4]="AUDUSD"; g_pairs[5]="NZDUSD"; g_pairs[6]="USDCAD";
   g_pairs[7]="EURJPY"; g_pairs[8]="GBPJPY"; g_pairs[9]="EURGBP"; g_pairs[10]="AUDJPY";

   datetime startDate = D'2020.01.01';
   datetime endDate   = D'2025.01.01';

   // Initialize pair data
   for(int p=0; p<NUM_PAIRS; p++)
   {
      g_startBar[p] = iBarShift(g_pairs[p], PERIOD_H1, startDate, false);
      g_endBar[p]   = iBarShift(g_pairs[p], PERIOD_H1, endDate, false);
      if(g_endBar[p]<0)    g_endBar[p]=0;
      if(g_startBar[p]<0)  g_startBar[p]=iBars(g_pairs[p],PERIOD_H1)-1;
      g_tickVal[p]  = MarketInfo(g_pairs[p], MODE_TICKVALUE);
      g_tickSz[p]   = MarketInfo(g_pairs[p], MODE_TICKSIZE);
      g_pointVal[p] = MarketInfo(g_pairs[p], MODE_POINT);
      g_spread[p]   = GetTypicalSpread(g_pairs[p]) * g_pointVal[p];
      Print(g_pairs[p], " bars: ", g_startBar[p]-g_endBar[p],
            " tv=", DoubleToStr(g_tickVal[p],4), " ts=", DoubleToStr(g_tickSz[p],6));
   }

   // Define indicator pools per slot
   ENUM_BASE_IND htfPool[];   ArrayResize(htfPool, 6);
   htfPool[0]=BASE_MCGINLEY; htfPool[1]=BASE_SUPERTREND; htfPool[2]=BASE_MAMA;
   htfPool[3]=BASE_T3; htfPool[4]=BASE_JMA; htfPool[5]=BASE_RANGEFILTER;

   ENUM_BASE_IND entryPool[]; ArrayResize(entryPool, 7);
   entryPool[0]=BASE_KELTNER; entryPool[1]=BASE_DONCHIAN; entryPool[2]=BASE_RANGEFILTER;
   entryPool[3]=BASE_SUPERTREND; entryPool[4]=BASE_HALFTREND; entryPool[5]=BASE_T3;
   entryPool[6]=BASE_JMA;

   ENUM_BASE_IND confirmPool[]; ArrayResize(confirmPool, 11);
   confirmPool[0]=BASE_SUPERTREND; confirmPool[1]=BASE_RANGEFILTER; confirmPool[2]=BASE_HALFTREND;
   confirmPool[3]=BASE_MAMA; confirmPool[4]=BASE_DONCHIAN; confirmPool[5]=BASE_KELTNER;
   confirmPool[6]=BASE_T3; confirmPool[7]=BASE_MCGINLEY; confirmPool[8]=BASE_JMA;
   confirmPool[9]=BASE_SQUEEZE; confirmPool[10]=BASE_NONE;

   ENUM_BASE_IND volumePool[]; ArrayResize(volumePool, 2);
   volumePool[0]=BASE_SQUEEZE; volumePool[1]=BASE_NONE;

   ENUM_BASE_IND exitPool[];   ArrayResize(exitPool, 7);
   exitPool[0]=BASE_HALFTREND; exitPool[1]=BASE_SUPERTREND; exitPool[2]=BASE_MAMA;
   exitPool[3]=BASE_T3; exitPool[4]=BASE_JMA; exitPool[5]=BASE_RANGEFILTER;
   exitPool[6]=BASE_MCGINLEY;

   // Count total valid combos (excluding duplicates)
   int totalCombos = 0;
   for(int a=0; a<6; a++)
   for(int b=0; b<7; b++)
   for(int c=0; c<11; c++)
   for(int d=0; d<2; d++)
   for(int e=0; e<7; e++)
   {
      // Skip duplicates: entry ≠ confirm (unless confirm is NONE)
      if(confirmPool[c] != BASE_NONE && entryPool[b] == confirmPool[c]) continue;
      // Skip duplicates: entry ≠ exit
      if(entryPool[b] == exitPool[e]) continue;
      // Skip duplicates: confirm ≠ exit (unless confirm is NONE)
      if(confirmPool[c] != BASE_NONE && confirmPool[c] == exitPool[e]) continue;
      totalCombos++;
   }

   Print("=== NNFX H1 Combo Sweep ===");
   Print("HTF(6) x Entry(7) x Confirm(11) x Volume(2) x Exit(7) = ", totalCombos, " valid combos");
   Print("x ", NUM_PAIRS, " pairs = ~", totalCombos * NUM_PAIRS, " backtests");
   Print("Settings: ", RISK_PCT, "% risk | SL ", SL_MULT, "x | TP ", TP1_MULT, "x | No session filter");
   Print("Composite Score = aggPF * sqrt(totalSignals)");

   // Results buffer — keep top N in memory
   int maxKeep = InpMaxResults * 2;  // Keep 2x for safety
   ComboResult results[];
   ArrayResize(results, maxKeep);
   int resultCount = 0;

   uint startTick = GetTickCount();
   int comboNum = 0;
   int partialNum = 0;

   // 5-nested loop combo generator
   for(int iHTF=0; iHTF<6; iHTF++)
   {
      if(IsStopped()) break;
      for(int iEntry=0; iEntry<7; iEntry++)
      {
         if(IsStopped()) break;
         for(int iConf=0; iConf<11; iConf++)
         {
            if(IsStopped()) break;
            // Skip duplicate: entry == confirm (unless NONE)
            if(confirmPool[iConf] != BASE_NONE && entryPool[iEntry] == confirmPool[iConf]) continue;

            for(int iVol=0; iVol<2; iVol++)
            {
               if(IsStopped()) break;
               for(int iExit=0; iExit<7; iExit++)
               {
                  if(IsStopped()) break;
                  // Skip duplicate: entry == exit
                  if(entryPool[iEntry] == exitPool[iExit]) continue;
                  // Skip duplicate: confirm == exit (unless NONE)
                  if(confirmPool[iConf] != BASE_NONE && confirmPool[iConf] == exitPool[iExit]) continue;

                  comboNum++;

                  // Progress reporting
                  if(comboNum % 100 == 0)
                  {
                     uint elapsed = GetTickCount() - startTick;
                     double pct = (double)comboNum / totalCombos * 100.0;
                     double remaining = (pct > 0) ? (elapsed / pct * (100.0 - pct)) / 1000.0 : 0;
                     Print("Progress: ", comboNum, "/", totalCombos, " (",
                           DoubleToStr(pct,1), "%) ~", DoubleToStr(remaining,0), "s remaining");
                  }

                  // Build combo config
                  ComboConfig cfg;
                  cfg.htfInd     = htfPool[iHTF];
                  cfg.entryInd   = entryPool[iEntry];
                  cfg.confirmInd = confirmPool[iConf];
                  cfg.volumeInd  = volumePool[iVol];
                  cfg.exitInd    = exitPool[iExit];

                  GetDefaultHTFParams(cfg.htfInd, cfg.htfP1, cfg.htfP2, cfg.htfP3);
                  GetDefaultEntryParams(cfg.entryInd, cfg.entP1, cfg.entP2, cfg.entP3);
                  GetDefaultConfirmParams(cfg.confirmInd, cfg.confP1, cfg.confP2, cfg.confP3, cfg.confP4);
                  cfg.volP1=20; cfg.volP2=2.0; cfg.volP3=20; cfg.volP4=1.5; // Squeeze defaults
                  GetDefaultExitParams(cfg.exitInd, cfg.exP1, cfg.exP2, cfg.exP3);

                  // Run across all pairs
                  double totalWR=0, totalPF=0, totalNet=0;
                  int totalSig=0, activePairs=0;
                  double worstDD=0;
                  double pairPF[], pairNet[];
                  ArrayResize(pairPF, NUM_PAIRS);
                  ArrayResize(pairNet, NUM_PAIRS);

                  for(int p=0; p<NUM_PAIRS; p++)
                  {
                     if(g_tickVal[p]<=0 || g_tickSz[p]<=0) { pairPF[p]=0; pairNet[p]=0; continue; }

                     PStats ps;
                     RunBacktest(g_pairs[p], g_startBar[p], g_endBar[p], g_spread[p],
                                 g_tickVal[p], g_tickSz[p], cfg, ps);

                     double net = ps.gp + ps.gl;
                     totalSig += ps.sig;
                     if(ps.maxDDPct > worstDD) worstDD = ps.maxDDPct;
                     pairPF[p]  = (ps.gl!=0) ? MathAbs(ps.gp/ps.gl) : 0;
                     pairNet[p] = net;
                     if(ps.sig > 0) { totalPF += pairPF[p]; activePairs++; }
                     totalNet += net;
                     double wr = (ps.sig>0) ? ((double)ps.wins/ps.sig*100.0) : 0;
                     totalWR += wr;
                  }

                  // Use AVERAGED per-pair PF (not raw GP/GL aggregate)
                  double aggPF = (activePairs>0) ? totalPF / activePairs : 0;
                  double aggNet = totalNet;
                  double avgWR = (activePairs>0) ? totalWR / activePairs : 0;
                  double compositeScore = aggPF * MathSqrt((double)totalSig);

                  // Build result
                  ComboResult res;
                  res.htfName  = BaseIndName(cfg.htfInd);
                  res.entName  = BaseIndName(cfg.entryInd);
                  res.confName = BaseIndName(cfg.confirmInd);
                  res.volName  = BaseIndName(cfg.volumeInd);
                  res.exName   = BaseIndName(cfg.exitInd);
                  for(int pp=0; pp<NUM_PAIRS; pp++) { res.pairPF[pp]=pairPF[pp]; res.pairNet[pp]=pairNet[pp]; }
                  res.aggPF = aggPF;
                  res.aggNet = aggNet;
                  res.avgWR = avgWR;
                  res.worstDD = worstDD;
                  res.totalSig = totalSig;
                  res.compositeScore = compositeScore;

                  InsertResult(results, resultCount, maxKeep, res);

                  // Partial save every 500 combos
                  if(InpPartialSave && comboNum % 500 == 0)
                  {
                     partialNum++;
                     SortResults(results, resultCount);
                     WriteCSV(results, resultCount, "NNFX_H1_ComboSweep_Partial.csv");
                     Print("  Partial save #", partialNum, " — top score: ",
                           DoubleToStr(results[0].compositeScore, 2));
                  }

               } // exit loop
            } // volume loop
         } // confirm loop
      } // entry loop
   } // HTF loop

   if(IsStopped()) Print("CANCELLED by user after ", comboNum, " combos.");

   // Final sort and save
   SortResults(results, resultCount);
   WriteCSV(results, resultCount, "NNFX_H1_ComboSweep_Results.csv");

   // Print top 20
   int topN = MathMin(resultCount, 20);
   Print("===== TOP ", topN, " COMBOS (by Composite Score) =====");
   for(int i=0; i<topN; i++)
   {
      Print(StringFormat("#%d %s|%s|%s|%s|%s  PF=%.2f Net=$%.0f WR=%.1f%% DD=%.1f%% Sig=%d Score=%.2f",
            i+1, results[i].htfName, results[i].entName, results[i].confName,
            results[i].volName, results[i].exName,
            results[i].aggPF, results[i].aggNet, results[i].avgWR,
            results[i].worstDD, results[i].totalSig, results[i].compositeScore));
   }

   uint totalTime = (GetTickCount() - startTick) / 1000;
   Print("=== Combo Sweep Complete: ", comboNum, " combos in ", totalTime, "s ===");
   Alert("NNFX H1 ComboSweep done! Check MQL4/Files/NNFX_H1_ComboSweep_Results.csv");
}
//+------------------------------------------------------------------+
