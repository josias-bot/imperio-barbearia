-- Império Barbearia: acesso ao histórico de agendamentos de clientes vinculados
-- Execute no Supabase > SQL Editor > Run.
--
-- Quando um cliente cria uma conta usando o telefone de um cadastro avulso,
-- o histórico continua apontando para o ID original em appointments.customer_id.
-- Esta política permite que a conta vinculada leia esses agendamentos.

DROP POLICY IF EXISTS "Linked customers view own appointments" ON public.appointments;

CREATE POLICY "Linked customers view own appointments"
ON public.appointments
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = appointments.customer_id
      AND (
        p.id = auth.uid()
        OR p.auth_user_id = auth.uid()
      )
      AND p.role = 'customer'
  )
);
