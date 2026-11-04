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

