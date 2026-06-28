# Xiaohongshu Viral Decoder

一个本地运行的小红书热点采集与内容拆解工作台。

它把小红书网页端可见内容、Excel/CSV/JSON、榜单截图整理成后续可复用的内容素材：选题候选、标题结构、封面风格、文案拆解、风险提示和 Codex Brief。

这个项目更像一份公开的 AI 工作流练习，不是成熟商业产品，也不用于绕过平台限制。

## 能做什么

- 采集已登录浏览器中正常可见的小红书搜索结果
- 筛选近 7 天、点赞靠前的样本
- 尽量打开目标笔记，读取网页端可见的详情正文
- 导入 Excel、CSV、JSON 或榜单截图
- 拆解标题公式、开头钩子、封面风格、正文结构和可复用点
- 生成 Codex 可以继续读取的内容 Brief
- 提供 `xhs-workbench-writer` skill，用工作台输出继续生成小红书笔记

## 本地使用

先安装 Python 依赖：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

启动工作台：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_xhs_workbench.ps1
```

默认访问：

```text
http://127.0.0.1:8765/
```

## 推荐流程

1. 在工作台输入关键词，比如 `AI工作流`、`Codex`、`AI内容运营`。
2. 点 `打开小红书登录/搜索`，在浏览器中完成登录。
3. 点 `按关键词采集`。
4. 采集完成后点 `直接分析`。
5. 在分析页查看内容候选、结构资产、封面分析、文案拆解和 Codex Brief。
6. 复制 Codex Brief，让 Codex 基于它生成下一篇内容。

## 调用 Skill

本仓库包含一个可选 skill：

```text
skills/xhs-workbench-writer/SKILL.md
```

它适合在 Codex 里处理这类请求：

```text
使用 xhs-workbench-writer skill，基于这份工作台 Brief，帮我写一篇小红书笔记。
```

这个 skill 不负责采集数据，只负责把工作台输出转成自然的小红书内容包，包括标题、正文、封面文案、配图建议、话题词和评论区互动。

## 项目结构

```text
.
├─ xiaohongshu_viral_decoder_v2.html   # 分析页面
├─ start_xhs_workbench.ps1              # 工作台启动脚本
├─ crawler/                             # 小红书网页端可见内容采集器
├─ data/                                # 本地数据目录说明
└─ skills/xhs-workbench-writer/          # Codex 写作 skill
```

## 数据安全

本项目默认只在本地运行，不会把采集数据上传到远程服务。

`.gitignore` 已排除以下内容：

- 小红书采集结果
- 浏览器登录配置
- 本地 Python 环境
- Codex 私有上下文
- 临时截图和预览图

公开分享前仍建议检查一次截图和数据目录，避免包含客户、品牌、达人、报价、账号或个人信息。

## 边界说明

这个工具只读取用户已登录浏览器中正常可见的网页内容，不绕过登录、扫码、验证码、App 限制或平台权限。

如果某条笔记网页端无法查看，工具只会保留列表可见信息，或用标题拆解作为兜底。
