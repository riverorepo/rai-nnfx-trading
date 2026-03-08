$mt4       = "C:\Program Files (x86)\OANDA - MetaTrader 4\terminal.exe"
$testerDir = "C:\Users\river\AppData\Roaming\MetaQuotes\Terminal\7E6C4A6F67D435CAE80890D8C1401332\tester"
$reportDir = "C:\Users\river\OneDrive\Documents\Claude\Trading\nnfx\Backtest"
$iniDir    = "C:\Users\river\OneDrive\Documents\Claude\Trading\nnfx\ini"

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
New-Item -ItemType Directory -Force -Path $iniDir    | Out-Null

$pairs = @("EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","USDCAD","NZDUSD")

function Make-Ini($pair) {
    return "[Tester]`r`n" +
           "Expert=NNFX_Bot`r`n" +
           "Symbol=$pair`r`n" +
           "Period=1440`r`n" +
           "Model=2`r`n" +
           "FromDate=2015.01.01`r`n" +
           "ToDate=2025.01.01`r`n" +
           "ForwardMode=0`r`n" +
           "Deposit=10000`r`n" +
           "Currency=USD`r`n" +
           "Leverage=50`r`n" +
           "Visual=0`r`n" +
           "ShutdownTerminal=1`r`n"
}

# MT4 reads EA inputs from <ExpertName>.ini in the tester directory.
# Format: XML-like with <inputs> section, each param has value + optimization fields.
function Make-ExpertIni() {
    return "<common>`r`n" +
           "positions=2`r`n" +
           "deposit=10000`r`n" +
           "currency=USD`r`n" +
           "fitnes=0`r`n" +
           "genetic=1`r`n" +
           "</common>`r`n" +
           "`r`n" +
           "<inputs>`r`n" +
           "_gen_sep_==== General Settings ===`r`n" +
           "InpMagicNumber=77701`r`n" +
           "InpMagicNumber,F=0`r`nInpMagicNumber,1=77701`r`nInpMagicNumber,2=0`r`nInpMagicNumber,3=0`r`n" +
           "InpRiskPercent=2.00000000`r`n" +
           "InpRiskPercent,F=0`r`nInpRiskPercent,1=2.00000000`r`nInpRiskPercent,2=0.00000000`r`nInpRiskPercent,3=0.00000000`r`n" +
           "InpSlippage=30`r`n" +
           "InpSlippage,F=0`r`nInpSlippage,1=30`r`nInpSlippage,2=0`r`nInpSlippage,3=0`r`n" +
           "InpEnableLogging=0`r`n" +
           "InpEnableLogging,F=0`r`nInpEnableLogging,1=0`r`nInpEnableLogging,2=1`r`nInpEnableLogging,3=1`r`n" +
           "_bl_sep_==== Baseline Settings ===`r`n" +
           "InpBaselineType=0`r`n" +
           "InpBaselineType,F=0`r`nInpBaselineType,1=0`r`nInpBaselineType,2=0`r`nInpBaselineType,3=0`r`n" +
           "InpKamaPeriod=10`r`n" +
           "InpKamaPeriod,F=0`r`nInpKamaPeriod,1=10`r`nInpKamaPeriod,2=0`r`nInpKamaPeriod,3=0`r`n" +
           "InpKamaFastMA=2.00000000`r`n" +
           "InpKamaFastMA,F=0`r`nInpKamaFastMA,1=2.00000000`r`nInpKamaFastMA,2=0.00000000`r`nInpKamaFastMA,3=0.00000000`r`n" +
           "InpKamaSlowMA=30.00000000`r`n" +
           "InpKamaSlowMA,F=0`r`nInpKamaSlowMA,1=30.00000000`r`nInpKamaSlowMA,2=0.00000000`r`nInpKamaSlowMA,3=0.00000000`r`n" +
           "InpHmaPeriod=20`r`n" +
           "InpHmaPeriod,F=0`r`nInpHmaPeriod,1=20`r`nInpHmaPeriod,2=0`r`nInpHmaPeriod,3=0`r`n" +
           "InpHmaDivisor=2.00000000`r`n" +
           "InpHmaDivisor,F=0`r`nInpHmaDivisor,1=2.00000000`r`nInpHmaDivisor,2=0.00000000`r`nInpHmaDivisor,3=0.00000000`r`n" +
           "InpHmaPrice=0`r`n" +
           "InpHmaPrice,F=0`r`nInpHmaPrice,1=0`r`nInpHmaPrice,2=0`r`nInpHmaPrice,3=0`r`n" +
           "_c1_sep_==== C1 - SSL Channel Settings ===`r`n" +
           "InpSSL_C1_Wicks=0`r`n" +
           "InpSSL_C1_Wicks,F=0`r`nInpSSL_C1_Wicks,1=0`r`nInpSSL_C1_Wicks,2=1`r`nInpSSL_C1_Wicks,3=1`r`n" +
           "InpSSL_C1_MA1Type=0`r`n" +
           "InpSSL_C1_MA1Type,F=0`r`nInpSSL_C1_MA1Type,1=0`r`nInpSSL_C1_MA1Type,2=0`r`nInpSSL_C1_MA1Type,3=0`r`n" +
           "InpSSL_C1_MA1Src=2`r`n" +
           "InpSSL_C1_MA1Src,F=0`r`nInpSSL_C1_MA1Src,1=0`r`nInpSSL_C1_MA1Src,2=0`r`nInpSSL_C1_MA1Src,3=0`r`n" +
           "InpSSL_C1_MA1Len=20`r`n" +
           "InpSSL_C1_MA1Len,F=0`r`nInpSSL_C1_MA1Len,1=20`r`nInpSSL_C1_MA1Len,2=0`r`nInpSSL_C1_MA1Len,3=0`r`n" +
           "InpSSL_C1_MA2Type=0`r`n" +
           "InpSSL_C1_MA2Type,F=0`r`nInpSSL_C1_MA2Type,1=0`r`nInpSSL_C1_MA2Type,2=0`r`nInpSSL_C1_MA2Type,3=0`r`n" +
           "InpSSL_C1_MA2Src=3`r`n" +
           "InpSSL_C1_MA2Src,F=0`r`nInpSSL_C1_MA2Src,1=0`r`nInpSSL_C1_MA2Src,2=0`r`nInpSSL_C1_MA2Src,3=0`r`n" +
           "InpSSL_C1_MA2Len=20`r`n" +
           "InpSSL_C1_MA2Len,F=0`r`nInpSSL_C1_MA2Len,1=20`r`nInpSSL_C1_MA2Len,2=0`r`nInpSSL_C1_MA2Len,3=0`r`n" +
           "_c2_sep_==== C2 - Confirmation 2 Settings ===`r`n" +
           "InpC2Type=1`r`n" +
           "InpC2Type,F=0`r`nInpC2Type,1=1`r`nInpC2Type,2=0`r`nInpC2Type,3=0`r`n" +
           "InpMacdFast=12`r`n" +
           "InpMacdFast,F=0`r`nInpMacdFast,1=12`r`nInpMacdFast,2=0`r`nInpMacdFast,3=0`r`n" +
           "InpMacdSlow=26`r`n" +
           "InpMacdSlow,F=0`r`nInpMacdSlow,1=26`r`nInpMacdSlow,2=0`r`nInpMacdSlow,3=0`r`n" +
           "InpMacdSignal=9`r`n" +
           "InpMacdSignal,F=0`r`nInpMacdSignal,1=9`r`nInpMacdSignal,2=0`r`nInpMacdSignal,3=0`r`n" +
           "InpMacdPrice=0`r`n" +
           "InpMacdPrice,F=0`r`nInpMacdPrice,1=0`r`nInpMacdPrice,2=0`r`nInpMacdPrice,3=0`r`n" +
           "InpStochK=14`r`n" +
           "InpStochK,F=0`r`nInpStochK,1=14`r`nInpStochK,2=0`r`nInpStochK,3=0`r`n" +
           "InpStochD=3`r`n" +
           "InpStochD,F=0`r`nInpStochD,1=3`r`nInpStochD,2=0`r`nInpStochD,3=0`r`n" +
           "InpStochSlowing=3`r`n" +
           "InpStochSlowing,F=0`r`nInpStochSlowing,1=3`r`nInpStochSlowing,2=0`r`nInpStochSlowing,3=0`r`n" +
           "InpStochOB=80.00000000`r`n" +
           "InpStochOB,F=0`r`nInpStochOB,1=80.00000000`r`nInpStochOB,2=0.00000000`r`nInpStochOB,3=0.00000000`r`n" +
           "InpStochOS=20.00000000`r`n" +
           "InpStochOS,F=0`r`nInpStochOS,1=20.00000000`r`nInpStochOS,2=0.00000000`r`nInpStochOS,3=0.00000000`r`n" +
           "_vol_sep_==== Volume - WAE Settings ===`r`n" +
           "InpWAE_Sensitive=150`r`n" +
           "InpWAE_Sensitive,F=0`r`nInpWAE_Sensitive,1=150`r`nInpWAE_Sensitive,2=0`r`nInpWAE_Sensitive,3=0`r`n" +
           "InpWAE_DeadZone=30`r`n" +
           "InpWAE_DeadZone,F=0`r`nInpWAE_DeadZone,1=30`r`nInpWAE_DeadZone,2=0`r`nInpWAE_DeadZone,3=0`r`n" +
           "InpWAE_ExplPower=15`r`n" +
           "InpWAE_ExplPower,F=0`r`nInpWAE_ExplPower,1=15`r`nInpWAE_ExplPower,2=0`r`nInpWAE_ExplPower,3=0`r`n" +
           "InpWAE_TrendPwr=15`r`n" +
           "InpWAE_TrendPwr,F=0`r`nInpWAE_TrendPwr,1=15`r`nInpWAE_TrendPwr,2=0`r`nInpWAE_TrendPwr,3=0`r`n" +
           "_exit_sep_==== Exit - SSL Channel Settings ===`r`n" +
           "InpSSL_Exit_Wicks=0`r`n" +
           "InpSSL_Exit_Wicks,F=0`r`nInpSSL_Exit_Wicks,1=0`r`nInpSSL_Exit_Wicks,2=1`r`nInpSSL_Exit_Wicks,3=1`r`n" +
           "InpSSL_Exit_MA1Type=0`r`n" +
           "InpSSL_Exit_MA1Type,F=0`r`nInpSSL_Exit_MA1Type,1=0`r`nInpSSL_Exit_MA1Type,2=0`r`nInpSSL_Exit_MA1Type,3=0`r`n" +
           "InpSSL_Exit_MA1Src=2`r`n" +
           "InpSSL_Exit_MA1Src,F=0`r`nInpSSL_Exit_MA1Src,1=0`r`nInpSSL_Exit_MA1Src,2=0`r`nInpSSL_Exit_MA1Src,3=0`r`n" +
           "InpSSL_Exit_MA1Len=20`r`n" +
           "InpSSL_Exit_MA1Len,F=0`r`nInpSSL_Exit_MA1Len,1=20`r`nInpSSL_Exit_MA1Len,2=0`r`nInpSSL_Exit_MA1Len,3=0`r`n" +
           "InpSSL_Exit_MA2Type=0`r`n" +
           "InpSSL_Exit_MA2Type,F=0`r`nInpSSL_Exit_MA2Type,1=0`r`nInpSSL_Exit_MA2Type,2=0`r`nInpSSL_Exit_MA2Type,3=0`r`n" +
           "InpSSL_Exit_MA2Src=3`r`n" +
           "InpSSL_Exit_MA2Src,F=0`r`nInpSSL_Exit_MA2Src,1=0`r`nInpSSL_Exit_MA2Src,2=0`r`nInpSSL_Exit_MA2Src,3=0`r`n" +
           "InpSSL_Exit_MA2Len=20`r`n" +
           "InpSSL_Exit_MA2Len,F=0`r`nInpSSL_Exit_MA2Len,1=20`r`nInpSSL_Exit_MA2Len,2=0`r`nInpSSL_Exit_MA2Len,3=0`r`n" +
           "_atr_sep_==== ATR Settings ===`r`n" +
           "InpATRPeriod=14`r`n" +
           "InpATRPeriod,F=0`r`nInpATRPeriod,1=14`r`nInpATRPeriod,2=0`r`nInpATRPeriod,3=0`r`n" +
           "InpSLMultiplier=1.50000000`r`n" +
           "InpSLMultiplier,F=0`r`nInpSLMultiplier,1=1.50000000`r`nInpSLMultiplier,2=0.00000000`r`nInpSLMultiplier,3=0.00000000`r`n" +
           "InpTP1Multiplier=1.00000000`r`n" +
           "InpTP1Multiplier,F=0`r`nInpTP1Multiplier,1=1.00000000`r`nInpTP1Multiplier,2=0.00000000`r`nInpTP1Multiplier,3=0.00000000`r`n" +
           "InpMaxATRDist=1.00000000`r`n" +
           "InpMaxATRDist,F=0`r`nInpMaxATRDist,1=1.00000000`r`nInpMaxATRDist,2=0.00000000`r`nInpMaxATRDist,3=0.00000000`r`n" +
           "</inputs>`r`n" +
           "`r`n" +
           "<limits>`r`n" +
           "balance_enable=0`r`nbalance=200.00`r`n" +
           "profit_enable=0`r`nprofit=10000.00`r`n" +
           "marginlevel_enable=0`r`nmarginlevel=30.00`r`n" +
           "maxdrawdown_enable=0`r`nmaxdrawdown=70.00`r`n" +
           "consecloss_enable=0`r`nconsecloss=5000.00`r`n" +
           "conseclossdeals_enable=0`r`nconseclossdeals=10.00`r`n" +
           "consecwin_enable=0`r`nconsecwin=10000.00`r`n" +
           "consecwindeals_enable=0`r`nconsecwindeals=30.00`r`n" +
           "</limits>`r`n"
}

# Write the expert inputs file once (same settings for all pairs)
$expertIniPath = "$testerDir\NNFX_Bot.ini"
Write-Host "Writing expert inputs file: $expertIniPath" -ForegroundColor Cyan
Make-ExpertIni | Set-Content -Path $expertIniPath -Encoding ASCII

foreach ($pair in $pairs) {
    Write-Host "[$pair] Creating INI..." -ForegroundColor Cyan
    $iniPath = "$iniDir\$pair.ini"
    Make-Ini $pair | Set-Content -Path $iniPath -Encoding ASCII
    Copy-Item $iniPath "$testerDir\current.ini" -Force

    # Kill any existing MT4 instance before starting (prevents single-instance conflict)
    $existing = Get-Process -Name terminal -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [$pair] Killing existing MT4 instance..." -ForegroundColor DarkYellow
        $existing | Stop-Process -Force
        Start-Sleep -Seconds 3
    }

    Write-Host "[$pair] Starting backtest..." -ForegroundColor Yellow
    $proc = Start-Process -FilePath $mt4 -ArgumentList "/config:$testerDir\current.ini" -PassThru

    $timeout = 900
    $elapsed = 0
    while (!$proc.HasExited -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        Write-Host "  [$pair] Running... ($elapsed s)" -ForegroundColor Gray
    }

    if (!$proc.HasExited) {
        Write-Host "[$pair] TIMEOUT - killing MT4" -ForegroundColor Red
        $proc.Kill()
    }

    $reportSrc = "C:\Users\river\AppData\Roaming\MetaQuotes\Terminal\7E6C4A6F67D435CAE80890D8C1401332\StrategyTester.htm"
    $reportDst = "$reportDir\$pair.htm"
    if (Test-Path $reportSrc) {
        Copy-Item $reportSrc $reportDst -Force
        Write-Host "[$pair] Report saved." -ForegroundColor Green
    } else {
        Write-Host "[$pair] No report generated." -ForegroundColor Red
    }

    Start-Sleep -Seconds 3
}

Write-Host "All backtests complete. Reports in: $reportDir" -ForegroundColor Cyan
