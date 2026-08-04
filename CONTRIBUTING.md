# Contributing

Contributions are welcome for bug fixes, documentation and operational safety improvements.

## Before submitting a change

1. Do not include world saves, Discord tokens, channel IDs, passwords, Unlim keys, logs or backups.
2. Keep the Palworld REST API bound to `127.0.0.1`.
3. Run the repository checks:

   ```powershell
   ./scripts/test-project.ps1
   ```

4. Run Pester when available:

   ```powershell
   Invoke-Pester ./tests/Project.Tests.ps1
   ```

5. Run the clean-checkout setup test:

   ```powershell
   ./tests/test-clean-checkout.ps1
   ```

6. Update the README or documentation when behavior changes.

Operational changes should preserve safe shutdown, verified backup and rollback behavior.
