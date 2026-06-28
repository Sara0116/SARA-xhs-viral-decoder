---
name: xhs-workbench-writer
description: Turn Xiaohongshu viral decoder workbench outputs into natural Xiaohongshu posts. Use when the user provides a Codex Brief, workbench JSON, exported analysis, content candidates, copy breakdowns, viral patterns, cover analysis, or asks to write Xiaohongshu content from the local hotspot/viral decoder workbench.
---

# XHS Workbench Writer

Use this skill to write Xiaohongshu posts from the user's local viral decoder workbench outputs.

The goal is not to copy viral posts. The goal is to turn workbench findings into one useful, human-feeling note that documents a real AI workflow, learning process, or content-operations experiment.

## Inputs To Look For

Prefer these fields when present:

- `content_candidates`: title direction, user pain, real scene, AI/Codex intervention, cover text, interaction prompt.
- `copy_breakdowns`: opening type, body structure, interaction style, reusable points, tags, detail level.
- `viral_patterns`: high-frequency hooks, title formulas, content formats, user pains, cover styles.
- `summary.filters`: time window, sort method, top count.
- `risk_rows`: sensitive or risky rows to avoid.
- `Codex Brief`: account positioning, data overview, topic recommendations, generation requirements.

If only a pasted brief is available, use the brief directly. If only raw JSON is available, infer the same fields from it.

## Writing Principles

- Write like a real person recording a tool-building or AI-workflow attempt.
- Keep the user as a learner or practitioner, not an AI expert.
- Do not overuse "广告乙方"; mention work scenes only when they naturally help the story.
- Do not foreground career-transition goals unless the user explicitly asks for a phase review.
- Do not promise growth, efficiency, or results beyond what the data supports.
- Do not copy source titles, captions, comments, or cover text verbatim except very short labels.
- Do not reveal client names, brand names, creator quotes, prices, budgets, backstage data, accounts, or contact details.
- If detail text is sparse, say the limitation plainly instead of pretending the analysis is complete.

## Default Output

Produce one ready-to-post package:

1. Title options: 3-5 options, natural and not clickbait.
2. Main post: 150-300 Chinese characters by default. Short paragraphs. Allow light emoji or symbols if they fit.
3. Cover copy: main title, subtitle, and optional small text.
4. Image or carousel suggestions: 3-6 frames if useful.
5. Hashtags: 6-10 tags, mix broad and specific.
6. Comment prompt: one low-pressure question.

Only add extra sections when the user asks.

## Structure For Tool-Building Posts

Use this sequence when the topic is "I built this workbench/tool/skill":

1. Hook: start with the real repeated pain.
2. Why: explain what manual step was annoying.
3. Build process: describe the simplest believable path, such as Excel, screenshots, visible page collection, filters, detail capture, Codex Brief.
4. Result: say what the tool can output now.
5. Limitation: mention what is still semi-automatic or unstable.
6. GitHub CTA: use a soft request if the repo is public.

Soft GitHub Star CTA examples:

- "我先放到 GitHub 了，想看后续迭代可以顺手点个 Star，当作催更。"
- "不是成熟产品，更像我的公开作业本；如果你也想试，可以去 GitHub 看看。"

Avoid hard CTA like "求点赞求转发" or "必须收藏".

## Title Patterns

Prefer:

- "我做了一个小红书热点采集分析工作台"
- "不想再手动刷热点，我让 Codex 帮我做了个工作台"
- "0 基础做 AI 工作流：先从一个小红书分析工具开始"
- "我把小红书热点整理成了 Codex 能读的 brief"

Avoid:

- "普通人必看"
- "颠覆认知"
- "小红书爆款密码"
- "全自动躺赚"
- Titles that imply platform bypassing or scraping private data.

## Final Check

Before finalizing:

- Confirm the post is about the user's own process, not a generic AI tutorial.
- Confirm the output does not sound like a course ad.
- Confirm the GitHub CTA is soft.
- Confirm limitations are honest.
- Confirm sensitive business data is absent.
