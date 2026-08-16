# CustomeOSDCloud

White-label, customer-configurable deployment orchestration on top of OSDCloud.

## Goals

- One generic deployment engine
- Customer-specific branding and configuration
- ZTI, Hybrid, and Interactive deployment modes
- Customer-specific Autopilot Group Tags and deployment profiles
- OSDCloud for Windows deployment, drivers, and updates
- No tenant secrets stored on USB media or in public bootstrap/config files
- Structured deployment telemetry with DeploymentId, stages, heartbeat, and errors
- State continuity from WinPE to installed Windows

## Status

V0.1 foundation. Destructive deployment actions are intentionally guarded while the orchestration, configuration, and telemetry contracts are established.

## Layout

- `Bootstrap.ps1` - customer-aware entry point
- `src/DeploymentEngine.psm1` - shared orchestration module
- `customers/example/config.json` - example white-label customer configuration
- `schema/customer-config.schema.json` - configuration contract
- `docs/ARCHITECTURE.md` - architecture and security model
- `docs/TELEMETRY.md` - telemetry event contract

## Example

```powershell
.\Bootstrap.ps1 -CustomerConfigUri '.\customers\example\config.json' -Mode Hybrid -WhatIf
```

For production hosting, the customer endpoint can resolve to the same bootstrap engine while supplying that customer's configuration, for example `customer1.osdcloud.example.tld`.
