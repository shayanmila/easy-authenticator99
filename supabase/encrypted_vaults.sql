-- Easy Authenticator Phase 2: private, encrypted per-user vault.
-- Run in Supabase SQL Editor. No plaintext TOTP secrets are stored here.
create table if not exists public.encrypted_vaults (
  user_id uuid primary key references auth.users(id) on delete cascade,
  envelope jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  constraint envelope_size_limit check (octet_length(envelope::text) <= 1048576)
);
alter table public.encrypted_vaults enable row level security;
revoke all on public.encrypted_vaults from anon;
grant select, insert, update, delete on public.encrypted_vaults to authenticated;
drop policy if exists "vault_select_owner" on public.encrypted_vaults;
drop policy if exists "vault_insert_owner" on public.encrypted_vaults;
drop policy if exists "vault_update_owner" on public.encrypted_vaults;
drop policy if exists "vault_delete_owner" on public.encrypted_vaults;
create policy "vault_select_owner" on public.encrypted_vaults for select to authenticated using ((select auth.uid()) = user_id);
create policy "vault_insert_owner" on public.encrypted_vaults for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "vault_update_owner" on public.encrypted_vaults for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "vault_delete_owner" on public.encrypted_vaults for delete to authenticated using ((select auth.uid()) = user_id);
-- Client must use optimistic revision checks; do not blindly overwrite remote vault.
