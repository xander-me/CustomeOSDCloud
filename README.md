# CustomeOSDCloud

**Status: deployment experiment; production behavior has not been validated.**

This repository explores customer-configurable Windows deployment on top of OSDCloud. The default branch currently contains [DefaultBoot.ps1](DefaultBoot.ps1) and this README.

## Current code and proposed foundation

`DefaultBoot.ps1` starts an OS deployment and generates post-install Autopilot registration code. It is an experiment, not a guarded bootstrap implementation. Its failure handling needs review, including restoring Administrator/autologon state when registration fails.

The proposed customer-aware foundation is in [PR #1](https://github.com/xander-me/CustomeOSDCloud/pull/1), on `agent/initial-osdcloud-platform`. That branch contains `Bootstrap.ps1`, the deployment modules, example customer configuration, schema and architecture documents. Those files are not available on main, and this README does not imply that the PR is accepted.

## Next work

Review PR #1's authorization, configuration and failure/recovery paths, then verify the selected flow in an authorized disposable Windows/WinPE lab before accepting deployment behavior. No deployment acceptance evidence was produced by the repository-organization review on 2026-09-21.

The separate [OSDCloud architecture project](https://github.com/xander-me/OSDCloud) describes a broader deployment/telemetry platform. This repository focuses on the customer bootstrap experiment; neither is the official upstream OSDCloud project.
