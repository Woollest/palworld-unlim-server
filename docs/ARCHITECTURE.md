# Architecture

## Directory layout

```text
PalworldServer/
├── compose.yaml                 # Docker Compose definition
├── .env.example                 # Public server configuration template
├── config/
│   ├── discord.env.example      # Public Discord configuration template
│   ├── discord.env              # Local Discord credentials (ignored)
│   └── admin.env                # Local REST API credential (ignored)
├── data/Saved/                  # Palworld world and server settings (ignored)
├── docker/helper.sh             # Official image startup wrapper
├── scripts/                     # Operations and automation
├── runtime/                     # PIDs, locks and state markers (ignored)
├── backups/                     # Verified external ZIP backups (ignored)
├── recovery/                    # Data preserved during restore/rollback (ignored)
├── logs/                        # Operational logs and metrics (ignored)
└── docs/                        # Operations documentation
```

## Data flow

Docker mounts `data/Saved` into `/pal/Package/Pal/Saved`. The management REST API is bound only to `127.0.0.1:8212`; Unlim publishes only the game UDP port. PowerShell scripts coordinate backups, monitoring, Discord updates and safe shutdowns.

## Repository boundary

Only code, documentation and example configuration belong in source control. World data, credentials, runtime state, backups, recovery copies and logs are excluded by `.gitignore`.
