\# Tuning Guide



\## Trivy severity

Default: HIGH,CRITICAL

To be stricter, include MEDIUM:

\- MEDIUM,HIGH,CRITICAL



\## ignore-unfixed

If true: do not fail on vulnerabilities with no fix yet.

If false: stricter, but can create noise.



\## Semgrep

Default config: p/ci

Semgrep fails the job when blocking rules fire.



