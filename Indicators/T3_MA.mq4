//+------------------------------------------------------------------+
//|                                                        T3_MA.mq4 |
//|              T3 Moving Average by Tim Tillson (S&C, Jan 1998)     |
//|   Formula:                                                        |
//|     GD(n,v) = EMA(n) * (1+v) - EMA(EMA(n)) * v                   |
//|     T3 = GD(GD(GD(n)))  (triple application of generalized DEMA) |
//|   Expanded: T3 = c1*e6 + c2*e5 + c3*e4 + c4*e3                  |
//|     where e1..e6 are sequential EMAs of the price                 |
//|     c1 = -v^3                                                     |
//|     c2 = 3*v^2 + 3*v^3                                            |
//|     c3 = -6*v^2 - 3*v - 3*v^3                                     |
//|     c4 = 1 + 3*v + v^3 + 3*v^2                                    |
//|     v = volume factor (default 0.7)                                |
//|   Non-repainting: standard EMA calculations                       |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_label1  "T3 Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "T3 Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpPeriod       = 8;       // T3 Period
input double InpVolumeFactor = 0.7;     // Volume Factor (0.0-1.0)
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Price Type

double UpBuf[], DnBuf[], SigBuf[];
double e1[], e2[], e3[], e4[], e5[], e6[], t3val[];

int OnInit()
{
   IndicatorBuffers(10);
   SetIndexBuffer(0, UpBuf);
   SetIndexBuffer(1, DnBuf);
   SetIndexBuffer(2, SigBuf);
   SetIndexBuffer(3, e1);
   SetIndexBuffer(4, e2);
   SetIndexBuffer(5, e3);
   SetIndexBuffer(6, e4);
   SetIndexBuffer(7, e5);
   SetIndexBuffer(8, e6);
   SetIndexBuffer(9, t3val);

   IndicatorSetString(INDICATOR_SHORTNAME, "T3(" + IntegerToString(InpPeriod) + "," + DoubleToString(InpVolumeFactor, 1) + ")");
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
   if (rates_total < InpPeriod * 6 + 2) return(0);

   double alpha = 2.0 / (InpPeriod + 1.0);
   double v = InpVolumeFactor;

   // Coefficients
   double c1 = -v * v * v;
   double c2 = 3.0 * v * v + 3.0 * v * v * v;
   double c3 = -6.0 * v * v - 3.0 * v - 3.0 * v * v * v;
   double c4 = 1.0 + 3.0 * v + v * v * v + 3.0 * v * v;

   int limit;
   if (prev_calculated == 0)
   {
      limit = rates_total - 2;

      // Initialize EMAs at the oldest bar
      int initBar = rates_total - 1;
      double initPrice = iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, initBar);
      e1[initBar] = e2[initBar] = e3[initBar] = initPrice;
      e4[initBar] = e5[initBar] = e6[initBar] = initPrice;
      t3val[initBar] = initPrice;
   }
   else
   {
      limit = rates_total - prev_calculated + 1;
   }

   for (int i = limit; i >= 0; i--)
   {
      double price = iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, i);

      e1[i] = alpha * price      + (1.0 - alpha) * e1[i + 1];
      e2[i] = alpha * e1[i]      + (1.0 - alpha) * e2[i + 1];
      e3[i] = alpha * e2[i]      + (1.0 - alpha) * e3[i + 1];
      e4[i] = alpha * e3[i]      + (1.0 - alpha) * e4[i + 1];
      e5[i] = alpha * e4[i]      + (1.0 - alpha) * e5[i + 1];
      e6[i] = alpha * e5[i]      + (1.0 - alpha) * e6[i + 1];

      t3val[i] = c1 * e6[i] + c2 * e5[i] + c3 * e4[i] + c4 * e3[i];

      // Slope-based signal
      double slope = (i + 1 < rates_total) ? t3val[i] - t3val[i + 1] : 0;
      if (slope > 0)
         SigBuf[i] = 1;
      else if (slope < 0)
         SigBuf[i] = -1;
      else
         SigBuf[i] = (i + 1 < rates_total) ? SigBuf[i + 1] : 0;

      UpBuf[i] = DnBuf[i] = EMPTY_VALUE;
      if (SigBuf[i] == 1)
         UpBuf[i] = t3val[i];
      else
         DnBuf[i] = t3val[i];
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
