//+------------------------------------------------------------------+
//|                                              DonchianChannel.mq4 |
//|              Donchian Channel (Price Channel) Breakout Indicator  |
//|   Formula:                                                        |
//|     Upper = Highest High over N bars                              |
//|     Lower = Lowest Low over N bars                                |
//|     Middle = (Upper + Lower) / 2                                  |
//|   Non-repainting: uses iHighest/iLowest on closed bars [i+1]     |
//|   Reference: Richard Donchian, "Turtle Trading" system            |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_label1  "Upper Band"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1
#property indicator_label2  "Middle Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  1
#property indicator_label4  "Signal (1=Up, -1=Down)"
#property indicator_type4   DRAW_NONE

//--- Input parameters (H1 defaults)
input int InpPeriod = 20;    // Channel Period
input bool InpShiftBars = true; // Use previous closed bars (non-repaint)

double UpperBuf[], MiddleBuf[], LowerBuf[], SigBuf[];

int OnInit()
{
   SetIndexBuffer(0, UpperBuf);
   SetIndexBuffer(1, MiddleBuf);
   SetIndexBuffer(2, LowerBuf);
   SetIndexBuffer(3, SigBuf);

   IndicatorSetString(INDICATOR_SHORTNAME, "Donchian(" + IntegerToString(InpPeriod) + ")");
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
   if (rates_total < InpPeriod + 2) return(0);

   int limit = rates_total - prev_calculated;
   if (prev_calculated == 0) limit = rates_total - InpPeriod - 2;

   for (int i = limit; i >= 0; i--)
   {
      // Shift by 1 to use only closed bars (prevents repainting)
      int shift = InpShiftBars ? 1 : 0;
      int startBar = i + shift;

      double highest = High[startBar];
      double lowest  = Low[startBar];

      for (int k = 0; k < InpPeriod; k++)
      {
         int idx = startBar + k;
         if (idx >= rates_total) break;
         if (High[idx] > highest) highest = High[idx];
         if (Low[idx]  < lowest)  lowest  = Low[idx];
      }

      UpperBuf[i]  = highest;
      LowerBuf[i]  = lowest;
      MiddleBuf[i] = (highest + lowest) / 2.0;

      // Signal: close above middle = bullish, below = bearish
      if (Close[i] > MiddleBuf[i])
         SigBuf[i] = 1;
      else if (Close[i] < MiddleBuf[i])
         SigBuf[i] = -1;
      else
         SigBuf[i] = (i + 1 < rates_total) ? SigBuf[i + 1] : 0;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
