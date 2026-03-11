//+------------------------------------------------------------------+
//|                                      NNFX_H1_ParamOptimizer.mq4 |
//|  Two-phase parameter optimizer for top combos from ComboSweep    |
//|  Phase 1: Coarse sweep (wide ranges, large steps)                |
//|  Phase 2: Fine sweep (narrow ranges around Phase 1 winner)       |
//|  Also sweeps SL/TP/Risk trade management params                  |
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

//+------------------------------------------------------------------+
//| INPUTS — Configure with your ComboSweep winners                  |
//+------------------------------------------------------------------+
input ENUM_BASE_IND InpHTF     = BASE_MCGINLEY;    // Slot 1: HTF Filter
input ENUM_BASE_IND InpEntry   = BASE_KELTNER;     // Slot 2: Entry Trigger
input ENUM_BASE_IND InpConfirm = BASE_T3;           // Slot 3: Confirmation (ComboSweep #16 winner)
input ENUM_BASE_IND InpVolume  = BASE_NONE;         // Slot 4: Volume
input ENUM_BASE_IND InpExit    = BASE_RANGEFILTER;  // Slot 5: Exit (ComboSweep #16 winner)

input int    InpPhase         = 0;     // Phase: 0=Both, 1=Coarse, 2=Fine
input int    InpMaxResults    = 100;   // Max results to save

// Fine-tune center overrides (set to 0 for auto from Phase 1)
input double InpFineHTF_P1   = 0;     // Fine: HTF P1 center (0=auto)
input double InpFineHTF_P2   = 0;     // Fine: HTF P2 center (0=auto)
input double InpFineEnt_P1   = 0;     // Fine: Entry P1 center (0=auto)
input double InpFineEnt_P2   = 0;     // Fine: Entry P2 center (0=auto)
input double InpFineEnt_P3   = 0;     // Fine: Entry P3 center (0=auto)
input double InpFineConf_P1  = 0;     // Fine: Confirm P1 center (0=auto)
input double InpFineConf_P2  = 0;     // Fine: Confirm P2 center (0=auto)
input double InpFineEx_P1    = 0;     // Fine: Exit P1 center (0=auto)

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define ATR_PERIOD       14
#define START_BALANCE    10000.0
#define NUM_PAIRS        11

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
struct ParamSet
{
   double htfP1, htfP2, htfP3;
   double entP1, entP2, entP3;
   double confP1, confP2, confP3, confP4;
   double volP1, volP2, volP3, volP4;
   double exP1, exP2, exP3;
   double slMult, tp1Mult, riskPct;
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

struct OptResult
{
   string label;
   double pairPF[NUM_PAIRS];
   double pairNet[NUM_PAIRS];
   double aggPF, aggNet, avgWR, worstDD;
   int    totalSig;
   double compositeScore;
   // Store winning params for Phase 2
   double htfP1, htfP2, entP1, entP2, entP3, confP1, confP2, exP1;
   double slMult, tp1Mult, riskPct;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string g_pairs[NUM_PAIRS];
int    g_startBar[NUM_PAIRS], g_endBar[NUM_PAIRS];
double g_tickVal[NUM_PAIRS], g_tickSz[NUM_PAIRS], g_pointVal[NUM_PAIRS], g_spread[NUM_PAIRS];

// Current locked slot types
ENUM_BASE_IND g_htfType, g_entryType, g_confirmType, g_volumeType, g_exitType;

int GetTypicalSpread(string s)
{
   if(s=="EURUSD") return 14; if(s=="GBPUSD") return 18; if(s=="USDJPY") return 14;
   if(s=="USDCHF") return 17; if(s=="AUDUSD") return 14; if(s=="NZDUSD") return 20;
   if(s=="USDCAD") return 20; if(s=="EURJPY") return 22; if(s=="GBPJPY") return 30;
   if(s=="EURGBP") return 18; if(s=="AUDJPY") return 22; return 20;
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
//| INDICATOR SIGNAL HELPERS (same as ComboSweep)                    |
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

//+------------------------------------------------------------------+
//| GENERIC DIRECTION DISPATCH                                        |
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
//| SLOT SIGNAL FUNCTIONS                                             |
//+------------------------------------------------------------------+
int GetHTFDir(string sym, int h1Bar, ParamSet &ps)
{
   datetime barTime = iTime(sym, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(sym, PERIOD_H4, barTime, false);
   if(htfBar < 1) return 0;
   return GetDirection(sym, PERIOD_H4, g_htfType, ps.htfP1, ps.htfP2, ps.htfP3, 0, htfBar);
}

bool HTFFlippedAgainst(string sym, int h1Bar, int tradeDir, ParamSet &ps)
{
   int dirNow  = GetHTFDir(sym, h1Bar,   ps);
   int dirPrev = GetHTFDir(sym, h1Bar+1, ps);
   if(tradeDir == 1  && dirNow == -1 && dirPrev != -1) return true;
   if(tradeDir == -1 && dirNow == 1  && dirPrev != 1)  return true;
   return false;
}

bool EntryFlipOccurred(string sym, int bar, int htfDir, ParamSet &ps)
{
   int dirCurr = GetDirection(sym, PERIOD_H1, g_entryType, ps.entP1, ps.entP2, ps.entP3, 0, bar);
   int dirPrev = GetDirection(sym, PERIOD_H1, g_entryType, ps.entP1, ps.entP2, ps.entP3, 0, bar+1);
   return (dirCurr == htfDir && dirPrev != htfDir);
}

bool ConfirmAgrees(string sym, int bar, int htfDir, ParamSet &ps)
{
   if(g_confirmType == BASE_NONE) return true;
   for(int i=0; i<=2; i++)
   {
      int dir = GetDirection(sym, PERIOD_H1, g_confirmType, ps.confP1, ps.confP2, ps.confP3, ps.confP4, bar+i);
      if(dir == htfDir) return true;
   }
   return false;
}

bool CheckVolume(string sym, int shift, int direction, ParamSet &ps)
{
   if(g_volumeType == BASE_NONE) return true;
   int bbLen=(int)ps.volP1; int kcLen=(int)ps.volP3; int momLen=bbLen;
   if(!SqueezeFiring(sym, PERIOD_H1, bbLen, ps.volP2, kcLen, ps.volP4, momLen, shift)) return false;
   int momDir = GetSqueezeDir(sym, PERIOD_H1, bbLen, ps.volP2, kcLen, ps.volP4, momLen, shift);
   if(momDir != direction) return false;
   return SqueezeMomGrowing(sym, PERIOD_H1, bbLen, ps.volP2, kcLen, ps.volP4, momLen, shift);
}

bool CheckExit(string sym, int shift, int tradeDir, ParamSet &ps)
{
   int dir = GetDirection(sym, PERIOD_H1, g_exitType, ps.exP1, ps.exP2, ps.exP3, 0, shift);
   if(tradeDir == 1  && dir == -1) return true;
   if(tradeDir == -1 && dir ==  1) return true;
   return false;
}

int EvalEntry(string sym, int bar, ParamSet &ps)
{
   int htfDir = GetHTFDir(sym, bar, ps);
   if(htfDir == 0) return 0;
   if(!EntryFlipOccurred(sym, bar, htfDir, ps)) return 0;
   if(!ConfirmAgrees(sym, bar, htfDir, ps)) return 0;
   if(!CheckVolume(sym, bar, htfDir, ps)) return 0;
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
      bal += pnl; t.pnl += pnl;
      if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
      t.o1Open = false;
   }
   if(t.o2Open)
   {
      double pnl = (t.dir==1) ? (ep-t.entry)/ts*tv*t.lots2 : (t.entry-ep)/ts*tv*t.lots2;
      bal += pnl; t.pnl += pnl;
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
            double &bal, double &peak, PStats &s, double tv, double ts, ParamSet &ps)
{
   double hi=iHigh(sym,PERIOD_H1,bar), lo=iLow(sym,PERIOD_H1,bar), cl=iClose(sym,PERIOD_H1,bar);
   double aHi=hi+spread, aCl=cl+spread;

   if(HTFFlippedAgainst(sym, bar, t.dir, ps))
   {
      double ep = (t.dir==1) ? cl : aCl;
      FClose(t, ep, bal, peak, s, tv, ts);
      return;
   }

   if(t.o1Open)
   {
      bool tp=false, sl=false; double pnl=0;
      if(t.dir==1)
      {
         if(hi>=t.tp1)  { tp=true; pnl=(t.tp1-t.entry)/ts*tv*t.lots1; }
         else if(lo<=t.sl){ sl=true; pnl=(t.sl-t.entry)/ts*tv*t.lots1; }
      }
      else
      {
         double aLo=lo+spread;
         if(aLo<=t.tp1)  { tp=true; pnl=(t.entry-t.tp1)/ts*tv*t.lots1; }
         else if(aHi>=t.sl){ sl=true; pnl=(t.entry-t.sl)/ts*tv*t.lots1; }
      }
      if(tp||sl)
      {
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
         t.o1Open=false;
         if(tp && t.o2Open) { t.sl=t.entry; t.movedBE=true; }
      }
   }

   if(t.o2Open)
   {
      bool slHit=false;
      if(t.dir==1 && lo<=t.sl) slHit=true;
      if(t.dir==-1 && aHi>=t.sl) slHit=true;

      bool exitFlip = CheckExit(sym, bar, t.dir, ps);

      double pnl=0;
      if(slHit)
      {
         pnl=(t.dir==1) ? (t.sl-t.entry)/ts*tv*t.lots2 : (t.entry-t.sl)/ts*tv*t.lots2;
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
         t.o2Open=false;
      }
      else if(exitFlip)
      {
         double ep=(t.dir==1)?cl:aCl;
         pnl=(t.dir==1) ? (ep-t.entry)/ts*tv*t.lots2 : (t.entry-ep)/ts*tv*t.lots2;
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0) s.gp+=pnl; else s.gl+=pnl;
         t.o2Open=false;
      }
   }

   if(!t.o1Open && !t.o2Open)
   {
      if(t.pnl>=0) s.wins++; else s.losses++;
   }
   if(bal>peak) peak=bal;
   double dd=peak-bal;
   if(dd>s.maxDD) { s.maxDD=dd; s.maxDDPct=(dd/peak)*100.0; }
}

//+------------------------------------------------------------------+
//| BACKTEST ENGINE                                                   |
//+------------------------------------------------------------------+
void RunBacktest(string sym, int startBar, int endBar, double spread,
                 double tickVal, double tickSz, ParamSet &ps, PStats &stats)
{
   stats.sig=0; stats.wins=0; stats.losses=0;
   stats.gp=0; stats.gl=0; stats.maxDD=0; stats.maxDDPct=0;
   stats.bal=START_BALANCE;

   double balance=START_BALANCE, peak=START_BALANCE;
   VTrade trade;
   trade.o1Open=false; trade.o2Open=false; trade.movedBE=false; trade.pnl=0;
   trade.dir=0; trade.entry=0; trade.sl=0; trade.tp1=0; trade.lots1=0; trade.lots2=0;

   for(int bar=startBar-1; bar>endBar; bar--)
   {
      if(trade.o1Open || trade.o2Open)
         Manage(sym, bar, spread, trade, balance, peak, stats, tickVal, tickSz, ps);
      if(trade.o1Open || trade.o2Open) continue;

      int signal = EvalEntry(sym, bar, ps);
      if(signal == 0) continue;
      stats.sig++;

      double atr = iATR(sym, PERIOD_H1, ATR_PERIOD, bar);
      if(atr <= 0) continue;

      double openNext = iOpen(sym, PERIOD_H1, bar-1);
      if(openNext <= 0) continue;

      double entry   = (signal==1) ? openNext + spread : openNext;
      double slDist  = ps.slMult * atr;
      double tp1Dist = ps.tp1Mult * atr;

      double risk    = balance * (ps.riskPct / 100.0);
      double slTicks = slDist / tickSz;
      double rpl     = slTicks * tickVal;
      if(rpl <= 0) continue;

      double half = MathFloor((risk / rpl) / 2.0 * 100.0) / 100.0;
      if(half < 0.01) half = 0.01;

      trade.dir=signal; trade.entry=entry;
      trade.lots1=half; trade.lots2=half;
      trade.o1Open=true; trade.o2Open=true;
      trade.movedBE=false; trade.pnl=0;

      if(signal==1) { trade.sl=entry-slDist; trade.tp1=entry+tp1Dist; }
      else          { trade.sl=entry+slDist; trade.tp1=entry-tp1Dist; }
   }

   if(trade.o1Open || trade.o2Open)
   {
      double lc = iClose(sym, PERIOD_H1, endBar);
      FClose(trade, (trade.dir==1)?lc:lc+spread, balance, peak, stats, tickVal, tickSz);
   }
   stats.bal = balance;
}

//+------------------------------------------------------------------+
//| RUN SWEEP ACROSS ALL PAIRS                                        |
//+------------------------------------------------------------------+
void RunAllPairs(ParamSet &ps, double &aggPF, double &aggNet, double &avgWR,
                 double &worstDD, int &totalSig, double &pairPF[], double &pairNet[])
{
   double totalWR=0, totalPF=0, totalNet=0;
   int activePairs=0;
   totalSig=0; worstDD=0;

   for(int p=0; p<NUM_PAIRS; p++)
   {
      if(g_tickVal[p]<=0 || g_tickSz[p]<=0) { pairPF[p]=0; pairNet[p]=0; continue; }
      PStats st;
      RunBacktest(g_pairs[p], g_startBar[p], g_endBar[p], g_spread[p],
                  g_tickVal[p], g_tickSz[p], ps, st);
      double net = st.gp + st.gl;
      totalSig += st.sig;
      if(st.maxDDPct > worstDD) worstDD = st.maxDDPct;
      pairPF[p] = (st.gl!=0) ? MathAbs(st.gp/st.gl) : 0;
      pairNet[p] = net;
      if(st.sig > 0) { totalPF += pairPF[p]; activePairs++; }
      totalNet += net;
      double wr = (st.sig>0) ? ((double)st.wins/st.sig*100.0) : 0;
      totalWR += wr;
   }
   // Use AVERAGED per-pair PF (not raw GP/GL aggregate)
   aggPF = (activePairs>0) ? totalPF / activePairs : 0;
   aggNet = totalNet;
   avgWR = (activePairs>0) ? totalWR / activePairs : 0;
}

//+------------------------------------------------------------------+
//| SORT & WRITE                                                      |
//+------------------------------------------------------------------+
void SortResults(OptResult &arr[], int count)
{
   for(int i=0; i<count-1; i++)
      for(int j=0; j<count-i-1; j++)
         if(arr[j].compositeScore < arr[j+1].compositeScore)
         { OptResult tmp=arr[j]; arr[j]=arr[j+1]; arr[j+1]=tmp; }
}

void InsertResult(OptResult &arr[], int &count, int maxKeep, OptResult &newRes)
{
   if(count < maxKeep) { arr[count]=newRes; count++; return; }
   int minIdx=0; double minScore=arr[0].compositeScore;
   for(int i=1; i<count; i++)
      if(arr[i].compositeScore < minScore) { minScore=arr[i].compositeScore; minIdx=i; }
   if(newRes.compositeScore > minScore) arr[minIdx]=newRes;
}

void WriteCSV(OptResult &res[], int count, string filename)
{
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle,
      "Rank","Label",
      "EURUSD_PF","GBPUSD_PF","USDJPY_PF","USDCHF_PF","AUDUSD_PF","NZDUSD_PF","USDCAD_PF",
      "EURJPY_PF","GBPJPY_PF","EURGBP_PF","AUDJPY_PF",
      "EURUSD_Net","GBPUSD_Net","USDJPY_Net","USDCHF_Net","AUDUSD_Net","NZDUSD_Net","USDCAD_Net",
      "EURJPY_Net","GBPJPY_Net","EURGBP_Net","AUDJPY_Net",
      "Agg_PF","Agg_Net","Avg_WR","Worst_DD","Total_Sig","Composite_Score",
      "SL_Mult","TP1_Mult","Risk_Pct");

   int toWrite = MathMin(count, InpMaxResults);
   for(int i=0; i<toWrite; i++)
   {
      FileWrite(handle,
         i+1, res[i].label,
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
         res[i].totalSig, DoubleToStr(res[i].compositeScore,2),
         DoubleToStr(res[i].slMult,2), DoubleToStr(res[i].tp1Mult,2),
         DoubleToStr(res[i].riskPct,1));
   }
   FileClose(handle);
   Print("Results saved: MQL4/Files/", filename);
}

//+------------------------------------------------------------------+
//| PARAMETER RANGE BUILDER                                           |
//| Returns arrays of values to sweep for a given indicator type      |
//+------------------------------------------------------------------+
void BuildHTFRanges(ENUM_BASE_IND ind, bool coarse,
                    double &p1Vals[], int &p1Count,
                    double &p2Vals[], int &p2Count)
{
   if(coarse)
   {
      switch(ind)
      {
         case BASE_MCGINLEY:
            { double v[]={10,14,18}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={0.6}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         case BASE_SUPERTREND:
            { double v[]={7,10,14}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={2.0,3.0}; ArrayCopy(p2Vals,v); p2Count=2; }
            break;
         case BASE_T3:
            { double v[]={5,8,12}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={0.7}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         case BASE_JMA:
            { double v[]={7,10,14}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={0}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         case BASE_MAMA:
            { double v[]={0.3,0.5,0.7}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={0.05}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         case BASE_RANGEFILTER:
            { double v[]={15,25,40}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={1.5,2.5,4.0}; ArrayCopy(p2Vals,v); p2Count=3; }
            break;
         default:
            { double v[]={14}; ArrayCopy(p1Vals,v); p1Count=1; }
            { double v[]={0.6}; ArrayCopy(p2Vals,v); p2Count=1; }
      }
   }
   else // fine — ±1 step around center, pin p2 for single-param indicators
   {
      double c1 = (InpFineHTF_P1>0) ? InpFineHTF_P1 : p1Vals[0];
      BuildFineRange(ind, 1, c1, p1Vals, p1Count);
      // Pin p2 for indicators where it's a constant (K, volfactor)
      if(ind==BASE_MCGINLEY || ind==BASE_T3 || ind==BASE_JMA)
      {
         double c2 = (InpFineHTF_P2>0) ? InpFineHTF_P2 : p2Vals[0];
         ArrayResize(p2Vals,1); p2Vals[0]=c2; p2Count=1;
      }
      else
      {
         double c2 = (InpFineHTF_P2>0) ? InpFineHTF_P2 : p2Vals[0];
         BuildFineRange(ind, 2, c2, p2Vals, p2Count);
      }
   }
}

void BuildEntryRanges(ENUM_BASE_IND ind, bool coarse,
                      double &p1Vals[], int &p1Count,
                      double &p2Vals[], int &p2Count,
                      double &p3Vals[], int &p3Count)
{
   p3Count=1; ArrayResize(p3Vals,1); p3Vals[0]=0;
   if(coarse)
   {
      switch(ind)
      {
         case BASE_KELTNER:
            { double v[]={14,20,26}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={14,20}; ArrayCopy(p2Vals,v); p2Count=2; }
            { double v[]={1.0,1.5,2.0}; ArrayCopy(p3Vals,v); p3Count=3; }
            break;
         case BASE_DONCHIAN:
            { double v[]={10,15,20,25}; ArrayCopy(p1Vals,v); p1Count=4; }
            { double v[]={0}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         case BASE_RANGEFILTER:
            { double v[]={15,25,35,50}; ArrayCopy(p1Vals,v); p1Count=4; }
            { double v[]={1.5,2.5,4.0}; ArrayCopy(p2Vals,v); p2Count=3; }
            break;
         case BASE_SUPERTREND:
            { double v[]={7,10,14}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={2.0,3.0}; ArrayCopy(p2Vals,v); p2Count=2; }
            break;
         case BASE_HALFTREND:
            { double v[]={2,3,5}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={2}; ArrayCopy(p2Vals,v); p2Count=1; }
            { double v[]={100}; ArrayCopy(p3Vals,v); p3Count=1; }
            break;
         case BASE_T3:
            { double v[]={5,8,12}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={0.7}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         case BASE_JMA:
            { double v[]={7,10,14}; ArrayCopy(p1Vals,v); p1Count=3; }
            { double v[]={0}; ArrayCopy(p2Vals,v); p2Count=1; }
            break;
         default:
            { double v[]={20}; ArrayCopy(p1Vals,v); p1Count=1; }
            { double v[]={0}; ArrayCopy(p2Vals,v); p2Count=1; }
      }
   }
   else
   {
      double c1=(InpFineEnt_P1>0)?InpFineEnt_P1:p1Vals[0];
      double c2=(InpFineEnt_P2>0)?InpFineEnt_P2:p2Vals[0];
      double c3=(InpFineEnt_P3>0)?InpFineEnt_P3:p3Vals[0];
      BuildFineRange(ind, 1, c1, p1Vals, p1Count);
      // Pin ATR period for Keltner (MA and ATR usually close)
      ArrayResize(p2Vals,1); p2Vals[0]=c2; p2Count=1;
      if(ind==BASE_KELTNER) BuildFineRange(ind, 3, c3, p3Vals, p3Count);
   }
}

void BuildConfirmRanges(ENUM_BASE_IND ind, bool coarse,
                        double &p1Vals[], int &p1Count,
                        double &p2Vals[], int &p2Count)
{
   if(ind == BASE_NONE)
   {
      ArrayResize(p1Vals,1); p1Vals[0]=0; p1Count=1;
      ArrayResize(p2Vals,1); p2Vals[0]=0; p2Count=1;
      return;
   }
   // Reuse HTF ranges as they share same indicator types
   BuildHTFRanges(ind, coarse, p1Vals, p1Count, p2Vals, p2Count);
   if(!coarse)
   {
      double c1=(InpFineConf_P1>0)?InpFineConf_P1:p1Vals[0];
      BuildFineRange(ind, 1, c1, p1Vals, p1Count);
      // Pin p2 (volfactor/K) for confirm — only sweep main period
      double c2=(InpFineConf_P2>0)?InpFineConf_P2:p2Vals[0];
      ArrayResize(p2Vals,1); p2Vals[0]=c2; p2Count=1;
   }
}

void BuildExitRanges(ENUM_BASE_IND ind, bool coarse,
                     double &p1Vals[], int &p1Count)
{
   if(coarse)
   {
      switch(ind)
      {
         case BASE_HALFTREND:
            { double v[]={2,3,4,5}; ArrayCopy(p1Vals,v); p1Count=4; } break;
         case BASE_SUPERTREND:
            { double v[]={7,10,14}; ArrayCopy(p1Vals,v); p1Count=3; } break;
         case BASE_T3:
            { double v[]={3,5,8}; ArrayCopy(p1Vals,v); p1Count=3; } break;
         case BASE_JMA:
            { double v[]={5,7,10}; ArrayCopy(p1Vals,v); p1Count=3; } break;
         case BASE_RANGEFILTER:
            { double v[]={15,20,30}; ArrayCopy(p1Vals,v); p1Count=3; } break;
         case BASE_MCGINLEY:
            { double v[]={8,10,14}; ArrayCopy(p1Vals,v); p1Count=3; } break;
         case BASE_MAMA:
            { double v[]={0.3,0.5,0.7}; ArrayCopy(p1Vals,v); p1Count=3; } break;
         default:
            { double v[]={3}; ArrayCopy(p1Vals,v); p1Count=1; }
      }
   }
   else
   {
      double c1=(InpFineEx_P1>0)?InpFineEx_P1:p1Vals[0];
      BuildFineRange(ind, 1, c1, p1Vals, p1Count);
   }
}

// Build fine range: ±1 step around center (3 values max)
void BuildFineRange(ENUM_BASE_IND ind, int paramIdx, double center,
                    double &vals[], int &count)
{
   double step = 1.0;
   // Determine step based on indicator type and parameter
   if(ind==BASE_MAMA || (ind==BASE_MCGINLEY && paramIdx==2))
      step = 0.05;
   else if(ind==BASE_KELTNER && paramIdx==3)
      step = 0.25;
   else if(ind==BASE_T3 && paramIdx==2)
      step = 0.1;
   else if(ind==BASE_RANGEFILTER && paramIdx==2)
      step = 0.5;
   else if(ind==BASE_SUPERTREND && paramIdx==2)
      step = 0.5;
   else
      step = (center >= 10) ? 2 : 1;

   ArrayResize(vals, 3);
   count = 0;
   for(int i=-1; i<=1; i++)
   {
      double v = center + i * step;
      if(v > 0) { vals[count] = v; count++; }
   }
}

//+------------------------------------------------------------------+
//| OnStart                                                           |
//+------------------------------------------------------------------+
void OnStart()
{
   g_pairs[0]="EURUSD"; g_pairs[1]="GBPUSD"; g_pairs[2]="USDJPY";
   g_pairs[3]="USDCHF"; g_pairs[4]="AUDUSD"; g_pairs[5]="NZDUSD"; g_pairs[6]="USDCAD";
   g_pairs[7]="EURJPY"; g_pairs[8]="GBPJPY"; g_pairs[9]="EURGBP"; g_pairs[10]="AUDJPY";

   datetime startDate = D'2020.01.01';
   datetime endDate   = D'2025.01.01';

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
   }

   // Set locked indicator types
   g_htfType     = InpHTF;
   g_entryType   = InpEntry;
   g_confirmType = InpConfirm;
   g_volumeType  = InpVolume;
   g_exitType    = InpExit;

   Print("=== NNFX H1 Parameter Optimizer ===");
   Print("HTF: ", BaseIndName(g_htfType), " | Entry: ", BaseIndName(g_entryType),
         " | Confirm: ", BaseIndName(g_confirmType), " | Volume: ", BaseIndName(g_volumeType),
         " | Exit: ", BaseIndName(g_exitType));

   // Trade management sweep values (coarse: fewer combos, fine will explore around winner)
   double slMults[]  = {0.75, 1.0, 1.5};
   double tp1Mults[] = {1.0, 1.5, 2.0};
   double riskPcts[] = {5.0};
   int numSL=3, numTP=3, numRisk=1;

   // Phase 1: Coarse
   OptResult phase1Results[];
   int phase1Count = 0;
   int maxKeep = InpMaxResults * 2;
   ArrayResize(phase1Results, maxKeep);

   if(InpPhase == 0 || InpPhase == 1)
   {
      Print("--- Phase 1: Coarse Parameter Sweep ---");

      double htfP1Vals[], htfP2Vals[];
      int htfP1N, htfP2N;
      BuildHTFRanges(g_htfType, true, htfP1Vals, htfP1N, htfP2Vals, htfP2N);

      double entP1Vals[], entP2Vals[], entP3Vals[];
      int entP1N, entP2N, entP3N;
      BuildEntryRanges(g_entryType, true, entP1Vals, entP1N, entP2Vals, entP2N, entP3Vals, entP3N);

      double confP1Vals[], confP2Vals[];
      int confP1N, confP2N;
      BuildConfirmRanges(g_confirmType, true, confP1Vals, confP1N, confP2Vals, confP2N);

      double exP1Vals[];
      int exP1N;
      BuildExitRanges(g_exitType, true, exP1Vals, exP1N);

      int totalConfigs = htfP1N * htfP2N * entP1N * entP2N * entP3N *
                         confP1N * confP2N * exP1N * numSL * numTP * numRisk;
      Print("Phase 1 configs: ", totalConfigs);

      uint startTick = GetTickCount();
      int cfgNum = 0;

      for(int iHP1=0; iHP1<htfP1N; iHP1++)
      for(int iHP2=0; iHP2<htfP2N; iHP2++)
      for(int iEP1=0; iEP1<entP1N; iEP1++)
      for(int iEP2=0; iEP2<entP2N; iEP2++)
      for(int iEP3=0; iEP3<entP3N; iEP3++)
      for(int iCP1=0; iCP1<confP1N; iCP1++)
      for(int iCP2=0; iCP2<confP2N; iCP2++)
      for(int iXP1=0; iXP1<exP1N; iXP1++)
      for(int iSL=0; iSL<numSL; iSL++)
      for(int iTP=0; iTP<numTP; iTP++)
      for(int iRK=0; iRK<numRisk; iRK++)
      {
         if(IsStopped()) break;
         cfgNum++;

         if(cfgNum % 100 == 0)
         {
            uint elapsed = GetTickCount() - startTick;
            double pct = (double)cfgNum / totalConfigs * 100.0;
            double remaining = (pct>0) ? (elapsed/pct*(100.0-pct))/1000.0 : 0;
            Print("Phase 1: ", cfgNum, "/", totalConfigs, " (", DoubleToStr(pct,1), "%) ~",
                  DoubleToStr(remaining,0), "s rem");
         }

         ParamSet ps;
         ps.htfP1=htfP1Vals[iHP1]; ps.htfP2=htfP2Vals[iHP2]; ps.htfP3=0;
         ps.entP1=entP1Vals[iEP1]; ps.entP2=entP2Vals[iEP2]; ps.entP3=entP3Vals[iEP3];
         ps.confP1=confP1Vals[iCP1]; ps.confP2=confP2Vals[iCP2]; ps.confP3=0; ps.confP4=0;
         // Set confirm p3/p4 for squeeze
         if(g_confirmType==BASE_SQUEEZE) { ps.confP3=confP1Vals[iCP1]; ps.confP4=confP2Vals[iCP2]; }
         if(g_confirmType==BASE_HALFTREND) { ps.confP3=100; }
         if(g_confirmType==BASE_KELTNER) { ps.confP3=1.5; }
         ps.volP1=20; ps.volP2=2.0; ps.volP3=20; ps.volP4=1.5;
         ps.exP1=exP1Vals[iXP1]; ps.exP2=0; ps.exP3=0;
         if(g_exitType==BASE_HALFTREND) { ps.exP2=2; ps.exP3=100; }
         if(g_exitType==BASE_SUPERTREND) { ps.exP2=2.0; }
         ps.slMult=slMults[iSL]; ps.tp1Mult=tp1Mults[iTP]; ps.riskPct=riskPcts[iRK];

         double aggPF, aggNet, avgWR, worstDD;
         int totalSig;
         double pPF[], pNet[];
         ArrayResize(pPF, NUM_PAIRS); ArrayResize(pNet, NUM_PAIRS);
         RunAllPairs(ps, aggPF, aggNet, avgWR, worstDD, totalSig, pPF, pNet);

         OptResult res;
         res.label = StringFormat("H(%s,%.0f,%.2f) E(%s,%.0f,%.0f,%.2f) C(%s,%.0f,%.2f) X(%s,%.0f) SL=%.2f TP=%.2f R=%.0f%%",
            BaseIndName(g_htfType), ps.htfP1, ps.htfP2,
            BaseIndName(g_entryType), ps.entP1, ps.entP2, ps.entP3,
            BaseIndName(g_confirmType), ps.confP1, ps.confP2,
            BaseIndName(g_exitType), ps.exP1,
            ps.slMult, ps.tp1Mult, ps.riskPct);
         for(int pp=0; pp<NUM_PAIRS; pp++) { res.pairPF[pp]=pPF[pp]; res.pairNet[pp]=pNet[pp]; }
         res.aggPF=aggPF; res.aggNet=aggNet; res.avgWR=avgWR; res.worstDD=worstDD;
         res.totalSig=totalSig;
         res.compositeScore = aggPF * MathSqrt((double)totalSig);
         res.htfP1=ps.htfP1; res.htfP2=ps.htfP2;
         res.entP1=ps.entP1; res.entP2=ps.entP2; res.entP3=ps.entP3;
         res.confP1=ps.confP1; res.confP2=ps.confP2;
         res.exP1=ps.exP1;
         res.slMult=ps.slMult; res.tp1Mult=ps.tp1Mult; res.riskPct=ps.riskPct;

         InsertResult(phase1Results, phase1Count, maxKeep, res);
      }

      SortResults(phase1Results, phase1Count);
      WriteCSV(phase1Results, phase1Count, "NNFX_H1_ParamOpt_Phase1.csv");

      int topN = MathMin(phase1Count, 10);
      Print("=== Phase 1 Top ", topN, " ===");
      for(int i=0; i<topN; i++)
         Print(StringFormat("#%d %s  PF=%.2f Net=$%.0f Score=%.2f",
               i+1, phase1Results[i].label, phase1Results[i].aggPF,
               phase1Results[i].aggNet, phase1Results[i].compositeScore));
   }

   // Phase 2: Fine sweep around Phase 1 winner
   if(InpPhase == 0 || InpPhase == 2)
   {
      Print("--- Phase 2: Fine Parameter Sweep ---");

      // Use Phase 1 winner as center, or use input overrides
      double centerHTFP1, centerHTFP2, centerEntP1, centerEntP2, centerEntP3;
      double centerConfP1, centerConfP2, centerExP1;
      double centerSL, centerTP, centerRisk;

      if(phase1Count > 0 && InpPhase == 0)
      {
         centerHTFP1=phase1Results[0].htfP1; centerHTFP2=phase1Results[0].htfP2;
         centerEntP1=phase1Results[0].entP1; centerEntP2=phase1Results[0].entP2; centerEntP3=phase1Results[0].entP3;
         centerConfP1=phase1Results[0].confP1; centerConfP2=phase1Results[0].confP2;
         centerExP1=phase1Results[0].exP1;
         centerSL=phase1Results[0].slMult; centerTP=phase1Results[0].tp1Mult; centerRisk=phase1Results[0].riskPct;
      }
      else
      {
         // Use fine input overrides or sensible defaults
         centerHTFP1=(InpFineHTF_P1>0)?InpFineHTF_P1:14;
         centerHTFP2=(InpFineHTF_P2>0)?InpFineHTF_P2:0.6;
         centerEntP1=(InpFineEnt_P1>0)?InpFineEnt_P1:20;
         centerEntP2=(InpFineEnt_P2>0)?InpFineEnt_P2:20;
         centerEntP3=(InpFineEnt_P3>0)?InpFineEnt_P3:1.5;
         centerConfP1=(InpFineConf_P1>0)?InpFineConf_P1:30;
         centerConfP2=(InpFineConf_P2>0)?InpFineConf_P2:2.5;
         centerExP1=(InpFineEx_P1>0)?InpFineEx_P1:3;
         centerSL=1.0; centerTP=1.5; centerRisk=5.0;
      }

      // Build fine ranges
      double fHTFP1[], fHTFP2[], fEntP1[], fEntP2[], fEntP3[], fConfP1[], fConfP2[], fExP1[];
      int nHP1, nHP2, nEP1, nEP2, nEP3, nCP1, nCP2, nXP1;

      BuildFineRange(g_htfType, 1, centerHTFP1, fHTFP1, nHP1);
      // Middle ground: 2 values for McGinley K (center and center+step)
      { double step=0.05;
        ArrayResize(fHTFP2,2); fHTFP2[0]=centerHTFP2; fHTFP2[1]=centerHTFP2+step; nHP2=2;
        if(fHTFP2[1]>1.0) { fHTFP2[1]=centerHTFP2-step; }
        if(fHTFP2[1]<=0)  { ArrayResize(fHTFP2,1); nHP2=1; }
      }
      BuildFineRange(g_entryType, 1, centerEntP1, fEntP1, nEP1);
      // Middle ground: 2 values for Keltner ATR period (center and center+step)
      { double step=(centerEntP2>=10)?2:1;
        ArrayResize(fEntP2,2); fEntP2[0]=centerEntP2; fEntP2[1]=centerEntP2+step; nEP2=2;
        if(fEntP2[1]<=0) { ArrayResize(fEntP2,1); nEP2=1; }
      }
      if(g_entryType==BASE_KELTNER)
         BuildFineRange(g_entryType, 3, centerEntP3, fEntP3, nEP3);
      else { ArrayResize(fEntP3,1); fEntP3[0]=centerEntP3; nEP3=1; }

      if(g_confirmType==BASE_NONE)
      { ArrayResize(fConfP1,1); fConfP1[0]=0; nCP1=1;
        ArrayResize(fConfP2,1); fConfP2[0]=0; nCP2=1; }
      else
      {
         BuildFineRange(g_confirmType, 1, centerConfP1, fConfP1, nCP1);
         // Middle ground: 2 values for T3 volfactor (center and center+step)
         { double step=0.1;
           ArrayResize(fConfP2,2); fConfP2[0]=centerConfP2; fConfP2[1]=centerConfP2+step; nCP2=2;
           if(fConfP2[1]>1.0) { fConfP2[1]=centerConfP2-step; }
           if(fConfP2[1]<=0)  { ArrayResize(fConfP2,1); nCP2=1; }
         }
      }
      BuildFineRange(g_exitType, 1, centerExP1, fExP1, nXP1);

      // Fine SL/TP/Risk: ±1 step around center
      double fSL[], fTP[], fRisk[];
      int nSL=3, nTP=3, nRisk=1;
      ArrayResize(fSL, 3); ArrayResize(fTP, 3); ArrayResize(fRisk, 1);
      fSL[0]=centerSL-0.15; fSL[1]=centerSL; fSL[2]=centerSL+0.15;
      fTP[0]=centerTP-0.15; fTP[1]=centerTP; fTP[2]=centerTP+0.15;
      fRisk[0]=centerRisk;
      // Clamp minimums
      for(int i=0; i<3; i++) { if(fSL[i]<0.5) fSL[i]=0.5; if(fTP[i]<0.5) fTP[i]=0.5; }

      int totalFine = nHP1*nHP2*nEP1*nEP2*nEP3*nCP1*nCP2*nXP1*nSL*nTP*nRisk;
      Print("Phase 2 configs: ", totalFine);

      OptResult phase2Results[];
      int phase2Count = 0;
      ArrayResize(phase2Results, maxKeep);

      uint startTick2 = GetTickCount();
      int cfgNum2 = 0;

      for(int iHP1=0; iHP1<nHP1; iHP1++)
      for(int iHP2=0; iHP2<nHP2; iHP2++)
      for(int iEP1=0; iEP1<nEP1; iEP1++)
      for(int iEP2=0; iEP2<nEP2; iEP2++)
      for(int iEP3=0; iEP3<nEP3; iEP3++)
      for(int iCP1=0; iCP1<nCP1; iCP1++)
      for(int iCP2=0; iCP2<nCP2; iCP2++)
      for(int iXP1=0; iXP1<nXP1; iXP1++)
      for(int iSL=0; iSL<nSL; iSL++)
      for(int iTP=0; iTP<nTP; iTP++)
      for(int iRK=0; iRK<nRisk; iRK++)
      {
         if(IsStopped()) break;
         cfgNum2++;

         if(cfgNum2 % 100 == 0)
         {
            uint elapsed2 = GetTickCount() - startTick2;
            double pct2 = (double)cfgNum2 / totalFine * 100.0;
            double rem2 = (pct2>0) ? (elapsed2/pct2*(100.0-pct2))/1000.0 : 0;
            Print("Phase 2: ", cfgNum2, "/", totalFine, " (", DoubleToStr(pct2,1), "%) ~",
                  DoubleToStr(rem2,0), "s rem");
         }

         ParamSet ps;
         ps.htfP1=fHTFP1[iHP1]; ps.htfP2=fHTFP2[iHP2]; ps.htfP3=0;
         ps.entP1=fEntP1[iEP1]; ps.entP2=fEntP2[iEP2]; ps.entP3=fEntP3[iEP3];
         ps.confP1=fConfP1[iCP1]; ps.confP2=fConfP2[iCP2]; ps.confP3=0; ps.confP4=0;
         if(g_confirmType==BASE_SQUEEZE) { ps.confP3=fConfP1[iCP1]; ps.confP4=fConfP2[iCP2]; }
         if(g_confirmType==BASE_HALFTREND) { ps.confP3=100; }
         if(g_confirmType==BASE_KELTNER) { ps.confP3=1.5; }
         ps.volP1=20; ps.volP2=2.0; ps.volP3=20; ps.volP4=1.5;
         ps.exP1=fExP1[iXP1]; ps.exP2=0; ps.exP3=0;
         if(g_exitType==BASE_HALFTREND) { ps.exP2=2; ps.exP3=100; }
         if(g_exitType==BASE_SUPERTREND) { ps.exP2=2.0; }
         ps.slMult=fSL[iSL]; ps.tp1Mult=fTP[iTP]; ps.riskPct=fRisk[iRK];

         double aggPF, aggNet, avgWR, worstDD;
         int totalSig;
         double pPF[], pNet[];
         ArrayResize(pPF, NUM_PAIRS); ArrayResize(pNet, NUM_PAIRS);
         RunAllPairs(ps, aggPF, aggNet, avgWR, worstDD, totalSig, pPF, pNet);

         OptResult res;
         res.label = StringFormat("H(%.0f,%.2f) E(%.0f,%.0f,%.2f) C(%.0f,%.2f) X(%.0f) SL=%.2f TP=%.2f R=%.0f%%",
            ps.htfP1, ps.htfP2, ps.entP1, ps.entP2, ps.entP3,
            ps.confP1, ps.confP2, ps.exP1,
            ps.slMult, ps.tp1Mult, ps.riskPct);
         for(int pp=0; pp<NUM_PAIRS; pp++) { res.pairPF[pp]=pPF[pp]; res.pairNet[pp]=pNet[pp]; }
         res.aggPF=aggPF; res.aggNet=aggNet; res.avgWR=avgWR; res.worstDD=worstDD;
         res.totalSig=totalSig;
         res.compositeScore = aggPF * MathSqrt((double)totalSig);
         res.slMult=ps.slMult; res.tp1Mult=ps.tp1Mult; res.riskPct=ps.riskPct;

         InsertResult(phase2Results, phase2Count, maxKeep, res);
      }

      SortResults(phase2Results, phase2Count);
      WriteCSV(phase2Results, phase2Count, "NNFX_H1_ParamOpt_Phase2.csv");

      int topN2 = MathMin(phase2Count, 10);
      Print("=== Phase 2 Top ", topN2, " ===");
      for(int i=0; i<topN2; i++)
         Print(StringFormat("#%d %s  PF=%.2f Net=$%.0f Score=%.2f",
               i+1, phase2Results[i].label, phase2Results[i].aggPF,
               phase2Results[i].aggNet, phase2Results[i].compositeScore));
   }

   // Also write combined output
   WriteCSV(phase1Results, phase1Count, "NNFX_H1_ParamOpt_Results.csv");

   Print("=== Parameter Optimization Complete ===");
   Alert("NNFX H1 ParamOpt done! Check MQL4/Files/NNFX_H1_ParamOpt_*.csv");
}
//+------------------------------------------------------------------+
