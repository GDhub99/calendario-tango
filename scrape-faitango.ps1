# Scarica l'agenda di faitango.it e produce un JSON con gli eventi raggruppati per giorno.
# Uso: powershell -File scrape-faitango.ps1 [-Days 60] [-OutDir .\out]
param(
    [int]$Days = 60,
    [string]$OutDir = (Join-Path $PSScriptRoot 'out')
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$start = (Get-Date).Date
$end = $start.AddDays($Days)
$fmt = 'dd/MM/yyyy'
$from = [uri]::EscapeDataString($start.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture))
$to = [uri]::EscapeDataString($end.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture))

$months = @{ January=1; February=2; March=3; April=4; May=5; June=6; July=7; August=8; September=9; October=10; November=11; December=12 }

function ConvertFrom-Html([string]$s) {
    $t = [regex]::Replace($s, '<[^>]+>', ' ')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

$byDay = [ordered]@{}
$seen = @{}
$coords = @{}
$year = $start.Year
$lastMonth = $start.Month
$currentDate = $null
$page = 1
$total = $null

while ($true) {
    $url = "https://www.faitango.it/agenda-eventi?f%5BdT%5D%5B0%5D=$from&f%5BdT%5D%5B1%5D=$to&page=$page"
    Write-Host "Pagina $page ..."
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 120
    $html = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())

    if ($null -eq $total) {
        $m = [regex]::Match($html, 'paginationDetail">\s*(\d+)\s*di\s*(\d+)')
        if ($m.Success) { $total = [int]$m.Groups[2].Value }
    }

    # Coordinate dalla mappa
    foreach ($m in [regex]::Matches($html, '\{"coordinates":\{"lat":([-\d.]+),"lng":([-\d.]+)\},"info":".*?scheda-evento-(\d+)')) {
        $coords[$m.Groups[3].Value] = @([double]$m.Groups[1].Value, [double]$m.Groups[2].Value)
    }

    $listStart = $html.IndexOf('<div id="box-mappa"')
    $listEnd = $html.IndexOf('paginationDetail', [Math]::Max($listStart, 0))
    if ($listStart -lt 0) { break }
    if ($listEnd -lt 0) { $listEnd = $html.Length }
    $list = $html.Substring($listStart, $listEnd - $listStart)

    # Token: intestazioni di giorno e righe evento, nell'ordine in cui compaiono
    $tokens = [regex]::Matches($list, '<h1>\s*(\w+)\s+(\d+)\s+(\w+)\s*</h1>|<a name="evento-(\d+)"></a>(.*?)(?=<a name="evento-|<h1>|$)', 'Singleline')
    $count = 0
    foreach ($t in $tokens) {
        if ($t.Groups[1].Success) {
            $mon = $months[$t.Groups[3].Value]
            if ($mon -lt $lastMonth) { $year++ }
            $lastMonth = $mon
            $currentDate = '{0:D4}-{1:D2}-{2:D2}' -f $year, $mon, [int]$t.Groups[2].Value
            continue
        }
        if (-not $currentDate) { continue }
        $id = $t.Groups[4].Value
        $block = $t.Groups[5].Value
        $key = "$currentDate|$id"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $count++

        $typeM = [regex]::Match($block, 'icon-event\s+([\w-]+)"\s+title="([^"]*)"')
        $cols = [regex]::Matches($block, '<div class="col-[^"]*">(.*?)</div>', 'Singleline')
        $city = if ($cols.Count -gt 0) { ConvertFrom-Html $cols[0].Groups[1].Value } else { '' }
        $titleM = [regex]::Match($block, 'col-md-5[^"]*">\s*<a href="([^"?]+)[^"]*">(.*?)</a>', 'Singleline')
        $orgM = [regex]::Match($block, 'col-md-3 col-lg-3">\s*(?:<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>)?', 'Singleline')

        $ev = [ordered]@{
            id    = $id
            t     = (ConvertFrom-Html $titleM.Groups[2].Value)
            k     = $typeM.Groups[1].Value
            kl    = [System.Net.WebUtility]::HtmlDecode($typeM.Groups[2].Value)
            c     = $city
            o     = (ConvertFrom-Html $orgM.Groups[2].Value)
            u     = $titleM.Groups[1].Value
            f     = [bool]($cols.Count -gt 0 -and $cols[0].Groups[1].Value -match 'glyphicon-star')
        }
        if (-not $byDay.Contains($currentDate)) { $byDay[$currentDate] = New-Object System.Collections.ArrayList }
        [void]$byDay[$currentDate].Add($ev)
    }

    $hasNext = $html -match 'rel="next"'
    if (-not $hasNext -or $count -eq 0) { break }
    $page++
    Start-Sleep -Milliseconds 500
}

# Aggiunge le coordinate
foreach ($d in $byDay.Keys) {
    foreach ($ev in $byDay[$d]) {
        if ($coords.ContainsKey($ev.id)) { $ev['g'] = $coords[$ev.id] }
    }
}

$n = ($byDay.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
# Controllo di sicurezza: non sovrascrivere i dati buoni con un risultato vuoto o incompleto
if ($n -lt 100 -or ($null -ne $total -and $n -ne $total)) {
    Write-Error "Scaricamento incompleto: $n eventi letti, il sito ne dichiara $total. Dati non salvati."
    exit 1
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$result = [ordered]@{
    updated = (Get-Date).ToString('o')
    from    = $start.ToString('yyyy-MM-dd')
    to      = $end.ToString('yyyy-MM-dd')
    count   = $n
    days    = $byDay
}
$json = $result | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText((Join-Path $OutDir 'events.json'), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "Eventi: $n (dichiarati dal sito: $total) su $($byDay.Count) giorni -> $OutDir\events.json"
