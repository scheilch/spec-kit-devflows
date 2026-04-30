# spec-kit-devflow

A [Spec Kit](https://github.com/github/spec-kit) extension that adds five production-tested development workflows — bugfix, modify, refactor, hotfix, and deprecate — covering the complete software development lifecycle beyond new features.

## Problem

Spec Kit provides excellent structured workflows for building new features (`/speckit.specify` -> `/speckit.plan` -> `/speckit.tasks` -> `/speckit.implement`). But the remaining ~75% of development work happens ad-hoc:

- **Bugs**: No systematic approach, regressions happen
- **Feature changes**: No impact analysis, breaking changes slip through
- **Code quality**: No metrics tracking, unclear if refactor helped
- **Emergencies**: No process, panic-driven development
- **Feature removal**: No plan, angry users

## Solution

Five workflows that bring spec-kit's structured approach to all development activities:

| Command | Purpose | Key Feature |
|---------|---------|-------------|
| `/speckit.devflow.bugfix` | Fix bugs systematically | Regression-test-first approach |
| `/speckit.devflow.modify` | Change existing features | Automatic impact analysis |
| `/speckit.devflow.refactor` | Improve code quality | Metrics tracking + behavior preservation |
| `/speckit.devflow.hotfix` | Handle production emergencies | Expedited process + mandatory post-mortem |
| `/speckit.devflow.deprecate` | Sunset features safely | Phased 3-step rollout (warnings -> disabled -> removed) |

## Installation

```bash
# Replace v2.1.1 with the desired version tag
specify extension add --from https://github.com/scheilch/spec-kit-devflows/archive/refs/tags/v2.1.1.zip devflow
```

After installation, the extension is available at `.specify/extensions/devflow/`.

## How It Works

Each workflow follows the same pattern:

```
/speckit.devflow.{workflow} "description"
       |
       v
  Setup script creates branch + directory structure
       |
       v
  Template guides documentation (bug report, impact analysis, etc.)
       |
       v
  /speckit.plan -> /speckit.tasks -> /speckit.implement
```

### Quick Decision Tree

```
Building something new?
  -> /speckit.specify "description"

Fixing broken behavior?
  Production emergency?
    -> /speckit.devflow.hotfix "incident description"
  Non-urgent bug?
    -> /speckit.devflow.bugfix "bug description"

Changing existing feature?
  Adding/modifying behavior?
    -> /speckit.devflow.modify 014 "change description"
  Improving code without changing behavior?
    -> /speckit.devflow.refactor "improvement description"

Removing a feature?
  -> /speckit.devflow.deprecate 014 "deprecation reason"
```

### Example: Fix a Bug

```bash
# 1. Initialize bugfix workflow (creates branch + bug report)
/speckit.devflow.bugfix "profile form crashes when submitting without image"

# 2. Investigate and update bug-report.md with root cause
# 3. Create fix plan
/speckit.plan

# 4. Generate tasks (includes regression test)
/speckit.tasks

# 5. Execute fix (regression test BEFORE implementation)
/speckit.implement
```

## Scripts

Each workflow includes setup scripts for both platforms:

| Platform | Location | Example |
|----------|----------|---------|
| **Bash** | `scripts/bash/` | `create-bugfix.sh --json "description"` |
| **PowerShell** | `scripts/powershell/` | `create-bugfix.ps1 -Json "description"` |

Additional workflow-specific scripts:

| Script | Location | Purpose |
|--------|----------|---------|
| `scan-dependencies.sh` / `.ps1` | `extensions/workflows/deprecate/` | Scan code dependencies before deprecation |
| `scan-impact.sh` / `.ps1` | `extensions/workflows/modify/` | Analyze impact of feature modification |
| `measure-metrics.sh` / `.ps1` | `extensions/workflows/refactor/` | Capture code quality metrics before/after |

## Requirements

- Spec Kit >= 0.4.0
- Git >= 2.0.0

## License

MIT