//+------------------------------------------------------------------+
//|                                                  RangeFilter.mq4 |
//|              Non-Repainting Range Filter (DW style from TV)       |
//|   Smoothed range filter for trend/range detection                 |
//|   Formula:                                                        |
//|     smoothrng = EMA(EMA(|close - close[1]|, period), 2*period-1)  |
//|                 * multiplier                                      |
//|     rngfilt: if close > prev_filt then                            |
//|       filt = max(prev_filt, close - smoothrng)                    |
//|     else filt = min(prev_filt, close + smoothrng)                 |
//|   Non-repainting: uses closed bar data only                       |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_label1  "Range Filter Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "Range Filter Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Filter Value"
#property indicator_type4   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpPeriod     = 50;     // Sampling Period
input double InpMultiplier = 3.0;    // Range Multiplier

double UpBuf[], DnBuf[], SigBuf[], ValBuf[];
double smoothRng[], rngFilt[];

int OnInit()
{
   IndicatorBuffers(6);
   SetIndexBuffer(0, UpBuf);
   SetIndexBuffer(1, DnBuf);
   SetIndexBuffer(2, SigBuf);
   SetIndexBuffer(3, ValBuf);
   SetIndexBuffer(4, smoothRng);
   SetIndexBuffer(5, rngFilt);

   IndicatorSetString(INDICATOR_SHORTNAME, "RangeFilter(" + IntegerToString(InpPeriod) + "," + DoubleToString(InpMultiplier, 1) + ")");
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
   if (rates_total < InpPeriod * 3) return(0);

   int limit = rates_total - prev_calculated;
   if (prev_calculated == 0) limit = rates_total - 1;

   // Step 1: Compute smoothed range using double EMA
   // First pass: absolute price changes
   double alpha1 = 2.0 / (InpPeriod + 1.0);
   int wper = InpPeriod * 2 - 1;
   double alpha2 = 2.0 / (wper + 1.0);

   // We need to compute from scratch for simplicity on full recalc
   if (prev_calculated == 0)
   {
      // Initialize arrays
      ArrayInitialize(smoothRng, 0);
      ArrayInitialize(rngFilt, 0);
      ArrayInitialize(SigBuf, 0);

      // Compute EMA of |close - close[1]| (first EMA)
      double ema1[];
      ArrayResize(ema1, rates_total);
      ArrayInitialize(ema1, 0);

      // Start from oldest bar
      ema1[rates_total - 1] = 0;
      for (int i = rates_total - 2; i >= 0; i--)
      {
         double absChange = MathAbs(Close[i] - Close[i + 1]);
         ema1[i] = alpha1 * absChange + (1.0 - alpha1) * ema1[i + 1];
      }

      // Second EMA (smoothing of the first)
      smoothRng[rates_total - 1] = 0;
      for (int i = rates_total - 2; i >= 0; i--)
      {
         smoothRng[i] = alpha2 * ema1[i] + (1.0 - alpha2) * smoothRng[i + 1];
         smoothRng[i] *= InpMultiplier;
      }

      ArrayFree(ema1);

      // Step 2: Compute range filter
      rngFilt[rates_total - 1] = Close[rates_total - 1];
      for (int i = rates_total - 2; i >= 0; i--)
      {
         double prevFilt = rngFilt[i + 1];
         double smrng = smoothRng[i];

         if (Close[i] > prevFilt)
         {
            rngFilt[i] = MathMax(prevFilt, Close[i] - smrng);
         }
         else
         {
            rngFilt[i] = MathMin(prevFilt, Close[i] + smrng);
         }
      }

      // Step 3: Determine signal direction
      for (int i = rates_total - 2; i >= 0; i--)
      {
         if (rngFilt[i] > rngFilt[i + 1])
            SigBuf[i] = 1;
         else if (rngFilt[i] < rngFilt[i + 1])
            SigBuf[i] = -1;
         else
            SigBuf[i] = SigBuf[i + 1];

         // Visual buffers
         ValBuf[i] = rngFilt[i];
         UpBuf[i] = DnBuf[i] = EMPTY_VALUE;
         if (SigBuf[i] == 1)
            UpBuf[i] = rngFilt[i];
         else
            DnBuf[i] = rngFilt[i];
      }
   }
   else
   {
      // Incremental update for bar 0
      for (int i = MathMin(limit, 1); i >= 0; i--)
      {
         double absChange = MathAbs(Close[i] - Close[i + 1]);

         // Approximate incremental EMA
         double prevEma1 = MathAbs(Close[i + 1] - Close[i + 2]);
         double ema1val = alpha1 * absChange + (1.0 - alpha1) * prevEma1;
         smoothRng[i] = (alpha2 * ema1val + (1.0 - alpha2) * (smoothRng[i + 1] / InpMultiplier)) * InpMultiplier;

         double prevFilt = rngFilt[i + 1];
         double smrng = smoothRng[i];
         if (Close[i] > prevFilt)
            rngFilt[i] = MathMax(prevFilt, Close[i] - smrng);
         else
            rngFilt[i] = MathMin(prevFilt, Close[i] + smrng);

         if (rngFilt[i] > rngFilt[i + 1])
            SigBuf[i] = 1;
         else if (rngFilt[i] < rngFilt[i + 1])
            SigBuf[i] = -1;
         else
            SigBuf[i] = SigBuf[i + 1];

         ValBuf[i] = rngFilt[i];
         UpBuf[i] = DnBuf[i] = EMPTY_VALUE;
         if (SigBuf[i] == 1)
            UpBuf[i] = rngFilt[i];
         else
            DnBuf[i] = rngFilt[i];
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
