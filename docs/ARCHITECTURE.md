# Architecture

## Design principles

CustomeOSDCloud is a white-label orchestration layer. OSDCloud remains the Windows deployment engine; customer identity, allowed choices, deployment profiles, Autopilot Group Tags, security controls, and observability are configuration-driven.

## Flow

1. Generic WinPE/OSDCloud media starts a customer bootstrap endpoint.
2. Bootstrap retrieves customer configuration over HTTPS.
3. A unique `DeploymentId` is generated.
4. Hardware and preflight data are collected.
5. The customer's deployment mode is resolved:
   - **ZTI**: profile defaults, no routine choices.
   - **Hybrid**: profile defaults with customer-approved overrides.
   - **Interactive**: technician chooses from customer-approved values.
6. Selection is passed to OSDCloud.
7. Deployment state is persisted to the installed OS so the same DeploymentId survives reboot.
8. Post-install actions apply timezone, updates and supported driver/firmware actions.
9. Autopilot registration uses interactive Microsoft authentication in V1. No client secret is stored on USB media or in customer configuration.
10. Registration/profile readiness is validated before returning the device to OOBE.

## White-label configuration

Customer-facing text and logo references live under `customer.branding`. The shared engine must not contain a provider brand. Customer Group Tags and deployment profiles are defined only in customer configuration.

## Security boundaries

- Customer configuration contains no passwords, client secrets, storage keys, or Graph credentials.
- Remote configuration must be HTTPS.
- Interactive Microsoft authentication is preferred for V1 Autopilot registration.
- A future telemetry ingestion API should issue short-lived deployment tokens. Endpoints must not receive Log Analytics or storage credentials.
- Destructive disk operations require an explicit confirmation unless an approved ZTI policy deliberately changes that behavior.
- Telemetry must avoid passwords, access tokens, refresh tokens, hardware hashes, and other authentication material.

## Planned components

- Customer-aware bootstrap
- Configuration validator/schema
- White-label WinPE UI
- OSDCloud adapter
- State handoff WinPE -> Windows
- Post-install runner
- Autopilot adapter
- Telemetry client and heartbeat
- Telemetry ingestion API
- Operations dashboard
