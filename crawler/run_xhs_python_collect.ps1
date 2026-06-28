$ErrorActionPreference = "Stop"

$python = Join-Path (Split-Path $PSScriptRoot -Parent) ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
  throw "Project Python was not found. Expected: $python"
}

& $python (Join-Path $PSScriptRoot "xhs_loggedin_visible_collector.py") `
  --use-current-tab `
  --wait-for-user `
  --max-items 40 `
  --scroll-times 5 `
  --delay-ms 1800 `
  --detail-limit 8
