# Hosting and Telemetry

## Decision

The platform separates distribution from observability.

```text
Customer DNS (*.using-it.dk)
          |
          v
GitHub Pages / repository distribution
          |
          +-- bootstrap / shared engine
          +-- customer config
          +-- branding assets

Deployment endpoint
          |
          +--> Basic telemetry API (default)
          |
          +--> Customer Azure telemetry (optional)
```

## GitHub distribution

GitHub is used for versioning and distribution of stateless deployment content. Customer DNS provides a stable, friendly entry point while the underlying implementation can remain a shared repository/site.

Do not store secrets in GitHub Pages content or customer configuration. Treat all client-downloadable content as discoverable.

Recommended content model:

```text
site/
  bootstrap.ps1
  engine/
  customers/
    customer1/config.json
    customer2/config.json
  assets/
    customer1/logo.png
```

A single shared Pages deployment is preferred over maintaining a separate codebase per customer.

## Basic telemetry

Basic telemetry is the default and requires no customer-owned Log Analytics workspace or Blob Storage account.

It is intended to store small structured events only:

- customer ID
- DeploymentId
- serial number
- manufacturer/model
- deployment profile / Group Tag where relevant
- stage / status
- timestamp / duration
- safe error code and error message

It must not store passwords, authentication tokens, private keys, Autopilot hardware hashes, authorization headers, or reusable secrets.

Example configuration:

```json
"telemetry": {
  "enabled": true,
  "mode": "Basic",
  "heartbeatSeconds": 30,
  "basic": {
    "endpoint": "https://log.using-it.dk/api/v1/events"
  }
}
```

The public endpoint shown above is an architecture target; the ingestion service must exist and be secured before production use.

## Enhanced Azure telemetry

Customers can optionally enable an Azure-backed destination. The deployment engine can send the same event envelope to Basic and Azure destinations without changing deployment logic.

```json
"azure": {
  "enabled": true,
  "endpoint": "https://customer-ingestion.example/api/events",
  "fullLogs": true
}
```

Endpoints must call an ingestion API, not expose Log Analytics shared keys, storage account keys, SAS tokens with broad/long-lived access, or other permanent Azure credentials to the deployment device.

## Backend-agnostic event routing

`Send-DeploymentEvent` resolves configured targets and posts the same structured event to each enabled destination. Failure to reach one telemetry target does not currently abort the OS deployment; it produces a local warning.

This allows these models:

- Basic only
- Azure only (once configuration supports disabling Basic explicitly)
- Basic + Azure
- future alternate backends

## Future ingestion security

Before Basic telemetry is production-ready, implement a small ingestion service that:

1. creates/validates a deployment session,
2. issues a short-lived token scoped to customer + DeploymentId,
3. validates event schema and allowed fields,
4. limits payload size and request rate,
5. rejects stale/replayed requests where practical,
6. writes structured events to the selected datastore,
7. stores large raw logs separately,
8. provides read access only to authenticated administrators/customer roles.

The endpoint must never trust a `customerId` supplied by an unauthenticated client as authorization to read or overwrite customer data.

## Heartbeat

The engine now exposes `Send-DeploymentHeartbeat`. Long-running adapters should call it at the configured interval. A later orchestration revision will add automatic heartbeat scheduling around OSDCloud, update, driver, and Autopilot wait operations.

## GitHub is not a logging backend

Do not write deployment logs back to repository files, GitHub Issues, Actions, or commits from endpoints. Doing so would require distributing a GitHub credential or creating an unsafe unauthenticated write mechanism. GitHub remains the read/distribution plane; telemetry uses a dedicated write/observability plane.
