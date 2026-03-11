//+------------------------------------------------------------------+
//|                                         NNFX_H1_Focused_BT.mq4  |
//|  Focused backtest: V3 winning combo on selected pairs            |
//|  H4 McGinley(14) + Keltner(20) entry + RangeFilter(30) confirm  |
//|  No volume filter + HalfTrend(3) exit                           |
//|  Compounding position sizing (risk % of current balance)        |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property strict
#property show_inputs

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input double InpRiskPct      = 3.0;    // Risk % per trade
input double InpStartBalance = 10000;  // Starting Balance ($)
input double InpSLMult       = 1.5;    // Stop Loss (x ATR)
input double InpTP1Mult      = 1.0;    // Take Profit (x ATR)
input int    InpATRPeriod    = 14;     // ATR Period
input int    InpSessionStart = 7;      // Session Start (GMT)
input int    InpSessionEnd   = 20;     // Session End (GMT)
input bool   InpUseSession   = true;   // Enable Session Filter
input string InpPairs        = "USDJPY,AUDUSD,USDCAD,EURUSD,GBPUSD"; // Pairs to test

// Indicator settings
input int    InpMcGinleyPer  = 14;     // HTF McGinley Period
input double InpMcGinleyK    = 0.6;    // HTF McGinley Constant
input int    InpKeltnerMA    = 20;     // Entry Keltner MA Period
input int    InpKeltnerATR   = 20;     // Entry Keltner ATR Period
input double InpKeltnerMult  = 1.5;    // Entry Keltner Multiplier
input int    InpRngFiltPer   = 30;     // Confirm RangeFilter Period
input double InpRngFiltMult  = 2.5;    // Confirm RangeFilter Multiplier
input int    InpHalfTrendAmp = 3;      // Exit HalfTrend Amplitude
input int    InpHalfTrendDev = 2;      // Exit HalfTrend Channel Dev
input int    InpHalfTrendATR = 100;    // Exit HalfTrend ATR Period

#define IND_MCGINLEY  "McGinley_Dynamic"
#define IND_KELTNER   "KeltnerChannel"
#define IND_RANGEFILT "RangeFilter"
#define IND_HALFTREND "HalfTrend"

//+------------------------------------------------------------------+
//| STRUCTS                                                           |
//+------------------------------------------------------------------+
struct VTrade
{
   int    dir;
   double entry, sl, tp1, lots1, lots2;
   bool   o1Open, o2Open, movedBE;
   double pnl;
   datetime openTime;
};

struct TradeRecord
{
   datetime openTime, closeTime;
   string   pair;
   int      dir;
   double   entry, exitPrice, pnl, balAfter;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string    g_pairs[];
int       g_pairCount;
TradeRecord g_trades[];
int       g_tradeCount;

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

void ParsePairs()
{
   string temp = InpPairs;
   g_pairCount = 0;
   ArrayResize(g_pairs, 10);

   int pos;
   while((pos = StringFind(temp, ",")) >= 0)
   {
      string p = StringTrimLeft(StringTrimRight(StringSubstr(temp, 0, pos)));
      if(StringLen(p) > 0)
      {
         g_pairs[g_pairCount] = p;
         g_pairCount++;
      }
      temp = StringSubstr(temp, pos + 1);
   }
   temp = StringTrimLeft(StringTrimRight(temp));
   if(StringLen(temp) > 0)
   {
      g_pairs[g_pairCount] = temp;
      g_pairCount++;
   }
   ArrayResize(g_pairs, g_pairCount);
}

//+------------------------------------------------------------------+
//| INDICATOR SIGNALS                                                 |
//+------------------------------------------------------------------+
int GetMcGinleyDir(string sym, int tf, int shift)
{
   double sig = iCustom(sym, tf, IND_MCGINLEY, InpMcGinleyPer, InpMcGinleyK, PRICE_CLOSE, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetKeltnerDir(string sym, int shift)
{
   double sig = iCustom(sym, PERIOD_H1, IND_KELTNER, InpKeltnerMA, InpKeltnerATR, InpKeltnerMult, MODE_EMA, PRICE_CLOSE, 3, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetRangeFilterDir(string sym, int shift)
{
   double sig = iCustom(sym, PERIOD_H1, IND_RANGEFILT, InpRngFiltPer, InpRngFiltMult, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

int GetHalfTrendDir(string sym, int shift)
{
   double sig = iCustom(sym, PERIOD_H1, IND_HALFTREND, InpHalfTrendAmp, InpHalfTrendDev, InpHalfTrendATR, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// HTF filter: H4 McGinley direction
int GetHTFDir(string sym, int h1Bar)
{
   datetime barTime = iTime(sym, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(sym, PERIOD_H4, barTime, false);
   if(htfBar < 1) return 0;
   return GetMcGinleyDir(sym, PERIOD_H4, htfBar);
}

bool HTFFlippedAgainst(string sym, int h1Bar, int tradeDir)
{
   int dirNow  = GetHTFDir(sym, h1Bar);
   int dirPrev = GetHTFDir(sym, h1Bar + 1);
   if(tradeDir == 1  && dirNow == -1 && dirPrev != -1) return true;
   if(tradeDir == -1 && dirNow == 1  && dirPrev != 1)  return true;
   return false;
}

// Entry: Keltner midline flip in HTF direction
bool EntryFlipOccurred(string sym, int bar, int htfDir)
{
   int dirCurr = GetKeltnerDir(sym, bar);
   int dirPrev = GetKeltnerDir(sym, bar + 1);
   return (dirCurr == htfDir && dirPrev != htfDir);
}

// Confirm: RangeFilter direction agrees
bool ConfirmAgrees(string sym, int bar, int htfDir)
{
   int confCurr = GetRangeFilterDir(sym, bar);
   int confPrev = GetRangeFilterDir(sym, bar + 1);
   return (confCurr == htfDir || confPrev == htfDir);
}

// Exit: HalfTrend flips against trade
bool ExitSignal(string sym, int bar, int tradeDir)
{
   int dir = GetHalfTrendDir(sym, bar);
   if(tradeDir == 1  && dir == -1) return true;
   if(tradeDir == -1 && dir ==  1) return true;
   return false;
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                  |
//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar)
{
   int htfDir = GetHTFDir(sym, bar);
   if(htfDir == 0) return 0;
   if(!EntryFlipOccurred(sym, bar, htfDir)) return 0;
   if(!ConfirmAgrees(sym, bar, htfDir)) return 0;
   // No volume filter
   return htfDir;
}

//+------------------------------------------------------------------+
//| RECORD TRADE                                                      |
//+------------------------------------------------------------------+
void RecordTrade(datetime openT, datetime closeT, string pair, int dir,
                 double entryP, double exitP, double pnl, double balAfter)
{
   int idx = g_tradeCount;
   g_tradeCount++;
   if(g_tradeCount > ArraySize(g_trades))
      ArrayResize(g_trades, g_tradeCount + 100);

   g_trades[idx].openTime   = openT;
   g_trades[idx].closeTime  = closeT;
   g_trades[idx].pair       = pair;
   g_trades[idx].dir        = dir;
   g_trades[idx].entry      = entryP;
   g_trades[idx].exitPrice  = exitP;
   g_trades[idx].pnl        = pnl;
   g_trades[idx].balAfter   = balAfter;
}

//+------------------------------------------------------------------+
//| OnStart                                                           |
//+------------------------------------------------------------------+
void OnStart()
{
   ParsePairs();

   datetime startDate = D'2020.01.01';
   datetime endDate   = D'2025.01.01';

   Print("=== NNFX H1 Focused Backtest ===");
   Print("Strategy: H4 McGinley(", InpMcGinleyPer, ") + Keltner(", InpKeltnerMA,
         ") entry + RangeFilter(", InpRngFiltPer, ") confirm + HalfTrend(", InpHalfTrendAmp, ") exit");
   Print("Risk: ", DoubleToStr(InpRiskPct, 1), "% | SL: ", DoubleToStr(InpSLMult, 1),
         "x ATR | TP1: ", DoubleToStr(InpTP1Mult, 1), "x ATR");
   Print("Balance: $", DoubleToStr(InpStartBalance, 0), " | Pairs: ", InpPairs);
   Print("Period: 2020-2025 | Session: ",
         InpUseSession ? IntegerToString(InpSessionStart)+"-"+IntegerToString(InpSessionEnd)+" GMT" : "OFF");
   Print("---");

   double grandBalance = InpStartBalance;
   double grandPeak = InpStartBalance;
   double grandMaxDD = 0;
   double grandMaxDDPct = 0;
   int grandWins = 0, grandLosses = 0;
   double grandGP = 0, grandGL = 0;

   g_tradeCount = 0;
   ArrayResize(g_trades, 500);

   // Run each pair with shared compounding balance
   // We need to interleave trades across pairs chronologically
   // Simpler approach: run sequentially per pair with independent balances,
   // then also run combined

   // === PER-PAIR RESULTS ===
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
      double spread   = GetTypicalSpread(sym) * pointVal;

      if(tickVal <= 0 || tickSz <= 0) { Print(sym, ": invalid market info, skipping"); continue; }

      double balance = InpStartBalance;
      double peak = InpStartBalance;
      double maxDD = 0, maxDDPct = 0;
      int wins = 0, losses = 0, totalSig = 0;
      double gp = 0, gl = 0;

      VTrade trade;
      trade.o1Open = false; trade.o2Open = false;
      trade.movedBE = false; trade.pnl = 0;
      trade.dir = 0; trade.entry = 0; trade.sl = 0; trade.tp1 = 0;
      trade.lots1 = 0; trade.lots2 = 0; trade.openTime = 0;

      for(int bar = startBar - 1; bar > endBar; bar--)
      {
         // Manage open trades
         if(trade.o1Open || trade.o2Open)
         {
            double hi  = iHigh(sym, PERIOD_H1, bar);
            double lo  = iLow(sym, PERIOD_H1, bar);
            double cl  = iClose(sym, PERIOD_H1, bar);
            double aHi = hi + spread;
            double aLo = lo + spread;
            double aCl = cl + spread;
            datetime barTime = iTime(sym, PERIOD_H1, bar);

            // HTF flip against
            if(HTFFlippedAgainst(sym, bar, trade.dir))
            {
               double ep = (trade.dir == 1) ? cl : aCl;
               // Close all
               if(trade.o1Open)
               {
                  double pnl1 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots1
                                                : (trade.entry-ep)/tickSz*tickVal*trade.lots1;
                  balance += pnl1; trade.pnl += pnl1;
                  if(pnl1>0) gp+=pnl1; else gl+=pnl1;
                  trade.o1Open = false;
               }
               if(trade.o2Open)
               {
                  double pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                                : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
                  balance += pnl2; trade.pnl += pnl2;
                  if(pnl2>0) gp+=pnl2; else gl+=pnl2;
                  trade.o2Open = false;
               }
               if(trade.pnl >= 0) wins++; else losses++;
               RecordTrade(trade.openTime, barTime, sym, trade.dir, trade.entry, ep, trade.pnl, balance);
               if(balance > peak) peak = balance;
               double dd = peak - balance;
               if(dd > maxDD) { maxDD = dd; maxDDPct = (dd/peak)*100.0; }
               continue;
            }

            // Order 1: TP1 / SL
            if(trade.o1Open)
            {
               bool tp=false, sl=false;
               double pnl1=0;
               if(trade.dir == 1)
               {
                  if(hi >= trade.tp1)  { tp=true; pnl1=(trade.tp1-trade.entry)/tickSz*tickVal*trade.lots1; }
                  else if(lo<=trade.sl){ sl=true; pnl1=(trade.sl-trade.entry)/tickSz*tickVal*trade.lots1; }
               }
               else
               {
                  if(aLo<=trade.tp1)   { tp=true; pnl1=(trade.entry-trade.tp1)/tickSz*tickVal*trade.lots1; }
                  else if(aHi>=trade.sl){ sl=true; pnl1=(trade.entry-trade.sl)/tickSz*tickVal*trade.lots1; }
               }
               if(tp || sl)
               {
                  balance += pnl1; trade.pnl += pnl1;
                  if(pnl1>0) gp+=pnl1; else gl+=pnl1;
                  trade.o1Open = false;
                  if(tp && trade.o2Open) { trade.sl = trade.entry; trade.movedBE = true; }
               }
            }

            // Order 2: Runner — SL or exit signal
            if(trade.o2Open)
            {
               bool slHit = false;
               if(trade.dir==1  && lo<=trade.sl)  slHit = true;
               if(trade.dir==-1 && aHi>=trade.sl) slHit = true;

               bool exitFlip = ExitSignal(sym, bar, trade.dir);

               double pnl2 = 0;
               if(slHit)
               {
                  pnl2 = (trade.dir==1) ? (trade.sl-trade.entry)/tickSz*tickVal*trade.lots2
                                        : (trade.entry-trade.sl)/tickSz*tickVal*trade.lots2;
                  balance += pnl2; trade.pnl += pnl2;
                  if(pnl2>0) gp+=pnl2; else gl+=pnl2;
                  trade.o2Open = false;
               }
               else if(exitFlip)
               {
                  double ep = (trade.dir==1) ? cl : aCl;
                  pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                        : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
                  balance += pnl2; trade.pnl += pnl2;
                  if(pnl2>0) gp+=pnl2; else gl+=pnl2;
                  trade.o2Open = false;
               }
            }

            if(!trade.o1Open && !trade.o2Open)
            {
               if(trade.pnl >= 0) wins++; else losses++;
               RecordTrade(trade.openTime, barTime, sym, trade.dir, trade.entry, cl, trade.pnl, balance);
            }

            if(balance > peak) peak = balance;
            double dd2 = peak - balance;
            if(dd2 > maxDD) { maxDD = dd2; maxDDPct = (dd2/peak)*100.0; }

            if(trade.o1Open || trade.o2Open) continue;
         }

         // Session filter
         datetime barTime2 = iTime(sym, PERIOD_H1, bar);
         if(!InSession(barTime2)) continue;

         // Evaluate entry
         int signal = EvalEntry(sym, bar);
         if(signal == 0) continue;
         totalSig++;

         double atr = iATR(sym, PERIOD_H1, InpATRPeriod, bar);
         if(atr <= 0) continue;

         double openNext = iOpen(sym, PERIOD_H1, bar - 1);
         if(openNext <= 0) continue;

         double entry   = (signal == 1) ? openNext + spread : openNext;
         double slDist  = InpSLMult * atr;
         double tp1Dist = InpTP1Mult * atr;

         // COMPOUNDING: risk % of CURRENT balance
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
         trade.movedBE = false;
         trade.pnl    = 0;
         trade.openTime = barTime2;

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

      // Close remaining
      if(trade.o1Open || trade.o2Open)
      {
         double lc = iClose(sym, PERIOD_H1, endBar);
         double ep = (trade.dir == 1) ? lc : lc + spread;
         if(trade.o1Open)
         {
            double pnl1 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots1
                                          : (trade.entry-ep)/tickSz*tickVal*trade.lots1;
            balance += pnl1; trade.pnl += pnl1;
            if(pnl1>0) gp+=pnl1; else gl+=pnl1;
            trade.o1Open = false;
         }
         if(trade.o2Open)
         {
            double pnl2 = (trade.dir==1) ? (ep-trade.entry)/tickSz*tickVal*trade.lots2
                                          : (trade.entry-ep)/tickSz*tickVal*trade.lots2;
            balance += pnl2; trade.pnl += pnl2;
            if(pnl2>0) gp+=pnl2; else gl+=pnl2;
            trade.o2Open = false;
         }
         if(trade.pnl >= 0) wins++; else losses++;
      }

      double pf = (gl != 0) ? MathAbs(gp / gl) : 0;
      double wr = (totalSig > 0) ? ((double)wins / totalSig * 100.0) : 0;
      double ret = ((balance - InpStartBalance) / InpStartBalance) * 100.0;

      Print("--- ", sym, " ---");
      Print("  Trades: ", totalSig, " | Wins: ", wins, " | Losses: ", losses, " | WR: ", DoubleToStr(wr, 1), "%");
      Print("  Gross Profit: $", DoubleToStr(gp, 2), " | Gross Loss: $", DoubleToStr(gl, 2));
      Print("  PF: ", DoubleToStr(pf, 2), " | Net: $", DoubleToStr(balance - InpStartBalance, 2));
      Print("  Start: $", DoubleToStr(InpStartBalance, 0), " → End: $", DoubleToStr(balance, 2),
            " (", DoubleToStr(ret, 1), "%)");
      Print("  Max Drawdown: $", DoubleToStr(maxDD, 2), " (", DoubleToStr(maxDDPct, 1), "%)");

      grandGP += gp; grandGL += gl;
      grandWins += wins; grandLosses += losses;
   }

   // === GRAND SUMMARY ===
   double grandPF = (grandGL != 0) ? MathAbs(grandGP / grandGL) : 0;
   double grandNet = grandGP + grandGL;
   int grandTotal = grandWins + grandLosses;
   double grandWR = (grandTotal > 0) ? ((double)grandWins / grandTotal * 100.0) : 0;

   Print("========================================");
   Print("GRAND TOTALS (", g_pairCount, " pairs, independent $", DoubleToStr(InpStartBalance, 0), " each):");
   Print("  Total Trades: ", grandTotal, " | Wins: ", grandWins, " | WR: ", DoubleToStr(grandWR, 1), "%");
   Print("  Aggregate PF: ", DoubleToStr(grandPF, 2));
   Print("  Total Net: $", DoubleToStr(grandNet, 2));
   Print("  GP: $", DoubleToStr(grandGP, 2), " | GL: $", DoubleToStr(grandGL, 2));
   Print("========================================");

   // Write trade log CSV
   WriteTrades();

   Print("=== Focused Backtest Complete ===");
   Alert("NNFX H1 Focused BT done! Check MQL4/Files/NNFX_H1_FocusedBT_Trades.csv");
}

//+------------------------------------------------------------------+
//| WRITE TRADE LOG                                                   |
//+------------------------------------------------------------------+
void WriteTrades()
{
   string filename = "NNFX_H1_FocusedBT_Trades.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ',');
   if(handle < 0) { Print("ERROR: Cannot open ", filename); return; }

   FileWrite(handle, "Open_Time", "Close_Time", "Pair", "Direction", "Entry", "Exit", "PnL", "Balance_After");

   for(int i = 0; i < g_tradeCount; i++)
   {
      FileWrite(handle,
                TimeToStr(g_trades[i].openTime, TIME_DATE|TIME_MINUTES),
                TimeToStr(g_trades[i].closeTime, TIME_DATE|TIME_MINUTES),
                g_trades[i].pair,
                (g_trades[i].dir == 1) ? "LONG" : "SHORT",
                DoubleToStr(g_trades[i].entry, 5),
                DoubleToStr(g_trades[i].exitPrice, 5),
                DoubleToStr(g_trades[i].pnl, 2),
                DoubleToStr(g_trades[i].balAfter, 2));
   }

   FileClose(handle);
   Print("Trade log saved: MQL4/Files/", filename);
}
//+------------------------------------------------------------------+
