$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $root ".venv\Scripts\python.exe"
$server = Join-Path $root "crawler\xhs_workbench_server.py"

if (-not (Test-Path $python)) {
  throw "没有找到项目 Python 环境：$python"
}

& $python $server
