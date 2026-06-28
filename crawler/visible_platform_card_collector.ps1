param(
  [string]$PageUrl = "",
  [string]$OutputFile = "",
  [int]$MaxItems = 80,
  [switch]$CollectDetails,
  [int]$MaxDetails = 20,
  [int]$ScrollTimes = 6,
  [int]$DelayMs = 1800,
  [int]$Port = 9223,
  [switch]$WaitForUser,
  [switch]$UseCurrentTab
)

$ErrorActionPreference = "Stop"

function Get-BrowserPath {
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

function Start-Browser($port) {
  try {
    Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 1 | Out-Null
    return
  } catch {}

  $browser = Get-BrowserPath
  $profile = Join-Path (Get-Location) ".collector-browser-profile"
  New-Item -ItemType Directory -Force -Path $profile | Out-Null
  Start-Process -FilePath $browser -ArgumentList @(
    "--remote-debugging-port=$port",
    "--user-data-dir=$profile",
    "--no-first-run",
    "--new-window",
    "about:blank"
  )
  Start-Sleep -Seconds 3
}

function Get-Tab($port, $pageUrl) {
  if ($pageUrl -and -not $UseCurrentTab) {
    $encoded = [uri]::EscapeDataString($pageUrl)
    try {
      return Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$port/json/new?$encoded"
    } catch {
      return Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/new?$encoded"
    }
  }

  $tabs = @(Invoke-RestMethod -Uri "http://127.0.0.1:$port/json")
  $tab = $tabs | Where-Object { $_.type -eq "page" -and $_.url -notmatch "about:blank|devtools://" } | Select-Object -First 1
  if (-not $tab) {
    throw "没有找到可采集的浏览器标签页。请先打开千瓜/蒲公英榜单页，或传入 -PageUrl。"
  }
  return $tab
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

function Collect-VisibleCards($tab, $scrollTimes, $delayMs, $maxItems) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  try {
    Invoke-Cdp $ws "Page.enable" | Out-Null
    Invoke-Cdp $ws "Runtime.enable" | Out-Null
    Start-Sleep -Milliseconds ($delayMs + 1200)

    for ($i = 0; $i -lt $scrollTimes; $i++) {
      Invoke-Cdp $ws "Runtime.evaluate" @{
        expression = "window.scrollBy(0, Math.max(700, Math.floor(window.innerHeight * 0.75)));"
        awaitPromise = $false
      } | Out-Null
      Start-Sleep -Milliseconds $delayMs
    }

    $expression = @"
(() => {
  const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const visible = (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 40 && r.height > 40;
  };
  const scoreText = (text) => {
    let score = 0;
    if (/互动|点赞|收藏|评论|发布|分类|达人|笔记|视频/.test(text)) score += 3;
    if (/Codex|AI|Agent|Claude|ChatGPT|工作流|技能|skill/i.test(text)) score += 3;
    if (/\d[\d,.]*\s*(点赞|收藏|评论|互动)?/.test(text)) score += 2;
    if (text.length >= 20 && text.length <= 500) score += 2;
    return score;
  };
  const bestTitle = (text) => {
    const lines = text.split(/\n| {2,}/).map(clean).filter(Boolean);
    const useful = lines.filter(x => x.length >= 6 && x.length <= 80 && !/点赞|收藏|评论|发布|暂无分类|互动量/.test(x));
    return useful[0] || lines[0] || '';
  };
  const parseNum = (label, text) => {
    const re = new RegExp('(\\\\d[\\\\d,.]*)(?:\\\\s*)' + label);
    const m1 = text.match(re);
    if (m1) return m1[1];
    const m2 = text.match(new RegExp(label + '[^\\\\d]{0,8}(\\\\d[\\\\d,.]*)'));
    if (m2) return m2[1];
    return '';
  };
  const cards = [];
  const seen = new Set();
  const normalizeUrl = (href) => {
    try { return new URL(href, location.href).href; } catch { return ''; }
  };
  const bestLink = (node) => {
    const links = [];
    let cur = node;
    for (let depth = 0; depth < 5 && cur; depth++) {
      if (cur.matches && cur.matches('a[href]')) links.push(cur.href);
      cur.querySelectorAll?.('a[href]').forEach(a => links.push(a.href));
      cur = cur.parentElement;
    }
    return links.map(normalizeUrl).find(url =>
      url &&
      !/javascript:|logout|login|register|#/.test(url) &&
      new URL(url).host === location.host
    ) || '';
  };
  const imageNodes = Array.from(document.querySelectorAll('img')).filter(visible);
  for (const img of imageNodes) {
    let node = img;
    let best = null;
    for (let depth = 0; depth < 7 && node; depth++) {
      const text = clean(node.innerText || node.textContent || '');
      const r = node.getBoundingClientRect();
      if (text.length > 12 && text.length < 900 && r.width > 120 && r.height > 120) {
        const s = scoreText(text);
        if (!best || s > best.score) best = { node, text, score: s, rect: r };
      }
      node = node.parentElement;
    }
    if (!best) continue;
    const title = bestTitle(best.text);
    const key = title + '|' + img.src;
    if (seen.has(key)) continue;
    seen.add(key);
    cards.push({
      source: 'visible-platform-card-collector',
      title,
      cover: title,
      caption: best.text,
      visible_text: best.text,
      cover_image_url: img.currentSrc || img.src || '',
      url: bestLink(best.node) || location.href,
      platform_page_url: location.href,
      final_url: location.href,
      likes: parseNum('点赞', best.text),
      collects: parseNum('收藏', best.text),
      comments: parseNum('评论', best.text),
      collected_at: new Date().toISOString()
    });
  }
  if (cards.length < 8) {
    const nodes = Array.from(document.querySelectorAll('article,li,[class*=card],[class*=item],[class*=note],[class*=list]')).filter(visible);
    for (const node of nodes) {
      const text = clean(node.innerText || node.textContent || '');
      if (scoreText(text) < 4) continue;
      const title = bestTitle(text);
      const key = title + '|' + text.slice(0, 80);
      if (seen.has(key)) continue;
      seen.add(key);
      const img = node.querySelector('img');
      cards.push({
        source: 'visible-platform-card-collector',
        title,
        cover: title,
        caption: text,
        visible_text: text,
        cover_image_url: img ? (img.currentSrc || img.src || '') : '',
        url: bestLink(node) || location.href,
        platform_page_url: location.href,
        final_url: location.href,
        likes: parseNum('点赞', text),
        collects: parseNum('收藏', text),
        comments: parseNum('评论', text),
        collected_at: new Date().toISOString()
      });
    }
  }
  return {
    page_title: document.title,
    page_url: location.href,
    items: cards.slice(0, $maxItems)
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
    $ws.Dispose()
  }
}

function Collect-DetailPage($port, $url, $delayMs) {
  if (-not $url) { return $null }
  $encoded = [uri]::EscapeDataString($url)
  try {
    $tab = Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$port/json/new?$encoded"
  } catch {
    $tab = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/new?$encoded"
  }

  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  try {
    Invoke-Cdp $ws "Page.enable" | Out-Null
    Invoke-Cdp $ws "Runtime.enable" | Out-Null
    Start-Sleep -Milliseconds ($delayMs + 2200)

    $expression = @"
(() => {
  const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const visible = (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 20 && r.height > 20;
  };
  const title = clean(document.querySelector('h1')?.innerText || document.title || '');
  const nodes = Array.from(document.querySelectorAll('h1,h2,h3,p,span,div,section,article')).filter(visible);
  const texts = [];
  const seen = new Set();
  for (const node of nodes) {
    const text = clean(node.innerText || node.textContent || '');
    if (text.length < 8 || text.length > 1600) continue;
    if (/登录|注册|首页|菜单|客服|版权|免责声明/.test(text) && text.length < 80) continue;
    if (seen.has(text)) continue;
    seen.add(text);
    texts.push(text);
    if (texts.join('\n').length > 8000) break;
  }
  const all = texts.join('\n');
  const likelyBody = texts
    .filter(t => t.length >= 30 && !/点赞|收藏|评论|发布|分类|互动量/.test(t))
    .sort((a, b) => b.length - a.length)
    .slice(0, 8)
    .join('\n');
  return {
    detail_url: location.href,
    detail_title: title,
    detail_text: all,
    detail_body_guess: likelyBody,
    detail_text_length: all.length,
    needs_login: /登录|验证码|安全验证|请先登录/.test(all)
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

if (-not $OutputFile) {
  $outDir = Join-Path (Get-Location) "data\processed"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $OutputFile = Join-Path $outDir ("platform_visible_cards_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

Start-Browser $Port

if ($WaitForUser) {
  Write-Host ""
  Write-Host "请在打开的浏览器里登录千瓜/蒲公英，并停留在要采集的榜单页。"
  Write-Host "完成后回到这个窗口按 Enter。"
  Read-Host | Out-Null
}

$tab = Get-Tab $Port $PageUrl
Write-Host "采集页面：$($tab.url)"
Write-Host "如果页面需要登录，请在打开的浏览器里登录并停留在榜单页，然后重新运行本脚本。"

$result = Collect-VisibleCards $tab $ScrollTimes $DelayMs $MaxItems
$items = @($result.items)

if ($CollectDetails) {
  $detailCount = 0
  $seenDetailUrls = @{}
  for ($i = 0; $i -lt $items.Count; $i++) {
    if ($detailCount -ge $MaxDetails) { break }
    $url = [string]$items[$i].url
    if (-not $url -or $url -eq $result.page_url -or $seenDetailUrls.ContainsKey($url)) { continue }
    $seenDetailUrls[$url] = $true
    $detailCount += 1
    Write-Host "详情 [$detailCount/$MaxDetails] $url"
    try {
      $detail = Collect-DetailPage $Port $url $DelayMs
      if ($detail) {
        $items[$i] | Add-Member -NotePropertyName detail_url -NotePropertyValue $detail.detail_url -Force
        $items[$i] | Add-Member -NotePropertyName detail_title -NotePropertyValue $detail.detail_title -Force
        $items[$i] | Add-Member -NotePropertyName detail_text -NotePropertyValue $detail.detail_text -Force
        $items[$i] | Add-Member -NotePropertyName detail_body_guess -NotePropertyValue $detail.detail_body_guess -Force
        $items[$i] | Add-Member -NotePropertyName detail_text_length -NotePropertyValue $detail.detail_text_length -Force
        $items[$i] | Add-Member -NotePropertyName needs_login -NotePropertyValue $detail.needs_login -Force
        if ($detail.detail_body_guess) {
          $items[$i].caption = $detail.detail_body_guess
          $items[$i].visible_text = $detail.detail_text
        }
      }
    } catch {
      $items[$i] | Add-Member -NotePropertyName detail_error -NotePropertyValue $_.Exception.Message -Force
    }
    Start-Sleep -Milliseconds 1000
  }
}

$output = [ordered]@{
  generated_at = (Get-Date).ToString("s")
  note = "仅采集当前浏览器中正常可见的榜单卡片和可见详情页文字；不绕过登录、验证码或权限限制。"
  page_title = $result.page_title
  page_url = $result.page_url
  collect_details = [bool]$CollectDetails
  items = $items
}

$json = $output | ConvertTo-Json -Depth 12
Set-Content -Path $OutputFile -Value $json -Encoding UTF8
Write-Host "完成：$OutputFile"
