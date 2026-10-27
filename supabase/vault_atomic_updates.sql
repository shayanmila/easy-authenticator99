-- Apply in Supabase SQL Editor after encrypted_vaults.sql.
-- Atomic compare-and-swap prevents one device silently overwriting a newer vault.
create or replace function public.update_encrypted_vault(
  expected_revision bigint,
  new_envelope jsonb
) returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare new_revision bigint;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if octet_length(new_envelope::text) > 1048576 then raise exception 'Vault too large'; end if;
  update public.encrypted_vaults
     set envelope = new_envelope,
         revision = revision + 1,
         updated_at = now()
   where user_id = auth.uid()
     and revision = expected_revision
  returning revision into new_revision;
  if new_revision is null then
    raise exception 'Vault changed on another device; download and merge before retrying';
  end if;
  return new_revision;
end;
$$;
revoke all on function public.update_encrypted_vault(bigint,jsonb) from public, anon;
grant execute on function public.update_encrypted_vault(bigint,jsonb) to authenticated;
