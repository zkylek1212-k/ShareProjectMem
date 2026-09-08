# Standalone installer for Windows PowerShell - works WITHOUT Claude Code.
#
#   .\install.ps1              # install into current repo
#   .\install.ps1 C:\my\repo   # install into another repo
#
# Requires Git Bash (ships with Git for Windows), which the hooks need anyway.

param([string]$Target = $PWD)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $Target
try {
    $env:CLAUDE_PLUGIN_ROOT = $Here
    bash "$Here/scripts/init-memory.sh"
    if ($LASTEXITCODE -ne 0) { throw "init-memory.sh failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
