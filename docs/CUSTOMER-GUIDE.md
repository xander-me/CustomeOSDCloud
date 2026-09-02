# Customer Guide - Windows Deployment

## Purpose

This guide describes the customer side of the Windows deployment solution: what the deployment tool does, what your organization controls, what a technician sees, how a device is deployed, what is sent to Autopilot, what operational data is collected, and what happens when something fails.

The deployment interface is white-label and can display your organization's name, logo, support text, deployment profiles, and approved installation choices.

## 1. What the solution does

The solution prepares a PC with a clean Windows installation and can register it for Microsoft Windows Autopilot.

A typical deployment is:

```text
Boot deployment USB
  -> load your organization's configuration
  -> verify device/network readiness
  -> choose deployment profile
  -> erase the target disk
  -> install Windows
  -> install appropriate drivers/updates
  -> configure regional settings
  -> register/verify Windows Autopilot
  -> return the PC to Windows OOBE
```

After this process, normal Microsoft Intune and Windows Autopilot policies take over.

## 2. Customer-specific configuration

Your organization defines the choices that appear in the deployment interface. Technicians are not automatically given every option supported by Windows or OSDCloud.

Customer-specific settings can include:

- organization name and logo
- supported deployment modes
- deployment profiles
- Windows versions
- Windows editions
- languages
- driver behavior
- timezone
- Autopilot Group Tags
- update/firmware behavior
- support text

This makes it possible to keep the process standardized while still supporting multiple device scenarios.

## 3. Deployment profiles

A deployment profile is a predefined device scenario.

Examples could be:

```text
Standard PC
Shared PC
Warehouse Device
Kiosk
Developer Workstation
```

A profile can preselect:

```text
Windows       Windows 11 25H2
Edition       Enterprise
Language      English (United States)
Drivers       Automatic
Autopilot     Standard PC / Group Tag STD
```

Profile names and Group Tags are agreed with your IT organization. They are not shared across customers.

## 4. Deployment modes

Your organization can decide which deployment modes technicians may use.

### ZTI

ZTI is the most standardized option. The selected deployment profile determines the installation settings and the technician does not routinely change individual Windows/language/driver/Group Tag values.

This is useful for repeatable high-volume deployments.

### Hybrid

Hybrid starts with approved defaults but allows the technician to change selected customer-approved settings.

Example: most PCs use the Standard profile, but a warehouse PC can select the Warehouse profile or Group Tag.

### Interactive

Interactive provides the technician with the approved choices for the customer. The technician can select Windows version, edition, language, driver option and Autopilot Group Tag where permitted.

No mode allows arbitrary values outside the customer's configured choices.

## 5. What the technician sees

The deployment window shows your organization's branding and the relevant device/deployment information.

Conceptually:

```text
+--------------------------------------------------+
|                 [ CUSTOMER LOGO ]                |
|                  Windows Deployment              |
|                                                  |
| Deployment mode       [ Hybrid              v ]  |
| Deployment profile    [ Standard PC         v ]  |
| Windows version       [ Windows 11 25H2     v ]  |
| Edition               [ Enterprise          v ]  |
| Language              [ English (US)        v ]  |
| Drivers               [ Automatic           v ]  |
| Autopilot Group Tag   [ Standard PC         v ]  |
|                                                  |
| Device: HP EliteBook ...                         |
| Serial: ABC123                                  |
|                                                  |
| [OK] Internet   [OK] TPM   [OK] Secure Boot     |
|                                                  |
|                 START DEPLOYMENT                 |
+--------------------------------------------------+
```

The exact choices depend on your organization's configuration.

## 6. Before starting

The target computer should normally have:

- power/AC connected
- working wired or supported network connectivity
- UEFI firmware
- TPM 2.0 for normal modern Windows/Autopilot scenarios
- Secure Boot enabled where required by customer policy
- no local data that needs to be preserved

The deployment process is designed for clean installation. **The target Windows disk is erased.**

Do not use the process on a computer containing data that has not been backed up.

## 7. Starting the deployment

1. Connect the approved deployment USB/media.
2. Boot the PC from the deployment media.
3. Wait for network and the customer configuration to load.
4. Confirm that the displayed manufacturer/model/serial number matches the intended device.
5. Review preflight checks.
6. Select the required deployment profile.
7. In Hybrid/Interactive mode, review any available Windows/language/driver/Group Tag choices.
8. Start deployment.
9. Confirm the destructive action when prompted.
10. Allow the deployment to run without removing power/network unless instructed.

The device can restart several times during the complete process.

## 8. Disk erase

The deployment performs a clean installation and the target disk is cleared by the OSDCloud deployment engine.

The deployment USB itself is excluded from target disk discovery by the wrapper. The process also requires the deployment environment to be running from WinPE before disk wipe is permitted.

These safeguards reduce risk but do not replace technician verification. Always confirm the correct physical/virtual device before starting.

## 9. Windows and drivers

Windows installation settings come from the selected customer profile/approved options.

Driver mode can be configured per customer. The intended standard behavior is automatic model-appropriate driver handling through the OSDCloud ecosystem.

Windows Update and firmware behavior are also customer-configurable. Exact behavior is documented in the customer's approved deployment configuration.

## 10. Windows Autopilot

If Autopilot is enabled for the customer, the device is registered using the Group Tag selected by the deployment profile/technician.

The Group Tag can be used by the customer's Microsoft Intune/Entra design to place devices into the appropriate deployment flow.

Example:

```text
Standard PC -> STD
Shared PC   -> SHARED
Warehouse   -> WH
Kiosk       -> KIOSK
```

Actual values are unique to each customer's design.

## 11. Authentication and passwords

The deployment solution is designed so that customer Microsoft credentials are not stored on the USB or in customer configuration files.

For the initial implementation, Autopilot registration uses Microsoft's interactive authentication experience. An authorized technician/administrator signs in to Microsoft when registration is required, including MFA/Conditional Access where applicable.

The deployment tool does not provide a custom password collection form and must not store the user's password.

## 12. Autopilot verification

The intended production workflow does more than submit the hardware identity.

It verifies that:

1. the device registration request succeeds
2. the device becomes visible in Autopilot
3. the expected Group Tag is associated with the device
4. the expected Autopilot profile becomes assigned
5. the device is ready to continue to OOBE

This reduces the risk of handing a device to a user before Autopilot is actually ready.

## 13. Remote deployment status

Every deployment receives a unique `DeploymentId`.

The deployment system reports structured status events so support personnel can follow progress without standing beside the PC.

Stages include:

```text
Bootstrap
Preflight
Disk preparation
Windows download
Windows installation
Drivers
Windows Update
Firmware
Windows boot
Post-install
Autopilot authentication
Autopilot registration
Autopilot profile
Ready for OOBE
Complete
```

This means support can determine whether a PC is, for example, downloading Windows, installing drivers, waiting for Autopilot, or has failed.

## 14. Heartbeat

During long-running operations the production solution is designed to send periodic heartbeat messages.

If a device stops reporting, support can see the last known stage and the time of the last contact. This is useful when the PC loses network connectivity, loses power, crashes, or becomes stuck without producing a normal error.

## 15. What operational information is collected

Deployment telemetry can include:

- DeploymentId
- customer identifier
- date/time
- device manufacturer/model
- serial number
- deployment profile
- selected Windows version/edition/language
- selected Autopilot Group Tag
- current deployment stage
- success/failure state
- safe error details and exit codes
- duration/timing
- heartbeat/last contact

Detailed deployment logs may also be retained for troubleshooting.

## 16. What must not be collected in telemetry

The design explicitly excludes authentication secrets such as:

- passwords
- access tokens
- refresh tokens
- private keys
- authorization headers
- reusable Graph credentials
- Autopilot hardware hashes as general telemetry data

Authentication is kept separate from deployment observability.

## 17. If a deployment fails

Do not repeatedly restart a failed deployment without understanding the failure, especially after disk preparation has started.

Provide support with the displayed device serial number and, where available, DeploymentId.

Support can then inspect:

```text
last contact
last successful stage
failure stage
error message / exit code
preceding deployment events
relevant detailed logs
```

This is intended to reduce the need for screenshots, phone descriptions, or physical access to every failed PC.

## 18. Common examples

### Device stops during Windows download

Support can see that the last successful stage was disk preparation and that Windows download stopped reporting. Network/source availability can be investigated.

### Driver installation fails

The failure is associated with the specific model, serial number and deployment. Support can compare failures across other devices of the same model.

### Autopilot takes a long time

Support can distinguish between authentication, registration and profile assignment instead of treating the entire Autopilot process as one opaque step.

### Wrong device type was selected

If the deployment has not yet started destructive processing, cancel and select the correct profile. If deployment has started, contact support before changing the workflow.

## 19. Changes to customer configuration

Changes to supported profiles, Group Tags, languages, Windows versions or other approved options should be coordinated with the platform administrator.

A typical change process is:

```text
Customer requirement
 -> configuration change
 -> validation
 -> test deployment
 -> customer acceptance/pilot
 -> production
```

This prevents an untested customer configuration from affecting active deployments.

## 20. Customer responsibilities

The customer remains responsible for the Microsoft Intune/Autopilot design that receives the device, including:

- valid Microsoft licensing
- Autopilot deployment profiles
- dynamic/static Entra group logic
- Intune assignments
- applications
- compliance/security policies
- Conditional Access implications
- authorized accounts used for Autopilot registration
- approval of Group Tags and deployment profiles

The deployment solution prepares and registers the endpoint; it does not replace the customer's Intune architecture.

## 21. Platform responsibilities

The deployment platform is responsible for the agreed provisioning workflow, including:

- loading the correct customer configuration
- presenting only approved deployment options
- invoking the Windows deployment engine
- maintaining deployment identity/state
- applying agreed post-install actions
- executing the agreed Autopilot registration workflow
- producing operational telemetry/logging
- protecting platform-side credentials and telemetry services

The exact operational/service boundary should be documented for each production customer.

## 22. Successful completion

A deployment should only be considered successfully prepared when the agreed stages have completed. For an Autopilot deployment, the intended final state is:

```text
Windows installed
Drivers/updates completed as configured
Timezone/time synchronization completed
Autopilot device registered
Correct Group Tag verified
Autopilot profile assigned
Deployment telemetry reports ReadyForOOBE/Complete
Device is presented at the expected Windows OOBE experience
```

At that point the normal customer Windows Autopilot and Microsoft Intune enrollment process can begin.
