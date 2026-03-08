//+------------------------------------------------------------------+
//|                                            NNFX_RepaintCheck.mq4 |
//|         Repaint detector — run in Strategy Tester (Every Tick)    |
//|         Records bar[1] values on each new bar, then checks if    |
//|         they change. Flags repainting indicators.                 |
//+------------------------------------------------------------------+
#property copyright "NNFX Bot"
#property link      ""
#property version   "1.00"
#property strict

input string   InpIndicatorName = "SSL_Channel";  // Indicator Name (.ex4)
input int      InpBuffer        = 0;               // Buffer Index to check
input int      InpParamCount    = 0;               // Number of indicator params (0-8)
input double   InpParam1        = 0;     // Param 1
input double   InpParam2        = 0;     // Param 2
input double   InpParam3        = 0;     // Param 3
input double   InpParam4        = 0;     // Param 4
input double   InpParam5        = 0;     // Param 5
input double   InpParam6        = 0;     // Param 6
input double   InpParam7        = 0;     // Param 7
input double   InpParam8        = 0;     // Param 8
input int      InpBarsToCheck   = 200;   // Bars to check before reporting

//--- Storage
datetime g_lastBarTime = 0;
double   g_prevBar1Value = 0;          // value of bar[1] when it was bar[1]
datetime g_prevBar1Time  = 0;          // time of that bar
bool     g_havePrevValue = false;
int      g_barsChecked   = 0;
int      g_repaintCount  = 0;
double   g_maxDeviation  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== NNFX Repaint Checker ===");
   Print("Indicator: ", InpIndicatorName, " | Buffer: ", InpBuffer);
   Print("Run in Strategy Tester with 'Every tick' model for accurate results.");
   Print("Will check ", InpBarsToCheck, " bars then report.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintResults();
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(Time[0] == g_lastBarTime)
      return;
   g_lastBarTime = Time[0];

   // On each new bar, bar[1] is the just-completed bar
   // First, check if the PREVIOUS bar[1] (now bar[2]) has changed
   if(g_havePrevValue)
   {
      // The bar that was bar[1] is now bar[2]
      double currentValue = GetIndicatorValue(2);

      double deviation = MathAbs(currentValue - g_prevBar1Value);

      // Allow tiny floating point tolerance
      if(deviation > 0.0000001)
      {
         g_repaintCount++;
         if(deviation > g_maxDeviation)
            g_maxDeviation = deviation;

         if(g_repaintCount <= 5) // Print first 5 instances
            Print("REPAINT DETECTED at ", TimeToStr(g_prevBar1Time),
                  " | Was: ", DoubleToStr(g_prevBar1Value, 8),
                  " | Now: ", DoubleToStr(currentValue, 8),
                  " | Deviation: ", DoubleToStr(deviation, 8));
      }

      g_barsChecked++;
   }

   // Store current bar[1] value for next comparison
   g_prevBar1Value = GetIndicatorValue(1);
   g_prevBar1Time  = Time[1];
   g_havePrevValue = true;

   // Auto-report after N bars
   if(g_barsChecked >= InpBarsToCheck)
   {
      PrintResults();
      ExpertRemove();
   }
}

//+------------------------------------------------------------------+
double GetIndicatorValue(int shift)
{
   switch(InpParamCount)
   {
      case 0:  return iCustom(NULL, 0, InpIndicatorName, InpBuffer, shift);
      case 1:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpBuffer, shift);
      case 2:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpBuffer, shift);
      case 3:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpParam3, InpBuffer, shift);
      case 4:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpParam3, InpParam4, InpBuffer, shift);
      case 5:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpBuffer, shift);
      case 6:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpParam6, InpBuffer, shift);
      case 7:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpParam6, InpParam7, InpBuffer, shift);
      case 8:  return iCustom(NULL, 0, InpIndicatorName, InpParam1, InpParam2, InpParam3, InpParam4, InpParam5, InpParam6, InpParam7, InpParam8, InpBuffer, shift);
      default: return iCustom(NULL, 0, InpIndicatorName, InpBuffer, shift);
   }
}

//+------------------------------------------------------------------+
void PrintResults()
{
   Print("========================================");
   Print("REPAINT CHECK RESULTS: ", InpIndicatorName);
   Print("Buffer: ", InpBuffer, " | Bars checked: ", g_barsChecked);
   Print("Repaint instances: ", g_repaintCount);

   if(g_repaintCount == 0)
   {
      Print("RESULT: NO REPAINTING DETECTED");
      Print("This indicator appears safe for backtesting.");
   }
   else
   {
      Print("RESULT: REPAINTING DETECTED (", g_repaintCount, " of ", g_barsChecked, " bars changed)");
      Print("Max deviation: ", DoubleToStr(g_maxDeviation, 8));
      Print("DO NOT USE this indicator for backtesting — results will be unreliable.");
   }
   Print("========================================");
}
//+------------------------------------------------------------------+
