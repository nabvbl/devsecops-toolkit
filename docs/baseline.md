\# DevSecOps Toolkit Baseline (v1)



This toolkit provides a reusable CI security baseline for repos.



\## What the baseline includes

\- Lint: Ruff

\- Tests: Pytest

\- SAST: Semgrep (config: p/ci)

\- Dependency + config scan: Trivy FS

\- Container image scan: Trivy image

\- SBOM: CycloneDX (uploaded as artifact)



\## What blocks the pipeline

\- Semgrep: any blocking rule fired (exit code 1)

\- Trivy: HIGH/CRITICAL vulnerabilities (exit code 1)



