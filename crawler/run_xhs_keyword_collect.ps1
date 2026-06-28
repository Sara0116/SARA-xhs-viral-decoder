param(
  [string]$Keyword = "AI工作流",
  [int]$MaxItems = 40,
  [int]$ScrollTimes = 6
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "xhs_loggedin_visible_collector.ps1"

& $scriptPath `
  -SearchKeyword $Keyword `
  -WaitForUser `
  -MaxItems $MaxItems `
  -ScrollTimes $ScrollTimes
