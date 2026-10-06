-- Roles infrastructure
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');
CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;
-- Early access submissions
CREATE TABLE public.early_access_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  email text NOT NULL,
  organization_name text NOT NULL,
  organization_type text NOT NULL,
  player_count text,
  staff_count text,
  location_count text,
  current_tools text,
  biggest_challenge text,
  message text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT INSERT ON public.early_access_submissions TO anon, authenticated;
GRANT SELECT ON public.early_access_submissions TO authenticated;
GRANT ALL ON public.early_access_submissions TO service_role;
ALTER TABLE public.early_access_submissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can submit an early access request"
  ON public.early_access_submissions FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);
CREATE POLICY "Admins can view all submissions"
  ON public.early_access_submissions FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
CREATE INDEX early_access_submissions_created_at_idx
  ON public.early_access_submissions (created_at DESC);
