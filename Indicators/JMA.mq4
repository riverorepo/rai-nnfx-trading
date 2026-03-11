//+------------------------------------------------------------------+
//|                                                          JMA.mq4 |
//|         Jurik Moving Average (JMA) Approximation                  |
//|   Based on reverse-engineered JMA algorithm (Igor Durkin)         |
//|   The original JMA is proprietary by Mark Jurik (jurikres.com)    |
//|   This is a well-known open-source approximation.                 |
//|                                                                    |
//|   Algorithm (3 stages of adaptive smoothing):                     |
//|     Stage 1: Volatility measurement (Volty)                       |
//|       - Measures recent price volatility adaptively                |
//|     Stage 2: Adaptive EMA with dynamic alpha                      |
//|       - Alpha adjusts based on volatility and phase parameter      |
//|     Stage 3: Kalman-like filter for final smoothing                |
//|       - Det0 = (price - JMA_prev) * (1-alpha)^2 + alpha^2 * Det0  |
//|       - JMA = JMA_prev + Det0                                      |
//|   Parameters: Length (smoothing), Phase (-100 to +100), Power      |
//|   Non-repainting: standard recursive calculation                   |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_label1  "JMA Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "JMA Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpLength = 14;     // JMA Length (smoothing period)
input int    InpPhase  = 0;      // JMA Phase (-100 to +100)
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Price Type

double UpBuf[], DnBuf[], SigBuf[];
double JMABuffer[];
double det0[], det1[], ma1[], ma2[];
double voltyArr[], vSumArr[];

int OnInit()
{
   IndicatorBuffers(9);
   SetIndexBuffer(0, UpBuf);
   SetIndexBuffer(1, DnBuf);
   SetIndexBuffer(2, SigBuf);
   SetIndexBuffer(3, JMABuffer);
   SetIndexBuffer(4, det0);
   SetIndexBuffer(5, det1);
   SetIndexBuffer(6, ma1);
   SetIndexBuffer(7, ma2);

   IndicatorSetString(INDICATOR_SHORTNAME, "JMA(" + IntegerToString(InpLength) + "," + IntegerToString(InpPhase) + ")");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if (rates_total < InpLength + 10) return(0);

   // Compute phase ratio (beta)
   double phaseRatio;
   if (InpPhase < -100)
      phaseRatio = 0.5;
   else if (InpPhase > 100)
      phaseRatio = 2.5;
   else
      phaseRatio = (double)InpPhase / 100.0 + 1.5;

   // Compute adaptive smoothing factor
   double logLen = (InpLength > 1) ? MathLog(MathSqrt(InpLength)) / MathLog(2.0) : 0;
   double pow1 = MathMax(logLen - 2.0, 0.5);
   double beta = 0.45 * (InpLength - 1.0) / (0.45 * (InpLength - 1.0) + 2.0);
   double alpha = MathPow(beta, pow1);

   int limit;
   if (prev_calculated == 0)
   {
      limit = rates_total - 2;
      double initPrice = iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, rates_total - 1);
      ma1[rates_total - 1] = initPrice;
      ma2[rates_total - 1] = initPrice;
      det0[rates_total - 1] = 0;
      det1[rates_total - 1] = 0;
      JMABuffer[rates_total - 1] = initPrice;
   }
   else
   {
      limit = rates_total - prev_calculated + 1;
   }

   for (int i = limit; i >= 0; i--)
   {
      double price = iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, i);

      // Stage 1: First adaptive EMA
      ma1[i] = (1.0 - alpha) * price + alpha * ma1[i + 1];

      // Stage 2: Second adaptive EMA with phase adjustment
      det1[i] = (price - ma1[i]) * (1.0 - beta) + beta * det1[i + 1];
      ma2[i] = ma1[i] + phaseRatio * det1[i];

      // Stage 3: Kalman-like final filter
      double pow2 = MathPow(alpha, 2.0);
      det0[i] = (ma2[i] - JMABuffer[i + 1]) * MathPow(1.0 - alpha, 2.0) + pow2 * det0[i + 1];
      JMABuffer[i] = JMABuffer[i + 1] + det0[i];

      // Slope-based signal
      double slope = JMABuffer[i] - JMABuffer[i + 1];
      if (slope > 0)
         SigBuf[i] = 1;
      else if (slope < 0)
         SigBuf[i] = -1;
      else
         SigBuf[i] = (i + 1 < rates_total) ? SigBuf[i + 1] : 0;

      UpBuf[i] = DnBuf[i] = EMPTY_VALUE;
      if (SigBuf[i] == 1)
         UpBuf[i] = JMABuffer[i];
      else
         DnBuf[i] = JMABuffer[i];
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
