param(
  [switch]$DryRun
)

Write-Host "Applying DevSecOps security baseline..."

$RepoRoot = Get-Location
$ToolkitTemplates = "C:\Users\nabvbl\Documents\devsecops-toolkit\templates"

# Safety check: must be inside a git repo
if (!(Test-Path ".git")) {
  Write-Host "ERROR: This folder is not a git repository (.git not found)." -ForegroundColor Red
  Write-Host "Run this inside your target project folder (the repo you want to secure)." -ForegroundColor Yellow
  exit 1
}

$WorkflowDir = ".github/workflows"
$WorkflowTarget = "$WorkflowDir/ci.yml"

$WorkflowSource = "$ToolkitTemplates/github-actions/python-docker-ci.yml"
$DockerignoreSource = "$ToolkitTemplates/docker/dockerignore"

Write-Host "Will write:"
Write-Host " - $WorkflowTarget"
Write-Host " - .dockerignore"

if ($DryRun) {
  Write-Host "DryRun enabled. No files written."
  exit 0
}

# Create folders if needed
if (!(Test-Path ".github")) { New-Item -ItemType Directory -Path ".github" | Out-Null }
if (!(Test-Path $WorkflowDir)) { New-Item -ItemType Directory -Path $WorkflowDir | Out-Null }

# Copy files
Copy-Item $WorkflowSource $WorkflowTarget -Force
Copy-Item $DockerignoreSource ".dockerignore" -Force

Write-Host "Security baseline applied successfully." -ForegroundColor Green
Write-Host "Next: git add + commit + push."
