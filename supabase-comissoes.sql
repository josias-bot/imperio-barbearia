-- Comissões por profissional: Rodrigo 100%; Josias e Diogo 50%.
CREATE TABLE IF NOT EXISTS public.professional_commissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id uuid NOT NULL UNIQUE REFERENCES public.appointments(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES public.professionals(id),
  service_id uuid NOT NULL REFERENCES public.services(id),
  service_price numeric(10,2) NOT NULL,
  commission_rate numeric(5,4) NOT NULL DEFAULT 0.5000,
  commission_amount numeric(10,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid')),
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS professional_commissions_professional_created_idx
  ON public.professional_commissions (professional_id, created_at);
CREATE INDEX IF NOT EXISTS professional_commissions_status_idx
  ON public.professional_commissions (status);

ALTER TABLE public.professional_commissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage professional commissions" ON public.professional_commissions;
CREATE POLICY "Admins manage professional commissions"
ON public.professional_commissions FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Professionals view own commissions" ON public.professional_commissions;
CREATE POLICY "Professionals view own commissions"
ON public.professional_commissions FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.professionals p
    WHERE p.id = professional_commissions.professional_id
      AND p.profile_id = auth.uid()
      AND p.active = true
  )
);

REVOKE ALL ON public.professional_commissions FROM anon;
GRANT SELECT ON public.professional_commissions TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.professional_commissions TO authenticated;

CREATE OR REPLACE FUNCTION public.create_professional_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_price numeric(10,2);
  v_name text;
  v_rate numeric(5,4);
BEGIN
  IF NEW.status = 'completed'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT s.price, p.name INTO v_price, v_name
    FROM public.services s
    JOIN public.professionals p ON p.id = NEW.professional_id
    WHERE s.id = NEW.service_id;

    IF v_price IS NOT NULL THEN
      v_rate := CASE WHEN lower(trim(coalesce(v_name,''))) = 'rodrigo' THEN 1.0000 ELSE 0.5000 END;
      INSERT INTO public.professional_commissions
        (appointment_id, professional_id, service_id, service_price, commission_rate, commission_amount)
      VALUES
        (NEW.id, NEW.professional_id, NEW.service_id, v_price, v_rate, round(v_price * v_rate, 2))
      ON CONFLICT (appointment_id) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS appointments_create_professional_commission ON public.appointments;
CREATE TRIGGER appointments_create_professional_commission
AFTER INSERT OR UPDATE OF status ON public.appointments
FOR EACH ROW
EXECUTE FUNCTION public.create_professional_commission();

-- Corrige também comissões já registradas, conforme o profissional responsável.
UPDATE public.professional_commissions c
SET commission_rate = CASE WHEN lower(trim(coalesce(p.name,''))) = 'rodrigo' THEN 1.0000 ELSE 0.5000 END,
    commission_amount = round(c.service_price * CASE WHEN lower(trim(coalesce(p.name,''))) = 'rodrigo' THEN 1.0000 ELSE 0.5000 END, 2)
FROM public.professionals p
WHERE p.id = c.professional_id;

-- Registra serviços concluídos anteriormente que ainda não tenham comissão.
INSERT INTO public.professional_commissions
  (appointment_id, professional_id, service_id, service_price, commission_rate, commission_amount)
SELECT a.id, a.professional_id, a.service_id, s.price,
       CASE WHEN lower(trim(coalesce(p.name,''))) = 'rodrigo' THEN 1.0000 ELSE 0.5000 END,
       round(s.price * CASE WHEN lower(trim(coalesce(p.name,''))) = 'rodrigo' THEN 1.0000 ELSE 0.5000 END, 2)
FROM public.appointments a
JOIN public.services s ON s.id = a.service_id
JOIN public.professionals p ON p.id = a.professional_id
WHERE a.status = 'completed'
ON CONFLICT (appointment_id) DO NOTHING;
