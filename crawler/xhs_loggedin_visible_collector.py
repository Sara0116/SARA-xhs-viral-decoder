from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import quote

import requests
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILE = PROJECT_ROOT / ".xhs-loggedin-browser-profile"
DEFAULT_OUT_DIR = PROJECT_ROOT / "data" / "processed"


COLLECT_SCRIPT = r"""
({ maxItems }) => {
  const clean = (s) => (s || "").replace(/\s+/g, " ").trim();
  const textFrom = (el) => clean(el?.innerText || el?.textContent || "");
  const visible = (el) => {
    if (!el) return false;
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== "none" && s.visibility !== "hidden" && r.width > 20 && r.height > 20;
  };
  const bestTitle = (text) => {
    const lines = text.split(/\n| {2,}/).map(clean).filter(Boolean);
    const useful = lines.filter((x) =>
      x.length >= 4 &&
      x.length <= 90 &&
      !/点赞|收藏|评论|关注|分享|举报|登录|扫码|打开小红书App|ICP|营业执照|许可证/.test(x)
    );
    return useful[0] || lines[0] || clean(document.title.replace(/\s*-\s*小红书.*/, ""));
  };
  const parseNum = (label, text) => {
    const m = text.match(new RegExp(label + "[^0-9万千kK]{0,8}([0-9,.]+\\s*[万千kK]?)"));
    return m ? m[1] : "";
  };
  const pickImage = (root = document) => {
    const img = Array.from(root.querySelectorAll("img")).find((x) => {
      const src = x.currentSrc || x.src || "";
      return visible(x) && src && !src.startsWith("data:");
    });
    return img ? (img.currentSrc || img.src || "") : "";
  };
  const scoreText = (text) => {
    let score = 0;
    if (/AI|Codex|Agent|Claude|ChatGPT|工作流|达人|投放|内容|运营|文案|脚本|选题/i.test(text)) score += 3;
    if (/点赞|收藏|评论|关注|分享|发布/.test(text)) score += 2;
    if (/小红书|笔记|展开|作者|搜索/.test(text)) score += 1;
    if (text.length >= 16 && text.length <= 900) score += 2;
    return score;
  };
  const pageText = textFrom(document.body);
  const pageTitle = clean((document.title || "").replace(/\s*-\s*小红书.*/, ""));
  const needsLogin = /登录|扫码|当前笔记暂时无法浏览|请打开小红书App|验证码|安全验证/.test(pageText);
  const items = [];
  const seen = new Set();

  const detailRoot = document.querySelector(".note-detail-mask .note-scroller, .note-detail-mask .interaction-container, .note-container .note-scroller");
  if (detailRoot && location.href.includes("/explore/")) {
    let detailText = textFrom(detailRoot);
    const commentStart = detailText.search(/共\s*\d+\s*条评论|说点什么|发送\s*取消/);
    if (commentStart > 80) detailText = detailText.slice(0, commentStart);
    detailText = clean(detailText);
    if (detailText.length >= 40) {
      items.push({
        source: "xhs-python-visible-note-detail",
        title: pageTitle || bestTitle(detailText),
        cover: pageTitle || bestTitle(detailText),
        caption: detailText,
        visible_text: detailText,
        comments: "",
        url: location.href,
        final_url: location.href,
        cover_image_url: pickImage(document.querySelector(".note-detail-mask, .note-container") || document),
        likes: parseNum("点赞", pageText),
        collects: parseNum("收藏", pageText),
        commentCount: parseNum("评论", pageText),
        collected_at: new Date().toISOString()
      });
      seen.add(location.href.split("?")[0]);
    }
  }

  if (!seen.has(location.href.split("?")[0]) && pageTitle && pageText.includes(pageTitle) && location.href.includes("/explore/")) {
    const start = pageText.lastIndexOf(pageTitle);
    let detailText = pageText.slice(start);
    const commentStart = detailText.search(/共\s*\d+\s*条评论|说点什么|发送\s*取消/);
    if (commentStart > 80) detailText = detailText.slice(0, commentStart);
    detailText = clean(detailText);
    if (detailText.length >= 40) {
      items.push({
        source: "xhs-python-visible-note-detail",
        title: pageTitle,
        cover: pageTitle,
        caption: detailText,
        visible_text: detailText,
        comments: "",
        url: location.href,
        final_url: location.href,
        cover_image_url: pickImage(document),
        likes: parseNum("点赞", pageText),
        collects: parseNum("收藏", pageText),
        commentCount: parseNum("评论", pageText),
        collected_at: new Date().toISOString()
      });
      seen.add(location.href.split("?")[0]);
    }
  }

  const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
  const pickCard = (a) => {
    let best = a;
    let bestText = textFrom(a);
    for (let p = a.parentElement; p && p !== document.body; p = p.parentElement) {
      const t = textFrom(p);
      if (visible(p) && t.length > bestText.length && t.length <= 520) {
        best = p;
        bestText = t;
      }
      if (t.length > 900) break;
    }
    return { node: best, text: bestText || textFrom(a) };
  };

  for (const a of anchors) {
    const href = a.href || "";
    const key = href.split("?")[0];
    if (!href || seen.has(key)) continue;
    const card = pickCard(a);
    const text = card.text || clean(a.getAttribute("aria-label") || a.getAttribute("title") || "");
    if (scoreText(text) < 3 || text.length > 900) continue;
    const node = card.node;
    if (!visible(node)) continue;
    const img = node.matches?.("img")
      ? node
      : Array.from(node.querySelectorAll("img")).find((x) => visible(x) && !((x.currentSrc || x.src || "").startsWith("data:")));
    seen.add(key);
    items.push({
      source: "xhs-python-visible-card",
      title: bestTitle(text),
      cover: bestTitle(text),
      caption: text,
      visible_text: text,
      comments: "",
      url: href,
      final_url: location.href,
      cover_image_url: img ? (img.currentSrc || img.src || "") : "",
      likes: parseNum("点赞", text),
      collects: parseNum("收藏", text),
      commentCount: parseNum("评论", text),
      collected_at: new Date().toISOString()
    });
    if (items.length >= maxItems) break;
  }

  if (!items.length && pageText.length > 20) {
    const cleaned = clean(pageText.replace(/沪ICP备[\s\S]{0,900}?电话：9501-3888/g, ""));
    items.push({
      source: "xhs-python-visible-page-fallback",
      title: bestTitle(cleaned),
      cover: bestTitle(cleaned),
      caption: cleaned.slice(0, 3000),
      visible_text: cleaned.slice(0, 3000),
      comments: "",
      url: location.href,
      final_url: location.href,
      cover_image_url: pickImage(document),
      likes: parseNum("点赞", cleaned),
      collects: parseNum("收藏", cleaned),
      commentCount: parseNum("评论", cleaned),
      collected_at: new Date().toISOString()
    });
  }

  return {
    page_title: document.title,
    page_url: location.href,
    needs_login: needsLogin,
    page_text_length: pageText.length,
    items: items.slice(0, maxItems)
  };
}
"""


COUNT_NOTE_CARDS_SCRIPT = r"""
() => {
  const visible = (el) => {
    if (!el) return false;
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== "none" && s.visibility !== "hidden" && r.width > 20 && r.height > 20;
  };
  return Array.from(document.querySelectorAll(".note-item"))
    .filter((el) => visible(el) && el.querySelector('a[href*="/explore/"]')).length;
}
"""


def find_browser() -> str:
    candidates = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    ]
    for path in candidates:
        if Path(path).exists():
            return path
    raise RuntimeError("Edge or Chrome was not found.")


def search_url(keyword: str) -> str:
    return f"https://www.xiaohongshu.com/search_result/?keyword={quote(keyword)}&source=web_search_result_notes&type=51"


def cdp_alive(port: int) -> bool:
    try:
        requests.get(f"http://127.0.0.1:{port}/json/version", timeout=1)
        return True
    except requests.RequestException:
        return False


def start_browser(port: int, page_url: str, profile: Path) -> None:
    if cdp_alive(port):
        return
    profile.mkdir(parents=True, exist_ok=True)
    subprocess.Popen(
        [
            find_browser(),
            f"--remote-debugging-port={port}",
            f"--user-data-dir={profile}",
            "--no-first-run",
            "--new-window",
            page_url,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
    )
    time.sleep(3)


def choose_page(browser, page_url: str, use_current_tab: bool):
    pages = [p for ctx in browser.contexts for p in ctx.pages]
    if use_current_tab:
        for page in pages:
            if "xiaohongshu.com" in page.url:
                return page
        for page in pages:
            if page.url and not page.url.startswith("devtools://"):
                return page
    context = browser.contexts[0] if browser.contexts else browser.new_context()
    page = context.new_page()
    page.goto(page_url, wait_until="domcontentloaded", timeout=45000)
    return page


def slow_scroll(page, scroll_times: int, delay_ms: int) -> None:
    for _ in range(max(scroll_times, 0)):
        try:
            page.evaluate("window.scrollBy(0, Math.max(650, Math.floor(window.innerHeight * 0.7)))")
        except Exception:
            break
        time.sleep(delay_ms / 1000)


def wait_for_note_detail(page, timeout_ms: int = 12000) -> None:
    deadline = time.time() + timeout_ms / 1000
    while time.time() < deadline:
        try:
            has_detail = page.locator(".note-detail-mask, .note-container").count() > 0
            title = page.title()
            if "/explore/" in page.url and has_detail and "搜索" not in title:
                return
        except Exception:
            pass
        time.sleep(0.5)


def collect_page(page, max_items: int, scroll_times: int, delay_ms: int) -> dict:
    try:
        page.wait_for_load_state("domcontentloaded", timeout=20000)
    except PlaywrightTimeoutError:
        pass
    if "search_result" in page.url:
        try:
            page.locator(".note-item").first.wait_for(state="visible", timeout=15000)
        except PlaywrightTimeoutError:
            pass
    time.sleep(max(delay_ms, 800) / 1000)
    slow_scroll(page, scroll_times, delay_ms)
    return page.evaluate(COLLECT_SCRIPT, {"maxItems": max_items})


def unique_items(items: list[dict]) -> list[dict]:
    by_key = {}
    output = []
    for item in items:
        enriched = enrich_item_meta(item)
        key = re.sub(r"\?.*$", "", enriched.get("url") or "") or (enriched.get("title"), enriched.get("caption", "")[:80])
        if key in by_key:
            existing = by_key[key]
            for field in ("likes", "collects", "commentCount", "publishDate", "publish_date", "author"):
                if not existing.get(field) and enriched.get(field):
                    existing[field] = enriched[field]
            if len(str(enriched.get("caption") or "")) > len(str(existing.get("caption") or "")):
                for field in ("title", "cover", "caption", "visible_text", "source", "url", "final_url", "cover_image_url"):
                    if enriched.get(field):
                        existing[field] = enriched[field]
            continue
        by_key[key] = enriched
        output.append(enriched)
    return output


def parse_xhs_number(value) -> int:
    text = str(value or "").replace(",", "").strip()
    if not text:
        return 0
    match = re.search(r"(\d+(?:\.\d+)?)\s*([万千kK]?)", text)
    if not match:
        return 0
    number = float(match.group(1))
    unit = match.group(2)
    if unit == "万":
        number *= 10000
    elif unit == "千":
        number *= 1000
    elif unit.lower() == "k":
        number *= 1000
    return int(number)


def parse_publish_date(text: str) -> str:
    value = str(text or "")
    now = datetime.now()
    patterns = [
        r"\d{4}-\d{1,2}-\d{1,2}",
        r"\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?",
        r"今天(?:\s+\d{1,2}:\d{2})?",
        r"昨天(?:\s+\d{1,2}:\d{2})?",
        r"前天(?:\s+\d{1,2}:\d{2})?",
        r"\d+\s*(?:分钟|小时|天|周)前",
    ]
    matches = []
    for pattern in patterns:
        matches.extend(re.finditer(pattern, value))
    if not matches:
        return ""
    token = max(matches, key=lambda m: m.start()).group(0).strip()
    try:
        if re.match(r"\d{4}-\d{1,2}-\d{1,2}", token):
            return datetime.strptime(token.split()[0], "%Y-%m-%d").date().isoformat()
        if re.match(r"\d{1,2}-\d{1,2}", token):
            month, day = [int(x) for x in token.split()[0].split("-")]
            year = now.year
            dt = datetime(year, month, day)
            if dt - now > timedelta(days=31):
                dt = datetime(year - 1, month, day)
            return dt.date().isoformat()
        if token.startswith("今天"):
            return now.date().isoformat()
        if token.startswith("昨天"):
            return (now - timedelta(days=1)).date().isoformat()
        if token.startswith("前天"):
            return (now - timedelta(days=2)).date().isoformat()
        relative = re.match(r"(\d+)\s*(分钟|小时|天|周)前", token)
        if relative:
            amount = int(relative.group(1))
            unit = relative.group(2)
            if unit in ("分钟", "小时"):
                return now.date().isoformat()
            if unit == "天":
                return (now - timedelta(days=amount)).date().isoformat()
            if unit == "周":
                return (now - timedelta(days=amount * 7)).date().isoformat()
    except ValueError:
        return ""
    return ""


def extract_card_likes(text: str) -> int:
    value = str(text or "")
    date_pattern = r"(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?|今天(?:\s+\d{1,2}:\d{2})?|昨天(?:\s+\d{1,2}:\d{2})?|前天(?:\s+\d{1,2}:\d{2})?|\d+\s*(?:分钟|小时|天|周)前)"
    matches = list(re.finditer(date_pattern, value))
    if not matches:
        return 0
    tail = value[matches[-1].end():]
    nums = re.findall(r"(?<![A-Za-z0-9])(\d+(?:\.\d+)?\s*[万千kK]?)(?![A-Za-z0-9])", tail)
    return parse_xhs_number(nums[-1]) if nums else 0


def extract_author(text: str) -> str:
    value = str(text or "").strip()
    date_pattern = r"(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?|今天(?:\s+\d{1,2}:\d{2})?|昨天(?:\s+\d{1,2}:\d{2})?|前天(?:\s+\d{1,2}:\d{2})?|\d+\s*(?:分钟|小时|天|周)前)"
    match = re.search(date_pattern, value)
    if not match:
        return ""
    before = value[: match.start()].strip()
    if not before:
        return ""
    parts = before.split()
    return parts[-1][:40] if len(parts) >= 2 else ""


def enrich_item_meta(item: dict) -> dict:
    out = dict(item)
    text = " ".join(str(out.get(field) or "") for field in ("title", "caption", "visible_text"))
    if not out.get("publishDate"):
        parsed_date = parse_publish_date(text)
        if parsed_date:
            out["publishDate"] = parsed_date
            out["publish_date"] = parsed_date
    if not parse_xhs_number(out.get("likes")):
        likes = extract_card_likes(text)
        if likes:
            out["likes"] = likes
    else:
        out["likes"] = parse_xhs_number(out.get("likes"))
    if not out.get("author"):
        author = extract_author(text)
        if author:
            out["author"] = author
    return out


def apply_item_filters(items: list[dict], days: int, sort_by: str, top: int) -> list[dict]:
    enriched = [enrich_item_meta(item) for item in items]
    if days > 0:
        start_date = (datetime.now() - timedelta(days=days)).date()
        enriched = [
            item for item in enriched
            if item.get("publishDate") and datetime.fromisoformat(str(item["publishDate"])).date() >= start_date
        ]
    if sort_by == "likes":
        enriched.sort(key=lambda item: parse_xhs_number(item.get("likes")), reverse=True)
    elif sort_by == "date":
        enriched.sort(key=lambda item: item.get("publishDate") or "", reverse=True)
    if top > 0:
        enriched = enriched[:top]
    return enriched


def collect_detail_links(context, links: list[str], limit: int, delay_ms: int) -> list[dict]:
    detail_items = []
    for url in links[: max(limit, 0)]:
        page = context.new_page()
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=45000)
            result = collect_page(page, max_items=1, scroll_times=1, delay_ms=delay_ms)
            for item in result.get("items", []):
                if item.get("caption"):
                    item["source"] = "xhs-python-visible-linked-detail"
                    detail_items.append(item)
                    break
        except Exception as exc:
            detail_items.append(
                {
                    "source": "xhs-python-visible-linked-detail-error",
                    "title": "",
                    "cover": "",
                    "caption": "",
                    "visible_text": "",
                    "comments": "",
                    "url": url,
                    "final_url": url,
                    "cover_image_url": "",
                    "error": str(exc),
                    "collected_at": datetime.now().isoformat(timespec="seconds"),
                }
            )
        finally:
            page.close()
        time.sleep(max(delay_ms, 1200) / 1000)
    return detail_items


def base_note_url(url: str) -> str:
    return re.sub(r"\?.*$", "", str(url or ""))


def note_id_from_url(url: str) -> str:
    match = re.search(r"/explore/([^/?#]+)", str(url or ""))
    return match.group(1) if match else ""


def collect_clicked_details(page, limit: int, delay_ms: int, target_urls: list[str] | None = None) -> list[dict]:
    detail_items = []
    original_url = page.url
    original_title = page.title()
    targets = target_urls[: max(limit, 0)] if target_urls else list(range(max(limit, 0)))
    for target in targets:
        try:
            if target_urls:
                note_id = note_id_from_url(str(target))
                if not note_id:
                    continue
                card = page.locator(f'.note-item:has(a[href*="{note_id}"])').first
                if card.count() == 0:
                    continue
            else:
                index = int(target)
                count = page.evaluate(COUNT_NOTE_CARDS_SCRIPT)
                if index >= count:
                    break
                card = page.locator(".note-item").nth(index)
            card.scroll_into_view_if_needed(timeout=8000)
            box = card.bounding_box()
            if not box:
                continue
            page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
            page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
            wait_for_note_detail(page)
            time.sleep(max(delay_ms, 1200) / 1000)
            try:
                page.wait_for_load_state("domcontentloaded", timeout=15000)
            except PlaywrightTimeoutError:
                pass
            result = collect_page(page, max_items=1, scroll_times=1, delay_ms=delay_ms)
            item = (result.get("items") or [{}])[0]
            caption = item.get("caption") or ""
            title = item.get("title") or ""
            weak_detail = (
                len(caption) < 100
                or (title and title in original_title)
                or ("活动" in caption and "关注" not in caption and len(caption) < 180)
            )
            if caption and not weak_detail:
                item["source"] = "xhs-python-visible-clicked-detail"
                detail_items.append(item)
            if page.url != original_url:
                page.go_back(wait_until="domcontentloaded", timeout=30000)
                if "search_result" in page.url:
                    try:
                        page.locator(".note-item").first.wait_for(state="visible", timeout=12000)
                    except PlaywrightTimeoutError:
                        pass
                time.sleep(max(delay_ms, 1200) / 1000)
            else:
                page.keyboard.press("Escape")
                time.sleep(max(delay_ms, 1200) / 1000)
        except Exception as exc:
            detail_items.append(
                {
                    "source": "xhs-python-visible-clicked-detail-error",
                    "title": "",
                    "cover": "",
                    "caption": "",
                    "visible_text": "",
                    "comments": "",
                    "url": page.url,
                    "final_url": page.url,
                    "cover_image_url": "",
                    "error": str(exc),
                    "collected_at": datetime.now().isoformat(timespec="seconds"),
                }
            )
            try:
                if page.url != original_url:
                    page.go_back(wait_until="domcontentloaded", timeout=30000)
                    if "search_result" in page.url:
                        try:
                            page.locator(".note-item").first.wait_for(state="visible", timeout=12000)
                        except PlaywrightTimeoutError:
                            pass
            except Exception:
                pass
            time.sleep(max(delay_ms, 1200) / 1000)
    return detail_items


def build_output_file(path_arg: str | None) -> Path:
    if path_arg:
        return Path(path_arg).expanduser().resolve()
    DEFAULT_OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return DEFAULT_OUT_DIR / f"xhs_python_visible_{stamp}.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect visible Xiaohongshu page text from a logged-in browser.")
    parser.add_argument("--page-url", default="https://www.xiaohongshu.com/")
    parser.add_argument("--keyword", default="")
    parser.add_argument("--output", default="")
    parser.add_argument("--max-items", type=int, default=60)
    parser.add_argument("--scroll-times", type=int, default=5)
    parser.add_argument("--delay-ms", type=int, default=1800)
    parser.add_argument("--port", type=int, default=9224)
    parser.add_argument("--profile", default=str(DEFAULT_PROFILE))
    parser.add_argument("--use-current-tab", action="store_true")
    parser.add_argument("--wait-for-user", action="store_true")
    parser.add_argument(
        "--detail-limit",
        type=int,
        default=0,
        help="Open this many visible note links and collect their visible detail text. Keep small and slow.",
    )
    parser.add_argument(
        "--detail-mode",
        choices=["click", "link"],
        default="click",
        help="click uses visible cards on the current page; link opens note URLs directly.",
    )
    parser.add_argument("--days", type=int, default=0, help="Keep only items published within this many days. 0 keeps all.")
    parser.add_argument("--sort-by", choices=["score", "likes", "date"], default="score")
    parser.add_argument("--top", type=int, default=0, help="Keep only the top N items after filtering. 0 keeps all.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    page_url = search_url(args.keyword) if args.keyword else args.page_url
    start_browser(args.port, page_url, Path(args.profile))

    if args.wait_for_user:
        print("")
        print("Log in in the opened browser, then stay on the Xiaohongshu search/topic/profile/note page.")
        print("This tool only reads visible page content. It does not bypass login, QR, captcha, or app-only pages.")
        input("Press Enter here when ready...")

    output_file = build_output_file(args.output)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(f"http://127.0.0.1:{args.port}")
        page = choose_page(browser, page_url, args.use_current_tab)
        print(f"Collecting page: {page.url}")
        result = collect_page(page, args.max_items, args.scroll_times, args.delay_ms)
        items = result.get("items", [])
        target_items = unique_items(items)
        if args.days > 0 or args.sort_by != "score" or args.top > 0:
            target_items = apply_item_filters(target_items, args.days, args.sort_by, args.top or args.max_items)
        else:
            target_items = target_items[: args.max_items]

        if args.detail_limit > 0:
            if args.detail_mode == "click" and "/explore/" not in page.url:
                target_urls = [item.get("url", "") for item in target_items if item.get("url")]
                print(f"Clicking target note cards for detail text: {min(args.detail_limit, len(target_urls))}")
                detail_items = collect_clicked_details(page, args.detail_limit, args.delay_ms, target_urls)
                if detail_items:
                    items = detail_items + items
            else:
                links = [
                    item.get("url", "")
                    for item in items
                    if item.get("url") and "/explore/" in item.get("url", "") and item.get("url") != page.url
                ]
                if links:
                    print(f"Opening visible note links for detail text: {min(args.detail_limit, len(links))}")
                    detail_items = collect_detail_links(page.context, links, args.detail_limit, args.delay_ms)
                    if detail_items:
                        items = detail_items + items

        final_items = unique_items(items)
        if args.days > 0 or args.sort_by != "score" or args.top > 0:
            final_items = apply_item_filters(final_items, args.days, args.sort_by, args.top)
        else:
            final_items = final_items[: args.max_items]

        output = {
            "generated_at": datetime.now().isoformat(timespec="seconds"),
            "note": "Only collects content visible in your logged-in browser; no login, QR, captcha, or permission bypass.",
            "filters": {
                "days": args.days,
                "sort_by": args.sort_by,
                "top": args.top,
            },
            "page_title": result.get("page_title", ""),
            "page_url": result.get("page_url", page.url),
            "needs_login": result.get("needs_login", False),
            "page_text_length": result.get("page_text_length", 0),
            "items": final_items,
        }
        output_file.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Done: {output_file}")
        print(f"Items: {len(output['items'])}")
        if output["needs_login"]:
            print("Warning: login/QR/unavailable text was detected. Results may be incomplete.")
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
