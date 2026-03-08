//+------------------------------------------------------------------+
//|                                              NNFX_Combined.mq4   |
//|         Combined EA: V1 on USDJPY/GBPUSD, V2 on EURUSD/NZDUSD   |
//|         Attach to each pair's D1 chart separately.                |
//|         Auto-detects which strategy to use based on Symbol().     |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input string   _gen_sep_        = "=== General Settings ===";        // ---
input int      InpMagicNumber   = 77702;       // Magic Number
input double   InpRiskPercent   = 2.0;         // Risk % of Account Balance
input int      InpSlippage      = 30;          // Max Slippage (points)
input bool     InpEnableLogging = true;        // Enable Journal Logging

//--- V1 params (USDJPY, GBPUSD): KAMA baseline + WAE volume
input string   _v1_sep_         = "=== V1 Settings (USDJPY, GBPUSD) ==="; // ---
input int      InpV1_KamaPeriod = 10;     // V1 KAMA Period
input double   InpV1_KamaFast   = 2.0;    // V1 KAMA Fast
input double   InpV1_KamaSlow   = 30.0;   // V1 KAMA Slow
input int      InpV1_WAE_Sens   = 150;    // V1 WAE Sensitivity
input int      InpV1_WAE_DZ     = 30;     // V1 WAE Dead Zone
input int      InpV1_WAE_EP     = 15;     // V1 WAE Explosion Power
input int      InpV1_WAE_TP     = 15;     // V1 WAE Trend Power

//--- V2 params (EURUSD, NZDUSD): Kijun baseline + MomMag volume
input string   _v2_sep_         = "=== V2 Settings (EURUSD, NZDUSD) ==="; // ---
input int      InpV2_KijunPer   = 20;     // V2 Kijun Period
input int      InpV2_MomPeriod  = 14;     // V2 Momentum Period

//--- Shared params
input string   _shared_sep_     = "=== Shared Settings ===";          // ---
input int      InpSSL_C1_Len    = 25;     // C1 SSL Length
input int      InpStochK        = 14;     // C2 Stoch %K
input int      InpStochD        = 3;      // C2 Stoch %D
input int      InpStochSlowing  = 3;      // C2 Stoch Slowing
input int      InpSSL_Exit_Len  = 5;      // Exit SSL Length
input int      InpATRPeriod     = 7;      // ATR Period
input double   InpSLMult        = 1.5;    // SL ATR Multiplier
input double   InpTP1Mult       = 1.0;    // TP1 ATR Multiplier
input double   InpMaxATRDist    = 1.0;    // Max Baseline Distance (ATR x)

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
#define IND_KAMA "KAMA"
#define IND_SSL  "SSL_Channel"
#define IND_WAE  "Waddah_Attar_Explosion"

datetime g_lastBarTime  = 0;
int      g_order1Ticket = -1;
int      g_order2Ticket = -1;
bool     g_order1Closed = false;
bool     g_movedToBE    = false;
double   g_entryPrice   = 0;
int      g_tradeDir     = 0;
int      g_strategy     = 0;  // 1=V1, 2=V2, 0=unsupported pair

//+------------------------------------------------------------------+
int OnInit()
{
   string sym = Symbol();
   if(sym == "USDJPY" || sym == "GBPUSD")
      g_strategy = 1;
   else if(sym == "EURUSD" || sym == "NZDUSD")
      g_strategy = 2;
   else
   {
      g_strategy = 0;
      Log("WARNING: " + sym + " is not in the combined portfolio. EA will not trade.");
      Log("Supported pairs: USDJPY, GBPUSD (V1) | EURUSD, NZDUSD (V2)");
   }

   if(g_strategy == 1)
      Log("Initialized V1 strategy (KAMA + WAE) on " + sym);
   else if(g_strategy == 2)
      Log("Initialized V2 strategy (Kijun + MomMag) on " + sym);

   RecoverOrderState();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Log("EA deinitialized. Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(g_strategy == 0) return;
   if(!IsNewBar()) return;

   ManageOpenTrades();

   if(HasOpenPosition()) return;

   g_order1Ticket = -1; g_order2Ticket = -1;
   g_order1Closed = false; g_movedToBE = false;
   g_entryPrice = 0; g_tradeDir = 0;

   int signal = EvaluateEntry();
   if(signal != 0)
      ExecuteEntry(signal);
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                  |
//+------------------------------------------------------------------+
int EvaluateEntry()
{
   int bar = 1;

   // 1. Baseline
   double blCurr = GetBaseline(bar);
   double blPrev = GetBaseline(bar + 1);
   if(blCurr == 0 || blPrev == 0) return 0;

   int blDir = 0;
   if(Close[bar] > blCurr) blDir = 1;
   else if(Close[bar] < blCurr) blDir = -1;
   if(blDir == 0) return 0;

   // Cross
   bool cross = false;
   if(blDir == 1 && Close[bar + 1] <= blPrev) cross = true;
   if(blDir == -1 && Close[bar + 1] >= blPrev) cross = true;
   if(!cross) return 0;

   Log("Baseline cross. Dir=" + (blDir == 1 ? "BUY" : "SELL") +
       " | Strategy=V" + IntegerToString(g_strategy));

   // ATR filter
   double atr = iATR(NULL, 0, InpATRPeriod, bar);
   if(MathAbs(Close[bar] - blCurr) > InpMaxATRDist * atr) return 0;

   // 2. C1: SSL
   double hlv = iCustom(NULL, 0, IND_SSL,
                          false, 0, 2, InpSSL_C1_Len, 0, 3, InpSSL_C1_Len, 0, bar);
   int c1Dir = 0;
   if(hlv > 0.5) c1Dir = 1; if(hlv < -0.5) c1Dir = -1;
   if(c1Dir != blDir) { Log("REJECTED: C1 disagrees"); return 0; }

   // 3. C2: Stochastic
   double stCurr = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing,
                                MODE_SMA, 0, MODE_MAIN, bar);
   double stPrev = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing,
                                MODE_SMA, 0, MODE_MAIN, bar + 1);
   int c2C = (stCurr > 50) ? 1 : (stCurr < 50) ? -1 : 0;
   int c2P = (stPrev > 50) ? 1 : (stPrev < 50) ? -1 : 0;
   if(c2C != blDir && c2P != blDir) { Log("REJECTED: C2 disagrees"); return 0; }

   // 4. Volume (strategy-dependent)
   bool volOK = false;
   if(g_strategy == 1)
      volOK = CheckWAE(bar, blDir);
   else
      volOK = CheckMomMag(bar);

   if(!volOK) { Log("REJECTED: Volume not confirmed"); return 0; }

   Log("ALL CONDITIONS MET. V" + IntegerToString(g_strategy) + " signal: " +
       (blDir == 1 ? "BUY" : "SELL"));
   return blDir;
}

//+------------------------------------------------------------------+
//| BASELINE (strategy-dependent)                                     |
//+------------------------------------------------------------------+
double GetBaseline(int shift)
{
   if(g_strategy == 1) // V1: KAMA
      return iCustom(NULL, 0, IND_KAMA, InpV1_KamaPeriod, InpV1_KamaFast, InpV1_KamaSlow, 0, shift);
   else // V2: Ichimoku Kijun
      return iIchimoku(NULL, 0, 9, InpV2_KijunPer, 52, MODE_KIJUNSEN, shift);
}

//+------------------------------------------------------------------+
//| VOLUME: V1 = WAE                                                  |
//+------------------------------------------------------------------+
bool CheckWAE(int shift, int direction)
{
   double green     = iCustom(NULL, 0, IND_WAE, InpV1_WAE_Sens, InpV1_WAE_DZ,
                               InpV1_WAE_EP, InpV1_WAE_TP,
                               true, 500, true, true, true, true, 0, shift);
   double red       = iCustom(NULL, 0, IND_WAE, InpV1_WAE_Sens, InpV1_WAE_DZ,
                               InpV1_WAE_EP, InpV1_WAE_TP,
                               true, 500, true, true, true, true, 1, shift);
   double explosion = iCustom(NULL, 0, IND_WAE, InpV1_WAE_Sens, InpV1_WAE_DZ,
                               InpV1_WAE_EP, InpV1_WAE_TP,
                               true, 500, true, true, true, true, 2, shift);
   double deadZone  = iCustom(NULL, 0, IND_WAE, InpV1_WAE_Sens, InpV1_WAE_DZ,
                               InpV1_WAE_EP, InpV1_WAE_TP,
                               true, 500, true, true, true, true, 3, shift);
   double greenPrev = iCustom(NULL, 0, IND_WAE, InpV1_WAE_Sens, InpV1_WAE_DZ,
                               InpV1_WAE_EP, InpV1_WAE_TP,
                               true, 500, true, true, true, true, 0, shift + 1);
   double redPrev   = iCustom(NULL, 0, IND_WAE, InpV1_WAE_Sens, InpV1_WAE_DZ,
                               InpV1_WAE_EP, InpV1_WAE_TP,
                               true, 500, true, true, true, true, 1, shift + 1);

   if(explosion <= deadZone) return false;
   bool trendMatch = false, trendGrow = false;
   if(direction == 1 && green > 0)  { trendMatch = true; trendGrow = (green > greenPrev); }
   if(direction == -1 && red > 0)   { trendMatch = true; trendGrow = (red > redPrev); }
   return (trendMatch && trendGrow);
}

//+------------------------------------------------------------------+
//| VOLUME: V2 = Momentum Magnitude                                   |
//+------------------------------------------------------------------+
bool CheckMomMag(int shift)
{
   double mom     = iMomentum(NULL, 0, InpV2_MomPeriod, PRICE_CLOSE, shift);
   double momPrev = iMomentum(NULL, 0, InpV2_MomPeriod, PRICE_CLOSE, shift + 1);
   double mag     = MathAbs(mom - 100);
   double magPrev = MathAbs(momPrev - 100);
   return (mag > magPrev && mag > 0.1);
}

//+------------------------------------------------------------------+
//| EXIT SSL                                                          |
//+------------------------------------------------------------------+
int GetExitSSLDir(int shift)
{
   double hlv = iCustom(NULL, 0, IND_SSL,
                          false, 0, 2, InpSSL_Exit_Len, 0, 3, InpSSL_Exit_Len, 0, shift);
   if(hlv > 0.5) return 1;
   if(hlv < -0.5) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| EXECUTE ENTRY                                                     |
//+------------------------------------------------------------------+
void ExecuteEntry(int direction)
{
   double atr = iATR(NULL, 0, InpATRPeriod, 1);
   if(atr <= 0) { Log("ERROR: ATR is zero"); return; }

   double slDist  = InpSLMult * atr;
   double tp1Dist = InpTP1Mult * atr;
   double totalLots = CalculateLotSize(slDist);
   if(totalLots <= 0) { Log("ERROR: Lot size zero"); return; }

   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double halfLot = MathFloor(totalLots / 2.0 / lotStep) * lotStep;
   if(halfLot < minLot) halfLot = minLot;
   if(halfLot > maxLot) halfLot = maxLot;

   double entryPrice, sl, tp1;
   int orderType;
   color arrowColor;

   if(direction == 1)
   {
      entryPrice = Ask; sl = entryPrice - slDist; tp1 = entryPrice + tp1Dist;
      orderType = OP_BUY; arrowColor = clrDodgerBlue;
   }
   else
   {
      entryPrice = Bid; sl = entryPrice + slDist; tp1 = entryPrice - tp1Dist;
      orderType = OP_SELL; arrowColor = clrOrangeRed;
   }
   sl  = NormalizeDouble(sl, Digits);
   tp1 = NormalizeDouble(tp1, Digits);

   Log("ENTRY: " + (direction == 1 ? "BUY" : "SELL") +
       " HalfLot=" + DoubleToStr(halfLot, 2) +
       " SL=" + DoubleToStr(sl, Digits) + " TP1=" + DoubleToStr(tp1, Digits));

   int ticket1 = OrderSend(Symbol(), orderType, halfLot, (orderType == OP_BUY) ? Ask : Bid,
                             InpSlippage, sl, tp1, "NNFX_TP1", InpMagicNumber, 0, arrowColor);
   if(ticket1 < 0)
   {
      Log("ERROR: Order 1 failed. Err=" + IntegerToString(GetLastError()));
      return;
   }

   int ticket2 = OrderSend(Symbol(), orderType, halfLot, (orderType == OP_BUY) ? Ask : Bid,
                             InpSlippage, sl, 0, "NNFX_Runner", InpMagicNumber, 0, arrowColor);
   if(ticket2 < 0)
   {
      Log("ERROR: Order 2 failed. Closing Order 1.");
      CloseOrderByTicket(ticket1);
      return;
   }

   g_order1Ticket = ticket1; g_order2Ticket = ticket2;
   g_order1Closed = false; g_movedToBE = false;
   g_entryPrice = entryPrice; g_tradeDir = direction;

   Log("ORDERS PLACED: T1=" + IntegerToString(ticket1) + " T2=" + IntegerToString(ticket2));
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   if(!HasOpenPosition()) return;
   RefreshTicketState();

   // Opposite baseline cross
   double blCurr = GetBaseline(1);
   double blPrev = GetBaseline(2);
   int blDir = 0;
   if(Close[1] > blCurr) blDir = 1; if(Close[1] < blCurr) blDir = -1;

   bool oppCross = false;
   if(g_tradeDir == 1 && blDir == -1 && Close[2] >= blPrev) oppCross = true;
   if(g_tradeDir == -1 && blDir == 1 && Close[2] <= blPrev) oppCross = true;
   if(oppCross)
   {
      Log("OPPOSITE BASELINE CROSS. Closing all.");
      CloseAllMyOrders();
      return;
   }

   // Order 1 TP hit -> move runner to BE
   if(!g_order1Closed && g_order1Ticket > 0)
   {
      if(!IsOrderOpen(g_order1Ticket))
      {
         g_order1Closed = true;
         Log("Order 1 closed (TP hit).");
         if(g_order2Ticket > 0 && IsOrderOpen(g_order2Ticket))
            MoveToBreakeven(g_order2Ticket);
      }
   }

   // Exit SSL -> close runner
   if(g_order2Ticket > 0 && IsOrderOpen(g_order2Ticket))
   {
      int exitDir = GetExitSSLDir(1);
      if(g_tradeDir == 1 && exitDir == -1)
      { Log("EXIT: SSL flipped bearish. Closing runner."); CloseOrderByTicket(g_order2Ticket); }
      else if(g_tradeDir == -1 && exitDir == 1)
      { Log("EXIT: SSL flipped bullish. Closing runner."); CloseOrderByTicket(g_order2Ticket); }
   }
}

//+------------------------------------------------------------------+
//| POSITION SIZING                                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
{
   if(slDist <= 0) return 0;
   double balance = AccountBalance();
   double riskAmt = balance * (InpRiskPercent / 100.0);
   double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSz  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   if(tickVal <= 0 || tickSz <= 0) return 0;

   double slTicks = slDist / tickSz;
   double riskPerLot = slTicks * tickVal;
   if(riskPerLot <= 0) return 0;

   double lots = riskAmt / riskPerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| ORDER HELPERS                                                     |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) return true;
   }
   return false;
}

bool IsOrderOpen(int ticket)
{
   if(ticket <= 0) return false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderTicket() == ticket) return true;
   }
   return false;
}

bool CloseOrderByTicket(int ticket)
{
   if(ticket <= 0) return false;
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   if(OrderCloseTime() != 0) return true;
   double cp = (OrderType() == OP_BUY) ? Bid : Ask;
   bool ok = OrderClose(ticket, OrderLots(), cp, InpSlippage, clrWhite);
   if(!ok) Log("ERROR closing ticket " + IntegerToString(ticket) + " Err=" + IntegerToString(GetLastError()));
   return ok;
}

void CloseAllMyOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      CloseOrderByTicket(OrderTicket());
   }
   g_order1Ticket = -1; g_order2Ticket = -1;
   g_order1Closed = false; g_movedToBE = false;
   g_entryPrice = 0; g_tradeDir = 0;
}

void MoveToBreakeven(int ticket)
{
   if(g_movedToBE) return;
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double newSL = OrderOpenPrice();
   bool ok = OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(newSL, Digits), OrderTakeProfit(), 0, clrYellow);
   if(ok || GetLastError() == ERR_NO_RESULT)
   {
      g_movedToBE = true;
      Log("Runner SL moved to BE at " + DoubleToStr(newSL, Digits));
   }
}

bool IsNewBar()
{
   datetime t = Time[0];
   if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   return false;
}

void RefreshTicketState()
{
   if(g_order1Ticket <= 0 && g_order2Ticket <= 0)
      RecoverOrderState();
}

void RecoverOrderState()
{
   int tp = -1, runner = -1; int dir = 0; double entry = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      string comment = OrderComment();
      if(StringFind(comment, "NNFX_TP1") >= 0) tp = OrderTicket();
      else if(StringFind(comment, "NNFX_Runner") >= 0) runner = OrderTicket();
      if(OrderType() == OP_BUY) dir = 1; if(OrderType() == OP_SELL) dir = -1;
      entry = OrderOpenPrice();
   }
   if(tp > 0 || runner > 0)
   {
      g_order1Ticket = tp; g_order2Ticket = runner;
      g_tradeDir = dir; g_entryPrice = entry;
      if(tp <= 0 && runner > 0)
      {
         g_order1Closed = true;
         if(OrderSelect(runner, SELECT_BY_TICKET))
         {
            if(MathAbs(OrderStopLoss() - OrderOpenPrice()) < Point * 5)
               g_movedToBE = true;
         }
      }
      Log("RECOVERED: TP=" + IntegerToString(tp) + " Runner=" + IntegerToString(runner) +
          " Dir=" + IntegerToString(dir) + " Strategy=V" + IntegerToString(g_strategy));
   }
}

void Log(string msg)
{
   if(InpEnableLogging)
      Print("[NNFX_Combined] " + Symbol() + " V" + IntegerToString(g_strategy) + " | " + msg);
}
//+------------------------------------------------------------------+
