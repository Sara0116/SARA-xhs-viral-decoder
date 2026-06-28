# crawler

本目录包含小红书网页端可见内容采集脚本。

核心脚本：

- `xhs_loggedin_visible_collector.py`：连接本机浏览器，读取已登录页面中正常可见的内容。
- `xhs_workbench_server.py`：本地工作台服务，负责打开页面、触发采集、跳转分析页。
- `run_xhs_python_collect.ps1`：命令行采集入口。

采集边界：

- 不绕过登录、扫码、验证码或 App 限制。
- 不调用隐藏接口。
- 不采集不可见或无权限访问的内容。

输出 JSON 默认保存在 `data/processed/`，该目录不会提交到 GitHub。
