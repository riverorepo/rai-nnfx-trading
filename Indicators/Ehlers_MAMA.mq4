//+------------------------------------------------------------------+
//|                                                  Ehlers_MAMA.mq4 |
//|         MESA Adaptive Moving Average (MAMA + FAMA) by J. Ehlers  |
//|   DSP-based indicator using Hilbert Transform Discriminator       |
//|   Formula (Ehlers, S&C Magazine Sept 2001):                       |
//|     1. Smooth price: (4*P + 3*P[1] + 2*P[2] + P[3]) / 10        |
//|     2. Hilbert Transform to extract InPhase & Quadrature          |
//|     3. Compute instantaneous phase & DeltaPhase                   |
//|     4. Alpha = FastLimit / DeltaPhase (clamped)                   |
//|     5. MAMA = alpha*Price + (1-alpha)*MAMA[1]                     |
//|     6. FAMA = 0.5*alpha*MAMA + (1-0.5*alpha)*FAMA[1]             |
//|   Cross of MAMA/FAMA = trend signal                               |
//|   Non-repainting: all calculations on closed bar data             |
//+------------------------------------------------------------------+
#property copyright "NNFX Indicator Collection"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_label1  "MAMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label2  "FAMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Signal (1=Up, -1=Down)"
#property indicator_type3   DRAW_NONE

//--- Input parameters (H1 defaults)
input double InpFastLimit = 0.5;    // Fast Limit (alpha max)
input double InpSlowLimit = 0.05;   // Slow Limit (alpha min)
input ENUM_APPLIED_PRICE InpPrice = PRICE_MEDIAN; // Price type

double MAMABuf[], FAMABuf[], SigBuf[];

// Internal arrays for Hilbert Transform computation
double Smooth[], Detrender[], Q1[], I1[], jI[], jQ[];
double I2[], Q2[], Re[], Im[], Period[], SmoothPeriod[], Phase[];

int OnInit()
{
   IndicatorBuffers(3);
   SetIndexBuffer(0, MAMABuf);
   SetIndexBuffer(1, FAMABuf);
   SetIndexBuffer(2, SigBuf);

   IndicatorSetString(INDICATOR_SHORTNAME, "MAMA(" + DoubleToString(InpFastLimit, 2) + "," + DoubleToString(InpSlowLimit, 2) + ")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ArrayFree(Smooth); ArrayFree(Detrender); ArrayFree(Q1); ArrayFree(I1);
   ArrayFree(jI); ArrayFree(jQ); ArrayFree(I2); ArrayFree(Q2);
   ArrayFree(Re); ArrayFree(Im); ArrayFree(Period); ArrayFree(SmoothPeriod); ArrayFree(Phase);
}

double GetPrice(int shift)
{
   return(iMA(NULL, 0, 1, 0, MODE_SMA, InpPrice, shift));
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
   if (rates_total < 50) return(0);

   if (prev_calculated == 0)
   {
      ArrayResize(Smooth, rates_total);
      ArrayResize(Detrender, rates_total);
      ArrayResize(Q1, rates_total);
      ArrayResize(I1, rates_total);
      ArrayResize(jI, rates_total);
      ArrayResize(jQ, rates_total);
      ArrayResize(I2, rates_total);
      ArrayResize(Q2, rates_total);
      ArrayResize(Re, rates_total);
      ArrayResize(Im, rates_total);
      ArrayResize(Period, rates_total);
      ArrayResize(SmoothPeriod, rates_total);
      ArrayResize(Phase, rates_total);

      ArrayInitialize(Smooth, 0); ArrayInitialize(Detrender, 0);
      ArrayInitialize(Q1, 0); ArrayInitialize(I1, 0);
      ArrayInitialize(jI, 0); ArrayInitialize(jQ, 0);
      ArrayInitialize(I2, 0); ArrayInitialize(Q2, 0);
      ArrayInitialize(Re, 0); ArrayInitialize(Im, 0);
      ArrayInitialize(Period, 0); ArrayInitialize(SmoothPeriod, 0);
      ArrayInitialize(Phase, 0);
      ArrayInitialize(MAMABuf, 0); ArrayInitialize(FAMABuf, 0);
   }

   int limit = (prev_calculated == 0) ? rates_total - 7 : rates_total - prev_calculated + 1;
   if (limit < 0) limit = 0;

   for (int i = limit; i >= 0; i--)
   {
      double price = GetPrice(i);

      // 1. Smooth price
      Smooth[i] = (4.0 * price + 3.0 * GetPrice(i + 1) + 2.0 * GetPrice(i + 2) + GetPrice(i + 3)) / 10.0;

      // 2. Hilbert Transform - Detrender
      double coeff = 0.0962;
      double coeff2 = 0.5769;
      double prd = (i + 6 < rates_total) ? Period[i + 1] : 6.0;
      if (prd == 0) prd = 6.0;

      double adjustedCoeff = 0.075 * prd + 0.54;

      Detrender[i] = (coeff * Smooth[i] + coeff2 * SafeGet(Smooth, i + 2, rates_total)
                     - coeff2 * SafeGet(Smooth, i + 4, rates_total) - coeff * SafeGet(Smooth, i + 6, rates_total))
                     * adjustedCoeff;

      // 3. Compute InPhase and Quadrature
      Q1[i] = (coeff * Detrender[i] + coeff2 * SafeGet(Detrender, i + 2, rates_total)
              - coeff2 * SafeGet(Detrender, i + 4, rates_total) - coeff * SafeGet(Detrender, i + 6, rates_total))
              * adjustedCoeff;
      I1[i] = SafeGet(Detrender, i + 3, rates_total);

      // 4. Advance phase by 90 degrees
      jI[i] = (coeff * I1[i] + coeff2 * SafeGet(I1, i + 2, rates_total)
              - coeff2 * SafeGet(I1, i + 4, rates_total) - coeff * SafeGet(I1, i + 6, rates_total))
              * adjustedCoeff;
      jQ[i] = (coeff * Q1[i] + coeff2 * SafeGet(Q1, i + 2, rates_total)
              - coeff2 * SafeGet(Q1, i + 4, rates_total) - coeff * SafeGet(Q1, i + 6, rates_total))
              * adjustedCoeff;

      // 5. Phasor addition for 3-bar averaging
      I2[i] = I1[i] - jQ[i];
      Q2[i] = Q1[i] + jI[i];

      // Smooth I2 and Q2
      I2[i] = 0.2 * I2[i] + 0.8 * SafeGet(I2, i + 1, rates_total);
      Q2[i] = 0.2 * Q2[i] + 0.8 * SafeGet(Q2, i + 1, rates_total);

      // 6. Homodyne discriminator
      Re[i] = I2[i] * SafeGet(I2, i + 1, rates_total) + Q2[i] * SafeGet(Q2, i + 1, rates_total);
      Im[i] = I2[i] * SafeGet(Q2, i + 1, rates_total) - Q2[i] * SafeGet(I2, i + 1, rates_total);

      Re[i] = 0.2 * Re[i] + 0.8 * SafeGet(Re, i + 1, rates_total);
      Im[i] = 0.2 * Im[i] + 0.8 * SafeGet(Im, i + 1, rates_total);

      // 7. Compute period
      if (Im[i] != 0 && Re[i] != 0)
         Period[i] = 2.0 * M_PI / MathArctan(Im[i] / Re[i]);
      else
         Period[i] = SafeGet(Period, i + 1, rates_total);

      // Clamp period
      if (Period[i] > 1.5 * SafeGet(Period, i + 1, rates_total))
         Period[i] = 1.5 * SafeGet(Period, i + 1, rates_total);
      if (Period[i] < 0.67 * SafeGet(Period, i + 1, rates_total))
         Period[i] = 0.67 * SafeGet(Period, i + 1, rates_total);
      if (Period[i] < 6)  Period[i] = 6;
      if (Period[i] > 50) Period[i] = 50;

      Period[i] = 0.2 * Period[i] + 0.8 * SafeGet(Period, i + 1, rates_total);
      SmoothPeriod[i] = 0.33 * Period[i] + 0.67 * SafeGet(SmoothPeriod, i + 1, rates_total);

      // 8. Compute phase
      if (I1[i] != 0)
         Phase[i] = MathArctan(Q1[i] / I1[i]) * (180.0 / M_PI);
      else
         Phase[i] = SafeGet(Phase, i + 1, rates_total);

      // 9. Compute DeltaPhase and alpha
      double deltaPhase = SafeGet(Phase, i + 1, rates_total) - Phase[i];
      if (deltaPhase < 1) deltaPhase = 1;

      double alpha = InpFastLimit / deltaPhase;
      if (alpha < InpSlowLimit) alpha = InpSlowLimit;
      if (alpha > InpFastLimit) alpha = InpFastLimit;

      // 10. MAMA and FAMA
      MAMABuf[i] = alpha * price + (1.0 - alpha) * SafeGet(MAMABuf, i + 1, rates_total);
      FAMABuf[i] = 0.5 * alpha * MAMABuf[i] + (1.0 - 0.5 * alpha) * SafeGet(FAMABuf, i + 1, rates_total);

      // Signal: MAMA > FAMA = bullish
      if (MAMABuf[i] > FAMABuf[i])
         SigBuf[i] = 1;
      else
         SigBuf[i] = -1;
   }

   return(rates_total);
}

double SafeGet(double &arr[], int idx, int size)
{
   if (idx >= 0 && idx < size) return(arr[idx]);
   return(0);
}
//+------------------------------------------------------------------+
