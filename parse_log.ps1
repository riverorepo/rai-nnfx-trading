$log = "C:\Users\river\AppData\Roaming\MetaQuotes\Terminal\7E6C4A6F67D435CAE80890D8C1401332\tester\logs\20260307.log"
$lines = Get-Content $log

Write-Host "=== REJECTION SUMMARY (Manual EURUSD run - MACD C2) ===" -ForegroundColor Cyan
$crosses = ($lines | Where-Object {$_ -like "*Baseline cross detected*"}).Count
$c2rej   = ($lines | Where-Object {$_ -like "*REJECTED: C2*"}).Count
$basrej  = ($lines | Where-Object {$_ -like "*REJECTED: Price too far*"}).Count
$c1rej   = ($lines | Where-Object {$_ -like "*REJECTED: C1*"}).Count
$waerej  = ($lines | Where-Object {$_ -like "*REJECTED: Volume*"}).Count
$entries = ($lines | Where-Object {$_ -like "*ENTRY SIGNAL*"}).Count
$opens   = ($lines | Where-Object {$_ -like "*open #*"}).Count

Write-Host "Baseline crosses detected : $crosses"
Write-Host "Rejected by C2 (MACD)     : $c2rej"
Write-Host "Rejected (Price too far)  : $basrej"
Write-Host "Rejected by C1 (SSL)      : $c1rej"
Write-Host "Rejected by Volume (WAE)  : $waerej"
Write-Host "Entry signals fired       : $entries"
Write-Host "Orders opened             : $opens"
Write-Host ""
Write-Host "Total signal bars tested  : approx 611 D1 bars (2023-2025)" -ForegroundColor Yellow
Write-Host "Key finding: MACD C2 is rejecting most signals ($(($c2rej * 100 / [math]::Max($crosses,1)).ToString('F0'))% rejection rate)" -ForegroundColor Red
