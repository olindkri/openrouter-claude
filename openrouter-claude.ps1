# openrouter-claude.ps1 — launch Claude Code routed through OpenRouter,
# with a model picker driven by OpenRouter's live programming leaderboard.
#
# Usage:
#   openrouter-claude
#   openrouter-claude -Model kimi
#   openrouter-claude -Model moonshotai/kimi-k2.6 -- --resume
#   openrouter-claude -List
#   openrouter-claude -List -Top 50
#   openrouter-claude -View month
#   openrouter-claude -Refresh

[CmdletBinding()]
param(
  [string]$Model = $env:OPENROUTER_MODEL,
  [switch]$List,
  [switch]$ListAll,
  [string]$View = $(if ($env:OPENROUTER_RANK_VIEW) { $env:OPENROUTER_RANK_VIEW } else { 'week' }),
  [int]$Top = $(if ($env:OPENROUTER_TOP_N) { [int]$env:OPENROUTER_TOP_N } else { 25 }),
  [switch]$Refresh,
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$ConfigDir   = Join-Path $env:USERPROFILE '.openrouter-claude'
$KeyFile     = Join-Path $ConfigDir 'key'
$ModelsCache = Join-Path $ConfigDir 'models.json'
$RankCache   = Join-Path $ConfigDir "rankings.v2.$View.tsv"
if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir | Out-Null }

# --- key (interactive prompt + save if missing) ---
$Key = $env:OPENROUTER_API_KEY
if (-not $Key -and (Test-Path $KeyFile)) { $Key = (Get-Content $KeyFile -Raw).Trim() }
if (-not $Key) {
  if (-not [Environment]::UserInteractive) {
    Write-Error "openrouter-claude: no OpenRouter key. Set `$env:OPENROUTER_API_KEY or write $KeyFile"
    exit 1
  }
  Write-Host "openrouter-claude: no OpenRouter API key configured." -ForegroundColor Yellow
  Write-Host "  Get one at: https://openrouter.ai/keys" -ForegroundColor DarkGray
  $secure = Read-Host "Paste your OpenRouter key (input hidden, starts with sk-or-)" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try   { $Key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  if ([string]::IsNullOrWhiteSpace($Key)) { Write-Error "empty key, aborting."; exit 1 }
  if (-not $Key.StartsWith('sk-or-')) {
    $confirm = Read-Host "Key doesn't start with 'sk-or-'. Save anyway? [y/N]"
    if ($confirm -notmatch '^(y|yes)$') { Write-Error "aborted."; exit 1 }
  }
  Set-Content -Path $KeyFile -Value $Key -NoNewline
  try {
    $acl = Get-Acl $KeyFile
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
      [Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $KeyFile -AclObject $acl
  } catch {}
  Write-Host "openrouter-claude: saved key to $KeyFile" -ForegroundColor Cyan
}

# --- short aliases ---
function Resolve-Model([string]$m) {
  switch ($m) {
    { $_ -in 'kimi','kimi-k2' }      { 'moonshotai/kimi-k2.6'; break }
    'kimi-thinking'                  { 'moonshotai/kimi-k2-thinking'; break }
    'sonnet'                         { 'anthropic/claude-sonnet-4.6'; break }
    'opus'                           { 'anthropic/claude-opus-4.7'; break }
    'haiku'                          { 'anthropic/claude-haiku-4.5'; break }
    { $_ -in 'deepseek','dsv4' }     { 'deepseek/deepseek-v4-pro'; break }
    'deepseek-flash'                 { 'deepseek/deepseek-v4-flash'; break }
    { $_ -in 'glm','glm5' }          { 'z-ai/glm-5.1'; break }
    'qwen'                           { 'qwen/qwen3.6-plus'; break }
    'qwen-coder'                     { 'qwen/qwen3-coder-plus'; break }
    'gemma'                          { 'google/gemma-4-31b-it'; break }
    'gemini'                         { 'google/gemini-2.5-pro'; break }
    'minimax'                        { 'minimax/minimax-m2.7'; break }
    'grok'                           { 'x-ai/grok-4.3'; break }
    'grok-code'                      { 'x-ai/grok-code-fast-1'; break }
    'gpt'                            { 'openai/gpt-5'; break }
    'hy3'                            { 'tencent/hy3-preview'; break }
    default                          { $m }
  }
}

function Get-CacheAgeHours([string]$f) {
  if (-not (Test-Path $f)) { return 999999 }
  return ((Get-Date) - (Get-Item $f).LastWriteTime).TotalHours
}

function Get-Catalog {
  if (-not $Refresh -and (Get-CacheAgeHours $ModelsCache) -lt 6) {
    return (Get-Content $ModelsCache -Raw | ConvertFrom-Json).data
  }
  try {
    $resp = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/models' `
              -Headers @{Authorization="Bearer $Key"} -TimeoutSec 15
    $resp | ConvertTo-Json -Depth 10 | Set-Content $ModelsCache
    return $resp.data
  } catch {
    if (Test-Path $ModelsCache) { return (Get-Content $ModelsCache -Raw | ConvertFrom-Json).data }
    throw
  }
}

function Find-BraceStart([string]$s, [int]$pos) {
  $d = 0
  for ($j = $pos; $j -ge 0; $j--) {
    $c = $s[$j]
    if ($c -eq '}') { $d++ }
    elseif ($c -eq '{') { if ($d -eq 0) { return $j }; $d-- }
  }
  return -1
}
function Find-BraceEnd([string]$s, [int]$start) {
  $d = 0
  for ($j = $start; $j -lt $s.Length; $j++) {
    $c = $s[$j]
    if ($c -eq '{') { $d++ }
    elseif ($c -eq '}') { $d--; if ($d -eq 0) { return $j + 1 } }
  }
  return -1
}

# Output TSV: id\tctx\tprice\tname\trank\ttokens\tdesc — same schema as bash version
function Get-RankedTsv([string]$view) {
  $cache = Join-Path $ConfigDir "rankings.v2.$view.tsv"
  if (-not $Refresh -and (Get-CacheAgeHours $cache) -lt 6) {
    return Get-Content $cache
  }
  $catalog = Get-Catalog
  $idSet    = @{}; foreach ($m in $catalog) { $idSet[$m.id] = $true }
  $nameToId = @{}; foreach ($m in $catalog) { if ($m.name) { $nameToId[$m.name] = $m.id } }
  $meta     = @{}; foreach ($m in $catalog) { $meta[$m.id] = $m }

  $html = (Invoke-WebRequest -Uri "https://openrouter.ai/rankings/programming?view=$view" -TimeoutSec 20).Content
  $pushes = [regex]::Matches($html, 'self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)')
  $sb = New-Object System.Text.StringBuilder
  foreach ($p in $pushes) {
    try { [void]$sb.Append((ConvertFrom-Json ('"' + $p.Groups[1].Value + '"'))) } catch {}
  }
  $allText = $sb.ToString()

  # 1) permaslug -> human name (from chunk #3 — entries with request_count + name)
  $permToName = @{}
  foreach ($m in [regex]::Matches($allText, '"request_count":\d+')) {
    $start = Find-BraceStart $allText $m.Index
    if ($start -lt 0) { continue }
    $end = Find-BraceEnd $allText $start
    if ($end -lt 0) { continue }
    try { $obj = $allText.Substring($start, $end - $start) | ConvertFrom-Json } catch { continue }
    if ($obj.slug -and $obj.name) { $permToName[$obj.slug] = $obj.name }
  }

  # 2) sum tokens per permaslug (chunk #2 — per-day rows)
  $tokens = @{}
  $tokRe  = [regex]'"model_permaslug":"([^"]+)"[\s\S]{0,400}?"total_completion_tokens":(\d+)[\s\S]{0,400}?"total_prompt_tokens":(\d+)'
  foreach ($m in $tokRe.Matches($allText)) {
    $perm = $m.Groups[1].Value
    $sum  = [int64]$m.Groups[2].Value + [int64]$m.Groups[3].Value
    if ($tokens.ContainsKey($perm)) { $tokens[$perm] += $sum } else { $tokens[$perm] = $sum }
  }

  function Resolve-Canonical($perm) {
    if ($idSet[$perm]) { return $perm }
    if ($permToName[$perm] -and $nameToId[$permToName[$perm]]) { return $nameToId[$permToName[$perm]] }
    $stripped = $perm -replace '-\d{8}$|-\d{4}-\d{2}-\d{2}$|-\d{4}$|-0\d{3}$',''
    if ($idSet[$stripped]) { return $stripped }
    return $null
  }

  $ranked = $tokens.GetEnumerator() | Sort-Object { -[int64]$_.Value }
  $lines = New-Object System.Collections.Generic.List[string]
  $rank = 0
  $seen = @{}
  foreach ($e in $ranked) {
    $cid = Resolve-Canonical $e.Key
    if (-not $cid -or $seen[$cid]) { continue }
    $seen[$cid] = $true
    $rank++
    $mm = $meta[$cid]
    $ctx = if ($mm.context_length) { [int64]$mm.context_length } else { 0 }
    $pm = 0.0
    try { if ($mm.pricing.prompt) { $pm = [double]$mm.pricing.prompt * 1e6 } } catch {}
    $tokB = "{0:F1}B" -f ($e.Value / 1e9)
    $desc = ($mm.description -replace "[\r\n\t]"," ").Trim()
    if ($desc.Length -gt 160) {
      $cut = $desc.IndexOf(". ")
      if ($cut -gt 0 -and $cut -lt 180) { $desc = $desc.Substring(0, $cut + 1) }
      else { $desc = $desc.Substring(0, 160).TrimEnd() + "…" }
    }
    $lines.Add(("{0}`t{1}`t{2:F2}`t{3}`t{4}`t{5}`t{6}" -f $cid, $ctx, $pm, $mm.name, $rank, $tokB, $desc))
  }
  $lines | Set-Content $cache
  return $lines
}

function Format-Ctx([int64]$n) {
  if ($n -ge 1000000) { return ("{0:F1}M" -f ($n / 1MB)).Replace(".0M","M") }
  if ($n -ge 1000)    { return "{0}k" -f [int]($n / 1000) }
  return "$n"
}

function Show-Table([string[]]$rows) {
  $i = 0
  $objs = foreach ($l in $rows) {
    $i++
    $f = $l -split "`t"
    [pscustomobject]@{
      '#'           = $i
      ID            = $f[0]
      CTX           = (Format-Ctx ([int64]$f[1]))
      'PromptUSD/M' = ('${0}' -f $f[2])
      Tokens        = $f[5]
      Name          = $f[3]
    }
  }
  $objs | Format-Table -AutoSize | Out-Host
}

# fzf picker: ollama-style multi-line entries. Returns canonical id or empty.
# Uses .NET Process API because PowerShell has no '<' stdin-redirect operator
# and we need to write raw NUL-delimited bytes to fzf's stdin while letting
# fzf draw its TUI on the terminal (it reads keyboard from the console, not stdin).
function Invoke-FzfPicker([string[]]$rows) {
  $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue
  if (-not $fzfCmd) { return $null }

  # Render entries to a byte buffer (UTF-8, NUL-delimited multi-line entries).
  $ms = New-Object IO.MemoryStream
  $sw = New-Object IO.StreamWriter($ms, (New-Object Text.UTF8Encoding($false)))
  foreach ($l in $rows) {
    $f = $l -split "`t"
    while ($f.Count -lt 7) { $f += '' }
    $cid, $ctx, $price, $name, $rank, $tokens, $desc = $f[0..6]
    $ctxs = Format-Ctx ([int64]$ctx)
    if (-not $desc) { $desc = '(no description)' }
    $C = [char]27 + '[36m'; $D = [char]27 + '[2m'; $R = [char]27 + '[0m'
    $sw.Write("$C$cid$R$D · $ctxs ctx · `$$price/M in · #$rank · $tokens$R")
    $sw.Write("`n")
    $sw.Write("      $D$desc$R")
    $sw.Write([char]0)
  }
  $sw.Flush()
  $bytes = $ms.ToArray()
  $sw.Dispose()

  # Spawn fzf with stdin redirected (we feed bytes), stdout captured (selection),
  # stderr unredirected so the TUI renders.
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $fzfCmd.Source
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  # ArgumentList isn't on PS5.1 so build a single Arguments string with quoting.
  $args = @(
    '--read0','--ansi','--height=80%','--reverse','--gap',
    '--layout=reverse-list','--pointer=  ','--marker=✓',
    '--prompt=Select model for Claude Code: ',
    '--header=Type to filter — ↑↓ to move — Enter to launch — Esc to cancel',
    '--no-info','--color=header:dim,prompt:bold,pointer:green:bold,gutter:-1'
  )
  $psi.Arguments = ($args | ForEach-Object {
    if ($_ -match '\s|"') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
  }) -join ' '

  $proc = [Diagnostics.Process]::Start($psi)
  try {
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.Close()
    $picked = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
  } catch {
    return $null
  }
  if ([string]::IsNullOrWhiteSpace($picked)) { return $null }
  $first = ($picked -split "`r?`n")[0] -replace ([char]27 + '\[[0-9;]*m'),''
  return ($first -split ' · ')[0].Trim()
}

if ($List) {
  $rows = (Get-RankedTsv $View) | Select-Object -First $Top
  Show-Table $rows
  Write-Host "(programming leaderboard, view=$View, top=$Top)" -ForegroundColor DarkGray
  exit 0
}
if ($ListAll) {
  $i = 0
  Get-Catalog | Sort-Object id | ForEach-Object {
    $i++
    $pm = 0.0
    try { if ($_.pricing.prompt) { $pm = [double]$_.pricing.prompt * 1e6 } } catch {}
    [pscustomobject]@{
      '#'           = $i
      ID            = $_.id
      CTX           = $_.context_length
      'PromptUSD/M' = ('${0:F2}' -f $pm)
      Name          = $_.name
    }
  } | Format-Table -AutoSize | Out-Host
  exit 0
}

if (-not $Model) {
  if (-not [Environment]::UserInteractive) { $Model = 'moonshotai/kimi-k2.6' }
  else {
    $rows = (Get-RankedTsv $View) | Select-Object -First $Top
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
      Write-Host "OpenRouter programming leaderboard (view=$View, top=$Top) — ↑↓ + Enter, type to filter" -ForegroundColor DarkGray
      $Model = Invoke-FzfPicker $rows
      if (-not $Model) { Write-Host "cancelled." -ForegroundColor Yellow; exit 0 }
    } else {
      Write-Host "Tip: install fzf for arrow-key picking:  winget install junegunn.fzf" -ForegroundColor DarkGray
      Show-Table $rows
      $choice = Read-Host "Pick model [number, full slug, or empty=#1]"
      if ([string]::IsNullOrWhiteSpace($choice)) {
        $Model = ($rows[0] -split "`t")[0]
      } elseif ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $rows.Count) { Write-Error "invalid selection"; exit 1 }
        $Model = ($rows[$idx] -split "`t")[0]
      } else { $Model = $choice }
    }
  }
}
$Model = Resolve-Model $Model

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Error "openrouter-claude: 'claude' CLI not found. Install: npm i -g @anthropic-ai/claude-code"
  exit 1
}

Write-Host "openrouter-claude -> model=$Model  endpoint=https://openrouter.ai/api" -ForegroundColor Cyan

$env:ANTHROPIC_BASE_URL   = 'https://openrouter.ai/api'
$env:ANTHROPIC_AUTH_TOKEN = $Key
$env:ANTHROPIC_API_KEY    = ''
$env:ANTHROPIC_MODEL      = $Model
if (-not $env:ANTHROPIC_SMALL_FAST_MODEL) { $env:ANTHROPIC_SMALL_FAST_MODEL = $Model }

& claude @Rest
exit $LASTEXITCODE
