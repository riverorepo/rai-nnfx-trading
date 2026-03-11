//+------------------------------------------------------------------+
//|                                           NNFX_Combined_H1.mq4   |
//|         H1 MTF Strategy — V3 Custom Indicator Combo              |
//|         HTF: H4 McGinley(14) trend filter                        |
//|         Entry: H1 Keltner(20) midline flip                       |
//|         Confirm: H1 RangeFilter(30,2.5)                          |
//|         Volume: None (custom indicators sufficiently selective)   |
//|         Exit: H1 HalfTrend(3) flip against trade                 |
//|         Magic 77703 — will NOT conflict with D1 bot (77702)      |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "3.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input string   _gen_sep_        = "=== General Settings ===";        // ---
input int      InpMagicNumber   = 77703;       // Magic Number (H1)
input double   InpRiskPercent   = 3.0;         // Risk % of Account Balance
input int      InpSlippage      = 30;          // Max Slippage (points)
input bool     InpEnableLogging = true;        // Enable Journal Logging

//--- Session filter
input string   _sess_sep_       = "=== Session Filter ===";          // ---
input bool     InpUseSession    = true;        // Enable Session Filter
input int      InpSessionStart  = 7;           // Session Start Hour (GMT)
input int      InpSessionEnd    = 20;          // Session End Hour (GMT)

//--- HTF Trend Filter: H4 McGinley Dynamic
input string   _htf_sep_        = "=== HTF Filter: H4 McGinley ==="; // ---
input int      InpMcGinleyPer   = 14;         // McGinley Period
input double   InpMcGinleyK     = 0.6;        // McGinley Constant

//--- Entry Trigger: H1 Keltner Channel midline flip
input string   _entry_sep_      = "=== Entry: H1 Keltner Channel ==="; // ---
input int      InpKeltnerMA     = 20;         // Keltner EMA Period
input int      InpKeltnerATR    = 20;         // Keltner ATR Period
input double   InpKeltnerMult   = 1.5;        // Keltner ATR Multiplier

//--- Confirmation: H1 RangeFilter
input string   _conf_sep_       = "=== Confirm: H1 RangeFilter ==="; // ---
input int      InpRngFiltPer    = 30;         // RangeFilter Period
input double   InpRngFiltMult   = 2.5;        // RangeFilter Multiplier

//--- Exit: H1 HalfTrend
input string   _exit_sep_       = "=== Exit: H1 HalfTrend ===";     // ---
input int      InpHalfTrendAmp  = 3;          // HalfTrend Amplitude
input int      InpHalfTrendDev  = 2;          // HalfTrend Channel Deviation
input int      InpHalfTrendATR  = 100;        // HalfTrend ATR Period

//--- Trade management
input string   _trade_sep_      = "=== Trade Management ===";        // ---
input int      InpATRPeriod     = 14;         // ATR Period
input double   InpSLMult        = 1.5;        // SL ATR Multiplier
input double   InpTP1Mult       = 1.0;        // TP1 ATR Multiplier

//--- Visual settings
input string   _vis_sep_        = "=== Visual Settings ===";          // ---
input bool     InpShowVisuals   = true;        // Show Chart Visuals
input int      InpBaselineBars  = 200;         // HTF Line: Bars to Draw
input color    InpHTFColor      = clrCyan;     // HTF Line Color
input int      InpHTFWidth      = 2;           // HTF Line Width
input color    InpEntryColor    = clrMagenta;  // Entry Keltner Mid Color
input color    InpBuyArrowClr   = clrDodgerBlue;  // Buy Signal Arrow Color
input color    InpSellArrowClr  = clrOrangeRed;   // Sell Signal Arrow Color
input color    InpSLColor       = clrRed;          // Stop Loss Line Color
input color    InpTPColor       = clrLime;         // Take Profit Line Color
input color    InpBEColor       = clrYellow;       // Breakeven Line Color

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
#define IND_MCGINLEY  "McGinley_Dynamic"
#define IND_KELTNER   "KeltnerChannel"
#define IND_RANGEFILT "RangeFilter"
#define IND_HALFTREND "HalfTrend"

#define OBJ_PREFIX "NNFXH1_"

datetime g_lastBarTime  = 0;
int      g_order1Ticket = -1;
int      g_order2Ticket = -1;
bool     g_order1Closed = false;
bool     g_movedToBE    = false;
double   g_entryPrice   = 0;
int      g_tradeDir     = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_H1)
      Log("WARNING: This EA is designed for H1. Current TF=" + IntegerToString(Period()));

   Log("Initialized V3 strategy on " + Symbol());
   Log("HTF: H4 McGinley(" + IntegerToString(InpMcGinleyPer) + ") | " +
       "Entry: Keltner(" + IntegerToString(InpKeltnerMA) + ") | " +
       "Confirm: RangeFilter(" + IntegerToString(InpRngFiltPer) + ") | " +
       "Exit: HalfTrend(" + IntegerToString(InpHalfTrendAmp) + ")");
   Log("Risk: " + DoubleToStr(InpRiskPercent, 1) + "% | SL: " + DoubleToStr(InpSLMult, 1) +
       "x ATR | TP1: " + DoubleToStr(InpTP1Mult, 1) + "x ATR");

   RecoverOrderState();

   if(InpShowVisuals)
   {
      DrawHTFLine();
      DrawEntryLine();
      DrawDashboard();
      DrawTradeLevels();
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAllVisuals();
   Log("EA deinitialized. Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   ManageOpenTrades();

   if(!HasOpenPosition())
   {
      g_order1Ticket = -1; g_order2Ticket = -1;
      g_order1Closed = false; g_movedToBE = false;
      g_entryPrice = 0; g_tradeDir = 0;

      if(!InSessionFilter())
      {
         if(InpShowVisuals)
         {
            DrawHTFLine();
            DrawEntryLine();
            DrawDashboard();
            DrawTradeLevels();
         }
         return;
      }

      int signal = EvaluateEntry();
      if(signal != 0)
         ExecuteEntry(signal);
   }

   if(InpShowVisuals)
   {
      DrawHTFLine();
      DrawEntryLine();
      DrawDashboard();
      DrawTradeLevels();
   }
}

//+------------------------------------------------------------------+
//| SESSION FILTER                                                    |
//+------------------------------------------------------------------+
bool InSessionFilter()
{
   if(!InpUseSession) return true;
   int hour = TimeHour(TimeCurrent());
   if(InpSessionStart < InpSessionEnd)
      return (hour >= InpSessionStart && hour < InpSessionEnd);
   else
      return (hour >= InpSessionStart || hour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| INDICATOR SIGNALS                                                 |
//+------------------------------------------------------------------+

// H4 McGinley Dynamic direction (slope-based)
int GetHTFDir(int h1Bar)
{
   datetime barTime = iTime(NULL, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(NULL, PERIOD_H4, barTime, false);
   if(htfBar < 1) return 0;

   double sig = iCustom(NULL, PERIOD_H4, IND_MCGINLEY,
                          InpMcGinleyPer, InpMcGinleyK, PRICE_CLOSE, 2, htfBar);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// H4 McGinley value (for visual line)
double GetHTFValue(int h1Bar)
{
   datetime barTime = iTime(NULL, PERIOD_H1, h1Bar);
   int htfBar = iBarShift(NULL, PERIOD_H4, barTime, false);
   if(htfBar < 0) return 0;
   // McGinley buffer 3 = MDBuffer (the actual value)
   return iCustom(NULL, PERIOD_H4, IND_MCGINLEY,
                   InpMcGinleyPer, InpMcGinleyK, PRICE_CLOSE, 3, htfBar);
}

// H1 Keltner Channel direction (price vs midline)
int GetKeltnerDir(int shift)
{
   double sig = iCustom(NULL, PERIOD_H1, IND_KELTNER,
                          InpKeltnerMA, InpKeltnerATR, InpKeltnerMult,
                          MODE_EMA, PRICE_CLOSE, 3, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// H1 Keltner midline value (for visual)
double GetKeltnerMid(int shift)
{
   return iCustom(NULL, PERIOD_H1, IND_KELTNER,
                   InpKeltnerMA, InpKeltnerATR, InpKeltnerMult,
                   MODE_EMA, PRICE_CLOSE, 1, shift);
}

// H1 RangeFilter direction
int GetRangeFilterDir(int shift)
{
   double sig = iCustom(NULL, PERIOD_H1, IND_RANGEFILT,
                          InpRngFiltPer, InpRngFiltMult, 2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

// H1 HalfTrend direction
int GetHalfTrendDir(int shift)
{
   double sig = iCustom(NULL, PERIOD_H1, IND_HALFTREND,
                          InpHalfTrendAmp, InpHalfTrendDev, InpHalfTrendATR,
                          2, shift);
   if(sig > 0.5)  return 1;
   if(sig < -0.5) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                  |
//+------------------------------------------------------------------+
int EvaluateEntry()
{
   int bar = 1;

   // 1. HTF Trend Filter — H4 McGinley direction
   int htfDir = GetHTFDir(bar);
   if(htfDir == 0)  return 0;

   // 2. Entry Trigger — Keltner midline FLIP in HTF direction
   int keltCurr = GetKeltnerDir(bar);
   int keltPrev = GetKeltnerDir(bar + 1);
   bool flip = (keltCurr == htfDir && keltPrev != htfDir);
   if(!flip) return 0;

   Log("Keltner flip detected. Dir=" + (htfDir == 1 ? "BUY" : "SELL") +
       " | HTF McGinley=" + (htfDir == 1 ? "BULL" : "BEAR"));

   // 3. Confirmation — RangeFilter must agree (current or previous bar)
   int rfCurr = GetRangeFilterDir(bar);
   int rfPrev = GetRangeFilterDir(bar + 1);
   if(rfCurr != htfDir && rfPrev != htfDir)
   {
      Log("REJECTED: RangeFilter disagrees (curr=" + IntegerToString(rfCurr) +
          " prev=" + IntegerToString(rfPrev) + ")");
      return 0;
   }

   // 4. No volume filter — custom indicators are selective enough

   Log("ALL CONDITIONS MET. V3 H1 signal: " + (htfDir == 1 ? "BUY" : "SELL"));
   return htfDir;
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
       " SL=" + DoubleToStr(sl, Digits) + " TP1=" + DoubleToStr(tp1, Digits) +
       " ATR=" + DoubleToStr(atr, Digits));

   int ticket1 = OrderSend(Symbol(), orderType, halfLot, (orderType == OP_BUY) ? Ask : Bid,
                             InpSlippage, sl, tp1, "NNFXH1_TP1", InpMagicNumber, 0, arrowColor);
   if(ticket1 < 0)
   {
      Log("ERROR: Order 1 failed. Err=" + IntegerToString(GetLastError()));
      return;
   }

   int ticket2 = OrderSend(Symbol(), orderType, halfLot, (orderType == OP_BUY) ? Ask : Bid,
                             InpSlippage, sl, 0, "NNFXH1_Runner", InpMagicNumber, 0, arrowColor);
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

   if(InpShowVisuals)
      DrawSignalArrow(Time[1], direction);
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   if(!HasOpenPosition()) return;
   RefreshTicketState();

   // HTF flip against trade — close all
   int htfNow  = GetHTFDir(1);
   int htfPrev = GetHTFDir(2);
   bool htfFlip = false;
   if(g_tradeDir == 1  && htfNow == -1 && htfPrev != -1) htfFlip = true;
   if(g_tradeDir == -1 && htfNow == 1  && htfPrev != 1)  htfFlip = true;
   if(htfFlip)
   {
      Log("HTF McGinley flipped against trade. Closing all.");
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

   // Exit: HalfTrend flip against trade -> close runner
   if(g_order2Ticket > 0 && IsOrderOpen(g_order2Ticket))
   {
      int exitDir = GetHalfTrendDir(1);
      if(g_tradeDir == 1 && exitDir == -1)
      { Log("EXIT: HalfTrend flipped bearish. Closing runner."); CloseOrderByTicket(g_order2Ticket); }
      else if(g_tradeDir == -1 && exitDir == 1)
      { Log("EXIT: HalfTrend flipped bullish. Closing runner."); CloseOrderByTicket(g_order2Ticket); }
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
      if(StringFind(comment, "NNFXH1_TP1") >= 0) tp = OrderTicket();
      else if(StringFind(comment, "NNFXH1_Runner") >= 0) runner = OrderTicket();
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
          " Dir=" + IntegerToString(dir));
   }
}

void Log(string msg)
{
   if(InpEnableLogging)
      Print("[NNFX_H1_V3] " + Symbol() + " | " + msg);
}

//+------------------------------------------------------------------+
//| VISUAL FUNCTIONS                                                  |
//+------------------------------------------------------------------+

// Draw H4 McGinley Dynamic mapped onto H1 chart
void DrawHTFLine()
{
   string namePrefix = OBJ_PREFIX + "HTF_";
   int bars = MathMin(InpBaselineBars, Bars - 2);

   for(int i = 0; i < bars; i++)
   {
      double val0 = GetHTFValue(i);
      double val1 = GetHTFValue(i + 1);
      if(val0 == 0 || val1 == 0) continue;

      string objName = namePrefix + IntegerToString(i);

      if(ObjectFind(objName) < 0)
         ObjectCreate(objName, OBJ_TREND, 0, Time[i + 1], val1, Time[i], val0);
      else
      {
         ObjectSet(objName, OBJPROP_TIME1, Time[i + 1]);
         ObjectSet(objName, OBJPROP_PRICE1, val1);
         ObjectSet(objName, OBJPROP_TIME2, Time[i]);
         ObjectSet(objName, OBJPROP_PRICE2, val0);
      }

      ObjectSet(objName, OBJPROP_COLOR, InpHTFColor);
      ObjectSet(objName, OBJPROP_WIDTH, InpHTFWidth);
      ObjectSet(objName, OBJPROP_RAY, false);
      ObjectSet(objName, OBJPROP_BACK, true);
      ObjectSet(objName, OBJPROP_SELECTABLE, false);
   }

   for(int j = bars; j < bars + 20; j++)
   {
      string oldName = namePrefix + IntegerToString(j);
      if(ObjectFind(oldName) >= 0) ObjectDelete(oldName);
   }
}

// Draw H1 Keltner Channel midline
void DrawEntryLine()
{
   string namePrefix = OBJ_PREFIX + "KELT_";
   int bars = MathMin(InpBaselineBars, Bars - 2);

   for(int i = 0; i < bars; i++)
   {
      double val0 = GetKeltnerMid(i);
      double val1 = GetKeltnerMid(i + 1);
      if(val0 == 0 || val1 == 0) continue;

      string objName = namePrefix + IntegerToString(i);

      if(ObjectFind(objName) < 0)
         ObjectCreate(objName, OBJ_TREND, 0, Time[i + 1], val1, Time[i], val0);
      else
      {
         ObjectSet(objName, OBJPROP_TIME1, Time[i + 1]);
         ObjectSet(objName, OBJPROP_PRICE1, val1);
         ObjectSet(objName, OBJPROP_TIME2, Time[i]);
         ObjectSet(objName, OBJPROP_PRICE2, val0);
      }

      ObjectSet(objName, OBJPROP_COLOR, InpEntryColor);
      ObjectSet(objName, OBJPROP_WIDTH, 1);
      ObjectSet(objName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSet(objName, OBJPROP_RAY, false);
      ObjectSet(objName, OBJPROP_BACK, true);
      ObjectSet(objName, OBJPROP_SELECTABLE, false);
   }

   for(int j = bars; j < bars + 20; j++)
   {
      string oldName = namePrefix + IntegerToString(j);
      if(ObjectFind(oldName) >= 0) ObjectDelete(oldName);
   }
}

void DrawSignalArrow(datetime time, int direction)
{
   static int arrowCount = 0;
   arrowCount++;

   string objName = OBJ_PREFIX + "Arrow_" + IntegerToString(arrowCount);

   if(direction == 1)
   {
      ObjectCreate(objName, OBJ_ARROW_UP, 0, time, Low[iBarShift(NULL, 0, time)] - iATR(NULL, 0, InpATRPeriod, 1) * 0.3);
      ObjectSet(objName, OBJPROP_COLOR, InpBuyArrowClr);
   }
   else
   {
      ObjectCreate(objName, OBJ_ARROW_DOWN, 0, time, High[iBarShift(NULL, 0, time)] + iATR(NULL, 0, InpATRPeriod, 1) * 0.3);
      ObjectSet(objName, OBJPROP_COLOR, InpSellArrowClr);
   }
   ObjectSet(objName, OBJPROP_WIDTH, 3);
   ObjectSet(objName, OBJPROP_SELECTABLE, false);
}

void DrawTradeLevels()
{
   ObjectDelete(OBJ_PREFIX + "SL_Line");
   ObjectDelete(OBJ_PREFIX + "TP_Line");
   ObjectDelete(OBJ_PREFIX + "BE_Line");
   ObjectDelete(OBJ_PREFIX + "SL_Label");
   ObjectDelete(OBJ_PREFIX + "TP_Label");
   ObjectDelete(OBJ_PREFIX + "BE_Label");

   if(!HasOpenPosition()) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;

      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      double entry = OrderOpenPrice();

      if(sl > 0 && ObjectFind(OBJ_PREFIX + "SL_Line") < 0)
      {
         ObjectCreate(OBJ_PREFIX + "SL_Line", OBJ_HLINE, 0, 0, sl);
         ObjectSet(OBJ_PREFIX + "SL_Line", OBJPROP_COLOR, InpSLColor);
         ObjectSet(OBJ_PREFIX + "SL_Line", OBJPROP_STYLE, STYLE_DASH);
         ObjectSet(OBJ_PREFIX + "SL_Line", OBJPROP_WIDTH, 1);
         ObjectSet(OBJ_PREFIX + "SL_Line", OBJPROP_SELECTABLE, false);
         ObjectSet(OBJ_PREFIX + "SL_Line", OBJPROP_BACK, true);
         ObjectCreate(OBJ_PREFIX + "SL_Label", OBJ_TEXT, 0, Time[5], sl);
         ObjectSetText(OBJ_PREFIX + "SL_Label", "SL " + DoubleToStr(sl, Digits), 8, "Arial", InpSLColor);
      }

      if(tp > 0 && ObjectFind(OBJ_PREFIX + "TP_Line") < 0)
      {
         ObjectCreate(OBJ_PREFIX + "TP_Line", OBJ_HLINE, 0, 0, tp);
         ObjectSet(OBJ_PREFIX + "TP_Line", OBJPROP_COLOR, InpTPColor);
         ObjectSet(OBJ_PREFIX + "TP_Line", OBJPROP_STYLE, STYLE_DASH);
         ObjectSet(OBJ_PREFIX + "TP_Line", OBJPROP_WIDTH, 1);
         ObjectSet(OBJ_PREFIX + "TP_Line", OBJPROP_SELECTABLE, false);
         ObjectSet(OBJ_PREFIX + "TP_Line", OBJPROP_BACK, true);
         ObjectCreate(OBJ_PREFIX + "TP_Label", OBJ_TEXT, 0, Time[5], tp);
         ObjectSetText(OBJ_PREFIX + "TP_Label", "TP " + DoubleToStr(tp, Digits), 8, "Arial", InpTPColor);
      }

      if(g_movedToBE && ObjectFind(OBJ_PREFIX + "BE_Line") < 0)
      {
         ObjectCreate(OBJ_PREFIX + "BE_Line", OBJ_HLINE, 0, 0, entry);
         ObjectSet(OBJ_PREFIX + "BE_Line", OBJPROP_COLOR, InpBEColor);
         ObjectSet(OBJ_PREFIX + "BE_Line", OBJPROP_STYLE, STYLE_DOT);
         ObjectSet(OBJ_PREFIX + "BE_Line", OBJPROP_WIDTH, 1);
         ObjectSet(OBJ_PREFIX + "BE_Line", OBJPROP_SELECTABLE, false);
         ObjectSet(OBJ_PREFIX + "BE_Line", OBJPROP_BACK, true);
         ObjectCreate(OBJ_PREFIX + "BE_Label", OBJ_TEXT, 0, Time[5], entry);
         ObjectSetText(OBJ_PREFIX + "BE_Label", "BE " + DoubleToStr(entry, Digits), 8, "Arial", InpBEColor);
      }
   }
}

void DrawDashboard()
{
   int bar = 1;
   int xStart = 10;
   int yStart = 30;
   int lineH  = 16;
   int row    = 0;

   CreateLabel("Dash_Title", "NNFX H1 V3 | " + Symbol(), xStart, yStart + lineH * row, clrCyan, 10);
   row++;
   CreateLabel("Dash_Sep", "--------------------------------------------", xStart, yStart + lineH * row, clrGray, 8);
   row++;

   // Session
   bool inSession = InSessionFilter();
   CreateLabel("Dash_Sess", "Session (" + IntegerToString(InpSessionStart) + "-" + IntegerToString(InpSessionEnd) +
               " GMT): " + (inSession ? "ACTIVE" : "CLOSED"), xStart, yStart + lineH * row,
               inSession ? clrLime : clrGray, 9);
   row++;

   // HTF McGinley
   int htfDir = GetHTFDir(bar);
   string htfStr = (htfDir == 1) ? "BULL" : (htfDir == -1) ? "BEAR" : "FLAT";
   color htfClr = (htfDir == 1) ? clrDodgerBlue : (htfDir == -1) ? clrOrangeRed : clrGray;
   CreateLabel("Dash_HTF", "HTF H4 McGinley(" + IntegerToString(InpMcGinleyPer) + "): " + htfStr,
               xStart, yStart + lineH * row, htfClr, 9);
   row++;

   // Entry Keltner
   int keltDir = GetKeltnerDir(bar);
   int keltPrev = GetKeltnerDir(bar + 1);
   bool keltFlip = (keltDir == htfDir && keltPrev != htfDir && htfDir != 0);
   string keltStr = (keltDir == 1) ? "BULL" : (keltDir == -1) ? "BEAR" : "FLAT";
   CreateLabel("Dash_Entry", "Entry Keltner(" + IntegerToString(InpKeltnerMA) + "): " + keltStr +
               (keltFlip ? " ** FLIP **" : ""),
               xStart, yStart + lineH * row, keltFlip ? clrLime : (keltDir == htfDir ? clrYellow : clrOrangeRed), 9);
   row++;

   // Confirm RangeFilter
   int rfDir = GetRangeFilterDir(bar);
   string rfStr = (rfDir == 1) ? "BULL" : (rfDir == -1) ? "BEAR" : "FLAT";
   bool rfMatch = (rfDir == htfDir && htfDir != 0);
   CreateLabel("Dash_Conf", "Confirm RngFilt(" + IntegerToString(InpRngFiltPer) + "): " + rfStr,
               xStart, yStart + lineH * row, rfMatch ? clrLime : clrOrangeRed, 9);
   row++;

   // Exit HalfTrend
   int htDir = GetHalfTrendDir(bar);
   string htStr = (htDir == 1) ? "BULL" : (htDir == -1) ? "BEAR" : "FLAT";
   CreateLabel("Dash_Exit", "Exit HalfTrend(" + IntegerToString(InpHalfTrendAmp) + "): " + htStr,
               xStart, yStart + lineH * row, clrSilver, 9);
   row++;

   // ATR
   double atr = iATR(NULL, 0, InpATRPeriod, bar);
   CreateLabel("Dash_ATR", "ATR(" + IntegerToString(InpATRPeriod) + "): " + DoubleToStr(atr, Digits) +
               " | SL: " + DoubleToStr(InpSLMult * atr, Digits) + " | TP1: " + DoubleToStr(InpTP1Mult * atr, Digits),
               xStart, yStart + lineH * row, clrSilver, 9);
   row++;

   CreateLabel("Dash_Sep2", "--------------------------------------------", xStart, yStart + lineH * row, clrGray, 8);
   row++;

   // Trade status
   string tradeStr = "";
   if(HasOpenPosition())
   {
      tradeStr = "IN TRADE: " + (g_tradeDir == 1 ? "LONG" : "SHORT");
      if(g_order1Closed) tradeStr += " | TP1 hit, runner active";
      if(g_movedToBE)    tradeStr += " | BE set";
   }
   else
      tradeStr = "NO POSITION - Waiting for signal...";

   color tradeClr = HasOpenPosition() ? clrDodgerBlue : clrGray;
   CreateLabel("Dash_Trade", tradeStr, xStart, yStart + lineH * row, tradeClr, 9);
   row++;

   // Condition count
   int condCount = 0;
   if(htfDir != 0) condCount++;
   if(keltFlip) condCount++;
   if(rfMatch) condCount++;
   color readyClr = (condCount == 3) ? clrLime : (condCount >= 2) ? clrYellow : clrGray;
   CreateLabel("Dash_Ready", "Conditions: " + IntegerToString(condCount) + "/3" +
               (condCount == 3 ? "  >>> SIGNAL <<<" : ""),
               xStart, yStart + lineH * row, readyClr, 9);
}

void CreateLabel(string suffix, string text, int x, int y, color clr, int fontSize)
{
   string name = OBJ_PREFIX + suffix;

   if(ObjectFind(name) < 0)
   {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(name, OBJPROP_SELECTABLE, false);
      ObjectSet(name, OBJPROP_HIDDEN, true);
   }
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, text, fontSize, "Consolas", clr);
}

void DeleteAllVisuals()
{
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, OBJ_PREFIX) == 0)
         ObjectDelete(name);
   }
}
//+------------------------------------------------------------------+
