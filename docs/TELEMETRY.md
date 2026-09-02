# Deployment Telemetry

## Objective

Provide remote visibility into every deployment without requiring physical access to the device.

## Core identity

Each run receives a GUID `DeploymentId`. It must survive the WinPE-to-Windows reboot boundary through persisted state.

## Stages

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

## Event envelope

```json
{
  "schemaVersion": "1.0",
  "deploymentId": "guid",
  "customerId": "customer1",
  "timestampUtc": "2026-08-16T08:00:00Z",
  "device": {
    "serialNumber": "SERIAL",
    "manufacturer": "HP",
    "model": "EliteBook"
  },
  "stage": "DriverInstallation",
  "event": "DriverInstallStarted",
  "status": "Running",
  "severity": "Information",
  "message": "Installing driver package",
  "data": {}
}
```

## Heartbeat

While a long-running stage is active, the endpoint should emit a heartbeat at the customer-configured interval. The operations layer can classify a deployment as stale when multiple heartbeat intervals are missed.

## Failure events

Failure events should include safe diagnostic context such as exception type, exit code, stage, previous action, and script stack trace. Authentication secrets, tokens, passwords, hardware hashes, and private keys must never be included.

## Storage direction

Structured events should go to an ingestion API and analytics store. Large raw logs (PowerShell transcript, OSDCloud, DISM, setup logs) should be uploaded separately to object/blob storage and referenced by DeploymentId rather than ingested wholesale into the analytics event stream.
