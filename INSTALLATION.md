# Installation

## Prerequisites

- [Spec Kit](https://github.com/github/spec-kit) >= 0.4.0 installed
- Git repository initialized
- A spec-kit project (directory with `.specify/` folder)

## Install

```bash
# Replace v1.0.0 with the desired version tag
specify extension add --from https://github.com/scheilch/spec-kit-devflows/archive/refs/tags/v1.0.0.zip devflow
```

## Verify

```bash
specify extension list
```

Expected output:

```text
Installed Extensions:

  ✓ Development Workflow Extensions (v1.0.0)
    Five production-tested workflows for bugfix, modify, refactor, hotfix, and deprecate
    Commands: 5 | Status: Enabled
```

## Usage

After installation, the following commands are available:

```bash
/speckit.devflow.bugfix "bug description"
/speckit.devflow.modify 014 "change description"
/speckit.devflow.refactor "improvement description"
/speckit.devflow.hotfix "incident description"
/speckit.devflow.deprecate 014 "deprecation reason"
```

## Update

```bash
specify extension update devflow
```

## Remove

```bash
specify extension remove devflow
```

## Development Installation

For local development and testing:

```bash
git clone https://github.com/scheilch/spec-kit-devflows.git
cd spec-kit-devflows

# Install in dev mode (symlink)
cd /path/to/your-project
specify extension add --dev /path/to/spec-kit-devflows
```