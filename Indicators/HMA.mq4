//------------------------------------------------------------------
#property copyright   "© mladen, 2019"
#property link        "mladenfx@gmail.com"
//------------------------------------------------------------------
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_label1  "Hull"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  2
#property indicator_label2  "Hull - slope down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "Hull - slope down"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrangeRed
#property indicator_width3  2

//
//
//

input int                inpPeriod  = 20;          // Period
input double             inpDivisor = 2.0;         // Divisor ("speed")
input ENUM_APPLIED_PRICE inpPrice   = PRICE_CLOSE; // Price

double val[],valda[],valdb[],valc[];

//------------------------------------------------------------------
//
//------------------------------------------------------------------ 
//
//
//

int OnInit()
{
   IndicatorBuffers(4);
   SetIndexBuffer(0,val  ,INDICATOR_DATA);
   SetIndexBuffer(1,valda,INDICATOR_DATA);
   SetIndexBuffer(2,valdb,INDICATOR_DATA);
   SetIndexBuffer(3,valc );
      iHull.init(inpPeriod,inpDivisor);
      IndicatorSetString(INDICATOR_SHORTNAME,"Hull ("+(string)inpPeriod+","+(string)inpDivisor+")");
   return (INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { }

//
//
//

int  OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int i=rates_total-prev_calculated+1; if (i>=rates_total) i=rates_total-1; 
   
   //
   //
   //
   
   if (valc[i]==-1) iCleanPoint(i,valda,valdb);
   for (; i>=0 && !_StopFlag; i--)
   {
      val[i]   = iHull.calculate(iMA(NULL,0,1,0,MODE_SMA,inpPrice,i),rates_total-i-1,rates_total);
      valc[i]  = (i<rates_total-1) ? (val[i]>val[i+1]) ? 1 : (val[i]<val[i+1]) ? -1 : valc[i+1] : 0;
      valda[i] = valdb[i] = EMPTY_VALUE;
            if (valc[i] == -1) iPlotPoint(i,valda,valdb,val);
   }
   return(rates_total);
}


//------------------------------------------------------------------
// Custom function(s)
//------------------------------------------------------------------
//
//---
//

class CHull
{
   private :
      int    m_fullPeriod;
      int    m_halfPeriod;
      int    m_sqrtPeriod;
      int    m_arraySize;
      double m_weight1;
      double m_weight2;
      double m_weight3;
      struct sHullArrayStruct
         {
            double value;
            double value3;
            double wsum1;
            double wsum2;
            double wsum3;
            double lsum1;
            double lsum2;
            double lsum3;
         };
      sHullArrayStruct m_array[];
  
   public :
      CHull() : m_fullPeriod(1), m_halfPeriod(1), m_sqrtPeriod(1), m_arraySize(-1) {                     }
     ~CHull()                                                                      { ArrayFree(m_array); }
    
      ///
      ///
      ///
    
      bool init(int period, double divisor)
      {
            m_fullPeriod = (int)(period>1 ? period : 1);  
            m_halfPeriod = (int)(m_fullPeriod>1 ? m_fullPeriod/(divisor>1 ? divisor : 1) : 1);
            m_sqrtPeriod = (int) MathSqrt(m_fullPeriod);
            m_arraySize  = -1; m_weight1 = m_weight2 = m_weight3 = 1;
               return(true);
      }
      
      //
      //
      //
      
      double calculate( double value, int i, int bars)
      {
         if (m_arraySize<bars) { m_arraySize = ArrayResize(m_array,bars+500); if (m_arraySize<bars) return(0); }
            
            //
            //
            //
            
            m_array[i].value=value;
            if (i>m_fullPeriod)
            {
               m_array[i].wsum1 = m_array[i-1].wsum1+value*m_halfPeriod-m_array[i-1].lsum1;
               m_array[i].lsum1 = m_array[i-1].lsum1+value-m_array[i-m_halfPeriod].value;
               m_array[i].wsum2 = m_array[i-1].wsum2+value*m_fullPeriod-m_array[i-1].lsum2;
               m_array[i].lsum2 = m_array[i-1].lsum2+value-m_array[i-m_fullPeriod].value;
            }
            else
            {
               m_array[i].wsum1 = m_array[i].wsum2 =
               m_array[i].lsum1 = m_array[i].lsum2 = m_weight1 = m_weight2 = 0;
               for(int k=0, w1=m_halfPeriod, w2=m_fullPeriod; w2>0 && i>=k; k++, w1--, w2--)
               {
                  if (w1>0)
                  {
                     m_array[i].wsum1 += m_array[i-k].value*w1;
                     m_array[i].lsum1 += m_array[i-k].value;
                     m_weight1        += w1;
                  }                  
                  m_array[i].wsum2 += m_array[i-k].value*w2;
                  m_array[i].lsum2 += m_array[i-k].value;
                  m_weight2        += w2;
               }
            }
            m_array[i].value3=2.0*m_array[i].wsum1/m_weight1-m_array[i].wsum2/m_weight2;
        
            //
            //---
            //
        
            if (i>m_sqrtPeriod)
            {
               m_array[i].wsum3 = m_array[i-1].wsum3+m_array[i].value3*m_sqrtPeriod-m_array[i-1].lsum3;
               m_array[i].lsum3 = m_array[i-1].lsum3+m_array[i].value3-m_array[i-m_sqrtPeriod].value3;
            }
            else
            {  
               m_array[i].wsum3 =
               m_array[i].lsum3 = m_weight3 = 0;
               for(int k=0, w3=m_sqrtPeriod; w3>0 && i>=k; k++, w3--)
               {
                  m_array[i].wsum3 += m_array[i-k].value3*w3;
                  m_array[i].lsum3 += m_array[i-k].value3;
                  m_weight3        += w3;
               }
            }        
         return(m_array[i].wsum3/m_weight3);
      }
};
CHull iHull;

//
//
//

void iCleanPoint(int i,double& first[],double& second[])
{
   if (i>=Bars-3) return;
   if ((second[i]  != EMPTY_VALUE) && (second[i+1] != EMPTY_VALUE))
        second[i+1] = EMPTY_VALUE;
   else
      if ((first[i] != EMPTY_VALUE) && (first[i+1] != EMPTY_VALUE) && (first[i+2] == EMPTY_VALUE))
          first[i+1] = EMPTY_VALUE;
}
void iPlotPoint(int i,double& first[],double& second[],double& from[])
{
   if (i>=Bars-2) return;
   if (first[i+1] == EMPTY_VALUE)
      if (first[i+2] == EMPTY_VALUE) 
            { first[i]  = from[i];  first[i+1]  = from[i+1]; second[i] = EMPTY_VALUE; }
      else  { second[i] =  from[i]; second[i+1] = from[i+1]; first[i]  = EMPTY_VALUE; }
   else     { first[i]  = from[i];                           second[i] = EMPTY_VALUE; }
}
