Write-Host "Applying DevSecOps security baseline..."

$CurrentPath = Get-Location
$ToolkitPath = "C:\Users\nabvbl\Documents\devsecops-toolkit\templates"

# Create .github/workflows if not exists
if (!(Test-Path ".github")) {
    New-Item -ItemType Directory -Path ".github" | Out-Null
}

if (!(Test-Path ".github/workflows")) {
    New-Item -ItemType Directory -Path ".github/workflows" | Out-Null
}

# Copy CI workflow
Copy-Item "$ToolkitPath\python-docker-ci.yml" ".github\workflows\ci.yml" -Force

# Copy dockerignore
Copy-Item "$ToolkitPath\dockerignore" ".dockerignore" -Force

Write-Host "Security baseline applied successfully."
