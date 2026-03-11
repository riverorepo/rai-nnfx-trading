//+------------------------------------------------------------------+
//|                                              KeltnerChannel.mq4  |
//|              Keltner Channel - ATR Volatility Envelope            |
//|   Based on EarnForex implementation (Chester Keltner, 1960)       |
//|   Formula:                                                        |
//|     Middle = EMA(Close, Period)                                    |
//|     Upper  = Middle + Multiplier * ATR(ATR_Period)                 |
//|     Lower  = Middle - Multiplier * ATR(ATR_Period)                 |
//|   Modern version uses EMA + ATR (vs original SMA + range avg)     |
//|   Non-repainting: standard EMA/ATR calculations                   |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_label1  "Upper Band"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrOrangeRed
#property indicator_width1  1
#property indicator_label2  "Middle Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_DASHDOT
#property indicator_width2  1
#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrangeRed
#property indicator_width3  1
#property indicator_label4  "Signal (1=Up, -1=Down)"
#property indicator_type4   DRAW_NONE

//--- Input parameters (H1 defaults)
input int    InpMAPeriod    = 20;       // EMA Period
input int    InpATRPeriod   = 20;       // ATR Period
input double InpMultiplier  = 1.5;      // ATR Multiplier
input ENUM_MA_METHOD InpMAMethod = MODE_EMA; // MA Method
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Price Type

double UpperBuf[], MiddleBuf[], LowerBuf[], SigBuf[];

int OnInit()
{
   SetIndexBuffer(0, UpperBuf);
   SetIndexBuffer(1, MiddleBuf);
   SetIndexBuffer(2, LowerBuf);
   SetIndexBuffer(3, SigBuf);

   IndicatorSetString(INDICATOR_SHORTNAME, "Keltner(" + IntegerToString(InpMAPeriod) + "," + DoubleToString(InpMultiplier, 1) + ")");
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
   int maxPeriod = MathMax(InpMAPeriod, InpATRPeriod);
   if (rates_total < maxPeriod + 2) return(0);

   int limit = rates_total - prev_calculated;
   if (prev_calculated == 0) limit = rates_total - maxPeriod - 1;

   for (int i = limit; i >= 0; i--)
   {
      double ma  = iMA(NULL, 0, InpMAPeriod, 0, InpMAMethod, InpPrice, i);
      double atr = iATR(NULL, 0, InpATRPeriod, i);

      MiddleBuf[i] = ma;
      UpperBuf[i]  = ma + InpMultiplier * atr;
      LowerBuf[i]  = ma - InpMultiplier * atr;

      // Signal: price relative to middle and bands
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
