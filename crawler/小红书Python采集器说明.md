# 小红书 Python 采集器说明

这个采集器用于读取“你已经登录并且当前网页端可见”的小红书内容，导出成 `xiaohongshu_viral_decoder_v2.html` 可以直接导入的 JSON。

它不会绕过登录、扫码、验证码、App 限制或隐藏接口。遇到平台不让网页端查看的笔记，只会跳过或记录列表可见信息。

## 常用方式

1. 打开小红书网页并登录。
2. 搜索你要看的关键词，比如 `AI工作流`、`Codex`、`AI内容运营`。
3. 更推荐打开统一工作台：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_xhs_workbench.ps1
```

工作台默认会从候选池里筛：

- 近 7 天
- 按点赞数排序
- 最多前 30 篇
- 同时尝试抓取部分详情正文，用于文案拆解

也可以运行旧的命令行方式：

```powershell
powershell -ExecutionPolicy Bypass -File .\crawler\run_xhs_python_collect.ps1
```

脚本会等待你确认，然后采集当前页：

- 列表页：抓标题、链接、列表可见互动数据。
- 详情页：抓当前笔记正文。
- 列表页自动点开详情：默认最多尝试 8 条，抓不到正文的会自动过滤掉。

输出文件在：

```text
data\processed\xhs_python_visible_时间.json
```

把这份 JSON 拖进 `xiaohongshu_viral_decoder_v2.html` 就能分析。

## 指定关键词采集

```powershell
.\.venv\Scripts\python.exe .\crawler\xhs_loggedin_visible_collector.py --keyword "AI工作流" --detail-limit 8
```

建议 `--detail-limit` 不要太大，先用 5 到 10 条，确认质量后再加。
