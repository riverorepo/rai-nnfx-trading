//+------------------------------------------------------------------+
//|                                            SqueezeMomentum.mq4   |
//|         Squeeze Momentum Indicator (LazyBear / John Carter TTM)   |
//|   Formula:                                                        |
//|     SQUEEZE DETECTION:                                             |
//|       BB_upper = SMA(close,20) + 2.0*StdDev(close,20)             |
//|       BB_lower = SMA(close,20) - 2.0*StdDev(close,20)             |
//|       KC_upper = SMA(close,20) + 1.5*ATR(20)                      |
//|       KC_lower = SMA(close,20) - 1.5*ATR(20)                      |
//|       sqzOn  = BB_lower > KC_lower AND BB_upper < KC_upper        |
//|       sqzOff = BB_lower < KC_lower AND BB_upper > KC_upper        |
//|     MOMENTUM:                                                      |
//|       DonchianMid = (HH(20) + LL(20)) / 2                        |
//|       delta = Close - (DonchianMid + SMA(close,20)) / 2           |
//|       momentum = LinearRegression(delta, 20)                       |
//|   Non-repainting: all calculations on closed bars                  |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_label1  "Momentum+"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrLime
#property indicator_width1  3
#property indicator_label2  "Momentum-"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrRed
#property indicator_width2  3
#property indicator_label3  "Squeeze On"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2
#property indicator_label4  "Squeeze Off"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2
#property indicator_label5  "Signal (1=Up, -1=Down)"
#property indicator_type5   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpBBLength     = 20;    // Bollinger Band Length
input double InpBBMult       = 2.0;   // Bollinger Band Multiplier
input int    InpKCLength     = 20;    // Keltner Channel Length
input double InpKCMult       = 1.5;   // Keltner Channel Multiplier
input int    InpMomLength    = 20;    // Momentum/LinReg Length

double MomPosBuf[], MomNegBuf[], SqzOnBuf[], SqzOffBuf[], SigBuf[];
double momBuf[], deltaBuf[];

int OnInit()
{
   IndicatorBuffers(7);
   SetIndexBuffer(0, MomPosBuf);
   SetIndexBuffer(1, MomNegBuf);
   SetIndexBuffer(2, SqzOnBuf);
   SetIndexBuffer(3, SqzOffBuf);
   SetIndexBuffer(4, SigBuf);
   SetIndexBuffer(5, momBuf);
   SetIndexBuffer(6, deltaBuf);

   SetIndexArrow(2, 158); // Small dot for squeeze on
   SetIndexArrow(3, 158); // Small dot for squeeze off

   IndicatorSetString(INDICATOR_SHORTNAME, "SqzMom(" + IntegerToString(InpBBLength) + "," + IntegerToString(InpKCLength) + ")");
   return(INIT_SUCCEEDED);
}

// Linear regression value at position 0
double LinReg(double &data[], int startIdx, int length, int totalBars)
{
   if (startIdx + length > totalBars) return(0);

   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   for (int k = 0; k < length; k++)
   {
      double x = k;
      double y = data[startIdx + k];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }
   double n = length;
   double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
   double intercept = (sumY - slope * sumX) / n;

   // Value at x=0 (most recent bar)
   return(intercept);
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
   int maxPeriod = MathMax(MathMax(InpBBLength, InpKCLength), InpMomLength);
   if (rates_total < maxPeriod * 2 + 2) return(0);

   int limit = rates_total - prev_calculated;
   if (prev_calculated == 0) limit = rates_total - maxPeriod - InpMomLength - 2;

   for (int i = limit; i >= 0; i--)
   {
      // Bollinger Bands
      double bbBasis = iMA(NULL, 0, InpBBLength, 0, MODE_SMA, PRICE_CLOSE, i);
      double bbDev   = 0;
      for (int k = 0; k < InpBBLength; k++)
      {
         double diff = Close[i + k] - bbBasis;
         bbDev += diff * diff;
      }
      bbDev = InpBBMult * MathSqrt(bbDev / InpBBLength);
      double bbUpper = bbBasis + bbDev;
      double bbLower = bbBasis - bbDev;

      // Keltner Channel
      double kcBasis = iMA(NULL, 0, InpKCLength, 0, MODE_SMA, PRICE_CLOSE, i);
      double kcRange = InpKCMult * iATR(NULL, 0, InpKCLength, i);
      double kcUpper = kcBasis + kcRange;
      double kcLower = kcBasis - kcRange;

      // Squeeze detection
      bool sqzOn  = (bbLower > kcLower) && (bbUpper < kcUpper);
      bool sqzOff = (bbLower < kcLower) && (bbUpper > kcUpper);

      // Momentum calculation
      // Donchian midline
      double highestHigh = High[i];
      double lowestLow   = Low[i];
      for (int k = 0; k < InpMomLength; k++)
      {
         if (High[i + k] > highestHigh) highestHigh = High[i + k];
         if (Low[i + k]  < lowestLow)   lowestLow   = Low[i + k];
      }
      double donchianMid = (highestHigh + lowestLow) / 2.0;
      double smaClose    = iMA(NULL, 0, InpMomLength, 0, MODE_SMA, PRICE_CLOSE, i);
      deltaBuf[i] = Close[i] - (donchianMid + smaClose) / 2.0;

      // Linear regression of delta values
      double mom = LinReg(deltaBuf, i, InpMomLength, rates_total);
      momBuf[i] = mom;

      // Visual output
      MomPosBuf[i] = MomNegBuf[i] = 0;
      if (mom >= 0)
         MomPosBuf[i] = mom;
      else
         MomNegBuf[i] = mom;

      SqzOnBuf[i] = SqzOffBuf[i] = EMPTY_VALUE;
      if (sqzOn)
         SqzOnBuf[i] = 0;
      else
         SqzOffBuf[i] = 0;

      // Signal
      if (mom > 0)
         SigBuf[i] = 1;
      else if (mom < 0)
         SigBuf[i] = -1;
      else
         SigBuf[i] = (i + 1 < rates_total) ? SigBuf[i + 1] : 0;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
