# Phase 2: Encrypted Cloud Vault

## Database setup
In Supabase Dashboard > SQL Editor > New query, run `supabase/encrypted_vaults.sql` once.
Check Table Editor > encrypted_vaults; RLS must be enabled.

## Security contract
- Never send TOTP secrets, issuer names or account labels unencrypted to Supabase.
- Encrypt on-device with AES-256-GCM and a unique random 96-bit nonce per write.
- Derive an encryption key from a **separate master password** using a password KDF with per-vault random salt; never send the password or key to the backend.
- Associate ciphertext with authenticated user ID and format version as authenticated data.
- Never automatically overwrite or delete local accounts after login or failed sync.
- Require explicit first-time upload and additive restore on second device.
- Use revision-based compare-and-swap on updates to prevent silent lost writes.
- Sign-out must not remove local accounts. Password reset cannot decrypt an existing vault; users need their vault master password or independent recovery backup.

## Current status
Phase 1 email registration and login work. Phase 2 schema is prepared; sync is **not yet enabled**. Applying SQL alone does not upload any accounts.
