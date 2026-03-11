//+------------------------------------------------------------------+
//|                                            McGinley_Dynamic.mq4  |
//|              McGinley Dynamic Moving Average                      |
//|   by John McGinley (Journal of Technical Analysis, 1991)          |
//|   Formula:                                                        |
//|     MD[i] = MD[i-1] + (Price - MD[i-1]) /                        |
//|             (k * N * (Price / MD[i-1])^4)                         |
//|   where k = 0.6 (McGinley constant)                               |
//|         N = smoothing period                                       |
//|   The (Price/MD)^4 term auto-adjusts speed:                       |
//|     - Speeds up when price moves away from MA                      |
//|     - Slows down when price is near MA                             |
//|   Non-repainting: standard recursive calculation                   |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_label1  "McGinley Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "McGinley Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE

//--- Input parameters (H1 defaults)
// Period should be ~60% of MA period you'd otherwise use
// If MA=20, use McGinley period=12
input int    InpPeriod   = 14;          // McGinley Period
input double InpConstant = 0.6;         // McGinley Constant (k)
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Price Type

double UpBuf[], DnBuf[], SigBuf[];
double MDBuffer[];

int OnInit()
{
   IndicatorBuffers(4);
   SetIndexBuffer(0, UpBuf);
   SetIndexBuffer(1, DnBuf);
   SetIndexBuffer(2, SigBuf);
   SetIndexBuffer(3, MDBuffer);

   IndicatorSetString(INDICATOR_SHORTNAME, "McGinley(" + IntegerToString(InpPeriod) + ")");
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

   int limit;
   if (prev_calculated == 0)
   {
      limit = rates_total - 2;
      // Initialize with price at oldest bar
      MDBuffer[rates_total - 1] = iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, rates_total - 1);
   }
   else
   {
      limit = rates_total - prev_calculated + 1;
   }

   for (int i = limit; i >= 0; i--)
   {
      double price = iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, i);
      double prevMD = MDBuffer[i + 1];

      if (prevMD == 0 || prevMD == EMPTY_VALUE)
      {
         MDBuffer[i] = price;
      }
      else
      {
         double ratio = price / prevMD;
         double divisor = InpConstant * InpPeriod * MathPow(ratio, 4.0);

         // Clamp divisor to prevent division by very small numbers
         if (divisor < 1.0) divisor = 1.0;

         MDBuffer[i] = prevMD + (price - prevMD) / divisor;
      }

      // Slope-based signal
      double slope = MDBuffer[i] - MDBuffer[i + 1];
      if (slope > 0)
         SigBuf[i] = 1;
      else if (slope < 0)
         SigBuf[i] = -1;
      else
         SigBuf[i] = (i + 1 < rates_total) ? SigBuf[i + 1] : 0;

      UpBuf[i] = DnBuf[i] = EMPTY_VALUE;
      if (SigBuf[i] == 1)
         UpBuf[i] = MDBuffer[i];
      else
         DnBuf[i] = MDBuffer[i];
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
