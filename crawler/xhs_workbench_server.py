from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import webbrowser
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

import requests


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PYTHON = PROJECT_ROOT / ".venv" / "Scripts" / "python.exe"
COLLECTOR = PROJECT_ROOT / "crawler" / "xhs_loggedin_visible_collector.py"
PROFILE = PROJECT_ROOT / ".xhs-loggedin-browser-profile"
DATA_DIR = PROJECT_ROOT / "data" / "processed"
PORT = 8765
XHS_PORT = 9224


def search_url(keyword: str) -> str:
    return f"https://www.xiaohongshu.com/search_result/?keyword={quote(keyword)}&source=web_search_result_notes&type=51"


def browser_path() -> str:
    candidates = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    raise RuntimeError("未找到 Edge 或 Chrome")


def cdp_alive() -> bool:
    try:
        requests.get(f"http://127.0.0.1:{XHS_PORT}/json/version", timeout=1)
        return True
    except requests.RequestException:
        return False


def open_xhs(keyword: str = "") -> str:
    url = search_url(keyword) if keyword else "https://www.xiaohongshu.com/"
    if cdp_alive():
        encoded = quote(url, safe="")
        try:
            requests.put(f"http://127.0.0.1:{XHS_PORT}/json/new?{encoded}", timeout=3)
        except requests.RequestException:
            requests.get(f"http://127.0.0.1:{XHS_PORT}/json/new?{encoded}", timeout=3)
        return url

    PROFILE.mkdir(parents=True, exist_ok=True)
    subprocess.Popen(
        [
            browser_path(),
            f"--remote-debugging-port={XHS_PORT}",
            f"--user-data-dir={PROFILE}",
            "--no-first-run",
            "--new-window",
            url,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
    )
    return url


def latest_outputs(limit: int = 8) -> list[dict]:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(DATA_DIR.glob("xhs_python_visible_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    outputs = []
    for path in files[:limit]:
        item_count = ""
        detail_count = ""
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            items = data.get("items", [])
            filters = data.get("filters") or {}
            item_count = len(items)
            detail_count = len([item for item in items if "detail" in str(item.get("source", ""))])
        except Exception:
            filters = {}
            pass
        rel = path.relative_to(PROJECT_ROOT).as_posix()
        outputs.append(
            {
                "name": path.name,
                "path": rel,
                "mtime": datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                "items": item_count,
                "details": detail_count,
                "filters": filters,
                "analyze_url": f"/xiaohongshu_viral_decoder_v2.html?data=/{quote(rel)}&view=candidates",
                "json_url": f"/{quote(rel)}",
            }
        )
    return outputs


def run_collect(payload: dict) -> dict:
    if not PYTHON.exists():
        raise RuntimeError(f"未找到项目 Python：{PYTHON}")

    keyword = str(payload.get("keyword") or "").strip()
    max_items = int(payload.get("max_items") or 30)
    detail_limit = int(payload.get("detail_limit") or 5)
    days = int(payload.get("days") or 0)
    sort_by = str(payload.get("sort_by") or "score")
    top = int(payload.get("top") or 0)
    scroll_times = int(payload.get("scroll_times") or 2)
    delay_ms = int(payload.get("delay_ms") or 1800)
    use_current = bool(payload.get("use_current", not keyword))

    command = [
        str(PYTHON),
        str(COLLECTOR),
        "--max-items",
        str(max_items),
        "--scroll-times",
        str(scroll_times),
        "--delay-ms",
        str(delay_ms),
        "--detail-limit",
        str(detail_limit),
        "--detail-mode",
        "click",
        "--port",
        str(XHS_PORT),
    ]
    if days > 0:
        command.extend(["--days", str(days)])
    if sort_by:
        command.extend(["--sort-by", sort_by])
    if top > 0:
        command.extend(["--top", str(top)])
    if keyword:
        command.extend(["--keyword", keyword])
    elif use_current:
        command.append("--use-current-tab")

    proc = subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=240,
    )
    output = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
    if proc.returncode != 0:
        raise RuntimeError(output.strip() or "采集失败")

    match = re.search(r"Done:\s*(.+\.json)", output)
    file_path = Path(match.group(1).strip()) if match else None
    latest = latest_outputs(1)
    if file_path and file_path.exists():
        rel = file_path.relative_to(PROJECT_ROOT).as_posix()
        latest = [
            {
                "name": file_path.name,
                "path": rel,
                "mtime": datetime.fromtimestamp(file_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                "items": "",
                "details": "",
                "filters": {"days": days, "sort_by": sort_by, "top": top},
                "analyze_url": f"/xiaohongshu_viral_decoder_v2.html?data=/{quote(rel)}&view=candidates",
                "json_url": f"/{quote(rel)}",
            }
        ]
    return {"ok": True, "log": output, "latest": latest[0] if latest else None, "outputs": latest_outputs()}


def read_json_body(handler: SimpleHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length") or 0)
    if not length:
        return {}
    raw = handler.rfile.read(length).decode("utf-8")
    return json.loads(raw or "{}")


def dashboard_html() -> str:
    return r"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>小红书采集分析工作台</title>
  <style>
    :root {
      --bg: #f8f5f2;
      --panel: #fffdfb;
      --ink: #282421;
      --muted: #756f6a;
      --line: #e7ddd5;
      --rose: #cf5c6f;
      --rose-dark: #a94456;
      --green: #7f9b87;
      --blue: #718aa1;
      --shadow: 0 16px 42px rgba(76, 58, 48, .10);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
      color: var(--ink);
      background: linear-gradient(180deg, #fbf8f5 0%, var(--bg) 100%);
    }
    .wrap { max-width: 1120px; margin: 0 auto; padding: 28px 20px 44px; }
    header { display: flex; justify-content: space-between; gap: 18px; align-items: flex-end; margin-bottom: 18px; }
    h1 { margin: 0 0 8px; font-size: 28px; letter-spacing: 0; }
    .sub { margin: 0; color: var(--muted); line-height: 1.7; }
    .grid { display: grid; grid-template-columns: 360px 1fr; gap: 16px; align-items: start; }
    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      box-shadow: var(--shadow);
      padding: 16px;
    }
    .panel h2 { margin: 0 0 12px; font-size: 16px; }
    label { display: block; margin: 13px 0 7px; font-size: 13px; color: var(--muted); }
    input, select {
      width: 100%;
      height: 40px;
      border: 1px solid var(--line);
      border-radius: 9px;
      padding: 0 11px;
      font: inherit;
      background: #fff;
      color: var(--ink);
    }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .actions { display: grid; gap: 10px; margin-top: 16px; }
    button, .linkbtn {
      border: 0;
      border-radius: 9px;
      min-height: 42px;
      padding: 0 14px;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: #fff;
      background: var(--rose);
    }
    button:hover, .linkbtn:hover { background: var(--rose-dark); }
    .secondary { background: #ebe3dc; color: var(--ink); }
    .secondary:hover { background: #dfd3ca; }
    .green { background: var(--green); }
    .green:hover { background: #6e8875; }
    .blue { background: var(--blue); }
    .blue:hover { background: #607a92; }
    .note { margin-top: 12px; padding: 11px; background: #faf3f0; border: 1px solid #efd7d2; border-radius: 10px; color: #7d4a43; line-height: 1.65; font-size: 13px; }
    .status { min-height: 54px; white-space: pre-wrap; line-height: 1.65; color: var(--muted); }
    .outputs { display: grid; gap: 10px; }
    .item { border: 1px solid var(--line); border-radius: 10px; padding: 12px; background: #fff; }
    .item-top { display: flex; justify-content: space-between; gap: 12px; align-items: center; }
    .name { font-weight: 700; word-break: break-all; }
    .meta { color: var(--muted); font-size: 12px; margin-top: 5px; }
    .item-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
    .item-actions a { min-height: 34px; padding: 0 11px; font-size: 13px; }
    .ghost { color: var(--rose-dark); background: #faece9; }
    .ghost:hover { background: #f4ddd8; }
    code { background: #f1ebe5; padding: 2px 5px; border-radius: 5px; }
    @media (max-width: 860px) { .grid { grid-template-columns: 1fr; } header { display: block; } }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div>
        <h1>小红书采集分析工作台</h1>
        <p class="sub">一个入口完成：打开小红书、采集可见内容、进入爆款拆解工具。</p>
      </div>
      <a class="linkbtn secondary" href="/xiaohongshu_viral_decoder_v2.html" target="_blank">打开空白分析页</a>
    </header>
    <div class="grid">
      <section class="panel">
        <h2>采集设置</h2>
        <label>关键词</label>
        <input id="keyword" value="AI工作流" placeholder="比如 Codex / AI内容运营 / 广告人学AI">
        <div class="row">
          <div>
            <label>候选池</label>
            <input id="maxItems" type="number" min="30" max="150" value="90">
          </div>
          <div>
            <label>详情正文</label>
            <input id="detailLimit" type="number" min="0" max="30" value="30">
          </div>
        </div>
        <div class="row">
          <div>
            <label>时间范围</label>
            <select id="days">
              <option value="7" selected>近一周</option>
              <option value="14">近两周</option>
              <option value="0">不限时间</option>
            </select>
          </div>
          <div>
            <label>输出</label>
            <select id="top">
              <option value="30" selected>点赞前 30</option>
              <option value="20">点赞前 20</option>
              <option value="50">点赞前 50</option>
            </select>
          </div>
        </div>
        <div class="actions">
          <button class="secondary" id="openBtn">1. 打开小红书登录/搜索</button>
          <button class="green" id="collectKeywordBtn">2. 按关键词采集</button>
          <button class="blue" id="collectCurrentBtn">采集当前打开页面</button>
        </div>
        <div class="note">默认会从候选池里筛“近一周、点赞最高的前 30 篇”，再尽量逐条打开抓详情正文。会慢一点，但文案拆解会更有用。</div>
      </section>
      <section class="panel">
        <h2>状态</h2>
        <div class="status" id="status">准备好了。你可以先打开小红书登录，再回来点采集。</div>
        <div class="actions" id="quickActions" style="display:none"></div>
      </section>
      <section class="panel" style="grid-column: 1 / -1;">
        <h2>最近采集结果</h2>
        <div class="outputs" id="outputs"></div>
      </section>
    </div>
  </div>
  <script>
    const $ = (s) => document.querySelector(s);
    const statusEl = $("#status");
    const outputsEl = $("#outputs");
    const quickActions = $("#quickActions");

    function settings() {
      return {
        keyword: $("#keyword").value.trim(),
        max_items: Number($("#maxItems").value || 90),
        detail_limit: Number($("#detailLimit").value || 30),
        days: Number($("#days").value || 7),
        sort_by: "likes",
        top: Number($("#top").value || 30),
        scroll_times: 4,
        delay_ms: 1800
      };
    }

    async function api(path, body) {
      const res = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body || {})
      });
      const data = await res.json();
      if (!res.ok || data.ok === false) throw new Error(data.error || "操作失败");
      return data;
    }

    function setBusy(text) {
      statusEl.textContent = text;
      document.querySelectorAll("button").forEach((btn) => btn.disabled = true);
    }

    function done(text) {
      statusEl.textContent = text;
      document.querySelectorAll("button").forEach((btn) => btn.disabled = false);
    }

    async function refreshOutputs() {
      const res = await fetch("/api/latest");
      const data = await res.json();
      renderOutputs(data.outputs || []);
    }

    function renderOutputs(outputs) {
      if (!outputs.length) {
        outputsEl.innerHTML = '<div class="note">还没有采集结果。先从左侧开始。</div>';
        return;
      }
      outputsEl.innerHTML = outputs.map((item) => `
        <div class="item">
          <div class="item-top">
            <div>
              <div class="name">${item.name}</div>
              <div class="meta">${item.mtime} · ${item.items || 0} 条 · 详情正文 ${item.details || 0} 条 · ${filterText(item.filters)}</div>
            </div>
          </div>
          <div class="item-actions">
            <a class="linkbtn" href="${item.analyze_url}" target="_blank">直接分析</a>
            <a class="linkbtn ghost" href="${item.json_url}" target="_blank">查看 JSON</a>
          </div>
        </div>
      `).join("");
    }

    function showLatestAction(item) {
      if (!item) return;
      quickActions.style.display = "grid";
      quickActions.innerHTML = `<a class="linkbtn" href="${item.analyze_url}" target="_blank">打开刚采集的数据分析</a>`;
    }

    function filterText(filters) {
      if (!filters) return "未筛选";
      const dayText = Number(filters.days || 0) > 0 ? `近 ${filters.days} 天` : "不限时间";
      const sortText = filters.sort_by === "likes" ? "按点赞" : "默认排序";
      const topText = Number(filters.top || 0) > 0 ? `前 ${filters.top}` : "全部";
      return `${dayText} · ${sortText} · ${topText}`;
    }

    $("#openBtn").addEventListener("click", async () => {
      try {
        setBusy("正在打开小红书窗口...");
        const data = await api("/api/open-xhs", { keyword: settings().keyword });
        done(`已打开：${data.url}\n如果还没登录，先在小红书窗口完成登录，再回来点采集。`);
      } catch (err) {
        done(err.message);
      }
    });

    $("#collectKeywordBtn").addEventListener("click", async () => {
      try {
        const body = settings();
        setBusy(`正在采集“${body.keyword || "当前关键词"}”，通常需要 30 秒到 2 分钟...`);
        const data = await api("/api/collect", body);
        done("采集完成。\n" + (data.log || "").split("\n").slice(-4).join("\n"));
        showLatestAction(data.latest);
        renderOutputs(data.outputs || []);
      } catch (err) {
        done(err.message);
      }
    });

    $("#collectCurrentBtn").addEventListener("click", async () => {
      try {
        const body = settings();
        body.keyword = "";
        body.use_current = true;
        setBusy("正在采集当前小红书页面...");
        const data = await api("/api/collect", body);
        done("采集完成。\n" + (data.log || "").split("\n").slice(-4).join("\n"));
        showLatestAction(data.latest);
        renderOutputs(data.outputs || []);
      } catch (err) {
        done(err.message);
      }
    });

    refreshOutputs();
  </script>
</body>
</html>"""


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PROJECT_ROOT), **kwargs)

    def send_json(self, data: dict, status: int = 200) -> None:
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            raw = dashboard_html().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if parsed.path == "/api/latest":
            self.send_json({"ok": True, "outputs": latest_outputs()})
            return
        self.path = unquote(self.path)
        super().do_GET()

    def do_POST(self) -> None:
        try:
            if self.path == "/api/open-xhs":
                payload = read_json_body(self)
                url = open_xhs(str(payload.get("keyword") or "").strip())
                self.send_json({"ok": True, "url": url})
                return
            if self.path == "/api/collect":
                payload = read_json_body(self)
                self.send_json(run_collect(payload))
                return
            self.send_json({"ok": False, "error": "未知接口"}, 404)
        except Exception as exc:
            self.send_json({"ok": False, "error": str(exc)}, 500)

    def log_message(self, format: str, *args) -> None:
        return


def main() -> int:
    os.chdir(PROJECT_ROOT)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"小红书工作台已启动：{url}")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("工作台已停止")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
