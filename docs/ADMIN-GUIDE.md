# Platform Administrator Guide

## Purpose

This guide is for the administrator who owns and operates the CustomeOSDCloud platform. It describes the provider side of the solution: shared code, customer onboarding, configuration, hosting, security, deployment modes, Autopilot integration, telemetry, troubleshooting, and lifecycle management.

> Status: the repository is currently an early implementation. The guide describes both implemented V0.1 behavior and the intended V1 architecture. Sections that depend on future components are explicitly marked.

## 1. Architecture overview

The platform separates shared deployment logic from customer-specific configuration.

```text
Generic OSDCloud WinPE/USB
        |
        v
Customer bootstrap endpoint
customer1.osdcloud.example.tld
        |
        +--> customer config / branding
        |
        v
Shared Bootstrap.ps1
        |
        +--> DeploymentEngine.psm1
        +--> DeploymentUI.psm1
        |
        v
OSDCloud
        |
        +--> Disk wipe
        +--> Windows deployment
        +--> Drivers / updates
        |
        v
Post-install / Autopilot
        |
        v
Windows OOBE

Throughout the process:
Endpoint --> Telemetry API --> Analytics / dashboard / log storage
```

The customer endpoint identifies the customer. The shared engine must not contain customer-specific Group Tags, credentials, tenant secrets, branding, or deployment decisions.

## 2. Repository structure

- `Bootstrap.ps1` - entry point and orchestration.
- `src/DeploymentEngine.psm1` - deployment context, preflight, telemetry, state, OSDCloud adapter and Autopilot foundation.
- `src/DeploymentUI.psm1` - white-label WPF deployment UI.
- `customers/<customer>/config.json` - customer-specific policy and choices.
- `schema/customer-config.schema.json` - configuration contract.
- `docs/ARCHITECTURE.md` - architecture and security boundaries.
- `docs/TELEMETRY.md` - telemetry event model.
- `docs/CUSTOMER-GUIDE.md` - customer-facing guide.

## 3. Customer onboarding

Create one configuration directory per customer. Do not fork the engine for individual customers.

Recommended naming:

```text
customers/
  contoso/
    config.json
    assets/
      logo.png
  fabrikam/
    config.json
```

Use a stable lowercase customer ID containing only letters, numbers and hyphens.

### 3.1 Branding

Configure customer-facing identity under `customer.branding`:

```json
{
  "customer": {
    "id": "contoso",
    "displayName": "Contoso A/S",
    "branding": {
      "windowTitle": "Contoso A/S - Windows Deployment",
      "heading": "Windows Deployment",
      "logoUri": "https://contoso.osdcloud.example.tld/assets/logo.png",
      "supportText": "Contact IT Service Desk if deployment fails."
    }
  }
}
```

The shared GUI has no provider branding. If `logoUri` is omitted/null, the GUI continues without a logo.

### 3.2 Deployment modes

Three modes are defined:

- **ZTI** - deployment profile values are locked. Intended for a highly standardized build.
- **Hybrid** - customer defaults are preselected but approved settings can be changed by the technician.
- **Interactive** - technician explicitly chooses from the customer-approved options.

Example:

```json
"deployment": {
  "defaultMode": "Hybrid",
  "allowedModes": ["ZTI", "Hybrid", "Interactive"],
  "requireWipeConfirmation": true
}
```

A customer can expose only the modes that make sense for its operating model.

### 3.3 Deployment profiles

Profiles describe common device personas. Prefer profiles over asking a technician to make every choice for every device.

```json
{
  "id": "warehouse",
  "displayName": "Warehouse Device",
  "description": "Shared Windows device used in warehouse operations",
  "default": false,
  "groupTag": "WH",
  "windowsVersion": "Windows 11 25H2",
  "edition": "Enterprise",
  "language": "en-us",
  "drivers": "Auto"
}
```

A profile may represent Standard PC, Shared PC, Warehouse, Kiosk, Developer, POS-support device, or another customer-defined persona.

### 3.4 Allowed values versus defaults

The `options` section controls the values the technician is permitted to choose.

```json
"languages": {
  "default": "en-us",
  "allowed": ["en-us", "da-dk"]
}
```

Do not expose an option merely because OSDCloud supports it. Expose only choices approved for the customer.

## 4. Autopilot Group Tags

Group Tags are customer-specific and must be configured per customer.

```json
"groupTags": [
  {
    "displayName": "Standard PC",
    "value": "STD",
    "description": "Standard corporate device",
    "default": true
  },
  {
    "displayName": "Warehouse",
    "value": "WH",
    "description": "Shared warehouse device",
    "default": false
  }
]
```

The `displayName` is for technicians. `value` is the actual Autopilot Group Tag.

Validate Group Tags against the customer's Intune/Entra dynamic group design before production use. A wrong Group Tag can cause a device to receive the wrong Autopilot profile, application set, configuration, or security baseline.

## 5. Security model

Never place the following in the USB, bootstrap script, customer JSON, Git repository, or browser-accessible static content:

- passwords
- client secrets
- private certificate keys
- refresh/access tokens
- Azure Storage account keys
- Log Analytics shared keys
- reusable Graph bearer tokens

### 5.1 Autopilot authentication

V1 uses interactive Microsoft authentication. The technician/admin authenticates to the customer's Microsoft tenant when Autopilot registration is required. MFA and applicable Conditional Access remain under Microsoft Entra control.

The platform must not implement a custom username/password capture form.

A future service-to-service implementation should put Graph credentials behind a protected backend/API rather than distributing credentials to endpoints.

### 5.2 Customer endpoint

Remote configuration must be served over HTTPS. A customer endpoint is an identifier and configuration entry point, not an authentication secret.

Assume that a person may discover a customer URL. Discovery of the URL must not grant access to customer Graph, Azure, Intune, telemetry storage, or other privileged services.

## 6. Boot media

The design goal is one generic OSDCloud-capable WinPE/USB image.

The media should contain only the minimum required bootstrap capability. Customer configuration and shared application logic should be retrieved centrally where practical so that routine customer changes do not require rebuilding every USB stick.

Before production rollout, pin/test compatible OSDCloud/OSD module versions rather than blindly consuming an untested latest version.

## 7. Starting a deployment

Current repository test example:

```powershell
.\Bootstrap.ps1 -CustomerConfigUri '.\customers\example\config.json' -WhatIf
```

Use `-WhatIf` for non-destructive validation.

For a real WinPE deployment, remove `-WhatIf` only on a VM or dedicated test device until the complete workflow has passed acceptance testing.

Scripted/no-GUI execution:

```powershell
.\Bootstrap.ps1 -CustomerConfigUri '.\customers\example\config.json' -Mode ZTI -ProfileId standard -NoGui
```

## 8. Disk wipe

Disk wipe is enabled through the OSDCloud workflow. The wrapper does not independently execute `Clear-Disk`; it hands the deployment to OSDCloud so there is one disk preparation mechanism.

Current safeguards include:

- system drive must be `X:` (WinPE)
- `Start-OSDCloud` must be available
- USB disks are excluded from target discovery
- PowerShell `ShouldProcess` / `-WhatIf` is supported
- disk wipe lifecycle is emitted as telemetry

Treat any real deployment as destructive. Verify device identity and test with dedicated hardware/VMs.

## 9. Preflight

The current preflight checks include:

- network/default gateway
- HTTPS connectivity to Microsoft
- TPM readiness
- Secure Boot status

Future production preflight should additionally validate AC power, disk suitability/free health indicators, UEFI state, date/time, DNS, customer configuration reachability, OSDCloud source availability, and telemetry endpoint reachability.

A failed internet check blocks deployment. TPM/Secure Boot are currently warnings because VM test environments may not expose them correctly; production policy can make them blocking conditions.

## 10. Deployment state

Every deployment receives a GUID `DeploymentId`.

State is persisted so the same deployment can be followed across WinPE and installed Windows. The target location is:

```text
C:\ProgramData\OSDDeployment\state.json
```

The state contains deployment identity and selected configuration. Never persist authentication tokens or passwords in this file.

## 11. Telemetry and remote operations

Telemetry is designed to answer three questions remotely:

1. Which devices are deploying right now?
2. How far has each deployment progressed?
3. What exactly failed, and where?

The stage model is:

1. Bootstrap
2. Preflight
3. DiskPreparation
4. WindowsDownload
5. WindowsInstallation
6. DriverInstallation
7. WindowsUpdate
8. Firmware
9. WindowsBoot
10. PostInstall
11. AutopilotAuthentication
12. AutopilotRegistration
13. AutopilotProfile
14. ReadyForOOBE
15. Complete

Structured events contain customer ID, DeploymentId, device identity, stage, event, status, severity, message, and safe diagnostic data.

### 11.1 Heartbeat

Long-running operations should emit a heartbeat. The dashboard can mark a deployment stale if multiple heartbeat intervals are missed. This allows remote detection of power loss, crashes, network loss, or a frozen process even when no explicit exception is generated.

### 11.2 Full logs

Do not ingest every raw log line into the analytics event store. Recommended separation:

```text
Structured events -> ingestion API -> analytics store
Raw logs          -> ingestion API -> blob/object storage
```

Raw logs can include PowerShell transcript, OSDCloud logs, DISM/setup logs and Windows Update diagnostics, referenced by DeploymentId.

### 11.3 Sensitive telemetry

Never log passwords, tokens, private keys, Autopilot hardware hashes, authorization headers, or complete authentication responses.

## 12. Telemetry backend - planned V1

The endpoint must not post directly using permanent Azure credentials. Recommended pattern:

```text
Deployment endpoint
    |
    | HTTPS + short-lived deployment token
    v
Telemetry ingestion API
    |
    +--> validate customer/deployment/token
    +--> rate limit / payload limit
    +--> structured events -> analytics
    +--> raw logs -> object storage
```

A deployment token should be scoped to a single deployment/customer and expire after a short period, for example several hours.

## 13. Operations dashboard - planned V1

The dashboard should provide:

- active deployments
- customer
- model/serial
- profile and Group Tag
- current stage
- elapsed time
- last heartbeat
- success/failure
- recent failures
- stage duration
- deployment event timeline
- downloadable raw logs

Useful aggregate metrics include success rate, average deployment duration, failure rate by customer/model/stage, driver failures, Windows Update failures, and Autopilot registration/profile delays.

## 14. Autopilot workflow - planned V1

Target workflow after Windows is applied:

```text
Boot Windows
  -> restore DeploymentId/state
  -> network/timezone/time sync
  -> interactive Microsoft authentication
  -> collect hardware identity
  -> import into Autopilot with selected Group Tag
  -> wait for device registration
  -> validate Group Tag
  -> wait for Autopilot profile assignment
  -> report ReadyForOOBE
  -> reboot/return to OOBE
```

Do not consider an upload alone to be success. The workflow should verify that the device exists and the expected profile has been assigned before declaring the deployment ready.

## 15. Customer change procedure

For a normal customer configuration change:

1. Change only the customer's `config.json` where possible.
2. Validate JSON against the schema.
3. Confirm default profile and Group Tag.
4. Verify every profile references an allowed OS/edition/language/driver option.
5. Test with `-WhatIf`.
6. Test on a disposable VM/dedicated device for changes affecting OSDCloud execution.
7. Review telemetry.
8. Publish configuration.

Changes to shared engine code affect every customer and therefore require broader regression testing.

## 16. Recommended release process

Maintain a development/test customer that never maps to a production tenant. Validate shared engine releases there first.

Suggested lifecycle:

```text
feature branch
 -> automated/static validation
 -> disposable VM test
 -> dedicated hardware test
 -> pilot customer/profile
 -> production release
```

Version both the engine and configuration schema. Telemetry events should include engine/config versions in a future revision so historical deployments can be correlated with the code that produced them.

## 17. Troubleshooting sequence

When a deployment fails remotely:

1. Locate the DeploymentId.
2. Check last heartbeat.
3. Identify last successful stage.
4. Inspect the failure event and exception/exit code.
5. Review the preceding event timeline.
6. Retrieve the relevant raw log by DeploymentId.
7. Determine whether the failure is device-specific, model-specific, customer-specific, or platform-wide.
8. Re-run only after understanding whether a retry is safe.

For widespread failures, stop new deployments until the shared dependency or configuration is understood.

## 18. Definition of production-ready

Before general customer use, complete at least:

- end-to-end OSDCloud parameter validation for supported Windows releases
- GUI testing in the actual WinPE image
- customer JSON schema validation at runtime
- WinPE-to-Windows state handoff
- post-install runner
- interactive Autopilot import and profile verification
- timezone/time sync
- heartbeat implementation
- authenticated telemetry ingestion API
- raw log upload
- operations dashboard
- retry/offline behavior
- code signing/integrity strategy
- documented supported OSDCloud/PowerShell/Windows versions
- recovery procedure if the central service is unavailable
