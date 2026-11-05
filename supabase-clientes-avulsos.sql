-- Império Barbearia: clientes avulsos e vínculo com conta futura
-- Execute no SQL Editor do Supabase antes de publicar as telas atualizadas.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;

-- Administrador pode criar perfis de clientes avulsos sem criar uma conta de acesso.
GRANT INSERT (id, full_name, phone, role) ON public.profiles TO authenticated;

DROP POLICY IF EXISTS "Admins insert walkin customer profiles" ON public.profiles;
CREATE POLICY "Admins insert walkin customer profiles"
ON public.profiles FOR INSERT TO authenticated
WITH CHECK (public.is_admin() AND role = 'customer');

-- Cria um cliente avulso. O telefone é obrigatório e armazenado em formato +55.
CREATE OR REPLACE FUNCTION public.create_walkin_customer(p_full_name text, p_phone text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id uuid;
  v_phone text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem cadastrar clientes avulsos.';
  END IF;
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  IF length(v_phone) IN (10,11) THEN
    v_phone := '55' || v_phone;
  END IF;
  IF left(v_phone,2) <> '55' OR length(v_phone) NOT IN (12,13) THEN
    RAISE EXCEPTION 'Informe um telefone brasileiro válido com DDD.';
  END IF;
  IF nullif(trim(p_full_name), '') IS NULL THEN
    RAISE EXCEPTION 'Informe o nome do cliente.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.role = 'customer'
      AND regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g') = v_phone
  ) THEN
    RAISE EXCEPTION 'Já existe um cliente cadastrado com este telefone.';
  END IF;
  INSERT INTO public.profiles(id, full_name, phone, role)
  VALUES (gen_random_uuid(), trim(p_full_name), '+' || v_phone, 'customer')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_walkin_customer(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_walkin_customer(text,text) TO authenticated;

-- Vincula a conta recém-criada ao perfil avulso existente sem duplicar o histórico.
-- Conforme solicitado, a associação usa somente o telefone, sem OTP adicional.
CREATE OR REPLACE FUNCTION public.claim_walkin_customer(p_phone text, p_full_name text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_phone text;
  v_auth_phone text;
  v_profile_id uuid;
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Entre na conta para concluir o cadastro.';
  END IF;
  SELECT regexp_replace(coalesce(u.phone,''), '[^0-9]', '', 'g')
    INTO v_auth_phone FROM auth.users u WHERE u.id = v_uid;
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  IF length(v_phone) IN (10,11) THEN v_phone := '55' || v_phone; END IF;
  IF v_auth_phone IS DISTINCT FROM v_phone THEN
    RAISE EXCEPTION 'O telefone informado não corresponde ao telefone da conta.';
  END IF;

  SELECT count(*), min(p.id::text)::uuid
    INTO v_count, v_profile_id
  FROM public.profiles p
  WHERE p.role = 'customer'
    AND regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g') = v_phone
    AND p.id <> v_uid
    AND p.auth_user_id IS NULL;

  IF v_count > 1 THEN
    RAISE EXCEPTION 'Há mais de um cadastro com este telefone. Procure a barbearia.';
  END IF;

  IF v_count = 1 THEN
    UPDATE public.profiles
      SET auth_user_id = v_uid,
          full_name = coalesce(nullif(trim(p_full_name), ''), full_name)
      WHERE id = v_profile_id;
    -- Remove somente o perfil vazio criado automaticamente para a nova conta,
    -- preservando o ID antigo referenciado pelos agendamentos e comissões.
    DELETE FROM public.profiles
      WHERE id = v_uid AND role = 'customer' AND auth_user_id IS NULL;
    RETURN v_profile_id;
  END IF;

  UPDATE public.profiles
    SET auth_user_id = v_uid,
        phone = '+' || v_phone,
        full_name = coalesce(nullif(trim(p_full_name), ''), full_name)
    WHERE id = v_uid AND role = 'customer';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Perfil de cliente não encontrado para vincular.';
  END IF;
  RETURN v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_walkin_customer(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_walkin_customer(text,text) TO authenticated;

-- Usuários autenticados consultam o próprio perfil vinculado.
DROP POLICY IF EXISTS "Users view own profile" ON public.profiles;
CREATE POLICY "Users view own profile"
ON public.profiles FOR SELECT TO authenticated
USING (id = auth.uid() OR auth_user_id = auth.uid() OR public.is_admin());
