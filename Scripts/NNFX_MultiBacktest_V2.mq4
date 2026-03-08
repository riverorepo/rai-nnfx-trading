//+------------------------------------------------------------------+
//|                                        NNFX_MultiBacktest_V2.mq4 |
//|         V2 Strategy: Kijun baseline + MomMag volume               |
//|         Separate from V1 — does NOT modify original files         |
//|         C1: SSL(25), C2: Stoch(14), Exit: SSL(5), ATR: 7         |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "2.00"
#property strict
#property show_inputs

//--- V2 Settings (optimized from MegaSweep)
input int      InpKijunPeriod     = 20;      // Baseline: Kijun Period
input int      InpSSL_C1_Len      = 25;      // C1: SSL Length
input int      InpStochK          = 14;      // C2: Stoch %K
input int      InpStochD          = 3;       // C2: Stoch %D
input int      InpStochSlowing    = 3;       // C2: Stoch Slowing
input int      InpMomPeriod       = 14;      // Volume: Momentum Period
input int      InpSSL_Exit_Len    = 5;       // Exit: SSL Length
input int      InpATRPeriod       = 7;       // ATR Period
input double   InpSLMultiplier    = 1.5;     // SL Multiplier (ATR x)
input double   InpTP1Multiplier   = 1.0;     // TP1 Multiplier (ATR x)
input double   InpMaxATRDist      = 1.0;     // Max Baseline Distance (ATR x)
input double   InpRiskPercent     = 2.0;     // Risk %
input double   InpStartBalance    = 10000.0; // Starting Balance
input int      InpSpreadMode      = 1;       // Spread: 0=Current, 1=Typical, 2=Custom
input int      InpCustomSpread    = 15;      // Custom Spread (points)

#define IND_SSL  "SSL_Channel"

struct VTrade
{
   int    dir;
   double entry, sl, tp1, lots1, lots2;
   bool   o1Open, o2Open, movedBE;
   double pnl;
   datetime entryTime;
};

struct PairResult
{
   string symbol;
   int    signals, orders, wins, losses;
   int    longSig, longWins, shortSig, shortWins;
   double grossProfit, grossLoss;
   double maxDD, maxDDPct, finalBal;
};

int GetTypicalSpread(string s)
{
   if(s=="EURUSD") return 14; if(s=="GBPUSD") return 18; if(s=="USDJPY") return 14;
   if(s=="USDCHF") return 17; if(s=="AUDUSD") return 14; if(s=="NZDUSD") return 20;
   if(s=="USDCAD") return 20; return 20;
}

//+------------------------------------------------------------------+
void OnStart()
{
   string pairs[] = {"EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","NZDUSD","USDCAD"};
   int numPairs = ArraySize(pairs);
   PairResult results[];
   ArrayResize(results, numPairs);

   Print("=== NNFX V2 Multi-Pair Backtest ===");
   Print("Baseline: Ichimoku Kijun(", InpKijunPeriod, ") | C1: SSL(", InpSSL_C1_Len,
         ") | C2: Stoch(", InpStochK, ") | Volume: MomMag(", InpMomPeriod,
         ") | Exit: SSL(", InpSSL_Exit_Len, ") | ATR: ", InpATRPeriod);

   for(int p=0; p<numPairs; p++)
   {
      string sym = pairs[p];
      Print("--- Processing ", sym, " ---");
      int totalBars = iBars(sym, PERIOD_D1);
      if(totalBars < 100) { Print("WARNING: ", sym, " skipped (insufficient data)"); results[p].symbol=sym; continue; }
      RunBacktest(sym, results[p]);
      PrintResult(results[p]);
   }

   WriteCSV(results, numPairs);
   WriteSummary(results, numPairs);

   Print("=== NNFX V2 Backtest Complete ===");
   Alert("NNFX V2 Backtest done! Check MQL4/Files/");
}

//+------------------------------------------------------------------+
void RunBacktest(string sym, PairResult &r)
{
   r.symbol=sym; r.signals=0; r.orders=0; r.wins=0; r.losses=0;
   r.longSig=0; r.longWins=0; r.shortSig=0; r.shortWins=0;
   r.grossProfit=0; r.grossLoss=0; r.maxDD=0; r.maxDDPct=0;
   r.finalBal=InpStartBalance;

   double balance=InpStartBalance, peak=InpStartBalance;
   double tickVal=MarketInfo(sym,MODE_TICKVALUE);
   double tickSz=MarketInfo(sym,MODE_TICKSIZE);
   double pointVal=MarketInfo(sym,MODE_POINT);

   int spreadPts;
   if(InpSpreadMode==1) spreadPts=GetTypicalSpread(sym);
   else if(InpSpreadMode==2) spreadPts=InpCustomSpread;
   else spreadPts=(int)MarketInfo(sym,MODE_SPREAD);
   double spread=spreadPts*pointVal;

   if(tickVal<=0||tickSz<=0||pointVal<=0) { Print("ERROR: market info for ",sym); return; }

   int totalBars=iBars(sym,PERIOD_D1);
   datetime startDate=D'2015.01.01', endDate=D'2025.01.01';
   int startBar=iBarShift(sym,PERIOD_D1,startDate,false);
   int endBar=iBarShift(sym,PERIOD_D1,endDate,false);
   if(endBar<0) endBar=0;
   if(startBar<0) startBar=totalBars-1;

   VTrade trade;
   trade.o1Open=false; trade.o2Open=false;

   for(int bar=startBar-1; bar>endBar; bar--)
   {
      if(trade.o1Open || trade.o2Open)
         ManageTrade(sym, bar, spread, trade, balance, peak, r, tickVal, tickSz);
      if(trade.o1Open || trade.o2Open) continue;

      int signal = EvalEntry(sym, bar);
      if(signal==0) continue;

      r.signals++; r.orders+=2;
      if(signal==1) r.longSig++; else r.shortSig++;

      double atr=iATR(sym,PERIOD_D1,InpATRPeriod,bar);
      if(atr<=0) continue;

      double openNext=iOpen(sym,PERIOD_D1,bar-1);
      double entryPrice=(signal==1)?openNext+spread:openNext;
      double slDist=InpSLMultiplier*atr, tp1Dist=InpTP1Multiplier*atr;

      double riskAmt=balance*(InpRiskPercent/100.0);
      double slTicks=slDist/tickSz;
      double rpl=slTicks*tickVal;
      if(rpl<=0) continue;
      double halfLot=MathFloor((riskAmt/rpl)/2.0*100)/100.0;
      if(halfLot<0.01) halfLot=0.01;

      trade.dir=signal; trade.entry=entryPrice;
      trade.lots1=halfLot; trade.lots2=halfLot;
      trade.o1Open=true; trade.o2Open=true;
      trade.movedBE=false; trade.pnl=0;
      trade.entryTime=iTime(sym,PERIOD_D1,bar-1);

      if(signal==1) { trade.sl=entryPrice-slDist; trade.tp1=entryPrice+tp1Dist; }
      else          { trade.sl=entryPrice+slDist; trade.tp1=entryPrice-tp1Dist; }
   }

   if(trade.o1Open || trade.o2Open)
   {
      double lc=iClose(sym,PERIOD_D1,endBar);
      double ep=(trade.dir==1)?lc:lc+spread;
      ForceClose(trade, ep, balance, peak, r, tickVal, tickSz);
   }
   r.finalBal=balance;
}

//+------------------------------------------------------------------+
int EvalEntry(string sym, int bar)
{
   // 1. Baseline: Ichimoku Kijun
   double blCurr = iIchimoku(sym, PERIOD_D1, 9, InpKijunPeriod, 52, MODE_KIJUNSEN, bar);
   double blPrev = iIchimoku(sym, PERIOD_D1, 9, InpKijunPeriod, 52, MODE_KIJUNSEN, bar+1);
   if(blCurr==0 || blPrev==0) return 0;

   double closeCurr = iClose(sym, PERIOD_D1, bar);
   double closePrev = iClose(sym, PERIOD_D1, bar+1);

   int blDir=0;
   if(closeCurr > blCurr) blDir=1;
   else if(closeCurr < blCurr) blDir=-1;
   if(blDir==0) return 0;

   // Baseline cross
   bool cross=false;
   if(blDir==1 && closePrev<=blPrev) cross=true;
   if(blDir==-1 && closePrev>=blPrev) cross=true;
   if(!cross) return 0;

   // ATR filter
   double atr=iATR(sym,PERIOD_D1,InpATRPeriod,bar);
   double dist=MathAbs(closeCurr-blCurr);
   if(dist > InpMaxATRDist*atr) return 0;

   // 2. C1: SSL Channel
   double hlv=iCustom(sym,PERIOD_D1,IND_SSL,
                        false,0,2,InpSSL_C1_Len,0,3,InpSSL_C1_Len,0,bar);
   int c1Dir=0;
   if(hlv>0.5) c1Dir=1; if(hlv<-0.5) c1Dir=-1;
   if(c1Dir!=blDir) return 0;

   // 3. C2: Stochastic (current or prev bar)
   double stCurr=iStochastic(sym,PERIOD_D1,InpStochK,InpStochD,InpStochSlowing,MODE_SMA,0,MODE_MAIN,bar);
   double stPrev=iStochastic(sym,PERIOD_D1,InpStochK,InpStochD,InpStochSlowing,MODE_SMA,0,MODE_MAIN,bar+1);
   int c2Curr=0, c2Prev=0;
   if(stCurr>50) c2Curr=1; if(stCurr<50) c2Curr=-1;
   if(stPrev>50) c2Prev=1; if(stPrev<50) c2Prev=-1;
   if(c2Curr!=blDir && c2Prev!=blDir) return 0;

   // 4. Volume: Momentum Magnitude (growing)
   double mom     = iMomentum(sym, PERIOD_D1, InpMomPeriod, PRICE_CLOSE, bar);
   double momPrev = iMomentum(sym, PERIOD_D1, InpMomPeriod, PRICE_CLOSE, bar+1);
   double mag     = MathAbs(mom - 100);
   double magPrev = MathAbs(momPrev - 100);
   if(!(mag > magPrev && mag > 0.1)) return 0;

   return blDir;
}

//+------------------------------------------------------------------+
void ManageTrade(string sym, int bar, double spread, VTrade &t,
                  double &bal, double &peak, PairResult &r, double tv, double ts)
{
   double hi=iHigh(sym,PERIOD_D1,bar), lo=iLow(sym,PERIOD_D1,bar), cl=iClose(sym,PERIOD_D1,bar);
   double aHi=hi+spread, aLo=lo+spread, aCl=cl+spread;

   // Opposite baseline cross
   double blCurr=iIchimoku(sym,PERIOD_D1,9,InpKijunPeriod,52,MODE_KIJUNSEN,bar);
   double blPrev=iIchimoku(sym,PERIOD_D1,9,InpKijunPeriod,52,MODE_KIJUNSEN,bar+1);
   double closePrev=iClose(sym,PERIOD_D1,bar+1);

   bool opp=false;
   if(t.dir==1 && cl<blCurr && closePrev>=blPrev) opp=true;
   if(t.dir==-1 && cl>blCurr && closePrev<=blPrev) opp=true;
   if(opp)
   {
      double ep=(t.dir==1)?cl:aCl;
      ForceClose(t, ep, bal, peak, r, tv, ts);
      return;
   }

   // Order 1: TP/SL
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
         if(pnl>0)r.grossProfit+=pnl; else r.grossLoss+=pnl;
         t.o1Open=false;
         if(tp&&t.o2Open){t.sl=t.entry;t.movedBE=true;}
      }
   }

   // Order 2: Runner
   if(t.o2Open)
   {
      bool slH=false;
      if(t.dir==1 && lo<=t.sl) slH=true;
      if(t.dir==-1 && aHi>=t.sl) slH=true;

      // Exit SSL
      double exHlv=iCustom(sym,PERIOD_D1,IND_SSL,
                             false,0,2,InpSSL_Exit_Len,0,3,InpSSL_Exit_Len,0,bar);
      int exDir=0;
      if(exHlv>0.5) exDir=1; if(exHlv<-0.5) exDir=-1;
      bool exitFlip=false;
      if(t.dir==1 && exDir==-1) exitFlip=true;
      if(t.dir==-1 && exDir==1) exitFlip=true;

      double pnl=0;
      if(slH)
      {
         if(t.dir==1) pnl=(t.sl-t.entry)/ts*tv*t.lots2;
         else         pnl=(t.entry-t.sl)/ts*tv*t.lots2;
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0)r.grossProfit+=pnl; else r.grossLoss+=pnl;
         t.o2Open=false;
      }
      else if(exitFlip)
      {
         double ep=(t.dir==1)?cl:aCl;
         if(t.dir==1) pnl=(ep-t.entry)/ts*tv*t.lots2;
         else         pnl=(t.entry-ep)/ts*tv*t.lots2;
         bal+=pnl; t.pnl+=pnl;
         if(pnl>0)r.grossProfit+=pnl; else r.grossLoss+=pnl;
         t.o2Open=false;
      }
   }

   if(!t.o1Open && !t.o2Open)
   {
      if(t.pnl>=0) { r.wins++; if(t.dir==1) r.longWins++; else r.shortWins++; }
      else r.losses++;
   }

   if(bal>peak) peak=bal;
   double dd=peak-bal;
   if(dd>r.maxDD){r.maxDD=dd;r.maxDDPct=(dd/peak)*100.0;}
}

//+------------------------------------------------------------------+
void ForceClose(VTrade &t, double ep, double &bal, double &peak,
                 PairResult &r, double tv, double ts)
{
   if(t.o1Open)
   {
      double pnl=(t.dir==1)?(ep-t.entry)/ts*tv*t.lots1:(t.entry-ep)/ts*tv*t.lots1;
      bal+=pnl; t.pnl+=pnl;
      if(pnl>0)r.grossProfit+=pnl; else r.grossLoss+=pnl;
      t.o1Open=false;
   }
   if(t.o2Open)
   {
      double pnl=(t.dir==1)?(ep-t.entry)/ts*tv*t.lots2:(t.entry-ep)/ts*tv*t.lots2;
      bal+=pnl; t.pnl+=pnl;
      if(pnl>0)r.grossProfit+=pnl; else r.grossLoss+=pnl;
      t.o2Open=false;
   }
   if(t.pnl>=0) { r.wins++; if(t.dir==1) r.longWins++; else r.shortWins++; }
   else r.losses++;
   if(bal>peak) peak=bal;
   double dd=peak-bal;
   if(dd>r.maxDD){r.maxDD=dd;r.maxDDPct=(dd/peak)*100.0;}
}

//+------------------------------------------------------------------+
void PrintResult(PairResult &r)
{
   double pf=(r.grossLoss!=0)?MathAbs(r.grossProfit/r.grossLoss):0;
   double net=r.grossProfit+r.grossLoss;
   double wr=(r.signals>0)?((double)r.wins/r.signals*100.0):0;
   double lwr=(r.longSig>0)?((double)r.longWins/r.longSig*100.0):0;
   double swr=(r.shortSig>0)?((double)r.shortWins/r.shortSig*100.0):0;
   Print(r.symbol,": Sig=",r.signals," WR=",DoubleToStr(wr,1),"%",
         " (L:",DoubleToStr(lwr,1),"% S:",DoubleToStr(swr,1),"%)",
         " Net=$",DoubleToStr(net,2)," PF=",DoubleToStr(pf,2),
         " DD=",DoubleToStr(r.maxDDPct,1),"%");
}

//+------------------------------------------------------------------+
void WriteCSV(PairResult &results[], int count)
{
   string filename="NNFX_V2_Results.csv";
   int handle=FileOpen(filename,FILE_WRITE|FILE_CSV,',');
   if(handle<0){Print("ERROR: Cannot open ",filename);return;}

   FileWrite(handle,"Symbol","Signals","Orders","Wins","Losses","WinRate%",
             "LongSig","LongWR%","ShortSig","ShortWR%",
             "NetProfit","GrossProfit","GrossLoss","ProfitFactor",
             "MaxDD$","MaxDD%","FinalBalance");

   for(int i=0;i<count;i++)
   {
      PairResult r=results[i];
      double pf=(r.grossLoss!=0)?MathAbs(r.grossProfit/r.grossLoss):0;
      double net=r.grossProfit+r.grossLoss;
      double wr=(r.signals>0)?((double)r.wins/r.signals*100.0):0;
      double lwr=(r.longSig>0)?((double)r.longWins/r.longSig*100.0):0;
      double swr=(r.shortSig>0)?((double)r.shortWins/r.shortSig*100.0):0;
      FileWrite(handle,r.symbol,r.signals,r.orders,r.wins,r.losses,DoubleToStr(wr,1),
                r.longSig,DoubleToStr(lwr,1),r.shortSig,DoubleToStr(swr,1),
                DoubleToStr(net,2),DoubleToStr(r.grossProfit,2),DoubleToStr(r.grossLoss,2),
                DoubleToStr(pf,2),DoubleToStr(r.maxDD,2),DoubleToStr(r.maxDDPct,1),
                DoubleToStr(r.finalBal,2));
   }
   FileClose(handle);
   Print("CSV: MQL4/Files/",filename);
}

//+------------------------------------------------------------------+
void WriteSummary(PairResult &results[], int count)
{
   string filename="NNFX_V2_Summary.txt";
   int handle=FileOpen(filename,FILE_WRITE|FILE_TXT);
   if(handle<0){Print("ERROR: Cannot open ",filename);return;}

   FileWriteString(handle,"NNFX V2 Strategy Backtest Results\r\n");
   FileWriteString(handle,"Baseline: Ichimoku Kijun("+IntegerToString(InpKijunPeriod)+
                   ") | C1: SSL("+IntegerToString(InpSSL_C1_Len)+
                   ") | C2: Stoch("+IntegerToString(InpStochK)+
                   ") | Volume: MomMag("+IntegerToString(InpMomPeriod)+
                   ") | Exit: SSL("+IntegerToString(InpSSL_Exit_Len)+")\r\n");
   FileWriteString(handle,"Period: 2015-2025 | D1 | Risk: "+DoubleToStr(InpRiskPercent,1)+
                   "% | ATR: "+IntegerToString(InpATRPeriod)+"\r\n\r\n");

   FileWriteString(handle,StringFormat("%-8s | %4s | %6s | %5s | %5s | %7s | %7s | %10s | %5s | %7s\r\n",
                   "Pair","Sig","Orders","Wins","WR%","LongWR%","ShrtWR%","Net Profit","PF","MaxDD%"));
   FileWriteString(handle,"---------|------|--------|-------|-------|---------|---------|------------|-------|--------\r\n");

   for(int i=0;i<count;i++)
   {
      PairResult r=results[i];
      double pf=(r.grossLoss!=0)?MathAbs(r.grossProfit/r.grossLoss):0;
      double net=r.grossProfit+r.grossLoss;
      double wr=(r.signals>0)?((double)r.wins/r.signals*100.0):0;
      double lwr=(r.longSig>0)?((double)r.longWins/r.longSig*100.0):0;
      double swr=(r.shortSig>0)?((double)r.shortWins/r.shortSig*100.0):0;
      FileWriteString(handle,StringFormat("%-8s | %4d | %6d | %5d | %5.1f%% | %6.1f%% | %6.1f%% | $%9.2f | %5.2f | %6.1f%%\r\n",
                      r.symbol,r.signals,r.orders,r.wins,wr,lwr,swr,net,pf,r.maxDDPct));
   }
   FileClose(handle);
   Print("Summary: MQL4/Files/",filename);
}
//+------------------------------------------------------------------+
