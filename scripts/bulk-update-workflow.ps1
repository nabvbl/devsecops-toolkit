param(
  [Parameter(Mandatory = $true)]
  [string]$Owner,                      # e.g. nabvbl

  [Parameter(Mandatory = $true)]
  [string]$FromRef,                    # e.g. v1

  [Parameter(Mandatory = $true)]
  [string]$ToRef,                      # e.g. v2

  [string]$ToolkitRepo = "devsecops-toolkit",

  # If this file exists in a repo, only it will be updated (old behavior).
  # If it does not exist, the script falls back to scanning all workflow YAML files.
  [string]$WorkflowPath = ".github/workflows/ci.yml",

  [switch]$DryRun,
  [int]$Limit = 200
)

$ErrorActionPreference = "Stop"

# Use absolute path because 'gh' is not on PATH in some environments
$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (!(Test-Path $gh)) {
  throw "GitHub CLI not found at: $gh"
}

function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host $msg -ForegroundColor Red }

$UsesFrom = "$Owner/$ToolkitRepo/.github/workflows/python-security-ci.yml@$FromRef"
$UsesTo   = "$Owner/$ToolkitRepo/.github/workflows/python-security-ci.yml@$ToRef"

Write-Info "Bulk update reusable workflow reference:"
Write-Info "  FROM: $UsesFrom"
Write-Info "  TO:   $UsesTo"
if ($DryRun) { Write-Warn "DryRun enabled: no pushes, no PRs." }

# Workspace where repos will be cloned/updated
$WorkDir = Join-Path $PWD "bulk-work"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# Get repo list (names only)
Write-Info "Fetching repos for $Owner (limit=$Limit)..."
$repoNames = & $gh repo list $Owner --limit $Limit --json name --jq '.[].name'
if (-not $repoNames) {
  throw "No repos returned. Check gh auth or owner name."
}
$repos = $repoNames -split "`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 }

# Summary counters
$summary = [ordered]@{
  total                 = 0
  skipped_toolkit       = 0
  skipped_empty         = 0
  skipped_no_workflows  = 0
  skipped_no_match      = 0
  updated               = 0
  errors                = 0
}

foreach ($repo in $repos) {
  $summary.total++

  # Skip the toolkit repo itself
  if ($repo -eq $ToolkitRepo) {
    $summary.skipped_toolkit++
    Write-Info "Skipping toolkit repo: $repo"
    continue
  }

  Write-Info "----"
  Write-Info "Repo: $Owner/$repo"

  $repoDir = Join-Path $WorkDir $repo

  try {
    # Bulletproof metadata fetch: no --jq, parse JSON in PowerShell
    $metaJson = & $gh repo view "$Owner/$repo" --json defaultBranchRef,isEmpty 2>$null
    if (-not $metaJson) { throw "Failed to query repo metadata via gh." }

    $meta = $metaJson | ConvertFrom-Json
    $defaultBranch = $meta.defaultBranchRef.name
    $isEmpty = [bool]$meta.isEmpty

    if ($isEmpty -or [string]::IsNullOrWhiteSpace($defaultBranch)) {
      $summary.skipped_empty++
      Write-Warn "Repo appears empty (no default branch). Skipping."
      continue
    }

    # Clone or update
    if (!(Test-Path $repoDir)) {
      Write-Info "Cloning..."
      git clone "https://github.com/$Owner/$repo.git" $repoDir | Out-Null
    } else {
      Write-Info "Updating existing clone..."
      pushd $repoDir
      git fetch --all --prune | Out-Null
      popd
    }

    pushd $repoDir

    # Checkout default branch safely
    git checkout $defaultBranch | Out-Null
    git pull | Out-Null

    # Decide which workflow files to inspect
    $targets = @()

    # Prefer explicit WorkflowPath if it exists in this repo
    if ($WorkflowPath -and (Test-Path $WorkflowPath)) {
      $targets += (Resolve-Path $WorkflowPath).Path
    } else {
      # Otherwise scan all workflows under .github/workflows
      $wfDir = ".github/workflows"
      if (!(Test-Path $wfDir)) {
        $summary.skipped_no_workflows++
        Write-Warn "No .github/workflows directory. Skipping."
        popd
        continue
      }

      $targets += Get-ChildItem -Path $wfDir -File -Recurse |
        Where-Object { $_.Extension -in @(".yml", ".yaml") } |
        ForEach-Object { $_.FullName }

      if ($targets.Count -eq 0) {
        $summary.skipped_no_workflows++
        Write-Warn "No workflow YAML files found. Skipping."
        popd
        continue
      }
    }

    # Apply replacements across all target workflow files
    $changedFiles = New-Object System.Collections.Generic.List[string]

    foreach ($file in $targets) {
      $content = Get-Content $file -Raw

      if ($content -match [regex]::Escape($UsesFrom)) {
        $newContent = $content.Replace($UsesFrom, $UsesTo)
        if ($newContent -ne $content) {
          Set-Content -Path $file -Value $newContent -NoNewline
          $changedFiles.Add($file)
        }
      }
    }

    if ($changedFiles.Count -eq 0) {
      $summary.skipped_no_match++
      Write-Warn "No workflow files reference FROM ref. Skipping."
      popd
      continue
    }

    # Create branch
    $branch = "chore/update-toolkit-workflow-$ToRef"
    git checkout -b $branch | Out-Null

    # Stage all changed workflow files
    foreach ($f in $changedFiles) {
      git add $f | Out-Null
    }

    $status = git status --porcelain
    if (-not $status) {
      $summary.skipped_no_match++
      Write-Warn "Nothing staged after edits. Skipping."
      git checkout $defaultBranch | Out-Null
      git branch -D $branch | Out-Null
      popd
      continue
    }

    $count = $changedFiles.Count
    git commit -m "chore: bump toolkit reusable workflow to $ToRef ($count file(s))" | Out-Null

    # Build a nice relative list of changed files (safe)
    $relList = ($changedFiles | ForEach-Object {
      try { Resolve-Path -Relative -Path $_ }
      catch { Split-Path $_ -Leaf }
    }) -join "`n"

    if ($DryRun) {
      $summary.updated++
      Write-Warn "DryRun: would push + open PR. Updated $count file(s):"
      $changedFiles | ForEach-Object {
        try { Write-Host ("  - " + (Resolve-Path -Relative -Path $_)) }
        catch { Write-Host ("  - " + (Split-Path $_ -Leaf)) }
      }
      popd
      continue
    }

    git push -u origin $branch | Out-Null

    # Open PR
    $title = "chore: bump toolkit workflow to $ToRef"
    $body  = @"
This updates the reusable workflow reference from `$FromRef` to `$ToRef`.

- FROM: $UsesFrom
- TO:   $UsesTo

Updated file(s):
$relList
"@

    & $gh pr create --title $title --body $body --base $defaultBranch --head $branch | Out-Null

    $summary.updated++
    Write-Info "PR opened for $Owner/$repo"

    popd
  }
  catch {
    $summary.errors++
    Write-Err "Error in ${Owner}/${repo}: $($_.Exception.Message)"
    try { popd 2>$null } catch {}
    continue
  }
}

Write-Info "==== Summary ===="
Write-Host ("Total repos:            {0}" -f $summary.total)
Write-Host ("Skipped (toolkit):      {0}" -f $summary.skipped_toolkit)
Write-Host ("Skipped (empty):        {0}" -f $summary.skipped_empty)
Write-Host ("Skipped (no workflows): {0}" -f $summary.skipped_no_workflows)
Write-Host ("Skipped (no match):     {0}" -f $summary.skipped_no_match)
Write-Host ("Updated (branch/PR):    {0}" -f $summary.updated)
Write-Host ("Errors:                 {0}" -f $summary.errors)

Write-Info "Done."
