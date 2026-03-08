//+------------------------------------------------------------------+
//| NNFXAutoTrade.mq4                                                |
//| Alex Cercos                                                      |
//| https://www.mql5.com                                             |
//+------------------------------------------------------------------+
#property copyright "Alex Cercos"
#property version   "1.00"
#property strict

//Button identificators
#define SELL_BUTTON      "SELL"
#define BUY_BUTTON       "BUY"
#define BREAKEVEN_BUTTON "BREAKEVEN"
#define TRAILING_BUTTON  "TRAILING"
#define CLOSE_BUTTON     "CLOSE"
#define PERCENT_INPUT    "PERCENTAJE"
#define SHOW_BUTTON      "SHOW"
#define ADVANCED_BUTTON  "ADV."
#define PIPV_LABEL       "PIP VALUE"
#define ATR_LABEL        "ATR"
#define LOTS_LABEL       "LOTS"
#define COST_LABEL       "COST"
#define MAIN_BG          "Background"
#define SHOW_BG          "Show Background"
#define ADVANCED_BG      "Advanced BG"
#define ADV_STOP         "ADV STOP"
#define ADV_TAKE         "ADV TAKE"
#define ADV_DATE         "DATE BUTTON"

// ------------------------------------------------------------------ //
// OANDA MT4 SETTINGS                                                  //
// Oanda uses 5-digit pricing (pipPoints=1), micro-lots (0.01 min)    //
// ------------------------------------------------------------------ //
input int    inital_y     = 30;   // Y position in the screen
input int    initial_x    = 10;   // X position in the screen
input double initialRisk  = 2.0;  // Default risk % per trade
input int    pipPoints    = 1;    // 1 = 5-digit broker (Oanda standard)
input int    lotsDecimals = 2;    // 2 decimal lots (0.01 min for Oanda)
int          extraAccount = 0;    // Extra balance in external account

//Private variables
bool   showValues    = true;
bool   useAdvanced   = false;
bool   useDate       = true;
double risk          = 2.0;
double pipValue;
double atr;
double lots;
double lotsValue;
double advStop       = 0;
double advTakeProfit = 0;

int OnInit() {
    risk = initialRisk;
    ChartSetInteger(0, CHART_FOREGROUND, 0);

    ObjectCreate(0, MAIN_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, MAIN_BG, OBJPROP_XSIZE,      140);
    ObjectSetInteger(0, MAIN_BG, OBJPROP_YSIZE,      240);
    ObjectSetInteger(0, MAIN_BG, OBJPROP_BGCOLOR,    clrGray);
    ObjectSetInteger(0, MAIN_BG, OBJPROP_XDISTANCE,  initial_x - 5);
    ObjectSetInteger(0, MAIN_BG, OBJPROP_YDISTANCE,  inital_y - 5);

    ObjectCreate(0, "PercentText", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "PercentText", OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, "PercentText", OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, "PercentText", OBJPROP_BGCOLOR,   clrLightGray);
    ObjectSetInteger(0, "PercentText", OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, "PercentText", OBJPROP_XDISTANCE, initial_x + 20);
    ObjectSetInteger(0, "PercentText", OBJPROP_YDISTANCE, inital_y + 5);
    ObjectSetString(0,  "PercentText", OBJPROP_TEXT,      "RISK");
    ObjectSetInteger(0, "PercentText", OBJPROP_BACK,      0);

    ObjectCreate(0, PERCENT_INPUT, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, PERCENT_INPUT, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, PERCENT_INPUT, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, PERCENT_INPUT, OBJPROP_XDISTANCE, initial_x + 80);
    ObjectSetInteger(0, PERCENT_INPUT, OBJPROP_YDISTANCE, inital_y);
    ObjectSetString(0,  PERCENT_INPUT, OBJPROP_TEXT,      DoubleToStr(risk, 2));
    ObjectSetInteger(0, PERCENT_INPUT, OBJPROP_BACK,      0);

    ObjectCreate(0, SELL_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_BGCOLOR,   clrOrangeRed);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_COLOR,     clrWhite);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_XDISTANCE, initial_x);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_YDISTANCE, inital_y + 40);
    ObjectSetString(0,  SELL_BUTTON, OBJPROP_TEXT,      SELL_BUTTON);
    ObjectSetInteger(0, SELL_BUTTON, OBJPROP_BACK,      0);

    ObjectCreate(0, BUY_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_BGCOLOR,   clrAqua);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_XDISTANCE, initial_x + 80);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_YDISTANCE, inital_y + 40);
    ObjectSetString(0,  BUY_BUTTON, OBJPROP_TEXT,      BUY_BUTTON);
    ObjectSetInteger(0, BUY_BUTTON, OBJPROP_BACK,      0);

    ObjectCreate(0, BREAKEVEN_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_XSIZE,     130);
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_BGCOLOR,   clrYellowGreen);
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_XDISTANCE, initial_x);
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_YDISTANCE, inital_y + 80);
    ObjectSetString(0,  BREAKEVEN_BUTTON, OBJPROP_TEXT,      "SL to BREAKEVEN");
    ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_BACK,      0);

    ObjectCreate(0, TRAILING_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_XSIZE,     130);
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_BGCOLOR,   clrLightGray);
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_XDISTANCE, initial_x);
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_YDISTANCE, inital_y + 120);
    ObjectSetString(0,  TRAILING_BUTTON, OBJPROP_TEXT,      "TRAILING STOP");
    ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_BACK,      0);

    ObjectCreate(0, CLOSE_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_XSIZE,     130);
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_BGCOLOR,   clrDarkRed);
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_COLOR,     clrWhite);
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_XDISTANCE, initial_x);
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_YDISTANCE, inital_y + 160);
    ObjectSetString(0,  CLOSE_BUTTON, OBJPROP_TEXT,      "CLOSE ALL");
    ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_BACK,      0);

    ObjectCreate(0, SHOW_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_BGCOLOR,   clrLightGray);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_XDISTANCE, initial_x);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_YDISTANCE, inital_y + 200);
    ObjectSetString(0,  SHOW_BUTTON, OBJPROP_TEXT,      SHOW_BUTTON);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_BACK,      0);
    ObjectSetInteger(0, SHOW_BUTTON, OBJPROP_STATE,     showValues);

    ObjectCreate(0, ADVANCED_BUTTON, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_BGCOLOR,   clrLightGray);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_XDISTANCE, initial_x + 80);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_YDISTANCE, inital_y + 200);
    ObjectSetString(0,  ADVANCED_BUTTON, OBJPROP_TEXT,      ADVANCED_BUTTON);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_BACK,      0);
    ObjectSetInteger(0, ADVANCED_BUTTON, OBJPROP_STATE,     useAdvanced);

    CreateShowMenu();
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    ObjectDelete(SELL_BUTTON);
    ObjectDelete(BUY_BUTTON);
    ObjectDelete(BREAKEVEN_BUTTON);
    ObjectDelete(TRAILING_BUTTON);
    ObjectDelete(CLOSE_BUTTON);
    ObjectDelete(PERCENT_INPUT);
    ObjectDelete(SHOW_BUTTON);
    ObjectDelete(ADVANCED_BUTTON);
    ObjectDelete(MAIN_BG);
    DeleteShowMenu();
    DeleteAdvancedMenu();
    ObjectDelete("PercentText");
}

void OnTick() {
    RecalculateValues();
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam) {
    if (sparam == SELL_BUTTON) {
        Print("SELL PRESSED");
        double halfLots = NormalizeDouble(lots / 2, lotsDecimals);
        double SL, TP;
        if (useAdvanced) {
            SL = advStop       * (Point * MathPow(10, pipPoints));
            TP = advTakeProfit * (Point * MathPow(10, pipPoints));
        } else {
            SL = atr * 1.5;
            TP = atr;
        }
        int ticket = OrderSend(Symbol(), OP_SELL, halfLots,      Bid, 3, Bid + SL, Bid - TP, NULL, 16384, 0, clrNONE);
        if (ticket > 0) { if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) Print("SELL order with TP opened : ", OrderOpenPrice()); }
        else Print("Error opening SELL order with TP: ", GetLastError());

        ticket = OrderSend(Symbol(), OP_SELL, lots - halfLots, Bid, 3, Bid + SL, 0, NULL, 16384, 0, clrNONE);
        if (ticket > 0) { if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) Print("SELL order without TP opened : ", OrderOpenPrice()); }
        else Print("Error opening SELL order without TP: ", GetLastError());

        ObjectSetInteger(0, SELL_BUTTON, OBJPROP_STATE, false);
        return;
    }
    else if (sparam == BUY_BUTTON) {
        Print("BUY PRESSED");
        double halfLots = NormalizeDouble(lots / 2, lotsDecimals);
        double SL, TP;
        if (useAdvanced) {
            SL = advStop       * (Point * MathPow(10, pipPoints));
            TP = advTakeProfit * (Point * MathPow(10, pipPoints));
        } else {
            SL = atr * 1.5;
            TP = atr;
        }
        int ticket = OrderSend(Symbol(), OP_BUY, halfLots,      Ask, 3, Ask - SL, Ask + TP, NULL, 16384, 0, clrNONE);
        if (ticket > 0) { if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) Print("BUY order with TP opened : ", OrderOpenPrice()); }
        else Print("Error opening BUY order with TP: ", GetLastError());

        ticket = OrderSend(Symbol(), OP_BUY, lots - halfLots, Ask, 3, Ask - SL, 0, NULL, 16384, 0, clrNONE);
        if (ticket > 0) { if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) Print("BUY order without TP opened : ", OrderOpenPrice()); }
        else Print("Error opening BUY order without TP: ", GetLastError());

        ObjectSetInteger(0, BUY_BUTTON, OBJPROP_STATE, false);
        return;
    }
    else if (sparam == BREAKEVEN_BUTTON) {
        Print("BREAKEVEN PRESSED");
        int total = OrdersTotal();
        for (int i = total - 1; i >= 0; i--) {
            if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
            if (OrderSymbol() == Symbol()) {
                if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice(), OrderTakeProfit(), OrderExpiration(), clrNONE))
                    Print("Error modifying order: ", GetLastError());
            }
        }
        ObjectSetInteger(0, BREAKEVEN_BUTTON, OBJPROP_STATE, false);
        return;
    }
    else if (sparam == TRAILING_BUTTON) {
        Print("TRAILING STOP PRESSED");
        int total = OrdersTotal();
        for (int i = total - 1; i >= 0; i--) {
            if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
            if (OrderSymbol() == Symbol()) {
                int    candle  = iBarShift(Symbol(), 0, OrderOpenTime());
                double hour    = (OrderOpenTime() - Time[candle]) / 3600.0;
                double openAtr = (useDate && hour < 12) ? iATR(Symbol(), 0, 14, candle + 1) : iATR(Symbol(), 0, 14, candle);

                if (OrderType() == OP_BUY) {
                    double movedPrice = Close[0] - OrderOpenPrice();
                    double startMove  = useAdvanced ? advStop * (Point * MathPow(10, pipPoints)) : openAtr * 2;
                    if (movedPrice > startMove) {
                        double currentStop  = OrderStopLoss();
                        double trailingStop = useAdvanced ? Close[0] - advStop * (Point * MathPow(10, pipPoints)) : Close[0] - 2 * openAtr;
                        if (trailingStop > currentStop)
                            if (!OrderModify(OrderTicket(), OrderOpenPrice(), trailingStop, OrderTakeProfit(), OrderExpiration(), clrNONE))
                                Print("Error modifying order: ", GetLastError());
                    }
                }
                else if (OrderType() == OP_SELL) {
                    double movedPrice = OrderOpenPrice() - Close[0];
                    double startMove  = useAdvanced ? advStop * (Point * MathPow(10, pipPoints)) : openAtr * 2;
                    if (movedPrice > startMove) {
                        double currentStop  = OrderStopLoss();
                        double trailingStop = useAdvanced ? Close[0] + advStop * (Point * MathPow(10, pipPoints)) : Close[0] + 2 * openAtr;
                        if (trailingStop < currentStop)
                            if (!OrderModify(OrderTicket(), OrderOpenPrice(), trailingStop, OrderTakeProfit(), OrderExpiration(), clrNONE))
                                Print("Error modifying order: ", GetLastError());
                    }
                }
            }
        }
        ObjectSetInteger(0, TRAILING_BUTTON, OBJPROP_STATE, false);
        return;
    }
    else if (sparam == CLOSE_BUTTON) {
        Print("CLOSE ALL TRADES PRESSED");
        int total = OrdersTotal();
        for (int i = total - 1; i >= 0; i--) {
            if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
            if (OrderSymbol() == Symbol()) {
                if (OrderType() == OP_BUY) {
                    if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrNONE)) Print("Error closing order: ", GetLastError());
                }
                else if (OrderType() == OP_SELL) {
                    if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrNONE)) Print("Error closing order: ", GetLastError());
                }
            }
        }
        ObjectSetInteger(0, CLOSE_BUTTON, OBJPROP_STATE, false);
        return;
    }
    else if (sparam == PERCENT_INPUT) {
        double newRisk = NormalizeDouble(StrToDouble(ObjectGetString(0, PERCENT_INPUT, OBJPROP_TEXT)), 2);
        if (risk != newRisk) {
            risk = newRisk;
            ObjectSetString(0, PERCENT_INPUT, OBJPROP_TEXT, DoubleToStr(risk, 2));
            Print("Risk set to ", risk, "%");
            RecalculateValues();
        }
    }
    else if (sparam == SHOW_BUTTON) {
        showValues = !showValues;
        if (showValues) CreateShowMenu(); else DeleteShowMenu();
    }
    else if (sparam == ADVANCED_BUTTON) {
        useAdvanced = !useAdvanced;
        if (useAdvanced) CreateAdvancedMenu(); else DeleteAdvancedMenu();
        RecalculateValues();
    }
    else if (sparam == ADV_STOP) {
        double newStop = NormalizeDouble(StrToDouble(ObjectGetString(0, ADV_STOP, OBJPROP_TEXT)), 1);
        if (advStop != newStop) {
            advStop = newStop;
            ObjectSetString(0, ADV_STOP, OBJPROP_TEXT, DoubleToStr(advStop, 1));
            RecalculateValues();
        }
    }
    else if (sparam == ADV_TAKE) {
        double newTake = NormalizeDouble(StrToDouble(ObjectGetString(0, ADV_TAKE, OBJPROP_TEXT)), 1);
        if (advTakeProfit != newTake) {
            advTakeProfit = newTake;
            ObjectSetString(0, ADV_TAKE, OBJPROP_TEXT, DoubleToStr(advTakeProfit, 1));
        }
    }
    else if (sparam == ADV_DATE) {
        useDate = !useDate;
        RecalculateValues();
    }
}

void RecalculateValues() {
    double hour = (TimeCurrent() - Time[0]) / 3600.0;
    atr = (useDate && hour < 12) ? iATR(NULL, 0, 14, 1) : iATR(NULL, 0, 14, 0);

    double atrInPips = atr / (Point * MathPow(10, pipPoints));
    double stopLoss  = useAdvanced ? advStop : atrInPips * 1.5;
    double riskTotal = (AccountBalance() + extraAccount) * risk / 100.0;

    pipValue = (stopLoss > 0) ? riskTotal / stopLoss : riskTotal;

    string accountCurrency   = AccountCurrency();
    string currencySecondary = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT);
    double askPrice          = GetCurrencyExchange(accountCurrency, currencySecondary);
    double digits            = MathPow(10, -SymbolInfoInteger(Symbol(), SYMBOL_DIGITS) + pipPoints);

    lots      = NormalizeDouble(pipValue / (askPrice * digits * 100000), lotsDecimals);
    lotsValue = lots * askPrice * digits * 100000 * (stopLoss > 0 ? stopLoss : 1);

    if (showValues) {
        ObjectSetString(0, ATR_LABEL,  OBJPROP_TEXT, "ATR: "       + DoubleToStr(atrInPips, pipPoints));
        ObjectSetString(0, PIPV_LABEL, OBJPROP_TEXT, "PIP VALUE: " + DoubleToStr(pipValue, 2));
        ObjectSetString(0, LOTS_LABEL, OBJPROP_TEXT, "LOTS: "      + DoubleToStr(lots, lotsDecimals));
        ObjectSetString(0, COST_LABEL, OBJPROP_TEXT, "RISK: "      + DoubleToStr(lotsValue, 2) + " " + accountCurrency);
    }
}

double GetCurrencyExchange(string from, string to) {
    if (from == to) return 1;
    double exchange;
    string symbol = from + to;
    if (SymbolInfoDouble(symbol, SYMBOL_ASK, exchange)) return 1 / exchange;
    symbol = to + from;
    if (SymbolInfoDouble(symbol, SYMBOL_ASK, exchange)) return exchange;
    Print("Symbol error: ", symbol, " not found");
    return 1;
}

void CreateShowMenu() {
    ObjectCreate(0, SHOW_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, SHOW_BG, OBJPROP_XSIZE,     160);
    ObjectSetInteger(0, SHOW_BG, OBJPROP_YSIZE,     100);
    ObjectSetInteger(0, SHOW_BG, OBJPROP_BGCOLOR,   clrBlack);
    ObjectSetInteger(0, SHOW_BG, OBJPROP_XDISTANCE, initial_x - 5);
    ObjectSetInteger(0, SHOW_BG, OBJPROP_YDISTANCE, inital_y + 245);

    string labels[] = { PIPV_LABEL, ATR_LABEL, LOTS_LABEL, COST_LABEL };
    string texts[]  = { "PIP VALUE", "ATR", "LOTS", "COST" };
    for (int i = 0; i < 4; i++) {
        ObjectCreate(0, labels[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, labels[i], OBJPROP_COLOR,     clrWhite);
        ObjectSetInteger(0, labels[i], OBJPROP_XDISTANCE, initial_x + 10);
        ObjectSetInteger(0, labels[i], OBJPROP_YDISTANCE, inital_y + 255 + i * 20);
        ObjectSetString(0,  labels[i], OBJPROP_TEXT,      texts[i]);
        ObjectSetInteger(0, labels[i], OBJPROP_BACK,      0);
    }
    RecalculateValues();
}

void DeleteShowMenu() {
    ObjectDelete(SHOW_BG);
    ObjectDelete(PIPV_LABEL);
    ObjectDelete(ATR_LABEL);
    ObjectDelete(LOTS_LABEL);
    ObjectDelete(COST_LABEL);
}

void CreateAdvancedMenu() {
    if (advStop == 0)       advStop       = atr / (Point * MathPow(10, pipPoints)) * 1.5;
    if (advTakeProfit == 0) advTakeProfit = atr / (Point * MathPow(10, pipPoints));

    ObjectCreate(0, ADVANCED_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, ADVANCED_BG, OBJPROP_XSIZE,     100);
    ObjectSetInteger(0, ADVANCED_BG, OBJPROP_YSIZE,     120);
    ObjectSetInteger(0, ADVANCED_BG, OBJPROP_BGCOLOR,   clrGray);
    ObjectSetInteger(0, ADVANCED_BG, OBJPROP_XDISTANCE, initial_x + 145);
    ObjectSetInteger(0, ADVANCED_BG, OBJPROP_YDISTANCE, inital_y - 5);

    ObjectCreate(0, "ADVStopText", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "ADVStopText", OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, "ADVStopText", OBJPROP_XDISTANCE, initial_x + 160);
    ObjectSetInteger(0, "ADVStopText", OBJPROP_YDISTANCE, inital_y + 5);
    ObjectSetString(0,  "ADVStopText", OBJPROP_TEXT,      "SL");

    ObjectCreate(0, ADV_STOP, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, ADV_STOP, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, ADV_STOP, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, ADV_STOP, OBJPROP_XDISTANCE, initial_x + 190);
    ObjectSetInteger(0, ADV_STOP, OBJPROP_YDISTANCE, inital_y);
    ObjectSetString(0,  ADV_STOP, OBJPROP_TEXT,      DoubleToStr(advStop, 1));

    ObjectCreate(0, "ADVTakeText", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "ADVTakeText", OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, "ADVTakeText", OBJPROP_XDISTANCE, initial_x + 160);
    ObjectSetInteger(0, "ADVTakeText", OBJPROP_YDISTANCE, inital_y + 45);
    ObjectSetString(0,  "ADVTakeText", OBJPROP_TEXT,      "TP");

    ObjectCreate(0, ADV_TAKE, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, ADV_TAKE, OBJPROP_XSIZE,     50);
    ObjectSetInteger(0, ADV_TAKE, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, ADV_TAKE, OBJPROP_XDISTANCE, initial_x + 190);
    ObjectSetInteger(0, ADV_TAKE, OBJPROP_YDISTANCE, inital_y + 40);
    ObjectSetString(0,  ADV_TAKE, OBJPROP_TEXT,      DoubleToStr(advTakeProfit, 1));

    ObjectCreate(0, ADV_DATE, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, ADV_DATE, OBJPROP_XSIZE,     90);
    ObjectSetInteger(0, ADV_DATE, OBJPROP_YSIZE,     30);
    ObjectSetInteger(0, ADV_DATE, OBJPROP_BGCOLOR,   clrLightGray);
    ObjectSetInteger(0, ADV_DATE, OBJPROP_COLOR,     clrBlack);
    ObjectSetInteger(0, ADV_DATE, OBJPROP_XDISTANCE, initial_x + 150);
    ObjectSetInteger(0, ADV_DATE, OBJPROP_YDISTANCE, inital_y + 80);
    ObjectSetString(0,  ADV_DATE, OBJPROP_TEXT,      "USE DATE");
    ObjectSetInteger(0, ADV_DATE, OBJPROP_STATE,     useDate);
}

void DeleteAdvancedMenu() {
    ObjectDelete(ADVANCED_BG);
    ObjectDelete("ADVStopText");
    ObjectDelete(ADV_STOP);
    ObjectDelete("ADVTakeText");
    ObjectDelete(ADV_TAKE);
    ObjectDelete(ADV_DATE);
}
