# Architecture

## Directory layout

```text
PalworldServer/
├── Open-Dashboard.cmd           # Primary operator entry point
├── Open-Server-Manager.cmd      # Compatibility alias to PalOps
├── Manage-Server.ps1            # PalOps launcher; -Legacy enables recovery menu
├── compose.yaml                 # Palworld container definition
├── .env.example                 # Public server configuration template
├── web/                         # Local PalOps HTML, CSS and JavaScript
├── config/
│   ├── PalWorldSettings.ini.example
│   ├── discord.env.example      # Public Discord configuration template
│   ├── discord.env              # Local Discord credentials (ignored)
│   └── admin.env                # Local REST API credential (ignored)
├── data/Saved/                  # Palworld world and server settings (ignored)
├── docker/helper.sh             # Official image startup wrapper
├── scripts/                     # PalOps backend, operations and automation
├── tests/                       # Pester and clean-checkout tests
├── .github/workflows/           # CI and release workflows
├── runtime/                     # PIDs, locks and state markers (ignored)
├── backups/                     # Verified external ZIP backups (ignored)
├── recovery/                    # Data preserved during restore/rollback (ignored)
├── exports/                     # Secret-free migration packages (ignored)
├── logs/                        # Operational logs and metrics (ignored)
├── reports/                     # Local test reports (ignored)
├── work/                        # Temporary restore/update work (ignored)
├── private/                     # Local-only notes (ignored)
└── docs/                        # Operations documentation
```

## Management layers

1. `web/` is the operator-facing PalOps interface.
2. `scripts/dashboard.ps1` exposes a localhost-only HTTP API and validates every request.
3. `scripts/dashboard-action.ps1` serializes long-running operations and records their result.
4. Dedicated scripts perform backup, restore, update, monitoring and Discord integration.
5. Docker runs the Palworld process; Unlim remains a host-side process for UDP connectivity.

PowerShell remains an implementation and recovery layer, but is no longer the normal operator interface.

## Data flow

Docker mounts `data/Saved` into `/pal/Package/Pal/Saved`. Palworld's management REST API is bound only to `127.0.0.1:8212`; PalOps is bound only to `127.0.0.1:8765`; Unlim publishes only the game UDP port. PalOps invokes constrained PowerShell operations for backups, monitoring, Discord updates and safe lifecycle control.

## Repository boundary

Only code, documentation and example configuration belong in source control. World data, credentials, runtime state, backups, recovery copies and logs are excluded by `.gitignore`.
