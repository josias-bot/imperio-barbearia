-- Correção para permitir perfis de clientes avulsos sem conta Auth
-- Execute no Supabase > SQL Editor.

ALTER TABLE public.profiles
DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- O vínculo com a conta de acesso passa a ser feito por auth_user_id,
-- preservando o ID original do perfil usado pelos agendamentos.
