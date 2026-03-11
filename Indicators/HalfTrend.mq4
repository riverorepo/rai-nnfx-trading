//+------------------------------------------------------------------+
//|                                                    HalfTrend.mq4 |
//|              Non-Repainting Trend Following Indicator             |
//|   Based on TradingView HalfTrend by Alex Orekhov (everget)       |
//|   Formula:                                                        |
//|     highMA = SMA(High, Amplitude)                                 |
//|     lowMA  = SMA(Low, Amplitude)                                  |
//|     highestHigh = Highest(High, Amplitude)                        |
//|     lowestLow   = Lowest(Low, Amplitude)                          |
//|     dev = ChannelDeviation * ATR(100)                             |
//|     Trend flips up when: Low[i] > prevMax + dev                   |
//|     Trend flips down when: High[i] < prevMin - dev               |
//|   Non-repainting: uses closed bar comparisons                     |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_label1  "HalfTrend Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "HalfTrend Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "HalfTrend Value"
#property indicator_type4   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpAmplitude     = 2;     // Amplitude (SMA period for high/low)
input int    InpChannelDev    = 2;     // Channel Deviation (ATR multiplier)
input int    InpATRPeriod     = 100;   // ATR Period for deviation

double UpBuf[], DnBuf[], SigBuf[], ValBuf[];
double trendArr[], maxLowArr[], minHighArr[];

int OnInit()
{
   IndicatorBuffers(7);
   SetIndexBuffer(0, UpBuf);
   SetIndexBuffer(1, DnBuf);
   SetIndexBuffer(2, SigBuf);
   SetIndexBuffer(3, ValBuf);
   SetIndexBuffer(4, trendArr);
   SetIndexBuffer(5, maxLowArr);
   SetIndexBuffer(6, minHighArr);

   IndicatorSetString(INDICATOR_SHORTNAME, "HalfTrend(" + IntegerToString(InpAmplitude) + "," + IntegerToString(InpChannelDev) + ")");
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
   int startBar = MathMax(InpAmplitude, InpATRPeriod) + 2;
   if (rates_total < startBar) return(0);

   int limit = rates_total - prev_calculated;
   if (prev_calculated == 0)
   {
      limit = rates_total - startBar;
      ArrayInitialize(trendArr, 0);
      ArrayInitialize(maxLowArr, 0);
      ArrayInitialize(minHighArr, 0);

      // Initialize at the starting bar
      int initBar = rates_total - startBar;
      trendArr[initBar] = 0;
      maxLowArr[initBar] = Low[initBar];
      minHighArr[initBar] = High[initBar];
   }

   for (int i = limit; i >= 0; i--)
   {
      // SMA of High and Low over Amplitude bars
      double highMA = 0, lowMA = 0;
      for (int k = 0; k < InpAmplitude; k++)
      {
         highMA += High[i + k];
         lowMA  += Low[i + k];
      }
      highMA /= InpAmplitude;
      lowMA  /= InpAmplitude;

      // Highest High and Lowest Low over Amplitude*2 bars
      double highestHigh = High[i];
      double lowestLow   = Low[i];
      for (int k = 0; k < InpAmplitude * 2; k++)
      {
         if (i + k < rates_total)
         {
            if (High[i + k] > highestHigh) highestHigh = High[i + k];
            if (Low[i + k]  < lowestLow)   lowestLow   = Low[i + k];
         }
      }

      double dev = InpChannelDev * iATR(NULL, 0, InpATRPeriod, i);

      int prevTrend = (int)trendArr[i + 1];
      double prevMaxLow = maxLowArr[i + 1];
      double prevMinHigh = minHighArr[i + 1];

      // Trend detection logic
      if (prevTrend == 0)
      {
         // Uptrend
         maxLowArr[i] = MathMax(prevMaxLow, lowestLow);

         if (highMA < maxLowArr[i] && Close[i] < Low[MathMin(i + 1, rates_total - 1)])
         {
            trendArr[i] = 1; // flip to downtrend
            minHighArr[i] = highestHigh;
            maxLowArr[i] = lowestLow;
         }
         else
         {
            trendArr[i] = 0;
            minHighArr[i] = prevMinHigh;
         }
      }
      else
      {
         // Downtrend
         minHighArr[i] = MathMin(prevMinHigh, highestHigh);

         if (lowMA > minHighArr[i] && Close[i] > High[MathMin(i + 1, rates_total - 1)])
         {
            trendArr[i] = 0; // flip to uptrend
            maxLowArr[i] = lowestLow;
            minHighArr[i] = highestHigh;
         }
         else
         {
            trendArr[i] = 1;
            maxLowArr[i] = prevMaxLow;
         }
      }

      // Set output values
      double htValue;
      if (trendArr[i] == 0) // uptrend
      {
         htValue = maxLowArr[i];
         SigBuf[i] = 1;
      }
      else // downtrend
      {
         htValue = minHighArr[i];
         SigBuf[i] = -1;
      }

      ValBuf[i] = htValue;
      UpBuf[i] = DnBuf[i] = EMPTY_VALUE;
      if (SigBuf[i] == 1)
         UpBuf[i] = htValue;
      else
         DnBuf[i] = htValue;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
