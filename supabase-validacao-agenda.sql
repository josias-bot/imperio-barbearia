-- Império Barbearia
-- Execute este arquivo no SQL Editor do Supabase para validar regras no banco.
-- Esta validação complementa a interface e protege inserts/updates feitos por qualquer tela.

CREATE OR REPLACE FUNCTION public.validate_professional_business_hours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  professional_name text;
  weekday integer;
  opening_time time;
  closing_time time;
BEGIN
  -- Atualizações apenas de situação não devem revalidar a data original.
  IF TG_OP = 'UPDATE'
     AND NEW.professional_id IS NOT DISTINCT FROM OLD.professional_id
     AND NEW.appointment_date IS NOT DISTINCT FROM OLD.appointment_date
     AND NEW.start_time IS NOT DISTINCT FROM OLD.start_time
     AND NEW.end_time IS NOT DISTINCT FROM OLD.end_time THEN
    RETURN NEW;
  END IF;

  -- Cancelamentos não precisam obedecer à janela de atendimento.
  IF lower(coalesce(NEW.status, '')) IN ('cancelled', 'canceled', 'cancelado') THEN
    RETURN NEW;
  END IF;

  IF NEW.appointment_date IS NULL OR NEW.start_time IS NULL OR NEW.end_time IS NULL
     OR NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'Data e horário do agendamento são inválidos.';
  END IF;

  IF NEW.appointment_date < (now() AT TIME ZONE 'America/Recife')::date THEN
    RAISE EXCEPTION 'Não é permitido criar ou alterar agendamento em data passada.';
  END IF;

  SELECT name INTO professional_name
  FROM public.professionals
  WHERE id = NEW.professional_id AND active = true;

  IF professional_name IS NULL THEN
    RAISE EXCEPTION 'Profissional não encontrado ou inativo.';
  END IF;

  weekday := EXTRACT(DOW FROM NEW.appointment_date)::integer;

  IF (lower(professional_name) = 'rodrigo' AND weekday IN (0, 1))
     OR (lower(professional_name) = 'diogo' AND weekday = 3)
     OR (lower(professional_name) = 'josias' AND weekday = 2) THEN
    RAISE EXCEPTION 'Este profissional não trabalha nesta data.';
  END IF;

  IF weekday = 0 THEN
    opening_time := TIME '08:00';
    closing_time := TIME '12:00';
  ELSIF weekday = 6 THEN
    opening_time := TIME '08:00';
    closing_time := TIME '19:00';
  ELSE
    opening_time := TIME '09:00';
    closing_time := TIME '19:00';
  END IF;

  IF NEW.start_time < opening_time OR NEW.end_time > closing_time THEN
    RAISE EXCEPTION 'Agendamento fora do horário de funcionamento da barbearia.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_professional_business_hours
ON public.appointments;

CREATE TRIGGER validate_professional_business_hours
BEFORE INSERT OR UPDATE OF professional_id, appointment_date, start_time, end_time, status
ON public.appointments
FOR EACH ROW
EXECUTE FUNCTION public.validate_professional_business_hours();

-- Protege também os bloqueios de horário.
CREATE OR REPLACE FUNCTION public.validate_professional_time_block_hours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  professional_name text;
  weekday integer;
  opening_time time;
  closing_time time;
BEGIN
  IF NEW.block_date IS NULL OR NEW.start_time IS NULL OR NEW.end_time IS NULL
     OR NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'Data e horário do bloqueio são inválidos.';
  END IF;
  IF NEW.block_date < (now() AT TIME ZONE 'America/Recife')::date THEN
    RAISE EXCEPTION 'Não é permitido criar ou alterar bloqueio em data passada.';
  END IF;
  SELECT name INTO professional_name FROM public.professionals
  WHERE id = NEW.professional_id AND active = true;
  IF professional_name IS NULL THEN
    RAISE EXCEPTION 'Profissional não encontrado ou inativo.';
  END IF;
  weekday := EXTRACT(DOW FROM NEW.block_date)::integer;
  IF (lower(professional_name) = 'rodrigo' AND weekday IN (0, 1))
     OR (lower(professional_name) = 'diogo' AND weekday = 3)
     OR (lower(professional_name) = 'josias' AND weekday = 2) THEN
    RAISE EXCEPTION 'Não é permitido bloquear a agenda em dia de folga do profissional.';
  END IF;
  IF weekday = 0 THEN
    opening_time := TIME '08:00'; closing_time := TIME '12:00';
  ELSIF weekday = 6 THEN
    opening_time := TIME '08:00'; closing_time := TIME '19:00';
  ELSE
    opening_time := TIME '09:00'; closing_time := TIME '19:00';
  END IF;
  IF NEW.start_time < opening_time OR NEW.end_time > closing_time THEN
    RAISE EXCEPTION 'Bloqueio fora do horário de funcionamento da barbearia.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_professional_time_block_hours
ON public.professional_time_blocks;

CREATE TRIGGER validate_professional_time_block_hours
BEFORE INSERT OR UPDATE OF professional_id, block_date, start_time, end_time
ON public.professional_time_blocks
FOR EACH ROW
EXECUTE FUNCTION public.validate_professional_time_block_hours();

-- Permite que o profissional atualize somente a situação dos próprios agendamentos.
-- O administrador também pode alterar a situação pela mesma coluna.
DROP POLICY IF EXISTS "Professionals update own appointment status" ON public.appointments;
CREATE POLICY "Professionals update own appointment status"
ON public.appointments
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.professionals p
    WHERE p.id = appointments.professional_id
      AND p.profile_id = auth.uid()
      AND p.active = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.professionals p
    WHERE p.id = appointments.professional_id
      AND p.profile_id = auth.uid()
      AND p.active = true
  )
);

-- Restringe a permissão de UPDATE dos usuários autenticados à coluna status.
-- A política "Admins manage appointments" continua controlando o acesso administrativo.
REVOKE UPDATE ON public.appointments FROM anon, authenticated;
GRANT UPDATE (status) ON public.appointments TO authenticated;



-- Inclui o estado confirmado no ciclo de vida dos agendamentos.
ALTER TABLE public.appointments
  DROP CONSTRAINT IF EXISTS appointments_status_check;
ALTER TABLE public.appointments
  ADD CONSTRAINT appointments_status_check
  CHECK (status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled'));
