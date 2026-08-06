# Sync the lua_SQLBuilder library into the vendored copy used by
# fireBookStore-backend (lualib/sqlBuilder).
#
# The vendored copy uses the `sqlBuilder.*` module prefix and its own
# class.lua (cfadmin's `require "class"` is not call-compatible with the
# library's component construction). json forwards to the app's `json`.
#
# Usage:
#   pwsh scripts/sync-vendor.ps1 -Apply   # write into fireBookStore
#   pwsh scripts/sync-vendor.ps1          # preview only (default)

param(
  [switch]$Apply,
  [string]$Repo = "D:\lua\lua_SQLBuilder",
  [string]$App = "D:\lua\fireBookStore-backend"
)

$src = Join-Path $Repo "lua_SQLBuilder"
$dst = Join-Path $App "lualib\sqlBuilder"
$preview = Join-Path $Repo ".vendor-preview\sqlBuilder"

$target = if ($Apply) { $dst } else { $preview }

Write-Host "==> syncing lua_SQLBuilder -> $target"

# Files copied verbatim (require prefix rewritten below)
$files = @(
  "class.lua", "dialect.lua", "SQLBuilder.lua", "SELECT.lua",
  "UPDATE.lua", "INSERT.lua", "DELETE.lua", "utils.lua"
)
$comps = @("WHERE", "OR", "ORDER", "GROUP", "HAVING", "LIMIT")

New-Item -ItemType Directory -Force -Path $target | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $target "sql_comp") | Out-Null

# Rewrite require prefixes: lua_SQLBuilder.X -> sqlBuilder.X
function Rewrite-Requires([string]$content) {
  return $content -replace 'require\s+"lua_SQLBuilder\.', 'require "sqlBuilder.'
}

foreach ($f in $files) {
  $content = Get-Content (Join-Path $src $f) -Raw
  $content = Rewrite-Requires $content
  Set-Content (Join-Path $target $f) $content -NoNewline
  Write-Host "  copied $f"
}
foreach ($c in $comps) {
  $content = Get-Content (Join-Path $src "sql_comp\$c.lua") -Raw
  $content = Rewrite-Requires $content
  Set-Content (Join-Path $target "sql_comp\$c.lua") $content -NoNewline
  Write-Host "  copied sql_comp\$c.lua"
}

# init.lua: module exports + MySQL default (fireBookStore is MySQL)
$init = @'
local SQLBuilder = require "sqlBuilder.SQLBuilder"
local SELECT = require "sqlBuilder.SELECT"
local UPDATE = require "sqlBuilder.UPDATE"
local INSERT = require "sqlBuilder.INSERT"
local DELETE = require "sqlBuilder.DELETE"

local M = {
    SQLBuilder = SQLBuilder,
    SELECT = SELECT,
    UPDATE = UPDATE,
    INSERT = INSERT,
    DELETE = DELETE,
}

-- The application is MySQL-flavored; declare it so dialect features are enabled.
local dialect = require("sqlBuilder.dialect")
M.set_default_dialect = dialect.set_default
M.get_default_dialect = dialect.get_default
M.set_default_dialect("mysql")

return M
'@
Set-Content (Join-Path $target "init.lua") $init -NoNewline
Write-Host "  wrote init.lua (default dialect: mysql)"

# Keep the vendored json/init.lua (forwards to the app's `json`) - do not copy
# the repo's json.lua. utils.lua requires "sqlBuilder.json" which resolves to
# json/init.lua.

# ---- verification: every .lua must parse under a local Lua interpreter ----
$lua = Get-Command lua -ErrorAction SilentlyContinue
if ($lua) {
  $fail = 0
  Get-ChildItem $target -Recurse -Filter "*.lua" | ForEach-Object {
    $path = $_.FullName -replace "\\", "/"
    $out = & lua -e "local f,e = loadfile('$path'); if not f then io.write(e) end" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "  SYNTAX FAIL: $($_.Name)"; $out; $fail++ }
  }
  if ($fail -eq 0) { Write-Host "==> all $((Get-ChildItem $target -Recurse -Filter '*.lua').Count) files parse OK" }
} else {
  Write-Host "==> lua not on PATH; skipped syntax verification"
}

Write-Host ""
if ($Apply) {
  Write-Host "==> applied to $dst"
} else {
  Write-Host "==> preview at $preview (run with -Apply to write into $dst)"
}
