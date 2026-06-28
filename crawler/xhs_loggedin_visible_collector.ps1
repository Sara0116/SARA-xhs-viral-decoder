param(
  [string]$PageUrl = "https://www.xiaohongshu.com/",
  [string]$SearchKeyword = "",
  [string]$OutputFile = "",
  [int]$MaxItems = 60,
  [int]$ScrollTimes = 5,
  [int]$DelayMs = 1800,
  [int]$Port = 9224,
  [switch]$UseCurrentTab,
  [switch]$WaitForUser
)

$ErrorActionPreference = "Stop"

function ConvertTo-XhsSearchUrl($keyword) {
  if (-not $keyword) { return "" }
  $encoded = [uri]::EscapeDataString($keyword)
  return "https://www.xiaohongshu.com/search_result?keyword=$encoded&source=web_search_result_notes"
}

function Get-BrowserPath {
  $candidates = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe"
  )
  foreach ($path in $candidates) {
    if (Test-Path $path) { return $path }
  }
  throw "Edge or Chrome was not found."
}

function Start-Browser($port) {
  try {
    Invoke-RestMethod -Uri "http://127.0.0.1:${port}/json/version" -TimeoutSec 1 | Out-Null
    return
  } catch {}

  $browser = Get-BrowserPath
  $profile = Join-Path (Get-Location) ".xhs-loggedin-browser-profile"
  New-Item -ItemType Directory -Force -Path $profile | Out-Null
  Start-Process -FilePath $browser -ArgumentList @(
    "--remote-debugging-port=$port",
    "--user-data-dir=$profile",
    "--no-first-run",
    "--new-window",
    $PageUrl
  )
  Start-Sleep -Seconds 3
}

function Get-TargetTab($port, $pageUrl, $useCurrentTab) {
  if (-not $useCurrentTab -and $pageUrl) {
    $encoded = [uri]::EscapeDataString($pageUrl)
    try {
      return Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:${port}/json/new?$encoded"
    } catch {
      return Invoke-RestMethod -Uri "http://127.0.0.1:${port}/json/new?$encoded"
    }
  }

  $tabs = @(Invoke-RestMethod -Uri "http://127.0.0.1:${port}/json")
  $tab = $tabs |
    Where-Object { $_.type -eq "page" -and $_.url -match "xiaohongshu\.com" } |
    Select-Object -First 1
  if (-not $tab) {
    $tab = $tabs |
      Where-Object { $_.type -eq "page" -and $_.url -notmatch "about:blank|devtools://" } |
      Select-Object -First 1
  }
  if (-not $tab) { throw "No collectible page was found. Open a Xiaohongshu page in the browser first." }
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

function Collect-XhsVisibleContent($tab, $scrollTimes, $delayMs, $maxItems) {
  $tab = @($tab)[0]
  $debuggerUrl = @($tab.webSocketDebuggerUrl)[0]
  if (-not $debuggerUrl) { throw "The selected page does not expose a debugger URL." }
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ws.ConnectAsync([Uri]$debuggerUrl, [Threading.CancellationToken]::None).Wait()
  try {
    Invoke-Cdp $ws "Page.enable" | Out-Null
    Invoke-Cdp $ws "Runtime.enable" | Out-Null
    Start-Sleep -Milliseconds ($delayMs + 1200)

    for ($i = 0; $i -lt $scrollTimes; $i++) {
      Invoke-Cdp $ws "Runtime.evaluate" @{
        expression = "window.scrollBy(0, Math.max(650, Math.floor(window.innerHeight * 0.7)));"
        awaitPromise = $false
      } | Out-Null
      Start-Sleep -Milliseconds $delayMs
    }

    $expression = @'
(() => {
  const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const visible = (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 20 && r.height > 20;
  };
  const textFrom = (el) => clean(el?.innerText || el?.textContent || '');
  const bestTitle = (text) => {
    const lines = text.split(/\n| {2,}/).map(clean).filter(Boolean);
    const useful = lines.filter(x =>
      x.length >= 4 &&
      x.length <= 90 &&
      !/点赞|收藏|评论|关注|分享|举报|登录|扫码|打开小红书App/.test(x)
    );
    return useful[0] || lines[0] || document.title || '';
  };
  const scoreText = (text) => {
    let score = 0;
    if (/AI|Codex|Agent|Claude|ChatGPT|工作流|达人|投放|内容|运营|文案|脚本|选题/i.test(text)) score += 3;
    if (/点赞|收藏|评论|关注|分享|发布/.test(text)) score += 2;
    if (/小红书|笔记|展开|作者|搜索/.test(text)) score += 1;
    if (text.length >= 20 && text.length <= 1200) score += 2;
    return score;
  };
  const parseNum = (label, text) => {
    const m = text.match(new RegExp(label + '[^0-9万千kK]{0,8}([0-9,.]+\\\\s*[万千kK]?)'));
    return m ? m[1] : '';
  };
  const pageText = textFrom(document.body);
  const needsLogin = /登录|扫码|当前笔记暂时无法浏览|请打开小红书App|验证码|安全验证/.test(pageText);

  const items = [];
  const seen = new Set();
  const pageTitle = clean((document.title || '').replace(/\s*-\s*小红书.*/, ''));
  const pickImage = (root = document) => {
    const img = Array.from(root.querySelectorAll('img')).find(x => {
      const src = x.currentSrc || x.src || '';
      return visible(x) && src && !src.startsWith('data:');
    });
    return img ? (img.currentSrc || img.src || '') : '';
  };
  if (pageTitle && pageText.includes(pageTitle)) {
    const start = pageText.lastIndexOf(pageTitle);
    let detailText = pageText.slice(start);
    const commentStart = detailText.search(/共\s*\d+\s*条评论|说点什么|发送\s*取消/);
    if (commentStart > 80) detailText = detailText.slice(0, commentStart);
    detailText = clean(detailText);
    if (detailText.length >= 40) {
      items.push({
        source: 'xhs-loggedin-visible-note-detail',
        title: pageTitle,
        cover: pageTitle,
        caption: detailText,
        visible_text: detailText,
        comments: '',
        url: location.href,
        final_url: location.href,
        cover_image_url: pickImage(document),
        likes: parseNum('点赞', pageText),
        collects: parseNum('收藏', pageText),
        commentCount: parseNum('评论', pageText),
        collected_at: new Date().toISOString()
      });
      seen.add(location.href.split('?')[0]);
    }
  }
  const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]')).filter(visible);
  const pickCard = (a) => {
    let best = a;
    let bestText = textFrom(a);
    for (let p = a.parentElement; p && p !== document.body; p = p.parentElement) {
      const t = textFrom(p);
      if (t.length > bestText.length && t.length <= 520) {
        best = p;
        bestText = t;
      }
      if (t.length > 900) break;
    }
    return { node: best, text: bestText || textFrom(a) };
  };

  for (const a of anchors) {
    const card = pickCard(a);
    const node = card.node;
    const text = card.text || clean(a.getAttribute('aria-label') || a.getAttribute('title') || '');
    if (scoreText(text) < 3) continue;
    if (text.length > 900) continue;
    const title = bestTitle(text);
    const img = node.matches?.('img') ? node : Array.from(node.querySelectorAll('img')).find(x => visible(x) && !((x.currentSrc || x.src || '').startsWith('data:')));
    const href = a.href || location.href;
    const key = href.split('?')[0];
    if (seen.has(key)) continue;
    seen.add(key);
    items.push({
      source: 'xhs-loggedin-visible-collector',
      title,
      cover: title,
      caption: text,
      visible_text: text,
      comments: '',
      url: href || location.href,
      final_url: location.href,
      cover_image_url: img ? (img.currentSrc || img.src || '') : '',
      likes: parseNum('点赞', text),
      collects: parseNum('收藏', text),
      commentCount: parseNum('评论', text),
      collected_at: new Date().toISOString()
    });
    if (items.length >= __MAX_ITEMS__) break;
  }

  if (items.length === 0 && pageText.length > 20) {
    const cleanedPageText = clean(pageText.replace(/沪ICP备[\s\S]{0,900}?电话：9501-3888/g, ''));
    items.push({
      source: 'xhs-loggedin-visible-collector',
      title: bestTitle(cleanedPageText),
      cover: bestTitle(cleanedPageText),
      caption: cleanedPageText.slice(0, 3000),
      visible_text: cleanedPageText.slice(0, 3000),
      comments: '',
      url: location.href,
      final_url: location.href,
      cover_image_url: pickImage(document),
      likes: parseNum('点赞', cleanedPageText),
      collects: parseNum('收藏', cleanedPageText),
      commentCount: parseNum('评论', cleanedPageText),
      collected_at: new Date().toISOString()
    });
  }

  return {
    page_title: document.title,
    page_url: location.href,
    needs_login: needsLogin,
    page_text_length: pageText.length,
    items: items.slice(0, __MAX_ITEMS__)
  };
})()
'@
    $expression = $expression.Replace("__MAX_ITEMS__", [string]$maxItems)
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

if (-not $OutputFile) {
  $outDir = Join-Path (Get-Location) "data\processed"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $OutputFile = Join-Path $outDir ("xhs_loggedin_visible_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

if ($SearchKeyword) {
  $PageUrl = ConvertTo-XhsSearchUrl $SearchKeyword
}

Start-Browser $Port

if ($WaitForUser) {
  Write-Host ""
  Write-Host "Log in in the opened browser, then stay on the Xiaohongshu search/topic/profile/note page to collect."
  if ($SearchKeyword) {
    Write-Host "Keyword: $SearchKeyword"
  }
  Write-Host "Return here and press Enter when ready."
  Read-Host | Out-Null
}

$tab = Get-TargetTab $Port $PageUrl $UseCurrentTab
Write-Host "Collecting page: $($tab.url)"

$result = Collect-XhsVisibleContent $tab $ScrollTimes $DelayMs $MaxItems
$output = [ordered]@{
  generated_at = (Get-Date).ToString("s")
  note = "仅采集已登录浏览器中正常可见的小红书页面文字和封面图地址；不绕过登录、扫码、验证码或权限限制。"
  page_title = $result.page_title
  page_url = $result.page_url
  needs_login = $result.needs_login
  page_text_length = $result.page_text_length
  items = $result.items
}

$json = $output | ConvertTo-Json -Depth 12
Set-Content -Path $OutputFile -Value $json -Encoding UTF8
Write-Host "Done: $OutputFile"
if ($result.needs_login) {
  Write-Host "Warning: login/QR/unavailable text was detected. Results may be incomplete."
}

