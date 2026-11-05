-- Permite que administradores corrijam nome e telefone dos clientes.
-- Execute no Supabase SQL Editor.
GRANT UPDATE (full_name, phone) ON public.profiles TO authenticated;

DROP POLICY IF EXISTS "Admins update customer profiles" ON public.profiles;
CREATE POLICY "Admins update customer profiles"
ON public.profiles
FOR UPDATE
TO authenticated
USING (public.is_admin() AND role = 'customer')
WITH CHECK (public.is_admin() AND role = 'customer');
