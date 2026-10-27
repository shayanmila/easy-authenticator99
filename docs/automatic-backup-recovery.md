# Automatic encrypted backup and recovery: security requirements

## Scheduling
Supported user settings: minute/hour/day interval, daily local time, weekday+local time, or one calendar date+local time. Schedules must persist per device, be timezone-aware, and show last success/failure. Never mark backup successful until Supabase acknowledges an atomic revision update. Handle offline retries and concurrent edits without overwriting another device. Android background jobs require OS-managed scheduling and may run late due to battery optimizations. Windows app-closed jobs require Task Scheduler or equivalent; an in-app timer is insufficient.

## Encryption and recovery
The original backup is encrypted directly with a master-password-derived key. It cannot be decrypted after forgetting the master password. Recovery requires generating a **new encrypted recovery path while the vault is unlocked**. Use 8 independently random, one-time recovery codes (at least 128 bits of entropy each). Store only separately encrypted key wraps or vault copies, not plaintext codes; consuming a code must atomically revoke it server-side, and rewrap under a new master password. Supabase login-password reset alone must not unlock the vault. Never log passwords, codes or plaintext TOTP data. Recovery setup should require the current master password and a secure confirmation that the codes were saved.

## Migration
Existing vaults must remain readable. No automated uploads or resets until migration is explicitly approved and tested. Provide a local encrypted backup before changing recovery configuration.
