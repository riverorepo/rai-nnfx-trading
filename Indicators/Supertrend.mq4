//+------------------------------------------------------------------+
//|                                                   Supertrend.mq4 |
//|                          Non-Repainting ATR-based Trend Indicator |
//|   Formula: Upper = (H+L)/2 + Multiplier*ATR(Period)              |
//|            Lower = (H+L)/2 - Multiplier*ATR(Period)              |
//|   Uses [i+1] (previous closed bar) for ATR to avoid repainting   |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_label1  "Supertrend Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "Supertrend Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Supertrend Value"
#property indicator_type4   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpATRPeriod   = 10;    // ATR Period
input double InpMultiplier  = 3.0;   // ATR Multiplier
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Price for MA

double UpBuffer[], DnBuffer[], SignalBuffer[], ValueBuffer[];
double upperBand[], lowerBand[];

int OnInit()
{
   IndicatorBuffers(6);
   SetIndexBuffer(0, UpBuffer);
   SetIndexBuffer(1, DnBuffer);
   SetIndexBuffer(2, SignalBuffer);
   SetIndexBuffer(3, ValueBuffer);
   SetIndexBuffer(4, upperBand);
   SetIndexBuffer(5, lowerBand);

   IndicatorSetString(INDICATOR_SHORTNAME, "Supertrend(" + IntegerToString(InpATRPeriod) + "," + DoubleToString(InpMultiplier, 1) + ")");
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
   int limit = rates_total - prev_calculated;
   if (limit > rates_total - InpATRPeriod - 2) limit = rates_total - InpATRPeriod - 2;
   if (prev_calculated == 0)
   {
      // Initialize
      for (int k = rates_total - 1; k >= 0; k--)
      {
         UpBuffer[k] = DnBuffer[k] = EMPTY_VALUE;
         SignalBuffer[k] = 0;
         ValueBuffer[k] = 0;
         upperBand[k] = 0;
         lowerBand[k] = 0;
      }
      limit = rates_total - InpATRPeriod - 2;
   }

   for (int i = limit; i >= 0; i--)
   {
      // Use [i+1] for ATR to prevent repainting on current bar
      double atr = iATR(NULL, 0, InpATRPeriod, i + 1);
      double median = (High[i] + Low[i]) / 2.0;

      double up = median - InpMultiplier * atr;
      double dn = median + InpMultiplier * atr;

      // Ratchet: only move bands in favorable direction
      if (i < rates_total - InpATRPeriod - 2)
      {
         if (up > lowerBand[i + 1] && Close[i + 1] > lowerBand[i + 1])
            lowerBand[i] = up;
         else if (Close[i + 1] > lowerBand[i + 1])
            lowerBand[i] = lowerBand[i + 1];
         else
            lowerBand[i] = up;

         if (dn < upperBand[i + 1] && Close[i + 1] < upperBand[i + 1])
            upperBand[i] = dn;
         else if (Close[i + 1] < upperBand[i + 1])
            upperBand[i] = upperBand[i + 1];
         else
            upperBand[i] = dn;
      }
      else
      {
         lowerBand[i] = up;
         upperBand[i] = dn;
      }

      // Determine trend direction
      if (i < rates_total - InpATRPeriod - 2)
      {
         double prevST = (SignalBuffer[i + 1] == 1) ? lowerBand[i + 1] : upperBand[i + 1];

         if (SignalBuffer[i + 1] == -1 && Close[i] > upperBand[i + 1])
            SignalBuffer[i] = 1;
         else if (SignalBuffer[i + 1] == 1 && Close[i] < lowerBand[i + 1])
            SignalBuffer[i] = -1;
         else
            SignalBuffer[i] = SignalBuffer[i + 1];
      }
      else
      {
         SignalBuffer[i] = (Close[i] > upperBand[i]) ? 1 : -1;
      }

      // Set visual buffers
      UpBuffer[i] = DnBuffer[i] = EMPTY_VALUE;
      if (SignalBuffer[i] == 1)
      {
         UpBuffer[i] = lowerBand[i];
         ValueBuffer[i] = lowerBand[i];
      }
      else
      {
         DnBuffer[i] = upperBand[i];
         ValueBuffer[i] = upperBand[i];
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
