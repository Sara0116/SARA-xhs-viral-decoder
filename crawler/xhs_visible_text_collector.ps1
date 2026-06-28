param(
  [Parameter(Mandatory = $true)]
  [string]$InputFile,

  [string]$OutputFile = "",
  [int]$MaxItems = 30,
  [int]$DelayMs = 5000,
  [int]$Port = 9222
)

$ErrorActionPreference = "Stop"

function Get-EdgePath {
  $candidates = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe"
  )
  foreach ($path in $candidates) {
    if (Test-Path $path) { return $path }
  }
  throw "找不到 Edge 或 Chrome。"
}

function ConvertTo-PlainText($value) {
  return ([string]$value).Replace("`r", " ").Replace("`n", " ").Trim()
}

function Import-CsvRows($path) {
  return @(Import-Csv -Path $path)
}

function Get-XlsxSharedStrings($zip) {
  $entry = $zip.GetEntry("xl/sharedStrings.xml")
  if (-not $entry) { return @() }
  $reader = New-Object System.IO.StreamReader($entry.Open())
  try {
    [xml]$xml = $reader.ReadToEnd()
  } finally {
    $reader.Close()
  }
  $strings = @()
  $items = $xml.SelectNodes("//*[local-name()='si']")
  foreach ($item in $items) {
    $texts = $item.SelectNodes(".//*[local-name()='t']") | ForEach-Object { $_.'#text' }
    $strings += (($texts -join "") -as [string])
  }
  return $strings
}

function Convert-ColumnNameToIndex($name) {
  $letters = ($name -replace "[^A-Z]", "")
  $index = 0
  foreach ($char in $letters.ToCharArray()) {
    $index = $index * 26 + ([int][char]$char - [int][char]'A' + 1)
  }
  return $index - 1
}

function Import-XlsxRows($path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
  try {
    $shared = Get-XlsxSharedStrings $zip
    $sheetEntry = $zip.GetEntry("xl/worksheets/sheet1.xml")
    if (-not $sheetEntry) { throw "只支持读取第一个工作表。请另存为 CSV 再试。" }
    $reader = New-Object System.IO.StreamReader($sheetEntry.Open())
    try {
      [xml]$sheet = $reader.ReadToEnd()
    } finally {
      $reader.Close()
    }

    $rows = @()
    foreach ($rowNode in $sheet.SelectNodes("//*[local-name()='row']")) {
      $cells = @{}
      foreach ($cell in $rowNode.SelectNodes("./*[local-name()='c']")) {
        $ref = [string]$cell.GetAttribute("r")
        $idx = Convert-ColumnNameToIndex $ref
        $type = [string]$cell.GetAttribute("t")
        $valueNode = $cell.SelectSingleNode("./*[local-name()='v']")
        $inlineNode = $cell.SelectSingleNode(".//*[local-name()='t']")
        $value = ""
        if ($type -eq "s" -and $valueNode) {
          $value = $shared[[int]$valueNode.InnerText]
        } elseif ($inlineNode) {
          $value = $inlineNode.InnerText
        } elseif ($valueNode) {
          $value = $valueNode.InnerText
        }
        $cells[$idx] = $value
      }
      $rows += ,$cells
    }

    if ($rows.Count -lt 2) { return @() }
    $headerCells = $rows[0]
    $headers = @()
    for ($i = 0; $i -lt ($headerCells.Keys | Measure-Object -Maximum).Maximum + 1; $i++) {
      $name = ConvertTo-PlainText $headerCells[$i]
      if (-not $name) { $name = "Column$($i + 1)" }
      $headers += $name
    }

    $objects = @()
    foreach ($row in $rows[1..($rows.Count - 1)]) {
      $obj = [ordered]@{}
      for ($i = 0; $i -lt $headers.Count; $i++) {
        $obj[$headers[$i]] = ConvertTo-PlainText $row[$i]
      }
      $objects += [pscustomobject]$obj
    }
    return $objects
  } finally {
    $zip.Dispose()
  }
}

function Import-InputRows($path) {
  $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
  if ($ext -eq ".csv") { return Import-CsvRows $path }
  if ($ext -eq ".xlsx") { return Import-XlsxRows $path }
  throw "采集器目前支持 .csv 和 .xlsx。"
}

function Find-Column($rows, $aliases, $mustMatchUrl) {
  if (-not $rows -or $rows.Count -eq 0) { return "" }
  $headers = $rows[0].PSObject.Properties.Name
  foreach ($header in $headers) {
    foreach ($alias in $aliases) {
      if ($header.ToLower().Contains($alias.ToLower())) { return $header }
    }
  }
  if ($mustMatchUrl) {
    foreach ($header in $headers) {
      foreach ($row in $rows) {
        if (([string]$row.$header) -match "xiaohongshu\.com|xhslink\.com") { return $header }
      }
    }
  }
  return ""
}

function Start-Browser($port) {
  try {
    Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 1 | Out-Null
    return
  } catch {}

  $edge = Get-EdgePath
  $profile = Join-Path (Get-Location) ".crawler-edge-profile"
  New-Item -ItemType Directory -Force -Path $profile | Out-Null
  $args = @(
    "--remote-debugging-port=$port",
    "--user-data-dir=$profile",
    "--no-first-run",
    "--new-window",
    "about:blank"
  )
  Start-Process -FilePath $edge -ArgumentList $args
  Start-Sleep -Seconds 3
}

function New-CdpTab($port, $url) {
  $encoded = [uri]::EscapeDataString($url)
  try {
    return Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$port/json/new?$encoded"
  } catch {
    return Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/new?$encoded"
  }
}

function Invoke-Cdp($ws, [string]$method, $params = @{}) {
  if (-not $script:CdpId) { $script:CdpId = 0 }
  $script:CdpId += 1
  $id = $script:CdpId
  $payload = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
  $segment = New-Object "System.ArraySegment[byte]" -ArgumentList @(,$bytes)
  $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()

  while ($true) {
    $buffer = New-Object byte[] 1048576
    $out = New-Object System.Collections.Generic.List[byte]
    do {
      $seg = New-Object "System.ArraySegment[byte]" -ArgumentList @(,$buffer)
      $result = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None).Result
      for ($i = 0; $i -lt $result.Count; $i++) { $out.Add($buffer[$i]) }
    } until ($result.EndOfMessage)

    $text = [System.Text.Encoding]::UTF8.GetString($out.ToArray())
    if (-not $text) { continue }
    $message = $text | ConvertFrom-Json
    if ($message.id -eq $id) { return $message }
  }
}

function Get-VisiblePageText($tab, $delayMs) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $uri = [Uri]$tab.webSocketDebuggerUrl
  $ws.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
  try {
    Invoke-Cdp $ws "Page.enable" | Out-Null
    Invoke-Cdp $ws "Runtime.enable" | Out-Null
    Start-Sleep -Milliseconds $delayMs

    $expression = @"
(() => {
  const isVisible = (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s && s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0;
  };
  const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const title = clean(document.querySelector('h1')?.innerText || document.title || '');
  const metaDescription = clean(document.querySelector('meta[name="description"]')?.content || '');
  const nodes = Array.from(document.querySelectorAll('h1,h2,h3,p,span,div,a'));
  const texts = [];
  const seen = new Set();
  for (const el of nodes) {
    if (!isVisible(el)) continue;
    const text = clean(el.innerText || el.textContent || '');
    if (text.length < 6 || text.length > 600) continue;
    if (seen.has(text)) continue;
    seen.add(text);
    texts.push(text);
    if (texts.length >= 180) break;
  }
  const visibleText = texts.join('\n');
  const needsLogin = /登录|验证码|安全验证|请先登录|扫码登录/.test(visibleText);
  return {
    final_url: location.href,
    title,
    meta_description: metaDescription,
    visible_text: visibleText,
    text_length: visibleText.length,
    needs_login: needsLogin
  };
})()
"@
    $response = Invoke-Cdp $ws "Runtime.evaluate" @{
      expression = $expression
      returnByValue = $true
      awaitPromise = $true
    }
    return $response.result.result.value
  } finally {
    try { Invoke-Cdp $ws "Page.close" | Out-Null } catch {}
    $ws.Dispose()
  }
}

if (-not (Test-Path $InputFile)) { throw "找不到输入文件：$InputFile" }
if (-not $OutputFile) {
  $outDir = Join-Path (Get-Location) "data\processed"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $OutputFile = Join-Path $outDir ("xhs_crawl_results_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$rows = Import-InputRows $InputFile
if (-not $rows -or $rows.Count -eq 0) { throw "没有读取到数据。" }

$urlColumn = Find-Column $rows @("链接", "url", "视频链接", "笔记链接") $true
$titleColumn = Find-Column $rows @("标题", "视频标题", "笔记标题", "作品标题") $false
if (-not $urlColumn) { throw "没有找到链接列。请确认 Excel 里有视频链接/笔记链接。" }

$queue = @()
foreach ($row in $rows) {
  $url = ConvertTo-PlainText $row.$urlColumn
  if ($url -match "xiaohongshu\.com|xhslink\.com") {
    $queue += [pscustomobject]@{
      url = $url
      original_title = if ($titleColumn) { ConvertTo-PlainText $row.$titleColumn } else { "" }
    }
  }
}
$queue = $queue | Select-Object -First $MaxItems
if ($queue.Count -eq 0) { throw "链接列里没有识别到小红书链接。" }

Start-Browser $Port
$results = @()
$index = 0
foreach ($item in $queue) {
  $index += 1
  Write-Host "[$index/$($queue.Count)] 打开 $($item.url)"
  try {
    $tab = New-CdpTab $Port $item.url
    $page = Get-VisiblePageText $tab $DelayMs
    $results += [pscustomobject]@{
      source = "xhs-visible-text-collector"
      url = $item.url
      final_url = $page.final_url
      title = if ($page.title) { $page.title } else { $item.original_title }
      original_title = $item.original_title
      caption = $page.visible_text
      visible_text = $page.visible_text
      meta_description = $page.meta_description
      text_length = $page.text_length
      needs_login = $page.needs_login
      collected_at = (Get-Date).ToString("s")
    }
  } catch {
    $results += [pscustomobject]@{
      source = "xhs-visible-text-collector"
      url = $item.url
      title = $item.original_title
      caption = ""
      visible_text = ""
      error = $_.Exception.Message
      collected_at = (Get-Date).ToString("s")
    }
  }
  Start-Sleep -Milliseconds 900
}

$output = [ordered]@{
  generated_at = (Get-Date).ToString("s")
  input_file = (Resolve-Path $InputFile).Path
  note = "仅采集浏览器中正常可见的页面文字；不绕过登录、验证码或权限限制。"
  items = $results
}

$json = $output | ConvertTo-Json -Depth 10
Set-Content -Path $OutputFile -Value $json -Encoding UTF8
Write-Host "完成：$OutputFile"
