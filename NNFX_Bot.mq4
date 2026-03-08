//+------------------------------------------------------------------+
//|                                                    NNFX_Bot.mq4  |
//|                         No Nonsense Forex Expert Advisor          |
//|                    Automated NNFX Algorithm Implementation        |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_BASELINE_TYPE
{
   BASELINE_KAMA = 0,  // KAMA - Kaufman Adaptive Moving Average
   BASELINE_HMA  = 1   // HMA - Hull Moving Average
};

enum ENUM_C2_TYPE
{
   C2_MACD       = 0,  // MACD
   C2_STOCHASTIC = 1   // Stochastic
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - General                                        |
//+------------------------------------------------------------------+
input string   _gen_sep_        = "=== General Settings ===";        // ---
input int      InpMagicNumber   = 77701;       // Magic Number
input double   InpRiskPercent   = 2.0;         // Risk % of Account Balance
input int      InpSlippage      = 30;          // Max Slippage (points, 5-digit)
input bool     InpEnableLogging = true;        // Enable Journal Logging

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Baseline                                       |
//+------------------------------------------------------------------+
input string              _bl_sep_           = "=== Baseline Settings ===";           // ---
input ENUM_BASELINE_TYPE  InpBaselineType    = BASELINE_KAMA;   // Baseline Indicator
// KAMA parameters
input int                 InpKamaPeriod      = 10;     // KAMA: Period
input double              InpKamaFastMA      = 2.0;    // KAMA: Fast MA Period
input double              InpKamaSlowMA      = 30.0;   // KAMA: Slow MA Period
// HMA parameters
input int                 InpHmaPeriod       = 20;     // HMA: Period
input double              InpHmaDivisor      = 2.0;    // HMA: Divisor (speed)
input ENUM_APPLIED_PRICE  InpHmaPrice        = PRICE_CLOSE; // HMA: Applied Price

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - C1 (SSL Channel)                               |
//+------------------------------------------------------------------+
input string              _c1_sep_           = "=== C1 - SSL Channel Settings ===";  // ---
input bool                InpSSL_C1_Wicks    = false;          // C1 SSL: Use Wicks
input ENUM_MA_METHOD      InpSSL_C1_MA1Type  = MODE_SMA;      // C1 SSL: MA1 Method
input ENUM_APPLIED_PRICE  InpSSL_C1_MA1Src   = PRICE_HIGH;    // C1 SSL: MA1 Source
input int                 InpSSL_C1_MA1Len   = 25;            // C1 SSL: MA1 Length
input ENUM_MA_METHOD      InpSSL_C1_MA2Type  = MODE_SMA;      // C1 SSL: MA2 Method
input ENUM_APPLIED_PRICE  InpSSL_C1_MA2Src   = PRICE_LOW;     // C1 SSL: MA2 Source
input int                 InpSSL_C1_MA2Len   = 25;            // C1 SSL: MA2 Length

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - C2 (MACD or Stochastic)                        |
//+------------------------------------------------------------------+
input string              _c2_sep_           = "=== C2 - Confirmation 2 Settings ==="; // ---
input ENUM_C2_TYPE        InpC2Type          = C2_MACD;        // C2 Indicator
// MACD parameters
input int                 InpMacdFast        = 12;             // MACD: Fast EMA
input int                 InpMacdSlow        = 26;             // MACD: Slow EMA
input int                 InpMacdSignal      = 9;              // MACD: Signal Period
input ENUM_APPLIED_PRICE  InpMacdPrice       = PRICE_CLOSE;    // MACD: Applied Price
// Stochastic parameters
input int                 InpStochK          = 14;             // Stoch: %K Period
input int                 InpStochD          = 3;              // Stoch: %D Period
input int                 InpStochSlowing    = 3;              // Stoch: Slowing
input double              InpStochOB         = 80.0;           // Stoch: Overbought Level
input double              InpStochOS         = 20.0;           // Stoch: Oversold Level

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Volume (Waddah Attar Explosion)                |
//+------------------------------------------------------------------+
input string   _vol_sep_        = "=== Volume - WAE Settings ===";   // ---
input int      InpWAE_Sensitive = 150;    // WAE: Sensitivity
input int      InpWAE_DeadZone  = 30;     // WAE: Dead Zone (pips)
input int      InpWAE_ExplPower = 15;     // WAE: Explosion Power
input int      InpWAE_TrendPwr  = 15;     // WAE: Trend Power

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Exit (SSL Channel)                             |
//+------------------------------------------------------------------+
input string              _exit_sep_           = "=== Exit - SSL Channel Settings ===";  // ---
input bool                InpSSL_Exit_Wicks    = false;          // Exit SSL: Use Wicks
input ENUM_MA_METHOD      InpSSL_Exit_MA1Type  = MODE_SMA;      // Exit SSL: MA1 Method
input ENUM_APPLIED_PRICE  InpSSL_Exit_MA1Src   = PRICE_HIGH;    // Exit SSL: MA1 Source
input int                 InpSSL_Exit_MA1Len   = 5;             // Exit SSL: MA1 Length
input ENUM_MA_METHOD      InpSSL_Exit_MA2Type  = MODE_SMA;      // Exit SSL: MA2 Method
input ENUM_APPLIED_PRICE  InpSSL_Exit_MA2Src   = PRICE_LOW;     // Exit SSL: MA2 Source
input int                 InpSSL_Exit_MA2Len   = 5;             // Exit SSL: MA2 Length

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - ATR                                            |
//+------------------------------------------------------------------+
input string   _atr_sep_       = "=== ATR Settings ===";            // ---
input int      InpATRPeriod    = 7;        // ATR Period
input double   InpSLMultiplier = 1.5;      // Stop Loss ATR Multiplier
input double   InpTP1Multiplier= 1.0;      // Take Profit 1 ATR Multiplier (half position)
input double   InpMaxATRDist   = 1.0;      // Max Entry Distance from Baseline (ATR x)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Continuation Trade                             |
//+------------------------------------------------------------------+
input string   _cont_sep_          = "=== Continuation Trade Settings ==="; // ---
input bool     InpAllowContinuation= false;   // Allow Continuation Trades (no baseline cross needed)
// Continuation = price already on correct side of baseline,
// but C1 SSL shows a fresh direction change as the trigger.

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;           // Track last processed bar time
int      g_order1Ticket = -1;         // Ticket for Order 1 (TP order)
int      g_order2Ticket = -1;         // Ticket for Order 2 (runner)
bool     g_order1Closed = false;      // Whether Order 1 has been closed/TP hit
bool     g_movedToBE    = false;      // Whether runner SL moved to breakeven
double   g_entryPrice   = 0;         // Entry price for breakeven reference
int      g_tradeDirection = 0;       // Current trade direction: 1=buy, -1=sell, 0=none

//+------------------------------------------------------------------+
//| Custom Indicator Name Constants                                   |
//+------------------------------------------------------------------+
#define IND_KAMA     "KAMA"
#define IND_HMA      "HMA"
#define IND_SSL      "SSL_Channel"
#define IND_WAE      "Waddah_Attar_Explosion"

//+------------------------------------------------------------------+
//| Buffer Index Constants (from reading indicator source code)       |
//+------------------------------------------------------------------+
// KAMA: Buffer 0 = KAMA line value
#define KAMA_BUF_VALUE    0

// HMA: Buffer 0 = Hull main line
#define HMA_BUF_VALUE     0

// SSL Channel:
//   Buffer 0 = Hlv1 (hidden direction: +1=bullish, -1=bearish)
//   Buffer 1 = sslUp line
//   Buffer 2 = sslDown line
//   Buffer 3 = Buy arrow signal
//   Buffer 4 = Sell arrow signal
#define SSL_BUF_HLV       0
#define SSL_BUF_UP        1
#define SSL_BUF_DOWN      2
#define SSL_BUF_BUY       3
#define SSL_BUF_SELL      4

// Waddah Attar Explosion:
//   Buffer 0 = Green histogram (bullish trend strength)
//   Buffer 1 = Red histogram (bearish trend strength)
//   Buffer 2 = Explosion line (Bollinger Band width)
//   Buffer 3 = Dead zone line
#define WAE_BUF_GREEN     0
#define WAE_BUF_RED       1
#define WAE_BUF_EXPLOSION 2
#define WAE_BUF_DEADZONE  3

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Log("NNFX Bot initialized on " + Symbol() + " " + EnumToString((ENUM_TIMEFRAMES)Period()));
   Log("Baseline: " + (InpBaselineType == BASELINE_KAMA ? "KAMA" : "HMA"));
   Log("C2: " + (InpC2Type == C2_MACD ? "MACD" : "Stochastic"));
   Log("Risk: " + DoubleToStr(InpRiskPercent, 1) + "% | SL: " + DoubleToStr(InpSLMultiplier, 1) +
       "x ATR | TP1: " + DoubleToStr(InpTP1Multiplier, 1) + "x ATR");

   // Recover state if EA is restarted with open orders
   RecoverOrderState();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Log("NNFX Bot deinitialized. Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only process on new bar open
   if(!IsNewBar())
      return;

   //--- Manage existing orders first (breakeven, exit signals, opposite baseline)
   ManageOpenTrades();

   //--- Check if we already have a position open on this pair
   if(HasOpenPosition())
      return;

   //--- Reset tracking variables when no position
   g_order1Ticket  = -1;
   g_order2Ticket  = -1;
   g_order1Closed  = false;
   g_movedToBE     = false;
   g_entryPrice    = 0;
   g_tradeDirection= 0;

   //--- Evaluate entry signals on the COMPLETED bar (index 1)
   int signal = EvaluateEntry();

   if(signal != 0)
   {
      ExecuteEntry(signal);
   }
}

//+------------------------------------------------------------------+
//| SIGNAL EVALUATION - Check all 5 NNFX conditions                  |
//+------------------------------------------------------------------+
int EvaluateEntry()
{
   int bar = 1; // Signal candle = last completed bar

   //--- 1. BASELINE DIRECTION: Did price cross baseline?
   double baselineCurr = GetBaseline(bar);
   double baselinePrev = GetBaseline(bar + 1);

   if(baselineCurr == 0 || baselinePrev == 0)
   {
      Log("Baseline value is 0, skipping.");
      return(0);
   }

   // Determine baseline direction: price above baseline = bullish, below = bearish
   int baselineDir = 0;
   if(Close[bar] > baselineCurr)
      baselineDir = 1;   // Bullish
   else if(Close[bar] < baselineCurr)
      baselineDir = -1;  // Bearish

   if(baselineDir == 0)
   {
      Log("Price at baseline, no direction. Skipping.");
      return(0);
   }

   // Check for baseline cross (price crossed from one side to the other)
   bool baselineCross = false;
   if(baselineDir == 1 && Close[bar + 1] <= baselinePrev)
      baselineCross = true;  // Bullish cross
   if(baselineDir == -1 && Close[bar + 1] >= baselinePrev)
      baselineCross = true;  // Bearish cross

   // Continuation trade logic: if no fresh baseline cross, check if
   // C1 SSL had a direction change as the entry trigger instead
   bool isContinuation = false;
   if(!baselineCross)
   {
      if(!InpAllowContinuation)
         return(0);

      // For continuation: require a fresh C1 SSL direction change
      int c1Curr = GetSSL_C1_Direction(bar);
      int c1Prev = GetSSL_C1_Direction(bar + 1);
      if(c1Curr != c1Prev && c1Curr == baselineDir)
         isContinuation = true;
      else
         return(0);  // No trigger for continuation
   }

   if(isContinuation)
      Log("CONTINUATION trade. Direction: " + (baselineDir == 1 ? "BUY" : "SELL") +
          " | Close=" + DoubleToStr(Close[bar], Digits) +
          " | Baseline=" + DoubleToStr(baselineCurr, Digits));
   else
      Log("Baseline cross detected. Direction: " + (baselineDir == 1 ? "BUY" : "SELL") +
          " | Close=" + DoubleToStr(Close[bar], Digits) +
          " | Baseline=" + DoubleToStr(baselineCurr, Digits));

   //--- 2. ATR FILTER: Price must be within 1x ATR of baseline
   double atrValue = iATR(NULL, 0, InpATRPeriod, bar);
   double distFromBaseline = MathAbs(Close[bar] - baselineCurr);

   if(distFromBaseline > InpMaxATRDist * atrValue)
   {
      Log("REJECTED: Price too far from baseline. Distance=" +
          DoubleToStr(distFromBaseline / Point, 0) + " pts > " +
          DoubleToStr(InpMaxATRDist * atrValue / Point, 0) + " pts (1x ATR)");
      return(0);
   }

   //--- 3. C1 CONFIRMATION (SSL Channel)
   int c1Signal = GetSSL_C1_Direction(bar);

   if(c1Signal != baselineDir)
   {
      Log("REJECTED: C1 (SSL) disagrees. C1=" + (c1Signal == 1 ? "BUY" : "SELL") +
          " vs Baseline=" + (baselineDir == 1 ? "BUY" : "SELL"));
      return(0);
   }
   Log("C1 (SSL Channel) CONFIRMS direction.");

   //--- 4. C2 CONFIRMATION (MACD or Stochastic) - current bar OR previous bar
   bool c2Confirmed = false;
   int c2Curr = GetC2Direction(bar);
   int c2Prev = GetC2Direction(bar + 1);

   if(c2Curr == baselineDir || c2Prev == baselineDir)
      c2Confirmed = true;

   if(!c2Confirmed)
   {
      Log("REJECTED: C2 (" + (InpC2Type == C2_MACD ? "MACD" : "Stoch") +
          ") disagrees on bar " + IntegerToString(bar) + " and bar " + IntegerToString(bar + 1));
      return(0);
   }
   Log("C2 (" + (InpC2Type == C2_MACD ? "MACD" : "Stoch") + ") CONFIRMS direction.");

   //--- 5. VOLUME CONFIRMATION (Waddah Attar Explosion)
   bool volumeOK = CheckVolumeConfirmation(bar, baselineDir);

   if(!volumeOK)
   {
      Log("REJECTED: Volume (WAE) not confirmed.");
      return(0);
   }
   Log("Volume (WAE) CONFIRMS. ALL 5 CONDITIONS MET.");

   return(baselineDir);
}

//+------------------------------------------------------------------+
//| GET BASELINE VALUE                                                |
//+------------------------------------------------------------------+
double GetBaseline(int shift)
{
   double value = 0;

   if(InpBaselineType == BASELINE_KAMA)
   {
      // KAMA.ex4 params: kama_period, fast_ma_period, slow_ma_period
      // Buffer 0 = KAMA value
      value = iCustom(NULL, 0, IND_KAMA,
                       InpKamaPeriod,       // kama_period
                       InpKamaFastMA,       // fast_ma_period
                       InpKamaSlowMA,       // slow_ma_period
                       KAMA_BUF_VALUE, shift);
   }
   else if(InpBaselineType == BASELINE_HMA)
   {
      // HMA.ex4 params: inpPeriod, inpDivisor, inpPrice
      // Buffer 0 = Hull main line value
      value = iCustom(NULL, 0, IND_HMA,
                       InpHmaPeriod,        // inpPeriod
                       InpHmaDivisor,       // inpDivisor
                       InpHmaPrice,         // inpPrice
                       HMA_BUF_VALUE, shift);
   }

   return(value);
}

//+------------------------------------------------------------------+
//| GET C1 (SSL Channel) DIRECTION                                    |
//| Returns: +1 for bullish, -1 for bearish, 0 for neutral           |
//+------------------------------------------------------------------+
int GetSSL_C1_Direction(int shift)
{
   // SSL_Channel buffer 0 = Hlv1: +1 = bullish, -1 = bearish
   double hlv = iCustom(NULL, 0, IND_SSL,
                         InpSSL_C1_Wicks,      // wicks
                         InpSSL_C1_MA1Type,     // ma1_type
                         InpSSL_C1_MA1Src,      // ma1_source
                         InpSSL_C1_MA1Len,      // ma1_length
                         InpSSL_C1_MA2Type,     // ma2_type
                         InpSSL_C1_MA2Src,      // ma2_source
                         InpSSL_C1_MA2Len,      // ma2_length
                         SSL_BUF_HLV, shift);

   if(hlv > 0.5)   return(1);   // Bullish
   if(hlv < -0.5)  return(-1);  // Bearish
   return(0);
}

//+------------------------------------------------------------------+
//| GET EXIT SSL DIRECTION                                            |
//| Returns: +1 for bullish, -1 for bearish                          |
//+------------------------------------------------------------------+
int GetSSL_Exit_Direction(int shift)
{
   double hlv = iCustom(NULL, 0, IND_SSL,
                         InpSSL_Exit_Wicks,
                         InpSSL_Exit_MA1Type,
                         InpSSL_Exit_MA1Src,
                         InpSSL_Exit_MA1Len,
                         InpSSL_Exit_MA2Type,
                         InpSSL_Exit_MA2Src,
                         InpSSL_Exit_MA2Len,
                         SSL_BUF_HLV, shift);

   if(hlv > 0.5)   return(1);
   if(hlv < -0.5)  return(-1);
   return(0);
}

//+------------------------------------------------------------------+
//| GET C2 DIRECTION (MACD or Stochastic)                             |
//| Returns: +1 for bullish, -1 for bearish, 0 for neutral           |
//+------------------------------------------------------------------+
int GetC2Direction(int shift)
{
   if(InpC2Type == C2_MACD)
   {
      // Built-in MACD: main line above 0 = bullish, below 0 = bearish
      double macdMain = iMACD(NULL, 0, InpMacdFast, InpMacdSlow, InpMacdSignal,
                               InpMacdPrice, MODE_MAIN, shift);

      if(macdMain > 0) return(1);
      if(macdMain < 0) return(-1);
      return(0);
   }
   else // C2_STOCHASTIC
   {
      // Built-in Stochastic: main line above 50 = bullish, below 50 = bearish
      // Also consider overbought/oversold for confirmation
      double stochMain = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing,
                                      MODE_SMA, 0, MODE_MAIN, shift);

      if(stochMain > 50.0) return(1);
      if(stochMain < 50.0) return(-1);
      return(0);
   }
}

//+------------------------------------------------------------------+
//| CHECK VOLUME CONFIRMATION (Waddah Attar Explosion)                |
//| WAE confirms when the explosion line (buffer 2) is above the     |
//| dead zone line (buffer 3), and the trend histogram matches        |
//| the trade direction.                                              |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation(int shift, int direction)
{
   // WAE buffers:
   //   0 = Green histogram (bullish trend)
   //   1 = Red histogram (bearish trend)
   //   2 = Explosion line (BB width)
   //   3 = Dead zone line
   double greenHist  = iCustom(NULL, 0, IND_WAE,
                                InpWAE_Sensitive,
                                InpWAE_DeadZone,
                                InpWAE_ExplPower,
                                InpWAE_TrendPwr,
                                true,              // AlertWindow
                                500,               // AlertCount
                                true,              // AlertLong
                                true,              // AlertShort
                                true,              // AlertExitLong
                                true,              // AlertExitShort
                                WAE_BUF_GREEN, shift);

   double redHist    = iCustom(NULL, 0, IND_WAE,
                                InpWAE_Sensitive,
                                InpWAE_DeadZone,
                                InpWAE_ExplPower,
                                InpWAE_TrendPwr,
                                true,
                                500,
                                true,
                                true,
                                true,
                                true,
                                WAE_BUF_RED, shift);

   double explosion  = iCustom(NULL, 0, IND_WAE,
                                InpWAE_Sensitive,
                                InpWAE_DeadZone,
                                InpWAE_ExplPower,
                                InpWAE_TrendPwr,
                                true,
                                500,
                                true,
                                true,
                                true,
                                true,
                                WAE_BUF_EXPLOSION, shift);

   double deadZone   = iCustom(NULL, 0, IND_WAE,
                                InpWAE_Sensitive,
                                InpWAE_DeadZone,
                                InpWAE_ExplPower,
                                InpWAE_TrendPwr,
                                true,
                                500,
                                true,
                                true,
                                true,
                                true,
                                WAE_BUF_DEADZONE, shift);

   // Also read previous bar values for trend strength comparison
   // (matches original WAE logic: Trend1 > Trend2, Explo1 > Explo2)
   double greenHistPrev = iCustom(NULL, 0, IND_WAE,
                                   InpWAE_Sensitive, InpWAE_DeadZone,
                                   InpWAE_ExplPower, InpWAE_TrendPwr,
                                   true, 500, true, true, true, true,
                                   WAE_BUF_GREEN, shift + 1);

   double redHistPrev   = iCustom(NULL, 0, IND_WAE,
                                   InpWAE_Sensitive, InpWAE_DeadZone,
                                   InpWAE_ExplPower, InpWAE_TrendPwr,
                                   true, 500, true, true, true, true,
                                   WAE_BUF_RED, shift + 1);

   double explosionPrev = iCustom(NULL, 0, IND_WAE,
                                   InpWAE_Sensitive, InpWAE_DeadZone,
                                   InpWAE_ExplPower, InpWAE_TrendPwr,
                                   true, 500, true, true, true, true,
                                   WAE_BUF_EXPLOSION, shift + 1);

   // Volume confirmed when:
   // 1. Explosion line is above dead zone (volatility exists)
   // 2. Trend histogram matches direction and is growing vs previous bar
   bool explosionAboveDead = (explosion > deadZone);
   bool trendMatches       = false;
   bool trendIncreasing    = false;

   if(direction == 1 && greenHist > 0)
   {
      trendMatches    = true;
      trendIncreasing = (greenHist > greenHistPrev);
   }
   if(direction == -1 && redHist > 0)
   {
      trendMatches    = true;
      trendIncreasing = (redHist > redHistPrev);
   }

   bool confirmed = explosionAboveDead && trendMatches && trendIncreasing;

   Log("WAE: Green=" + DoubleToStr(greenHist, Digits) +
       " Red=" + DoubleToStr(redHist, Digits) +
       " Explosion=" + DoubleToStr(explosion, Digits) +
       " DeadZone=" + DoubleToStr(deadZone, Digits) +
       " | ExpAboveDead=" + (explosionAboveDead ? "YES" : "NO") +
       " | TrendMatch=" + (trendMatches ? "YES" : "NO") +
       " | TrendIncreasing=" + (trendIncreasing ? "YES" : "NO"));

   return(confirmed);
}

//+------------------------------------------------------------------+
//| EXECUTE ENTRY - Split into 2 orders                               |
//+------------------------------------------------------------------+
void ExecuteEntry(int direction)
{
   double atrValue = iATR(NULL, 0, InpATRPeriod, 1);

   if(atrValue <= 0)
   {
      Log("ERROR: ATR is zero. Cannot calculate SL/TP.");
      return;
   }

   //--- Calculate SL and TP in price distance
   double slDistance  = InpSLMultiplier  * atrValue;  // 1.5x ATR
   double tp1Distance = InpTP1Multiplier * atrValue;  // 1.0x ATR

   //--- Calculate lot size based on risk %
   double totalLots = CalculateLotSize(slDistance);

   if(totalLots <= 0)
   {
      Log("ERROR: Calculated lot size is zero or negative.");
      return;
   }

   //--- Split into two halves
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);

   double halfLot = MathFloor(totalLots / 2.0 / lotStep) * lotStep;
   if(halfLot < minLot)
      halfLot = minLot;
   if(halfLot > maxLot)
      halfLot = maxLot;

   //--- Determine prices
   double entryPrice, sl, tp1;
   int    orderType;
   color  arrowColor;

   if(direction == 1) // BUY
   {
      entryPrice = Ask;
      sl  = entryPrice - slDistance;
      tp1 = entryPrice + tp1Distance;
      orderType  = OP_BUY;
      arrowColor = clrDodgerBlue;
   }
   else // SELL
   {
      entryPrice = Bid;
      sl  = entryPrice + slDistance;
      tp1 = entryPrice - tp1Distance;
      orderType  = OP_SELL;
      arrowColor = clrOrangeRed;
   }

   //--- Normalize prices
   sl  = NormalizeDouble(sl,  Digits);
   tp1 = NormalizeDouble(tp1, Digits);

   Log("ENTRY SIGNAL: " + (direction == 1 ? "BUY" : "SELL") +
       " | Entry~" + DoubleToStr(entryPrice, Digits) +
       " | SL=" + DoubleToStr(sl, Digits) +
       " | TP1=" + DoubleToStr(tp1, Digits) +
       " | ATR=" + DoubleToStr(atrValue, Digits) +
       " | HalfLot=" + DoubleToStr(halfLot, 2) +
       " | TotalLot=" + DoubleToStr(totalLots, 2));

   //--- Order 1: With TP (half position - takes profit at 1x ATR)
   int ticket1 = PlaceOrder(orderType, halfLot, sl, tp1, "NNFX_TP1", arrowColor);

   if(ticket1 < 0)
   {
      Log("ERROR: Failed to place Order 1 (TP order).");
      return;
   }

   //--- Order 2: Runner (no TP, just SL - held for exit signal)
   int ticket2 = PlaceOrder(orderType, halfLot, sl, 0, "NNFX_Runner", arrowColor);

   if(ticket2 < 0)
   {
      Log("ERROR: Failed to place Order 2 (Runner). Closing Order 1.");
      CloseOrderByTicket(ticket1);
      return;
   }

   //--- Store state
   g_order1Ticket  = ticket1;
   g_order2Ticket  = ticket2;
   g_order1Closed  = false;
   g_movedToBE     = false;
   g_entryPrice    = entryPrice;
   g_tradeDirection= direction;

   Log("ORDERS PLACED: Ticket1=" + IntegerToString(ticket1) +
       " (TP) | Ticket2=" + IntegerToString(ticket2) + " (Runner)");
}

//+------------------------------------------------------------------+
//| PLACE A SINGLE ORDER                                              |
//+------------------------------------------------------------------+
int PlaceOrder(int type, double lots, double sl, double tp, string comment, color clr)
{
   double price = (type == OP_BUY) ? Ask : Bid;

   int ticket = OrderSend(Symbol(), type, lots, price, InpSlippage,
                           sl, tp, comment, InpMagicNumber, 0, clr);

   if(ticket < 0)
   {
      int err = GetLastError();
      Log("OrderSend FAILED: Error " + IntegerToString(err) + " - " + ErrorDescription(err) +
          " | Type=" + IntegerToString(type) + " Lots=" + DoubleToStr(lots, 2) +
          " Price=" + DoubleToStr(price, Digits) +
          " SL=" + DoubleToStr(sl, Digits) + " TP=" + DoubleToStr(tp, Digits));
   }

   return(ticket);
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE based on risk % and ATR stop loss              |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   if(slDistancePrice <= 0) return(0);

   double balance    = AccountBalance();
   double riskAmount = balance * (InpRiskPercent / 100.0);

   // Tick value and tick size for proper calculation
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double lotStep   = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot    = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot    = MarketInfo(Symbol(), MODE_MAXLOT);

   if(tickValue <= 0 || tickSize <= 0)
   {
      Log("ERROR: TickValue or TickSize is zero.");
      return(0);
   }

   // SL distance in ticks
   double slTicks = slDistancePrice / tickSize;

   // Risk per lot for this SL
   double riskPerLot = slTicks * tickValue;

   if(riskPerLot <= 0)
   {
      Log("ERROR: Risk per lot is zero.");
      return(0);
   }

   // Calculate raw lot size
   double lots = riskAmount / riskPerLot;

   // Round down to lot step
   lots = MathFloor(lots / lotStep) * lotStep;

   // Enforce bounds
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES                                                |
//| - Check if Order 1 (TP) was hit -> move runner to breakeven      |
//| - Check Exit SSL signal -> close runner                           |
//| - Check opposite baseline signal -> close everything              |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   if(!HasOpenPosition())
      return;

   //--- Refresh ticket tracking in case of state issues
   RefreshTicketState();

   //--- 1. Check for OPPOSITE BASELINE SIGNAL -> close all immediately
   int baselineDir = 0;
   double baselineCurr = GetBaseline(1);
   if(Close[1] > baselineCurr) baselineDir = 1;
   if(Close[1] < baselineCurr) baselineDir = -1;

   // Check for a fresh cross in the opposite direction
   double baselinePrev = GetBaseline(2);
   bool oppositeCross = false;
   if(g_tradeDirection == 1 && baselineDir == -1 && Close[2] >= baselinePrev)
      oppositeCross = true;
   if(g_tradeDirection == -1 && baselineDir == 1 && Close[2] <= baselinePrev)
      oppositeCross = true;

   if(oppositeCross)
   {
      Log("OPPOSITE BASELINE CROSS detected! Closing ALL orders.");
      CloseAllMyOrders();
      return;
   }

   //--- 2. Check if Order 1 (TP order) was closed (TP hit)
   if(!g_order1Closed && g_order1Ticket > 0)
   {
      if(!IsOrderOpen(g_order1Ticket))
      {
         g_order1Closed = true;
         Log("Order 1 (TP) closed (likely TP hit). Ticket=" + IntegerToString(g_order1Ticket));

         //--- Move Order 2 SL to breakeven
         if(g_order2Ticket > 0 && IsOrderOpen(g_order2Ticket))
         {
            MoveToBreakeven(g_order2Ticket);
         }
      }
   }

   //--- 3. Check EXIT SSL signal -> close runner (Order 2)
   if(g_order2Ticket > 0 && IsOrderOpen(g_order2Ticket))
   {
      int exitSSLDir = GetSSL_Exit_Direction(1);

      // SSL flip against our trade direction = exit
      if(g_tradeDirection == 1 && exitSSLDir == -1)
      {
         Log("EXIT SIGNAL: SSL flipped bearish while in BUY. Closing runner.");
         CloseOrderByTicket(g_order2Ticket);
      }
      else if(g_tradeDirection == -1 && exitSSLDir == 1)
      {
         Log("EXIT SIGNAL: SSL flipped bullish while in SELL. Closing runner.");
         CloseOrderByTicket(g_order2Ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| MOVE STOP LOSS TO BREAKEVEN                                       |
//+------------------------------------------------------------------+
void MoveToBreakeven(int ticket)
{
   if(g_movedToBE) return;

   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Log("ERROR: Cannot select ticket " + IntegerToString(ticket) + " for BE move.");
      return;
   }

   double newSL = OrderOpenPrice();

   // Add a small buffer (1 point spread) to ensure breakeven is slightly positive
   // For buys, SL moves up to entry. For sells, SL moves down to entry.
   bool result = OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(newSL, Digits),
                              OrderTakeProfit(), 0, clrYellow);

   if(result)
   {
      g_movedToBE = true;
      Log("Runner SL moved to BREAKEVEN at " + DoubleToStr(newSL, Digits) +
          " | Ticket=" + IntegerToString(ticket));
   }
   else
   {
      int err = GetLastError();
      // Error 1 (no result) may occur if SL is already at or past breakeven
      if(err == ERR_NO_RESULT)
      {
         g_movedToBE = true;
         Log("Runner SL already at breakeven level.");
      }
      else
      {
         Log("ERROR: Failed to move SL to BE. Error " + IntegerToString(err) +
             " - " + ErrorDescription(err));
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK IF WE HAVE AN OPEN POSITION (our magic number, this pair)  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| CHECK IF A SPECIFIC ORDER IS STILL OPEN                           |
//+------------------------------------------------------------------+
bool IsOrderOpen(int ticket)
{
   if(ticket <= 0) return(false);

   // Check in open orders pool
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderTicket() == ticket)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| CLOSE A SPECIFIC ORDER BY TICKET                                  |
//+------------------------------------------------------------------+
bool CloseOrderByTicket(int ticket)
{
   if(ticket <= 0) return(false);

   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Log("ERROR: Cannot select ticket " + IntegerToString(ticket) + " for close.");
      return(false);
   }

   if(OrderCloseTime() != 0)
   {
      // Already closed
      return(true);
   }

   double closePrice;
   if(OrderType() == OP_BUY)
      closePrice = Bid;
   else
      closePrice = Ask;

   bool result = OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrWhite);

   if(!result)
   {
      int err = GetLastError();
      Log("ERROR: OrderClose failed for ticket " + IntegerToString(ticket) +
          " Error " + IntegerToString(err) + " - " + ErrorDescription(err));
   }
   else
   {
      Log("Order closed: Ticket=" + IntegerToString(ticket));
   }

   return(result);
}

//+------------------------------------------------------------------+
//| CLOSE ALL ORDERS belonging to this EA on this symbol              |
//+------------------------------------------------------------------+
void CloseAllMyOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;

      int ticket = OrderTicket();
      CloseOrderByTicket(ticket);
   }

   // Reset state
   g_order1Ticket   = -1;
   g_order2Ticket   = -1;
   g_order1Closed   = false;
   g_movedToBE      = false;
   g_entryPrice     = 0;
   g_tradeDirection = 0;
}

//+------------------------------------------------------------------+
//| DETECT NEW BAR                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = Time[0];

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| REFRESH TICKET STATE - recover tracking after restart             |
//+------------------------------------------------------------------+
void RefreshTicketState()
{
   // If we have no tracked tickets but have open orders, re-discover them
   if(g_order1Ticket <= 0 && g_order2Ticket <= 0)
   {
      RecoverOrderState();
   }
}

//+------------------------------------------------------------------+
//| RECOVER ORDER STATE - find our orders after EA restart            |
//+------------------------------------------------------------------+
void RecoverOrderState()
{
   int tpTicket     = -1;
   int runnerTicket = -1;
   int direction    = 0;
   double entry     = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;

      // Identify by comment
      string comment = OrderComment();
      if(StringFind(comment, "NNFX_TP1") >= 0)
         tpTicket = OrderTicket();
      else if(StringFind(comment, "NNFX_Runner") >= 0)
         runnerTicket = OrderTicket();

      // Determine direction from order type
      if(OrderType() == OP_BUY)  direction = 1;
      if(OrderType() == OP_SELL) direction = -1;
      entry = OrderOpenPrice();
   }

   if(tpTicket > 0 || runnerTicket > 0)
   {
      g_order1Ticket   = tpTicket;
      g_order2Ticket   = runnerTicket;
      g_tradeDirection = direction;
      g_entryPrice     = entry;

      // If only runner remains, TP order was already closed
      if(tpTicket <= 0 && runnerTicket > 0)
      {
         g_order1Closed = true;
         // Check if SL is at breakeven
         if(OrderSelect(runnerTicket, SELECT_BY_TICKET))
         {
            double slDiff = MathAbs(OrderStopLoss() - OrderOpenPrice());
            if(slDiff < Point * 5)  // Within 5 points of entry = already at BE
               g_movedToBE = true;
         }
      }

      Log("RECOVERED state: TP Ticket=" + IntegerToString(tpTicket) +
          " Runner Ticket=" + IntegerToString(runnerTicket) +
          " Direction=" + IntegerToString(direction));
   }
}

//+------------------------------------------------------------------+
//| LOGGING                                                           |
//+------------------------------------------------------------------+
void Log(string message)
{
   if(InpEnableLogging)
   {
      Print("[NNFX] " + Symbol() + " | " + message);
   }
}

//+------------------------------------------------------------------+
//| ERROR DESCRIPTION helper                                          |
//+------------------------------------------------------------------+
string ErrorDescription(int errorCode)
{
   switch(errorCode)
   {
      case 0:    return("No error");
      case 1:    return("No error, trade conditions not changed");
      case 2:    return("Common error");
      case 3:    return("Invalid trade parameters");
      case 4:    return("Trade server is busy");
      case 5:    return("Old version of client terminal");
      case 6:    return("No connection with trade server");
      case 7:    return("Not enough rights");
      case 8:    return("Too frequent requests");
      case 9:    return("Malfunctional trade operation");
      case 64:   return("Account disabled");
      case 65:   return("Invalid account");
      case 128:  return("Trade timeout");
      case 129:  return("Invalid price");
      case 130:  return("Invalid stops");
      case 131:  return("Invalid trade volume");
      case 132:  return("Market is closed");
      case 133:  return("Trade is disabled");
      case 134:  return("Not enough money");
      case 135:  return("Price changed");
      case 136:  return("Off quotes");
      case 137:  return("Broker is busy");
      case 138:  return("Requote");
      case 139:  return("Order is locked");
      case 140:  return("Long positions only allowed");
      case 141:  return("Too many requests");
      case 145:  return("Modification denied, order too close to market");
      case 146:  return("Trade context is busy");
      case 147:  return("Expirations are denied by broker");
      case 148:  return("Too many open/pending orders");
      case 149:  return("Hedging prohibited");
      case 150:  return("Prohibited by FIFO rules");
      default:   return("Unknown error " + IntegerToString(errorCode));
   }
}
//+------------------------------------------------------------------+
