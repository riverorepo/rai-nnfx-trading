//+------------------------------------------------------------------+
//|                                          NNFX_H1_Sweep_V2.mq4   |
//|  H1 intraday sweep — multi-timeframe architecture:               |
//|    Slot 1: HTF Trend Filter (H4/D1) — direction only             |
//|    Slot 2: H1 Entry Trigger — indicator FLIP in HTF direction    |
//|    Slot 3: H1 Confirmation — direction must agree                |
//|    Slot 4: H1 Volume/Strength — momentum/volatility filter       |
//|    Slot 5: H1 Exit — fast flip against trade closes runner       |
//|  ~120 configs x 7 pairs. 2020-2025.                              |
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
   // HTF Trend Filter (slot 1) — returns direction via line vs price
   IND_HTF_EMA,
   IND_HTF_SMA,
   IND_HTF_KAMA,
   IND_HTF_KIJUN,
   IND_HTF_NONE,        // No filter — always allow both directions

   // Entry Trigger (slot 2) — flip detection on H1
   IND_ENTRY_SSL,
   IND_ENTRY_EMA_PRICE, // EMA cross price
   IND_ENTRY_MACD_ZERO,
   IND_ENTRY_STOCH_50,
   IND_ENTRY_CCI_ZERO,
   IND_ENTRY_RSI_50,
   IND_ENTRY_SAR,
   IND_ENTRY_HMA,

   // Confirmation (slot 3) — direction check
   IND_CONF_STOCH,
   IND_CONF_RSI,
   IND_CONF_MACD,
   IND_CONF_CCI,
   IND_CONF_MOMENTUM,
   IND_CONF_ADX_DIR,
   IND_CONF_WPR,
   IND_CONF_DEMARKER,
   IND_CONF_BULLS_BEARS,

   // Volume (slot 4)
   IND_VOL_ADX,
   IND_VOL_WAE,
   IND_VOL_BB_WIDTH,
   IND_VOL_MOM_MAG,
   IND_VOL_ATR_EXP,
   IND_VOL_NONE,        // No filter — always pass

   // Exit (slot 5) — flip against trade direction
   IND_EXIT_SSL,
   IND_EXIT_RSI,
   IND_EXIT_SAR,
   IND_EXIT_EMA,
   IND_EXIT_CCI,
   IND_EXIT_STOCH,
   IND_EXIT_HMA,
   IND_EXIT_MACD
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
//| LOCKED DEFAULT CONSTANTS                                          |
//+------------------------------------------------------------------+
// HTF Trend (H4 EMA 50)
#define LOCKED_HTF_TF       PERIOD_H4
#define LOCKED_HTF_EMA_PER  50

// Entry Trigger (H1 SSL(10) flip)
#define LOCKED_ENTRY_SSL_LEN 10

// Confirmation (H1 Stoch(14) above/below 50)
#define LOCKED_CONF_STOCH_K  14
#define LOCKED_CONF_STOCH_D  3
#define LOCKED_CONF_STOCH_SL 3

// Volume (H1 ADX(14) > 20)
#define LOCKED_VOL_ADX_PER  14
#define LOCKED_VOL_ADX_TH   20.0

// Exit (H1 SSL(5) flip)
#define LOCKED_EXIT_SSL_LEN  5

// Trade management
#define LOCKED_ATR          14
#define LOCKED_SL           1.5
#define LOCKED_TP1          1.0
#define LOCKED_RISK         1.0
#define LOCKED_BAL          10000.0

// Custom indicator names
#define IND_NAME_KAMA "KAMA"
#define IND_NAME_SSL  "SSL_Channel"
#define IND_NAME_WAE  "Waddah_Attar_Explosion"
#define IND_NAME_HMA  "HMA"

// WAE locked params
#define LOCKED_WAE_SENS  150
#define LOCKED_WAE_DZ    30
#define LOCKED_WAE_EP    15
#define LOCKED_WAE_TP    15

//+------------------------------------------------------------------+
//| STRUCTS                                                           |
//+------------------------------------------------------------------+
struct SweepConfig
{
   int            slot;      // 1=HTF, 2=Entry, 3=Confirm, 4=Volume, 5=Exit
   ENUM_IND_TYPE  indType;
   double         p1, p2, p3, p4; // p4: for slot 1, 240=H4, 1440=D1
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

   Print("=== NNFX H1 Sweep V2 ===");
   Print("Architecture: HTF filter + H1 flip entry + H1 confirm + H1 volume + H1 exit");
   Print("Session: ", InpUseSession ?
         IntegerToString(InpSessionStart)+"-"+IntegerToString(InpSessionEnd)+" GMT" : "OFF");
   Print("Locked defaults: H4 EMA(50) | SSL(10) flip | Stoch(14)>50 | ADX(14)>20 | SSL(5) exit");

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

      if((c+1) % 5 == 0)
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

   int outCount = MathMin(resultCount, InpMaxResults);
   WriteCSV(results, resultCount);
   PrintTop(results, outCount);

   uint totalTime = (GetTickCount() - startTick) / 1000;
   Print("=== H1 Sweep V2 Complete in ", totalTime, "s ===");
   Alert("NNFX H1 Sweep V2 done! Check MQL4/Files/NNFX_H1_SweepV2_Results.csv");
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
   ArrayResize(configs, 300);

   //--- SLOT 1: HTF Trend Filter (~18 configs)
   // p4 encodes timeframe: 240=H4, 1440=D1
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_HTF)
   {
      // H4 EMA
      int htfEmaP[] = {20,50,100,200};
      for(int i=0;i<4;i++)
         AddCfg(configs,n, 1, IND_HTF_EMA, htfEmaP[i],0,0,240,
                "HTF:H4_EMA("+IntegerToString(htfEmaP[i])+")");
      // H4 SMA
      int htfSmaP[] = {50,100,200};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 1, IND_HTF_SMA, htfSmaP[i],0,0,240,
                "HTF:H4_SMA("+IntegerToString(htfSmaP[i])+")");
      // H4 KAMA
      int htfKamaP[] = {10,20,30};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 1, IND_HTF_KAMA, htfKamaP[i],2,30,240,
                "HTF:H4_KAMA("+IntegerToString(htfKamaP[i])+")");
      // H4 Kijun
      int htfKijP[] = {20,26,33};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 1, IND_HTF_KIJUN, htfKijP[i],0,0,240,
                "HTF:H4_Kijun("+IntegerToString(htfKijP[i])+")");
      // D1 EMA
      int d1EmaP[] = {20,50};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 1, IND_HTF_EMA, d1EmaP[i],0,0,1440,
                "HTF:D1_EMA("+IntegerToString(d1EmaP[i])+")");
      // D1 KAMA
      int d1KamaP[] = {10,20};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 1, IND_HTF_KAMA, d1KamaP[i],2,30,1440,
                "HTF:D1_KAMA("+IntegerToString(d1KamaP[i])+")");
      // No filter
      AddCfg(configs,n, 1, IND_HTF_NONE, 0,0,0,0, "HTF:NoFilter");
   }

   //--- SLOT 2: H1 Entry Trigger (~22 configs) — must detect a FLIP
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_ENTRY)
   {
      // SSL flip
      int sslLen[] = {5,8,10,15,20};
      for(int i=0;i<5;i++)
         AddCfg(configs,n, 2, IND_ENTRY_SSL, sslLen[i],0,0,0,
                "ENTRY:SSL("+IntegerToString(sslLen[i])+")flip");
      // EMA cross price
      int emaP[] = {8,13,20,50};
      for(int i=0;i<4;i++)
         AddCfg(configs,n, 2, IND_ENTRY_EMA_PRICE, emaP[i],0,0,0,
                "ENTRY:EMA("+IntegerToString(emaP[i])+")xPrice");
      // MACD zero cross
      AddCfg(configs,n, 2, IND_ENTRY_MACD_ZERO, 12,26,9,0, "ENTRY:MACD(12/26/9)zero");
      // Stoch cross 50
      int stP[] = {5,8,14};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 2, IND_ENTRY_STOCH_50, stP[i],3,3,0,
                "ENTRY:Stoch("+IntegerToString(stP[i])+")x50");
      // CCI cross 0
      int cciP[] = {14,20};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 2, IND_ENTRY_CCI_ZERO, cciP[i],0,0,0,
                "ENTRY:CCI("+IntegerToString(cciP[i])+")x0");
      // RSI cross 50
      int rsiP[] = {7,14};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 2, IND_ENTRY_RSI_50, rsiP[i],0,0,0,
                "ENTRY:RSI("+IntegerToString(rsiP[i])+")x50");
      // SAR flip
      AddCfg(configs,n, 2, IND_ENTRY_SAR, 0.02,0.2,0,0, "ENTRY:SAR(0.02/0.2)");
      // HMA direction change
      int hmaP[] = {14,20};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 2, IND_ENTRY_HMA, hmaP[i],2,0,0,
                "ENTRY:HMA("+IntegerToString(hmaP[i])+")dir");
   }

   //--- SLOT 3: H1 Confirmation (~16 configs)
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_CONFIRM)
   {
      // Stoch above/below 50
      int stcP[] = {8,14,21};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 3, IND_CONF_STOCH, stcP[i],3,3,0,
                "CONF:Stoch("+IntegerToString(stcP[i])+")");
      // RSI above/below 50
      int rsiCP[] = {7,14};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 3, IND_CONF_RSI, rsiCP[i],0,0,0,
                "CONF:RSI("+IntegerToString(rsiCP[i])+")");
      // MACD above/below 0
      AddCfg(configs,n, 3, IND_CONF_MACD, 12,26,9,0, "CONF:MACD(12/26/9)");
      // CCI above/below 0
      int cciCP[] = {14,20};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 3, IND_CONF_CCI, cciCP[i],0,0,0,
                "CONF:CCI("+IntegerToString(cciCP[i])+")");
      // Momentum above/below 100
      int momCP[] = {10,14};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 3, IND_CONF_MOMENTUM, momCP[i],0,0,0,
                "CONF:Mom("+IntegerToString(momCP[i])+")");
      // ADX directional (+DI vs -DI, ADX>20)
      AddCfg(configs,n, 3, IND_CONF_ADX_DIR, 14,20,0,0, "CONF:ADXdir(14)");
      // WPR above/below -50
      int wprCP[] = {7,14};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 3, IND_CONF_WPR, wprCP[i],0,0,0,
                "CONF:WPR("+IntegerToString(wprCP[i])+")");
      // DeMarker above/below 0.5
      int demCP[] = {7,13};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 3, IND_CONF_DEMARKER, demCP[i],0,0,0,
                "CONF:DeMarker("+IntegerToString(demCP[i])+")");
      // Bulls+Bears net above/below 0
      AddCfg(configs,n, 3, IND_CONF_BULLS_BEARS, 13,0,0,0, "CONF:BullBear(13)");
   }

   //--- SLOT 4: H1 Volume/Strength (~15 configs)
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_VOLUME)
   {
      // ADX main > threshold
      int adxVP[] = {7,14,21}; double adxTh[] = {20.0,25.0};
      for(int i=0;i<3;i++) for(int j=0;j<2;j++)
         AddCfg(configs,n, 4, IND_VOL_ADX, adxVP[i],adxTh[j],0,0,
                "VOL:ADX("+IntegerToString(adxVP[i])+">"+DoubleToStr(adxTh[j],0)+")");
      // WAE: explosion > deadzone + trend matches + growing
      AddCfg(configs,n, 4, IND_VOL_WAE, 150,30,15,15, "VOL:WAE(150/30)");
      // BB width expanding
      AddCfg(configs,n, 4, IND_VOL_BB_WIDTH, 20,2.0,0,0, "VOL:BBwidth(20)");
      AddCfg(configs,n, 4, IND_VOL_BB_WIDTH, 30,2.0,0,0, "VOL:BBwidth(30)");
      // Momentum magnitude growing and > 0.05
      int momMP[] = {10,14};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 4, IND_VOL_MOM_MAG, momMP[i],0,0,0,
                "VOL:MomMag("+IntegerToString(momMP[i])+")");
      // ATR expanding: current > previous
      AddCfg(configs,n, 4, IND_VOL_ATR_EXP, 14,0,0,0, "VOL:ATR(14)exp");
      // No volume filter
      AddCfg(configs,n, 4, IND_VOL_NONE, 0,0,0,0, "VOL:NoFilter");
   }

   //--- SLOT 5: H1 Exit (~16 configs) — flip against trade direction
   if(InpSweepSlot==SWEEP_ALL || InpSweepSlot==SWEEP_EXIT)
   {
      // SSL flip against
      int sslExP[] = {3,5,8,10};
      for(int i=0;i<4;i++)
         AddCfg(configs,n, 5, IND_EXIT_SSL, sslExP[i],0,0,0,
                "EXIT:SSL("+IntegerToString(sslExP[i])+")");
      // RSI cross 50 against
      int rsiExP[] = {5,7,14};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 5, IND_EXIT_RSI, rsiExP[i],0,0,0,
                "EXIT:RSI("+IntegerToString(rsiExP[i])+")");
      // SAR flip against
      AddCfg(configs,n, 5, IND_EXIT_SAR, 0.02,0.2,0,0, "EXIT:SAR(0.02/0.2)");
      AddCfg(configs,n, 5, IND_EXIT_SAR, 0.03,0.2,0,0, "EXIT:SAR(0.03/0.2)");
      // EMA price cross against
      int emaExP[] = {5,8,13};
      for(int i=0;i<3;i++)
         AddCfg(configs,n, 5, IND_EXIT_EMA, emaExP[i],0,0,0,
                "EXIT:EMA("+IntegerToString(emaExP[i])+")");
      // CCI cross 0 against
      int cciExP[] = {14,20};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 5, IND_EXIT_CCI, cciExP[i],0,0,0,
                "EXIT:CCI("+IntegerToString(cciExP[i])+")");
      // Stoch cross 50 against
      int stExP[] = {5,8};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 5, IND_EXIT_STOCH, stExP[i],3,3,0,
                "EXIT:Stoch("+IntegerToString(stExP[i])+")");
      // HMA direction change against
      int hmaExP[] = {7,14};
      for(int i=0;i<2;i++)
         AddCfg(configs,n, 5, IND_EXIT_HMA, hmaExP[i],2,0,0,
                "EXIT:HMA("+IntegerToString(hmaExP[i])+")");
      // MACD zero cross against
      AddCfg(configs,n, 5, IND_EXIT_MACD, 12,26,9,0, "EXIT:MACD(12/26/9)");
   }

   ArrayResize(configs, n);
}

//+------------------------------------------------------------------+
//| HTF TREND FILTER (Slot 1)                                        |
//| Returns +1 (longs only) / -1 (shorts only) / 0 (no trade)       |
//| Uses HTF bar mapping via iBarShift                               |
//+------------------------------------------------------------------+
int GetHTFDir(string sym, int h1Bar, SweepConfig &cfg)
{
   // Determine which config to use for HTF
   ENUM_IND_TYPE iType;
   double p1, p2, p3;
   int htfTF;

   if(cfg.slot == 1)
   {
      iType = cfg.indType;
      p1    = cfg.p1;
      p2    = cfg.p2;
      p3    = cfg.p3;
      htfTF = (cfg.p4 >= 1440) ? PERIOD_D1 : PERIOD_H4;
   }
   else
   {
      // Locked: H4 EMA(50)
      iType = IND_HTF_EMA;
      p1    = LOCKED_HTF_EMA_PER;
      p2    = 0; p3 = 0;
      htfTF = LOCKED_HTF_TF;
   }

   if(iType == IND_HTF_NONE) return 1; // No filter — allow any direction (return 1, caller treats specially)

   // Map H1 bar time to HTF bar index
   datetime barTime = iTime(sym, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(sym, htfTF, barTime, false);
   if(htfBar < 0) return 0;

   double lineVal = 0;
   switch(iType)
   {
      case IND_HTF_EMA:
         lineVal = iMA(sym, htfTF, (int)p1, 0, MODE_EMA, PRICE_CLOSE, htfBar);
         break;
      case IND_HTF_SMA:
         lineVal = iMA(sym, htfTF, (int)p1, 0, MODE_SMA, PRICE_CLOSE, htfBar);
         break;
      case IND_HTF_KAMA:
         lineVal = iCustom(sym, htfTF, IND_NAME_KAMA, (int)p1, p2, p3, 0, htfBar);
         break;
      case IND_HTF_KIJUN:
         lineVal = iIchimoku(sym, htfTF, 9, (int)p1, 52, MODE_KIJUNSEN, htfBar);
         break;
      default:
         return 0;
   }

   double cl = iClose(sym, htfTF, htfBar);
   if(lineVal == 0) return 0;
   if(cl > lineVal) return 1;
   if(cl < lineVal) return -1;
   return 0;
}

// Special version for HTF_NONE — returns true always for direction check
bool IsHTFNone(SweepConfig &cfg)
{
   if(cfg.slot == 1 && cfg.indType == IND_HTF_NONE) return true;
   return false;
}

// Detect opposite HTF direction change (for closing all trades)
// Returns true if HTF has flipped AGAINST the open trade direction
bool HTFFlippedAgainst(string sym, int h1Bar, int tradeDir, SweepConfig &cfg)
{
   if(IsHTFNone(cfg)) return false; // No HTF filter → never close on HTF flip

   int dirNow  = GetHTFDir(sym, h1Bar,   cfg);
   int dirPrev = GetHTFDir(sym, h1Bar+1, cfg);

   if(tradeDir == 1  && dirNow == -1 && dirPrev != -1) return true;
   if(tradeDir == -1 && dirNow == 1  && dirPrev != 1)  return true;
   return false;
}

//+------------------------------------------------------------------+
//| ENTRY TRIGGER (Slot 2) — direction on H1                         |
//| Used for flip detection: current vs previous bar                 |
//+------------------------------------------------------------------+
int GetEntryDir(string sym, int shift, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType = (cfg.slot == 2) ? cfg.indType : IND_ENTRY_SSL;
   double p1 = (cfg.slot == 2) ? cfg.p1 : LOCKED_ENTRY_SSL_LEN;
   double p2 = (cfg.slot == 2) ? cfg.p2 : 0;
   double p3 = (cfg.slot == 2) ? cfg.p3 : 0;

   if(cfg.slot != 2) iType = IND_ENTRY_SSL;

   switch(iType)
   {
      case IND_ENTRY_SSL:
      {
         int len = (int)p1;
         double hlv = iCustom(sym, PERIOD_H1, IND_NAME_SSL,
                               false, 0, 2, len, 0, 3, len, 0, shift);
         if(hlv >  0.5) return 1;
         if(hlv < -0.5) return -1;
         return 0;
      }
      case IND_ENTRY_EMA_PRICE:
      {
         double ema   = iMA(sym, PERIOD_H1, (int)p1, 0, MODE_EMA, PRICE_CLOSE, shift);
         double close = iClose(sym, PERIOD_H1, shift);
         if(close > ema) return 1;
         if(close < ema) return -1;
         return 0;
      }
      case IND_ENTRY_MACD_ZERO:
      {
         double val = iMACD(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                             PRICE_CLOSE, MODE_MAIN, shift);
         if(val > 0) return 1;
         if(val < 0) return -1;
         return 0;
      }
      case IND_ENTRY_STOCH_50:
      {
         double val = iStochastic(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                                   MODE_SMA, 0, MODE_MAIN, shift);
         if(val > 50) return 1;
         if(val < 50) return -1;
         return 0;
      }
      case IND_ENTRY_CCI_ZERO:
      {
         double val = iCCI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(val > 0) return 1;
         if(val < 0) return -1;
         return 0;
      }
      case IND_ENTRY_RSI_50:
      {
         double val = iRSI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(val > 50) return 1;
         if(val < 50) return -1;
         return 0;
      }
      case IND_ENTRY_SAR:
      {
         double sar   = iSAR(sym, PERIOD_H1, p1, p2, shift);
         double close = iClose(sym, PERIOD_H1, shift);
         if(sar < close) return 1;  // SAR below price = bullish
         if(sar > close) return -1;
         return 0;
      }
      case IND_ENTRY_HMA:
      {
         double hma     = iCustom(sym, PERIOD_H1, IND_NAME_HMA, (int)p1, p2, PRICE_CLOSE, 0, shift);
         double hmaPrev = iCustom(sym, PERIOD_H1, IND_NAME_HMA, (int)p1, p2, PRICE_CLOSE, 0, shift+1);
         if(hma > hmaPrev) return 1;
         if(hma < hmaPrev) return -1;
         return 0;
      }
      default: return 0;
   }
}

// Flip = current bar is in HTF direction AND previous bar was not
bool EntryFlipOccurred(string sym, int bar, int htfDir, SweepConfig &cfg)
{
   int dirCurr = GetEntryDir(sym, bar,   cfg);
   int dirPrev = GetEntryDir(sym, bar+1, cfg);
   // Flip: current matches htfDir AND previous did not match htfDir
   return (dirCurr == htfDir && dirPrev != htfDir);
}

//+------------------------------------------------------------------+
//| CONFIRMATION (Slot 3) — direction on H1                          |
//+------------------------------------------------------------------+
int GetConfirmDir(string sym, int shift, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType = (cfg.slot == 3) ? cfg.indType : IND_CONF_STOCH;
   double p1 = (cfg.slot == 3) ? cfg.p1 : LOCKED_CONF_STOCH_K;
   double p2 = (cfg.slot == 3) ? cfg.p2 : LOCKED_CONF_STOCH_D;
   double p3 = (cfg.slot == 3) ? cfg.p3 : LOCKED_CONF_STOCH_SL;

   if(cfg.slot != 3) iType = IND_CONF_STOCH;

   switch(iType)
   {
      case IND_CONF_STOCH:
      {
         double val = iStochastic(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                                   MODE_SMA, 0, MODE_MAIN, shift);
         if(val > 50) return 1;
         if(val < 50) return -1;
         return 0;
      }
      case IND_CONF_RSI:
      {
         double val = iRSI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(val > 50) return 1;
         if(val < 50) return -1;
         return 0;
      }
      case IND_CONF_MACD:
      {
         double val = iMACD(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                             PRICE_CLOSE, MODE_MAIN, shift);
         if(val > 0) return 1;
         if(val < 0) return -1;
         return 0;
      }
      case IND_CONF_CCI:
      {
         double val = iCCI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(val > 0) return 1;
         if(val < 0) return -1;
         return 0;
      }
      case IND_CONF_MOMENTUM:
      {
         double val = iMomentum(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(val > 100) return 1;
         if(val < 100) return -1;
         return 0;
      }
      case IND_CONF_ADX_DIR:
      {
         double plusDI  = iADX(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, MODE_PLUSDI,  shift);
         double minusDI = iADX(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, MODE_MINUSDI, shift);
         double adxMain = iADX(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, MODE_MAIN,    shift);
         if(adxMain < p2) return 0;
         if(plusDI > minusDI) return 1;
         if(minusDI > plusDI) return -1;
         return 0;
      }
      case IND_CONF_WPR:
      {
         double val = iWPR(sym, PERIOD_H1, (int)p1, shift);
         if(val > -50) return 1;
         if(val < -50) return -1;
         return 0;
      }
      case IND_CONF_DEMARKER:
      {
         double val = iDeMarker(sym, PERIOD_H1, (int)p1, shift);
         if(val > 0.5) return 1;
         if(val < 0.5) return -1;
         return 0;
      }
      case IND_CONF_BULLS_BEARS:
      {
         double bulls = iBullsPower(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         double bears = iBearsPower(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         double net   = bulls + bears;
         if(net > 0) return 1;
         if(net < 0) return -1;
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
   ENUM_IND_TYPE iType = (cfg.slot == 4) ? cfg.indType : IND_VOL_ADX;
   double p1 = (cfg.slot == 4) ? cfg.p1 : LOCKED_VOL_ADX_PER;
   double p2 = (cfg.slot == 4) ? cfg.p2 : LOCKED_VOL_ADX_TH;

   if(cfg.slot != 4) iType = IND_VOL_ADX;

   switch(iType)
   {
      case IND_VOL_ADX:
      {
         double adx = iADX(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, MODE_MAIN, shift);
         return (adx > p2);
      }
      case IND_VOL_WAE:
      {
         int sens = (int)cfg.p1, dz = (int)cfg.p2, ep = (int)cfg.p3, tp = (int)cfg.p4;
         double green     = iCustom(sym, PERIOD_H1, IND_NAME_WAE, sens,dz,ep,tp,
                                     true,500,true,true,true,true, 0, shift);
         double red       = iCustom(sym, PERIOD_H1, IND_NAME_WAE, sens,dz,ep,tp,
                                     true,500,true,true,true,true, 1, shift);
         double explosion = iCustom(sym, PERIOD_H1, IND_NAME_WAE, sens,dz,ep,tp,
                                     true,500,true,true,true,true, 2, shift);
         double deadZone  = iCustom(sym, PERIOD_H1, IND_NAME_WAE, sens,dz,ep,tp,
                                     true,500,true,true,true,true, 3, shift);
         double greenPrev = iCustom(sym, PERIOD_H1, IND_NAME_WAE, sens,dz,ep,tp,
                                     true,500,true,true,true,true, 0, shift+1);
         double redPrev   = iCustom(sym, PERIOD_H1, IND_NAME_WAE, sens,dz,ep,tp,
                                     true,500,true,true,true,true, 1, shift+1);
         if(explosion <= deadZone) return false;
         bool trendMatch=false, trendGrow=false;
         if(direction == 1  && green>0) { trendMatch=true; trendGrow=(green>greenPrev); }
         if(direction == -1 && red>0)   { trendMatch=true; trendGrow=(red>redPrev); }
         return (trendMatch && trendGrow);
      }
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
      case IND_VOL_MOM_MAG:
      {
         double mom     = iMomentum(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         double momPrev = iMomentum(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift+1);
         double mag     = MathAbs(mom - 100.0);
         double magPrev = MathAbs(momPrev - 100.0);
         return (mag > magPrev && mag > 0.05);
      }
      case IND_VOL_ATR_EXP:
      {
         double atr     = iATR(sym, PERIOD_H1, (int)p1, shift);
         double atrPrev = iATR(sym, PERIOD_H1, (int)p1, shift+1);
         return (atr > atrPrev);
      }
      case IND_VOL_NONE:
         return true;
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
//| EXIT (Slot 5) — flip against trade direction closes runner       |
//+------------------------------------------------------------------+
bool CheckExit(string sym, int shift, int tradeDir, SweepConfig &cfg)
{
   ENUM_IND_TYPE iType = (cfg.slot == 5) ? cfg.indType : IND_EXIT_SSL;
   double p1 = (cfg.slot == 5) ? cfg.p1 : LOCKED_EXIT_SSL_LEN;
   double p2 = (cfg.slot == 5) ? cfg.p2 : 0;
   double p3 = (cfg.slot == 5) ? cfg.p3 : 0;

   if(cfg.slot != 5) iType = IND_EXIT_SSL;

   switch(iType)
   {
      case IND_EXIT_SSL:
      {
         int len = (int)p1;
         double hlv = iCustom(sym, PERIOD_H1, IND_NAME_SSL,
                               false, 0, 2, len, 0, 3, len, 0, shift);
         int dir = 0;
         if(hlv >  0.5) dir =  1;
         if(hlv < -0.5) dir = -1;
         if(tradeDir == 1  && dir == -1) return true;
         if(tradeDir == -1 && dir ==  1) return true;
         return false;
      }
      case IND_EXIT_RSI:
      {
         double rsi = iRSI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(tradeDir == 1  && rsi < 50) return true;
         if(tradeDir == -1 && rsi > 50) return true;
         return false;
      }
      case IND_EXIT_SAR:
      {
         double sar   = iSAR(sym, PERIOD_H1, p1, p2, shift);
         double close = iClose(sym, PERIOD_H1, shift);
         if(tradeDir == 1  && sar > close) return true;
         if(tradeDir == -1 && sar < close) return true;
         return false;
      }
      case IND_EXIT_EMA:
      {
         double ema   = iMA(sym, PERIOD_H1, (int)p1, 0, MODE_EMA, PRICE_CLOSE, shift);
         double close = iClose(sym, PERIOD_H1, shift);
         if(tradeDir == 1  && close < ema) return true;
         if(tradeDir == -1 && close > ema) return true;
         return false;
      }
      case IND_EXIT_CCI:
      {
         double cci = iCCI(sym, PERIOD_H1, (int)p1, PRICE_CLOSE, shift);
         if(tradeDir == 1  && cci < 0) return true;
         if(tradeDir == -1 && cci > 0) return true;
         return false;
      }
      case IND_EXIT_STOCH:
      {
         double st = iStochastic(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                                  MODE_SMA, 0, MODE_MAIN, shift);
         if(tradeDir == 1  && st < 50) return true;
         if(tradeDir == -1 && st > 50) return true;
         return false;
      }
      case IND_EXIT_HMA:
      {
         double hma     = iCustom(sym, PERIOD_H1, IND_NAME_HMA, (int)p1, p2, PRICE_CLOSE, 0, shift);
         double hmaPrev = iCustom(sym, PERIOD_H1, IND_NAME_HMA, (int)p1, p2, PRICE_CLOSE, 0, shift+1);
         if(tradeDir == 1  && hma < hmaPrev) return true;
         if(tradeDir == -1 && hma > hmaPrev) return true;
         return false;
      }
      case IND_EXIT_MACD:
      {
         double macd = iMACD(sym, PERIOD_H1, (int)p1, (int)p2, (int)p3,
                              PRICE_CLOSE, MODE_MAIN, shift);
         if(tradeDir == 1  && macd < 0) return true;
         if(tradeDir == -1 && macd > 0) return true;
         return false;
      }
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                  |
//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar, SweepConfig &cfg)
{
   // 1. HTF Trend Filter — determines allowed direction
   int htfDir;
   bool noFilter = IsHTFNone(cfg);
   if(noFilter)
   {
      // Determine signal direction from the entry trigger itself
      // We'll check both directions; actual direction comes from entry flip
      htfDir = 0; // Will be assigned by entry trigger below
   }
   else
   {
      htfDir = GetHTFDir(sym, bar, cfg);
      if(htfDir == 0) return 0; // No clear HTF trend
   }

   // 2. Entry Trigger — must be a FLIP in the HTF direction
   if(noFilter)
   {
      // No filter: detect flip in either direction
      int dirCurr = GetEntryDir(sym, bar,   cfg);
      int dirPrev = GetEntryDir(sym, bar+1, cfg);
      if(dirCurr == 0 || dirCurr == dirPrev) return 0; // No flip
      htfDir = dirCurr; // Trade in the flip direction
   }
   else
   {
      if(!EntryFlipOccurred(sym, bar, htfDir, cfg)) return 0;
   }

   // 3. Confirmation — current or previous bar must agree
   int confCurr = GetConfirmDir(sym, bar,   cfg);
   int confPrev = GetConfirmDir(sym, bar+1, cfg);
   if(confCurr != htfDir && confPrev != htfDir) return 0;

   // 4. Volume
   if(!CheckVolume(sym, bar, htfDir, cfg)) return 0;

   return htfDir;
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
   trade.movedBE=false; trade.pnl=0;
   trade.dir=0; trade.entry=0; trade.sl=0; trade.tp1=0;
   trade.lots1=0; trade.lots2=0;

   for(int bar=startBar-1; bar>endBar; bar--)
   {
      // Manage open trades first (24/7 — no session filter on management)
      if(trade.o1Open || trade.o2Open)
         Manage(sym, bar, spread, trade, balance, peak, stats, tickVal, tickSz, cfg);
      if(trade.o1Open || trade.o2Open) continue;

      // Session filter — only new entries during session hours
      datetime barTime = iTime(sym, PERIOD_H1, bar);
      if(!InSession(barTime)) continue;

      // Evaluate entry
      int signal = EvalEntry(sym, bar, cfg);
      if(signal == 0) continue;
      stats.sig++;

      double atr = iATR(sym, PERIOD_H1, LOCKED_ATR, bar);
      if(atr <= 0) continue;

      // Enter at open of NEXT bar
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

   // Close any remaining trade at end of period
   if(trade.o1Open || trade.o2Open)
   {
      double lc = iClose(sym, PERIOD_H1, endBar);
      double ep = (trade.dir==1) ? lc : lc + spread;
      FClose(trade, ep, balance, peak, stats, tickVal, tickSz);
   }
   stats.bal = balance;
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT — called on each H1 bar while trade is open     |
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

   // Opposite HTF trend change — close all immediately
   if(HTFFlippedAgainst(sym, bar, t.dir, cfg))
   {
      double ep = (t.dir==1) ? cl : aCl;
      FClose(t, ep, bal, peak, s, tv, ts);
      return;
   }

   // Order 1: fixed TP1 and SL
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
         // After TP1 hit, move runner SL to breakeven
         if(tp && t.o2Open)
         {
            t.sl      = t.entry;
            t.movedBE = true;
         }
      }
   }

   // Order 2: runner — no TP, trail with exit indicator
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

   // Trade fully closed — record win/loss
   if(!t.o1Open && !t.o2Open)
   {
      if(t.pnl >= 0) s.wins++; else s.losses++;
   }

   // Update peak and drawdown
   if(bal > peak) peak = bal;
   double dd = peak - bal;
   if(dd > s.maxDD)
   {
      s.maxDD    = dd;
      s.maxDDPct = (dd / peak) * 100.0;
   }
}

//+------------------------------------------------------------------+
//| FORCE CLOSE all open orders at given exit price                  |
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
   Print("===== TOP ", count, " H1 V2 CONFIGS (by Aggregate PF) =====");
   for(int i=0; i<count; i++)
   {
      Print(StringFormat("#%d %s | Net=$%.2f PF=%.2f WR=%.1f%% DD=%.1f%% Sig=%d",
            i+1, res[i].label, res[i].aggNet, res[i].aggPF,
            res[i].avgWR, res[i].worstDD, res[i].totalSig));
   }
}

void WriteCSV(SweepResult &res[], int count)
{
   string filename = "NNFX_H1_SweepV2_Results.csv";
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
