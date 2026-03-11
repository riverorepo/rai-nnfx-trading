//+------------------------------------------------------------------+
//|                                         NNFX_MegaSweep_H1.mq4   |
//|         H1 version of MegaSweep — tests ALL built-in MT4         |
//|         indicators across all 5 NNFX slots on H1 timeframe.      |
//|         Includes session filter (London+NY by default).           |
//|         Does NOT touch D1 bot files.                              |
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
   SWEEP_ALL      = 0,  // All Slots (run sequentially)
   SWEEP_BASELINE = 1,  // Baseline only
   SWEEP_C1       = 2,  // C1 only
   SWEEP_C2       = 3,  // C2 only
   SWEEP_VOLUME   = 4,  // Volume only
   SWEEP_EXIT     = 5   // Exit only
};

enum ENUM_IND_TYPE
{
   // Baselines
   IND_KAMA, IND_HMA, IND_SMA, IND_EMA, IND_SAR, IND_ICHIMOKU_KIJUN, IND_BANDS_MID,
   // Confirmations (C1/C2)
   IND_SSL, IND_MACD, IND_RSI, IND_CCI, IND_MOMENTUM, IND_ADX_DIR,
   IND_DEMARKER, IND_WPR, IND_STOCH, IND_BULLS_BEARS, IND_MA_CROSS,
   // Volume
   IND_WAE, IND_ADX_STRENGTH, IND_MFI, IND_OBV, IND_BANDS_WIDTH, IND_MOM_MAG,
   // Exit-specific
   IND_EMA_EXIT, IND_MACD_EXIT, IND_CCI_EXIT, IND_STOCH_EXIT, IND_HMA_EXIT,
   IND_SAR_EXIT, IND_RSI_EXIT
};

//+------------------------------------------------------------------+
//| INPUT                                                             |
//+------------------------------------------------------------------+
input ENUM_SWEEP_SLOT InpSweepSlot  = SWEEP_ALL;  // Which Slot(s) to Sweep
input int      InpMaxResults        = 50;          // Max results per slot in CSV
input int      InpSessionStart      = 7;           // Session Start Hour (GMT)
input int      InpSessionEnd        = 20;          // Session End Hour (GMT)
input bool     InpUseSession        = true;        // Enable Session Filter

//+------------------------------------------------------------------+
//| LOCKED STRATEGY CONSTANTS (H1 defaults)                           |
//+------------------------------------------------------------------+
#define LOCKED_KAMA_PERIOD     20
#define LOCKED_KAMA_FAST       2.0
#define LOCKED_KAMA_SLOW       30.0
#define LOCKED_SSL_C1_LEN      25
#define LOCKED_STOCH_K         14
#define LOCKED_STOCH_D         3
#define LOCKED_STOCH_SLOW      3
#define LOCKED_WAE_SENS        150
#define LOCKED_WAE_DZ          30
#define LOCKED_WAE_EP          15
#define LOCKED_WAE_TP          15
#define LOCKED_SSL_EXIT_LEN    5
#define LOCKED_ATR             14
#define LOCKED_SL              1.5
#define LOCKED_TP1             1.0
#define LOCKED_MAX_DIST        1.0
#define LOCKED_RISK            1.0
#define LOCKED_BAL             10000.0
#define LOCKED_KIJUN_PER       26

#define TF PERIOD_H1

#define IND_NAME_KAMA "KAMA"
#define IND_NAME_SSL  "SSL_Channel"
#define IND_NAME_WAE  "Waddah_Attar_Explosion"
#define IND_NAME_HMA  "HMA"

//+------------------------------------------------------------------+
//| STRUCTS                                                           |
//+------------------------------------------------------------------+
struct SweepConfig
{
   int            slot;
   ENUM_IND_TYPE  indType;
   double         p1, p2, p3, p4;
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

//--- Pairs
string g_pairs[7];
int    g_startBar[7], g_endBar[7];
double g_tickVal[7], g_tickSz[7], g_pointVal[7], g_spread[7];

int GetTypicalSpread(string s)
{
   // Typical Oanda H1 spreads (same as D1, pip-based)
   if(s=="EURUSD") return 14; if(s=="GBPUSD") return 18; if(s=="USDJPY") return 14;
   if(s=="USDCHF") return 17; if(s=="AUDUSD") return 14; if(s=="NZDUSD") return 20;
   if(s=="USDCAD") return 20; return 20;
}

//+------------------------------------------------------------------+
void OnStart()
{
   g_pairs[0]="EURUSD"; g_pairs[1]="GBPUSD"; g_pairs[2]="USDJPY";
   g_pairs[3]="USDCHF"; g_pairs[4]="AUDUSD"; g_pairs[5]="NZDUSD"; g_pairs[6]="USDCAD";

   datetime startDate = D'2020.01.01';
   datetime endDate   = D'2025.01.01';

   for(int p=0; p<7; p++)
   {
      g_startBar[p] = iBarShift(g_pairs[p], TF, startDate, false);
      g_endBar[p]   = iBarShift(g_pairs[p], TF, endDate, false);
      if(g_endBar[p]<0) g_endBar[p]=0;
      if(g_startBar[p]<0) g_startBar[p]=iBars(g_pairs[p],TF)-1;
      g_tickVal[p]  = MarketInfo(g_pairs[p], MODE_TICKVALUE);
      g_tickSz[p]   = MarketInfo(g_pairs[p], MODE_TICKSIZE);
      g_pointVal[p] = MarketInfo(g_pairs[p], MODE_POINT);
      g_spread[p]   = GetTypicalSpread(g_pairs[p]) * g_pointVal[p];
      Print(g_pairs[p], " H1 bars: ", g_startBar[p]-g_endBar[p],
            " (", g_startBar[p], " to ", g_endBar[p], ")");
   }

   Print("=== NNFX H1 MegaSweep v1.0 ===");
   Print("Session filter: ", InpUseSession ? IntegerToString(InpSessionStart)+"-"+IntegerToString(InpSessionEnd)+" GMT" : "OFF");
   Print("Locked: KAMA(", LOCKED_KAMA_PERIOD, ") | SSL C1(", LOCKED_SSL_C1_LEN,
         ") | Stoch(", LOCKED_STOCH_K, ") | WAE | SSL Exit(", LOCKED_SSL_EXIT_LEN,
         ") | ATR(", LOCKED_ATR, ") | Risk ", DoubleToStr(LOCKED_RISK,1), "%");

   // Build configs
   SweepConfig configs[];
   BuildConfigs(configs);
   int total = ArraySize(configs);
   Print("Total configs to test: ", total);

   // Run
   SweepResult results[];
   ArrayResize(results, total);
   int resultCount = 0;
   uint startTick = GetTickCount();

   for(int c=0; c<total; c++)
   {
      if(IsStopped()) { Print("CANCELLED by user."); break; }
      if((c+1) % 10 == 0)
      {
         uint elapsed = GetTickCount() - startTick;
         double pct = (double)(c+1)/total*100;
         double estTotal = elapsed / pct * 100;
         double remaining = (estTotal - elapsed) / 1000.0;
         Print("Progress: ", c+1, "/", total, " (", DoubleToStr(pct, 1), "%) ~",
               DoubleToStr(remaining, 0), "s remaining");
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
         totalGP += ps.gp;
         totalGL += ps.gl;
         res.totalSig += ps.sig;
         if(ps.maxDDPct > res.worstDD) res.worstDD = ps.maxDDPct;
         res.pairPF[p] = (ps.gl!=0) ? MathAbs(ps.gp/ps.gl) : 0;
         res.pairNet[p] = net;
         double wr = (ps.sig>0) ? ((double)ps.wins/ps.sig*100.0) : 0;
         totalWR += wr;
      }
      res.aggPF = (totalGL!=0) ? MathAbs(totalGP/totalGL) : 0;
      res.avgWR = totalWR / 7.0;

      results[resultCount] = res;
      resultCount++;
   }

   // Sort by PF
   SortResults(results, resultCount);

   // Output
   int outCount = MathMin(resultCount, InpMaxResults);
   WriteCSV(results, resultCount);
   PrintTop(results, outCount);

   uint totalTime = (GetTickCount() - startTick) / 1000;
   Print("=== H1 MegaSweep Complete in ", totalTime, "s ===");
   Alert("NNFX H1 MegaSweep done! Check MQL4/Files/NNFX_H1_MegaSweep_Results.csv");
}

//+------------------------------------------------------------------+
//| SESSION FILTER                                                    |
//+------------------------------------------------------------------+
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
//| BUILD ALL SWEEP CONFIGS                                           |
//+------------------------------------------------------------------+
void BuildConfigs(SweepConfig &configs[])
{
   int n = 0;
   ArrayResize(configs, 200);

   // === BASELINE (slot 1) ===
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_BASELINE)
   {
      // KAMA with different periods (longer for H1)
      int kamaPer[] = {10,20,30,50};
      for(int i=0;i<4;i++) AddCfg(configs,n, 1, IND_KAMA, kamaPer[i],2,30,0, "BL:KAMA("+IntegerToString(kamaPer[i])+")");
      // HMA
      int hmaPer[] = {14,20,30,50,100};
      for(int i=0;i<5;i++) AddCfg(configs,n, 1, IND_HMA, hmaPer[i],2,0,0, "BL:HMA("+IntegerToString(hmaPer[i])+")");
      // SMA
      int smaPer[] = {20,50,100,200};
      for(int i=0;i<4;i++) AddCfg(configs,n, 1, IND_SMA, smaPer[i],0,0,0, "BL:SMA("+IntegerToString(smaPer[i])+")");
      // EMA
      int emaPer[] = {20,50,100,200};
      for(int i=0;i<4;i++) AddCfg(configs,n, 1, IND_EMA, emaPer[i],0,0,0, "BL:EMA("+IntegerToString(emaPer[i])+")");
      // SAR
      double sarStep[] = {0.01,0.02,0.03}; double sarMax[] = {0.1,0.2};
      for(int i=0;i<3;i++) for(int j=0;j<2;j++)
         AddCfg(configs,n, 1, IND_SAR, sarStep[i],sarMax[j],0,0,
                "BL:SAR("+DoubleToStr(sarStep[i],2)+"/"+DoubleToStr(sarMax[j],1)+")");
      // Kijun
      int kijPer[] = {20,26,33,52};
      for(int i=0;i<4;i++) AddCfg(configs,n, 1, IND_ICHIMOKU_KIJUN, kijPer[i],0,0,0, "BL:Kijun("+IntegerToString(kijPer[i])+")");
      // BB mid
      int bbPer[] = {20,30,50};
      for(int i=0;i<3;i++) AddCfg(configs,n, 1, IND_BANDS_MID, bbPer[i],2,0,0, "BL:BBmid("+IntegerToString(bbPer[i])+")");
   }

   // === C1 (slot 2) ===
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_C1)
   {
      // SSL with different lengths
      int sslLen[] = {10,15,20,25,30,50};
      for(int i=0;i<6;i++) AddCfg(configs,n, 2, IND_SSL, sslLen[i],0,0,0, "C1:SSL("+IntegerToString(sslLen[i])+")");
      // MACD
      AddCfg(configs,n, 2, IND_MACD, 8,21,5,0, "C1:MACD(8/21/5)");
      AddCfg(configs,n, 2, IND_MACD, 12,26,9,0, "C1:MACD(12/26/9)");
      AddCfg(configs,n, 2, IND_MACD, 19,39,9,0, "C1:MACD(19/39/9)");
      // RSI
      int rsiPer[] = {7,14,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 2, IND_RSI, rsiPer[i],0,0,0, "C1:RSI("+IntegerToString(rsiPer[i])+")");
      // CCI
      int cciPer[] = {14,20,50};
      for(int i=0;i<3;i++) AddCfg(configs,n, 2, IND_CCI, cciPer[i],0,0,0, "C1:CCI("+IntegerToString(cciPer[i])+")");
      // Momentum
      int momPer[] = {10,14,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 2, IND_MOMENTUM, momPer[i],0,0,0, "C1:Mom("+IntegerToString(momPer[i])+")");
      // ADX directional
      int adxPer[] = {7,14,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 2, IND_ADX_DIR, adxPer[i],20,0,0, "C1:ADXdir("+IntegerToString(adxPer[i])+")");
      // DeMarker
      int demPer[] = {7,13,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 2, IND_DEMARKER, demPer[i],0,0,0, "C1:DeMark("+IntegerToString(demPer[i])+")");
      // WPR
      int wprPer[] = {7,14,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 2, IND_WPR, wprPer[i],0,0,0, "C1:WPR("+IntegerToString(wprPer[i])+")");
      // Stochastic
      int stPer[] = {5,8,14,21};
      for(int i=0;i<4;i++) AddCfg(configs,n, 2, IND_STOCH, stPer[i],3,3,0, "C1:Stoch("+IntegerToString(stPer[i])+")");
      // Bulls+Bears
      AddCfg(configs,n, 2, IND_BULLS_BEARS, 7,0,0,0, "C1:BullBear(7)");
      AddCfg(configs,n, 2, IND_BULLS_BEARS, 13,0,0,0, "C1:BullBear(13)");
      // MA crossover
      AddCfg(configs,n, 2, IND_MA_CROSS, 5,20,0,0, "C1:MACross(5/20)");
      AddCfg(configs,n, 2, IND_MA_CROSS, 8,21,0,0, "C1:MACross(8/21)");
      AddCfg(configs,n, 2, IND_MA_CROSS, 13,34,0,0, "C1:MACross(13/34)");
      AddCfg(configs,n, 2, IND_MA_CROSS, 20,50,0,0, "C1:MACross(20/50)");
   }

   // === C2 (slot 3) ===
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_C2)
   {
      AddCfg(configs,n, 3, IND_STOCH, 14,3,3,0, "C2:Stoch(14)");
      AddCfg(configs,n, 3, IND_STOCH, 8,3,3,0, "C2:Stoch(8)");
      AddCfg(configs,n, 3, IND_STOCH, 21,3,3,0, "C2:Stoch(21)");
      AddCfg(configs,n, 3, IND_MACD, 12,26,9,0, "C2:MACD(12/26/9)");
      int rsiPer[] = {7,14,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 3, IND_RSI, rsiPer[i],0,0,0, "C2:RSI("+IntegerToString(rsiPer[i])+")");
      int cciPer[] = {14,20,50};
      for(int i=0;i<3;i++) AddCfg(configs,n, 3, IND_CCI, cciPer[i],0,0,0, "C2:CCI("+IntegerToString(cciPer[i])+")");
      int momPer[] = {10,14,21};
      for(int i=0;i<3;i++) AddCfg(configs,n, 3, IND_MOMENTUM, momPer[i],0,0,0, "C2:Mom("+IntegerToString(momPer[i])+")");
      AddCfg(configs,n, 3, IND_DEMARKER, 7,0,0,0, "C2:DeMark(7)");
      AddCfg(configs,n, 3, IND_DEMARKER, 13,0,0,0, "C2:DeMark(13)");
      AddCfg(configs,n, 3, IND_WPR, 7,0,0,0, "C2:WPR(7)");
      AddCfg(configs,n, 3, IND_WPR, 14,0,0,0, "C2:WPR(14)");
      AddCfg(configs,n, 3, IND_ADX_DIR, 14,20,0,0, "C2:ADXdir(14)");
      AddCfg(configs,n, 3, IND_ADX_DIR, 21,20,0,0, "C2:ADXdir(21)");
      AddCfg(configs,n, 3, IND_BULLS_BEARS, 13,0,0,0, "C2:BullBear(13)");
   }

   // === VOLUME (slot 4) ===
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_VOLUME)
   {
      AddCfg(configs,n, 4, IND_WAE, 150,30,15,15, "VOL:WAE(150/30)");
      AddCfg(configs,n, 4, IND_WAE, 100,20,15,15, "VOL:WAE(100/20)");
      // ADX strength
      int adxP[] = {7,14,21}; double adxTh[] = {20,25};
      for(int i=0;i<3;i++) for(int j=0;j<2;j++)
         AddCfg(configs,n, 4, IND_ADX_STRENGTH, adxP[i],adxTh[j],0,0,
                "VOL:ADX("+IntegerToString(adxP[i])+"/"+DoubleToStr(adxTh[j],0)+")");
      // MFI
      AddCfg(configs,n, 4, IND_MFI, 7,0,0,0, "VOL:MFI(7)");
      AddCfg(configs,n, 4, IND_MFI, 14,0,0,0, "VOL:MFI(14)");
      // OBV
      AddCfg(configs,n, 4, IND_OBV, 0,0,0,0, "VOL:OBV");
      // Bands width
      double bbP[] = {20,30}; double bbD[] = {1.5,2.0};
      for(int i=0;i<2;i++) for(int j=0;j<2;j++)
         AddCfg(configs,n, 4, IND_BANDS_WIDTH, bbP[i],bbD[j],0,0,
                "VOL:BBwidth("+DoubleToStr(bbP[i],0)+"/"+DoubleToStr(bbD[j],1)+")");
      // Momentum magnitude
      AddCfg(configs,n, 4, IND_MOM_MAG, 7,0,0,0, "VOL:MomMag(7)");
      AddCfg(configs,n, 4, IND_MOM_MAG, 10,0,0,0, "VOL:MomMag(10)");
      AddCfg(configs,n, 4, IND_MOM_MAG, 14,0,0,0, "VOL:MomMag(14)");
   }

   // === EXIT (slot 5) ===
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_EXIT)
   {
      int sslExLen[] = {3,5,8,10,15};
      for(int i=0;i<5;i++) AddCfg(configs,n, 5, IND_SSL, sslExLen[i],0,0,0, "EXIT:SSL("+IntegerToString(sslExLen[i])+")");
      // RSI
      int rsiP[] = {5,7,10,14};
      for(int i=0;i<4;i++) AddCfg(configs,n, 5, IND_RSI_EXIT, rsiP[i],0,0,0, "EXIT:RSI("+IntegerToString(rsiP[i])+")");
      // SAR
      AddCfg(configs,n, 5, IND_SAR_EXIT, 0.02,0.2,0,0, "EXIT:SAR(0.02/0.2)");
      AddCfg(configs,n, 5, IND_SAR_EXIT, 0.03,0.2,0,0, "EXIT:SAR(0.03/0.2)");
      // EMA
      int emaP[] = {5,8,13,20};
      for(int i=0;i<4;i++) AddCfg(configs,n, 5, IND_EMA_EXIT, emaP[i],0,0,0, "EXIT:EMA("+IntegerToString(emaP[i])+")");
      // MACD
      AddCfg(configs,n, 5, IND_MACD_EXIT, 12,26,9,0, "EXIT:MACD(12/26/9)");
      // CCI
      AddCfg(configs,n, 5, IND_CCI_EXIT, 14,0,0,0, "EXIT:CCI(14)");
      AddCfg(configs,n, 5, IND_CCI_EXIT, 20,0,0,0, "EXIT:CCI(20)");
      // Stochastic
      int stP[] = {5,8,14};
      for(int i=0;i<3;i++) AddCfg(configs,n, 5, IND_STOCH_EXIT, stP[i],3,3,0, "EXIT:Stoch("+IntegerToString(stP[i])+")");
      // HMA
      AddCfg(configs,n, 5, IND_HMA_EXIT, 7,2,0,0, "EXIT:HMA(7)");
      AddCfg(configs,n, 5, IND_HMA_EXIT, 14,2,0,0, "EXIT:HMA(14)");
   }

   ArrayResize(configs, n);
}

void AddCfg(SweepConfig &arr[], int &n, int slot, ENUM_IND_TYPE type,
            double p1, double p2, double p3, double p4, string lbl)
{
   if(n >= ArraySize(arr)) ArrayResize(arr, n+50);
   arr[n].slot = slot;
   arr[n].indType = type;
   arr[n].p1 = p1; arr[n].p2 = p2; arr[n].p3 = p3; arr[n].p4 = p4;
   arr[n].label = lbl;
   n++;
}

//+------------------------------------------------------------------+
//| SIGNAL DISPATCHERS                                                |
//+------------------------------------------------------------------+

double GetBLValue(string sym, int shift, SweepConfig &cfg)
{
   if(cfg.slot != 1)
      return iCustom(sym, TF, IND_NAME_KAMA, LOCKED_KAMA_PERIOD, LOCKED_KAMA_FAST, LOCKED_KAMA_SLOW, 0, shift);

   switch(cfg.indType)
   {
      case IND_KAMA:
         return iCustom(sym, TF, IND_NAME_KAMA, (int)cfg.p1, cfg.p2, cfg.p3, 0, shift);
      case IND_HMA:
         return iCustom(sym, TF, IND_NAME_HMA, (int)cfg.p1, cfg.p2, PRICE_CLOSE, 0, shift);
      case IND_SMA:
         return iMA(sym, TF, (int)cfg.p1, 0, MODE_SMA, PRICE_CLOSE, shift);
      case IND_EMA:
         return iMA(sym, TF, (int)cfg.p1, 0, MODE_EMA, PRICE_CLOSE, shift);
      case IND_SAR:
         return iSAR(sym, TF, cfg.p1, cfg.p2, shift);
      case IND_ICHIMOKU_KIJUN:
         return iIchimoku(sym, TF, 9, (int)cfg.p1, 52, MODE_KIJUNSEN, shift);
      case IND_BANDS_MID:
         return iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_MAIN, shift);
      default:
         return 0;
   }
}

int GetBLDirection(string sym, int shift, SweepConfig &cfg)
{
   double bl = GetBLValue(sym, shift, cfg);
   double close = iClose(sym, TF, shift);
   if(bl == 0) return 0;

   if(cfg.slot == 1 && cfg.indType == IND_SAR)
   {
      if(bl < close) return 1;
      if(bl > close) return -1;
      return 0;
   }

   if(close > bl) return 1;
   if(close < bl) return -1;
   return 0;
}

bool GetBLCross(string sym, int bar, SweepConfig &cfg)
{
   int dirCurr = GetBLDirection(sym, bar, cfg);
   int dirPrev = GetBLDirection(sym, bar+1, cfg);
   return (dirCurr != 0 && dirCurr != dirPrev);
}

int GetConfirmDir(string sym, int shift, SweepConfig &cfg)
{
   switch(cfg.indType)
   {
      case IND_SSL:
      {
         int len = (int)cfg.p1;
         double hlv = iCustom(sym, TF, IND_NAME_SSL,
                               false, 0, 2, len, 0, 3, len, 0, shift);
         if(hlv > 0.5) return 1;
         if(hlv < -0.5) return -1;
         return 0;
      }
      case IND_MACD:
      {
         double val = iMACD(sym, TF, (int)cfg.p1, (int)cfg.p2, (int)cfg.p3,
                            PRICE_CLOSE, MODE_MAIN, shift);
         if(val > 0) return 1; if(val < 0) return -1; return 0;
      }
      case IND_RSI:
      {
         double val = iRSI(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         if(val > 50) return 1; if(val < 50) return -1; return 0;
      }
      case IND_CCI:
      {
         double val = iCCI(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         if(val > 0) return 1; if(val < 0) return -1; return 0;
      }
      case IND_MOMENTUM:
      {
         double val = iMomentum(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         if(val > 100) return 1; if(val < 100) return -1; return 0;
      }
      case IND_ADX_DIR:
      {
         double plusDI  = iADX(sym, TF, (int)cfg.p1, PRICE_CLOSE, MODE_PLUSDI, shift);
         double minusDI = iADX(sym, TF, (int)cfg.p1, PRICE_CLOSE, MODE_MINUSDI, shift);
         double adxMain = iADX(sym, TF, (int)cfg.p1, PRICE_CLOSE, MODE_MAIN, shift);
         if(adxMain < cfg.p2) return 0;
         if(plusDI > minusDI) return 1; if(minusDI > plusDI) return -1; return 0;
      }
      case IND_DEMARKER:
      {
         double val = iDeMarker(sym, TF, (int)cfg.p1, shift);
         if(val > 0.5) return 1; if(val < 0.5) return -1; return 0;
      }
      case IND_WPR:
      {
         double val = iWPR(sym, TF, (int)cfg.p1, shift);
         if(val > -50) return 1; if(val < -50) return -1; return 0;
      }
      case IND_STOCH:
      {
         double val = iStochastic(sym, TF, (int)cfg.p1, (int)cfg.p2, (int)cfg.p3,
                                   MODE_SMA, 0, MODE_MAIN, shift);
         if(val > 50) return 1; if(val < 50) return -1; return 0;
      }
      case IND_BULLS_BEARS:
      {
         double bulls = iBullsPower(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         double bears = iBearsPower(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         double net = bulls + bears;
         if(net > 0) return 1; if(net < 0) return -1; return 0;
      }
      case IND_MA_CROSS:
      {
         double fast = iMA(sym, TF, (int)cfg.p1, 0, MODE_EMA, PRICE_CLOSE, shift);
         double slow = iMA(sym, TF, (int)cfg.p2, 0, MODE_EMA, PRICE_CLOSE, shift);
         if(fast > slow) return 1; if(fast < slow) return -1; return 0;
      }
      default: return 0;
   }
}

int GetLockedC1(string sym, int shift)
{
   double hlv = iCustom(sym, TF, IND_NAME_SSL,
                          false, 0, 2, LOCKED_SSL_C1_LEN, 0, 3, LOCKED_SSL_C1_LEN, 0, shift);
   if(hlv > 0.5) return 1; if(hlv < -0.5) return -1; return 0;
}

int GetLockedC2(string sym, int shift)
{
   double val = iStochastic(sym, TF, LOCKED_STOCH_K, LOCKED_STOCH_D, LOCKED_STOCH_SLOW,
                             MODE_SMA, 0, MODE_MAIN, shift);
   if(val > 50) return 1; if(val < 50) return -1; return 0;
}

bool CheckVolume(string sym, int shift, int direction, SweepConfig &cfg)
{
   if(cfg.slot != 4) return CheckLockedWAE(sym, shift, direction);

   switch(cfg.indType)
   {
      case IND_WAE:
      {
         double green     = iCustom(sym, TF, IND_NAME_WAE, (int)cfg.p1, (int)cfg.p2,
                                     (int)cfg.p3, (int)cfg.p4, true, 500, true, true, true, true, 0, shift);
         double red       = iCustom(sym, TF, IND_NAME_WAE, (int)cfg.p1, (int)cfg.p2,
                                     (int)cfg.p3, (int)cfg.p4, true, 500, true, true, true, true, 1, shift);
         double explosion = iCustom(sym, TF, IND_NAME_WAE, (int)cfg.p1, (int)cfg.p2,
                                     (int)cfg.p3, (int)cfg.p4, true, 500, true, true, true, true, 2, shift);
         double deadZone  = iCustom(sym, TF, IND_NAME_WAE, (int)cfg.p1, (int)cfg.p2,
                                     (int)cfg.p3, (int)cfg.p4, true, 500, true, true, true, true, 3, shift);
         double greenPrev = iCustom(sym, TF, IND_NAME_WAE, (int)cfg.p1, (int)cfg.p2,
                                     (int)cfg.p3, (int)cfg.p4, true, 500, true, true, true, true, 0, shift+1);
         double redPrev   = iCustom(sym, TF, IND_NAME_WAE, (int)cfg.p1, (int)cfg.p2,
                                     (int)cfg.p3, (int)cfg.p4, true, 500, true, true, true, true, 1, shift+1);
         if(explosion <= deadZone) return false;
         bool trendMatch=false, trendGrow=false;
         if(direction==1 && green>0)  { trendMatch=true; trendGrow=(green>greenPrev); }
         if(direction==-1 && red>0)   { trendMatch=true; trendGrow=(red>redPrev); }
         return (trendMatch && trendGrow);
      }
      case IND_ADX_STRENGTH:
      {
         double adx = iADX(sym, TF, (int)cfg.p1, PRICE_CLOSE, MODE_MAIN, shift);
         return (adx > cfg.p2);
      }
      case IND_MFI:
      {
         double mfi = iMFI(sym, TF, (int)cfg.p1, shift);
         double mfiPrev = iMFI(sym, TF, (int)cfg.p1, shift+1);
         if(direction == 1 && mfi > 50 && mfi < 80 && mfi > mfiPrev) return true;
         if(direction == -1 && mfi < 50 && mfi > 20 && mfi < mfiPrev) return true;
         return false;
      }
      case IND_OBV:
      {
         double obv     = iOBV(sym, TF, PRICE_CLOSE, shift);
         double obvPrev = iOBV(sym, TF, PRICE_CLOSE, shift+1);
         if(direction == 1 && obv > obvPrev) return true;
         if(direction == -1 && obv < obvPrev) return true;
         return false;
      }
      case IND_BANDS_WIDTH:
      {
         double upper  = iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_UPPER, shift);
         double lower  = iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_LOWER, shift);
         double mid    = iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_MAIN, shift);
         double upperP = iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_UPPER, shift+1);
         double lowerP = iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_LOWER, shift+1);
         double midP   = iBands(sym, TF, (int)cfg.p1, cfg.p2, 0, PRICE_CLOSE, MODE_MAIN, shift+1);
         if(mid == 0 || midP == 0) return false;
         double width     = (upper - lower) / mid;
         double widthPrev = (upperP - lowerP) / midP;
         return (width > widthPrev);
      }
      case IND_MOM_MAG:
      {
         double mom     = iMomentum(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         double momPrev = iMomentum(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift+1);
         double mag     = MathAbs(mom - 100);
         double magPrev = MathAbs(momPrev - 100);
         return (mag > magPrev && mag > 0.05);  // Lower threshold for H1
      }
      default: return false;
   }
}

bool CheckLockedWAE(string sym, int shift, int direction)
{
   double green     = iCustom(sym, TF, IND_NAME_WAE, LOCKED_WAE_SENS, LOCKED_WAE_DZ,
                               LOCKED_WAE_EP, LOCKED_WAE_TP, true, 500, true, true, true, true, 0, shift);
   double red       = iCustom(sym, TF, IND_NAME_WAE, LOCKED_WAE_SENS, LOCKED_WAE_DZ,
                               LOCKED_WAE_EP, LOCKED_WAE_TP, true, 500, true, true, true, true, 1, shift);
   double explosion = iCustom(sym, TF, IND_NAME_WAE, LOCKED_WAE_SENS, LOCKED_WAE_DZ,
                               LOCKED_WAE_EP, LOCKED_WAE_TP, true, 500, true, true, true, true, 2, shift);
   double deadZone  = iCustom(sym, TF, IND_NAME_WAE, LOCKED_WAE_SENS, LOCKED_WAE_DZ,
                               LOCKED_WAE_EP, LOCKED_WAE_TP, true, 500, true, true, true, true, 3, shift);
   double greenPrev = iCustom(sym, TF, IND_NAME_WAE, LOCKED_WAE_SENS, LOCKED_WAE_DZ,
                               LOCKED_WAE_EP, LOCKED_WAE_TP, true, 500, true, true, true, true, 0, shift+1);
   double redPrev   = iCustom(sym, TF, IND_NAME_WAE, LOCKED_WAE_SENS, LOCKED_WAE_DZ,
                               LOCKED_WAE_EP, LOCKED_WAE_TP, true, 500, true, true, true, true, 1, shift+1);

   if(explosion <= deadZone) return false;
   bool trendMatch=false, trendGrow=false;
   if(direction==1 && green>0)  { trendMatch=true; trendGrow=(green>greenPrev); }
   if(direction==-1 && red>0)   { trendMatch=true; trendGrow=(red>redPrev); }
   return (trendMatch && trendGrow);
}

bool CheckExit(string sym, int shift, int tradeDir, SweepConfig &cfg)
{
   if(cfg.slot != 5) return CheckLockedExit(sym, shift, tradeDir);

   switch(cfg.indType)
   {
      case IND_SSL:
      {
         int len = (int)cfg.p1;
         double hlv = iCustom(sym, TF, IND_NAME_SSL,
                               false, 0, 2, len, 0, 3, len, 0, shift);
         int dir = 0;
         if(hlv > 0.5) dir = 1; if(hlv < -0.5) dir = -1;
         if(tradeDir == 1 && dir == -1) return true;
         if(tradeDir == -1 && dir == 1) return true;
         return false;
      }
      case IND_RSI_EXIT:
      {
         double rsi = iRSI(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         if(tradeDir == 1 && rsi < 50) return true;
         if(tradeDir == -1 && rsi > 50) return true;
         return false;
      }
      case IND_SAR_EXIT:
      {
         double sar   = iSAR(sym, TF, cfg.p1, cfg.p2, shift);
         double close = iClose(sym, TF, shift);
         if(tradeDir == 1 && sar > close) return true;
         if(tradeDir == -1 && sar < close) return true;
         return false;
      }
      case IND_EMA_EXIT:
      {
         double ema   = iMA(sym, TF, (int)cfg.p1, 0, MODE_EMA, PRICE_CLOSE, shift);
         double close = iClose(sym, TF, shift);
         if(tradeDir == 1 && close < ema) return true;
         if(tradeDir == -1 && close > ema) return true;
         return false;
      }
      case IND_MACD_EXIT:
      {
         double macd = iMACD(sym, TF, (int)cfg.p1, (int)cfg.p2, (int)cfg.p3,
                              PRICE_CLOSE, MODE_MAIN, shift);
         if(tradeDir == 1 && macd < 0) return true;
         if(tradeDir == -1 && macd > 0) return true;
         return false;
      }
      case IND_CCI_EXIT:
      {
         double cci = iCCI(sym, TF, (int)cfg.p1, PRICE_CLOSE, shift);
         if(tradeDir == 1 && cci < 0) return true;
         if(tradeDir == -1 && cci > 0) return true;
         return false;
      }
      case IND_STOCH_EXIT:
      {
         double st = iStochastic(sym, TF, (int)cfg.p1, (int)cfg.p2, (int)cfg.p3,
                                  MODE_SMA, 0, MODE_MAIN, shift);
         if(tradeDir == 1 && st < 50) return true;
         if(tradeDir == -1 && st > 50) return true;
         return false;
      }
      case IND_HMA_EXIT:
      {
         double hma     = iCustom(sym, TF, IND_NAME_HMA, (int)cfg.p1, cfg.p2, PRICE_CLOSE, 0, shift);
         double hmaPrev = iCustom(sym, TF, IND_NAME_HMA, (int)cfg.p1, cfg.p2, PRICE_CLOSE, 0, shift+1);
         if(tradeDir == 1 && hma < hmaPrev) return true;
         if(tradeDir == -1 && hma > hmaPrev) return true;
         return false;
      }
      default: return false;
   }
}

bool CheckLockedExit(string sym, int shift, int tradeDir)
{
   double hlv = iCustom(sym, TF, IND_NAME_SSL,
                          false, 0, 2, LOCKED_SSL_EXIT_LEN, 0, 3, LOCKED_SSL_EXIT_LEN, 0, shift);
   int dir = 0;
   if(hlv > 0.5) dir = 1; if(hlv < -0.5) dir = -1;
   if(tradeDir == 1 && dir == -1) return true;
   if(tradeDir == -1 && dir == 1) return true;
   return false;
}

//+------------------------------------------------------------------+
//| BACKTEST ENGINE                                                   |
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

   for(int bar=startBar-1; bar>endBar; bar--)
   {
      if(trade.o1Open || trade.o2Open)
         Manage(sym, bar, spread, trade, balance, peak, stats, tickVal, tickSz, cfg);
      if(trade.o1Open || trade.o2Open) continue;

      // Session filter for new entries only
      datetime barTime = iTime(sym, TF, bar);
      if(!InSession(barTime)) continue;

      int signal = EvalEntry(sym, bar, cfg);
      if(signal == 0) continue;
      stats.sig++;

      double atr = iATR(sym, TF, LOCKED_ATR, bar);
      if(atr <= 0) continue;

      double openNext = iOpen(sym, TF, bar-1);
      double entry = (signal==1) ? openNext+spread : openNext;
      double slDist = LOCKED_SL*atr, tp1Dist = LOCKED_TP1*atr;
      double risk = balance*(LOCKED_RISK/100.0);
      double slTicks = slDist/tickSz;
      double rpl = slTicks*tickVal;
      if(rpl<=0) continue;
      double half = MathFloor((risk/rpl)/2.0*100)/100.0;
      if(half<0.01) half=0.01;

      trade.dir=signal; trade.entry=entry;
      trade.lots1=half; trade.lots2=half;
      trade.o1Open=true; trade.o2Open=true;
      trade.movedBE=false; trade.pnl=0;
      if(signal==1) { trade.sl=entry-slDist; trade.tp1=entry+tp1Dist; }
      else          { trade.sl=entry+slDist; trade.tp1=entry-tp1Dist; }
   }

   if(trade.o1Open || trade.o2Open)
   {
      double lc = iClose(sym, TF, endBar);
      double ep = (trade.dir==1) ? lc : lc+spread;
      FClose(trade, ep, balance, peak, stats, tickVal, tickSz);
   }
   stats.bal = balance;
}

//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar, SweepConfig &cfg)
{
   // 1. Baseline
   int blDir = GetBLDirection(sym, bar, cfg);
   if(blDir == 0) return 0;
   if(!GetBLCross(sym, bar, cfg)) return 0;

   // ATR filter
   double atr = iATR(sym, TF, LOCKED_ATR, bar);
   if(cfg.slot==1 && cfg.indType==IND_SAR)
   { /* SAR: no ATR distance filter */ }
   else
   {
      double bl = GetBLValue(sym, bar, cfg);
      double close = iClose(sym, TF, bar);
      if(MathAbs(close - bl) > LOCKED_MAX_DIST * atr) return 0;
   }

   // 2. C1
   int c1;
   if(cfg.slot == 2) c1 = GetConfirmDir(sym, bar, cfg);
   else              c1 = GetLockedC1(sym, bar);
   if(c1 != blDir) return 0;

   // 3. C2
   int c2Curr, c2Prev;
   if(cfg.slot == 3)
   { c2Curr = GetConfirmDir(sym, bar, cfg); c2Prev = GetConfirmDir(sym, bar+1, cfg); }
   else
   { c2Curr = GetLockedC2(sym, bar); c2Prev = GetLockedC2(sym, bar+1); }
   if(c2Curr != blDir && c2Prev != blDir) return 0;

   // 4. Volume
   if(!CheckVolume(sym, bar, blDir, cfg)) return 0;

   return blDir;
}

//+------------------------------------------------------------------+
void Manage(string sym, int bar, double spread, VTrade &t,
             double &bal, double &peak, PStats &s, double tv, double ts, SweepConfig &cfg)
{
   double hi=iHigh(sym,TF,bar), lo=iLow(sym,TF,bar), cl=iClose(sym,TF,bar);
   double aHi=hi+spread, aLo=lo+spread, aCl=cl+spread;

   // Opposite baseline cross
   int dirNow  = GetBLDirection(sym, bar, cfg);
   int dirPrev = GetBLDirection(sym, bar+1, cfg);
   bool opp = false;
   if(t.dir==1 && dirNow==-1 && dirPrev!=-1) opp=true;
   if(t.dir==-1 && dirNow==1 && dirPrev!=1) opp=true;
   if(opp)
   {
      double ep = (t.dir==1)?cl:aCl;
      FClose(t, ep, bal, peak, s, tv, ts);
      return;
   }

   // Order 1
   if(t.o1Open)
   {
      bool tp=false, sl=false; double pnl=0;
      if(t.dir==1)
      { if(hi>=t.tp1){tp=true;pnl=(t.tp1-t.entry)/ts*tv*t.lots1;} else if(lo<=t.sl){sl=true;pnl=(t.sl-t.entry)/ts*tv*t.lots1;} }
      else
      { if(aLo<=t.tp1){tp=true;pnl=(t.entry-t.tp1)/ts*tv*t.lots1;} else if(aHi>=t.sl){sl=true;pnl=(t.entry-t.sl)/ts*tv*t.lots1;} }
      if(tp||sl)
      {
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0)s.gp+=pnl; else s.gl+=pnl;
         t.o1Open=false;
         if(tp&&t.o2Open){t.sl=t.entry;t.movedBE=true;}
      }
   }

   // Order 2
   if(t.o2Open)
   {
      bool slH=false;
      if(t.dir==1 && lo<=t.sl) slH=true;
      if(t.dir==-1 && aHi>=t.sl) slH=true;

      bool exitFlip = CheckExit(sym, bar, t.dir, cfg);

      double pnl=0;
      if(slH)
      {
         if(t.dir==1) pnl=(t.sl-t.entry)/ts*tv*t.lots2;
         else         pnl=(t.entry-t.sl)/ts*tv*t.lots2;
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0)s.gp+=pnl; else s.gl+=pnl;
         t.o2Open=false;
      }
      else if(exitFlip)
      {
         double ep=(t.dir==1)?cl:aCl;
         if(t.dir==1) pnl=(ep-t.entry)/ts*tv*t.lots2;
         else         pnl=(t.entry-ep)/ts*tv*t.lots2;
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0)s.gp+=pnl; else s.gl+=pnl;
         t.o2Open=false;
      }
   }

   if(!t.o1Open && !t.o2Open)
   { if(t.pnl>=0) s.wins++; else s.losses++; }

   if(bal>peak) peak=bal;
   double dd=peak-bal;
   if(dd>s.maxDD){s.maxDD=dd;s.maxDDPct=(dd/peak)*100.0;}
}

//+------------------------------------------------------------------+
void FClose(VTrade &t, double ep, double &bal, double &peak, PStats &s, double tv, double ts)
{
   if(t.o1Open)
   {
      double pnl=(t.dir==1)?(ep-t.entry)/ts*tv*t.lots1:(t.entry-ep)/ts*tv*t.lots1;
      bal+=pnl; t.pnl+=pnl;
      if(pnl>0)s.gp+=pnl; else s.gl+=pnl;
      t.o1Open=false;
   }
   if(t.o2Open)
   {
      double pnl=(t.dir==1)?(ep-t.entry)/ts*tv*t.lots2:(t.entry-ep)/ts*tv*t.lots2;
      bal+=pnl; t.pnl+=pnl;
      if(pnl>0)s.gp+=pnl; else s.gl+=pnl;
      t.o2Open=false;
   }
   if(t.pnl>=0) s.wins++; else s.losses++;
   if(bal>peak) peak=bal;
   double dd=peak-bal;
   if(dd>s.maxDD){s.maxDD=dd;s.maxDDPct=(dd/peak)*100.0;}
}

//+------------------------------------------------------------------+
//| SORT & OUTPUT                                                     |
//+------------------------------------------------------------------+
void SortResults(SweepResult &arr[], int count)
{
   for(int i=0;i<count-1;i++)
      for(int j=0;j<count-i-1;j++)
         if(arr[j].aggPF < arr[j+1].aggPF)
         { SweepResult tmp=arr[j]; arr[j]=arr[j+1]; arr[j+1]=tmp; }
}

void PrintTop(SweepResult &res[], int count)
{
   Print("===== TOP ", count, " H1 INDICATOR COMBOS (by Aggregate PF) =====");
   for(int i=0;i<count;i++)
   {
      Print(StringFormat("#%d %s | Net=$%.2f PF=%.2f WR=%.1f%% DD=%.1f%% Sig=%d",
            i+1, res[i].label, res[i].aggNet, res[i].aggPF, res[i].avgWR, res[i].worstDD, res[i].totalSig));
   }
}

void WriteCSV(SweepResult &res[], int count)
{
   string filename = "NNFX_H1_MegaSweep_Results.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle<0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle, "Rank", "Indicator", "Slot",
             "EURUSD_PF", "GBPUSD_PF", "USDJPY_PF", "USDCHF_PF", "AUDUSD_PF", "NZDUSD_PF", "USDCAD_PF",
             "EURUSD_Net", "GBPUSD_Net", "USDJPY_Net", "USDCHF_Net", "AUDUSD_Net", "NZDUSD_Net", "USDCAD_Net",
             "Agg_NetProfit", "Agg_PF", "Avg_WR%", "Worst_DD%", "Total_Signals");

   for(int i=0;i<count;i++)
   {
      SweepResult r = res[i];
      string slotName = "";
      if(r.slot==1) slotName="Baseline"; if(r.slot==2) slotName="C1";
      if(r.slot==3) slotName="C2"; if(r.slot==4) slotName="Volume"; if(r.slot==5) slotName="Exit";

      FileWrite(handle, i+1, r.label, slotName,
                DoubleToStr(r.pairPF[0],2), DoubleToStr(r.pairPF[1],2), DoubleToStr(r.pairPF[2],2),
                DoubleToStr(r.pairPF[3],2), DoubleToStr(r.pairPF[4],2), DoubleToStr(r.pairPF[5],2),
                DoubleToStr(r.pairPF[6],2),
                DoubleToStr(r.pairNet[0],2), DoubleToStr(r.pairNet[1],2), DoubleToStr(r.pairNet[2],2),
                DoubleToStr(r.pairNet[3],2), DoubleToStr(r.pairNet[4],2), DoubleToStr(r.pairNet[5],2),
                DoubleToStr(r.pairNet[6],2),
                DoubleToStr(r.aggNet,2), DoubleToStr(r.aggPF,2),
                DoubleToStr(r.avgWR,1), DoubleToStr(r.worstDD,1), r.totalSig);
   }
   FileClose(handle);
   Print("Results saved to: MQL4/Files/", filename);
}
//+------------------------------------------------------------------+
