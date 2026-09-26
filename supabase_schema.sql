-- ==============================================================================
-- ROOTDECK PRODUCTION DATABASE SCHEMA & SECURITY POLICIES
-- Target Engine: PostgreSQL 15+ (Supabase)
-- Author: Principal Full-Stack Engineer & Cybersecurity Specialist
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 2. TABLE DEFINITIONS
-- ==============================================================================

-- 2.1 Public User Profiles (Mirrors auth.users safely for display and associations)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2.2 Projects Catalog (Admin Managed, Public Read)
CREATE TABLE IF NOT EXISTS public.projects (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    full_details TEXT,
    image_url TEXT,
    download_url TEXT NOT NULL,
    category TEXT DEFAULT 'Tool',
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2.3 Issues Tracker (Public Anonymous Display, Authenticated Submission, Admin Replies)
CREATE TABLE IF NOT EXISTS public.issues (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    project TEXT NOT NULL,
    details TEXT NOT NULL,
    screenshot_url TEXT,
    admin_reply TEXT,
    replied_at TIMESTAMPTZ,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2.4 Project Downloads Audit Log (User Download History)
CREATE TABLE IF NOT EXISTS public.downloads (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_name TEXT NOT NULL,
    user_email TEXT NOT NULL,
    project_id BIGINT REFERENCES public.projects(id) ON DELETE SET NULL,
    project_name TEXT NOT NULL,
    downloaded_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2.5 Issues Audit Log (Security & Administrative History)
CREATE TABLE IF NOT EXISTS public.issue_audit_log (
    id BIGSERIAL PRIMARY KEY,
    issue_id BIGINT REFERENCES public.issues(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('created', 'replied', 'status_changed', 'deleted')),
    performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- ==============================================================================
-- 3. INDEXES FOR HIGH-PERFORMANCE QUERYING
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_issues_created_at ON public.issues (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_issues_user_id ON public.issues (user_id);
CREATE INDEX IF NOT EXISTS idx_downloads_user_id ON public.downloads (user_id);
CREATE INDEX IF NOT EXISTS idx_downloads_downloaded_at ON public.downloads (downloaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_projects_is_active ON public.projects (is_active);
CREATE INDEX IF NOT EXISTS idx_issue_audit_issue_id ON public.issue_audit_log (issue_id);

-- ==============================================================================
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.downloads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issue_audit_log ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- 4.1 Profiles Table Policies
-- ------------------------------------------------------------------------------
CREATE POLICY "Users can view own profile"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ------------------------------------------------------------------------------
-- 4.2 Projects Table Policies
-- ------------------------------------------------------------------------------
CREATE POLICY "Public can view active projects"
    ON public.projects
    FOR SELECT
    TO anon, authenticated
    USING (is_active = TRUE);

CREATE POLICY "Service role full access on projects"
    ON public.projects
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ------------------------------------------------------------------------------
-- 4.3 Issues Table Policies
-- ------------------------------------------------------------------------------
-- Anyone can view all issues publicly for transparency
CREATE POLICY "Public can view issues"
    ON public.issues
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- Authenticated users can insert their own issues
CREATE POLICY "Authenticated users can report issues"
    ON public.issues
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Only Admin / Service Role can update issues (e.g. adding admin_reply, status)
CREATE POLICY "Service role can update issues"
    ON public.issues
    FOR UPDATE
    TO service_role
    USING (true)
    WITH CHECK (true);

-- STRICT REQUIREMENT: Users CANNOT delete issues once created.
-- Only service_role can delete issues if necessary for maintenance.
CREATE POLICY "Service role can delete issues"
    ON public.issues
    FOR DELETE
    TO service_role
    USING (true);

-- ------------------------------------------------------------------------------
-- 4.4 Downloads Table Policies
-- ------------------------------------------------------------------------------
CREATE POLICY "Users can view their own downloads"
    ON public.downloads
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Authenticated users can record downloads"
    ON public.downloads
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role full access on downloads"
    ON public.downloads
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ------------------------------------------------------------------------------
-- 4.5 Issue Audit Log Policies
-- ------------------------------------------------------------------------------
CREATE POLICY "Users can view audit log for their own issues"
    ON public.issue_audit_log
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.issues
            WHERE issues.id = issue_audit_log.issue_id
            AND issues.user_id = auth.uid()
        )
    );

CREATE POLICY "Service role full access on issue audit log"
    ON public.issue_audit_log
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ==============================================================================
-- 5. RATE LIMITING: DAILY HARD LIMIT POLICY (MAX 20 ISSUES PER ROLLING 24 HOURS)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.check_issues_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
    issue_count_last_24h INTEGER;
BEGIN
    -- Count all issues created across all users in the rolling past 24 hours
    SELECT COUNT(*) INTO issue_count_last_24h
    FROM public.issues
    WHERE created_at >= (NOW() - INTERVAL '24 hours');

    -- Hard Limit Enforcement
    IF issue_count_last_24h >= 20 THEN
        RAISE EXCEPTION 'Daily submission limit exceeded. A maximum of 20 issues can be reported across all users within a 24-hour window. Please try again later.'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_check_issues_rate_limit ON public.issues;
CREATE TRIGGER trg_check_issues_rate_limit
    BEFORE INSERT ON public.issues
    FOR EACH ROW
    EXECUTE FUNCTION public.check_issues_rate_limit();

-- ==============================================================================
-- 6. AUTOMATED AUDIT LOGGING TRIGGERS
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.log_issue_lifecycle()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.issue_audit_log (issue_id, action, performed_by, details, created_at)
        VALUES (
            NEW.id,
            'created',
            NEW.user_id,
            jsonb_build_object(
                'project', NEW.project,
                'has_screenshot', (NEW.screenshot_url IS NOT NULL)
            ),
            NOW()
        );
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (NEW.admin_reply IS DISTINCT FROM OLD.admin_reply AND NEW.admin_reply IS NOT NULL) THEN
            INSERT INTO public.issue_audit_log (issue_id, action, performed_by, details, created_at)
            VALUES (
                NEW.id,
                'replied',
                auth.uid(),
                jsonb_build_object(
                    'admin_reply', NEW.admin_reply,
                    'replied_at', NEW.replied_at
                ),
                NOW()
            );
        END IF;

        IF (NEW.status IS DISTINCT FROM OLD.status) THEN
            INSERT INTO public.issue_audit_log (issue_id, action, performed_by, details, created_at)
            VALUES (
                NEW.id,
                'status_changed',
                auth.uid(),
                jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status),
                NOW()
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_log_issue_lifecycle ON public.issues;
CREATE TRIGGER trg_log_issue_lifecycle
    AFTER INSERT OR UPDATE ON public.issues
    FOR EACH ROW
    EXECUTE FUNCTION public.log_issue_lifecycle();

-- ==============================================================================
-- 7. AUTOMATED USER PROFILE SYNCHRONIZATION TRIGGER
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, name, email, created_at, updated_at)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        NEW.email,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
    SET name = EXCLUDED.name,
        email = EXCLUDED.email,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ==============================================================================
-- 8. SECURE ACCOUNT DELETION FUNCTION (USER SELF-DELETION VIA AUTH API)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS VOID AS $$
DECLARE
    current_uid UUID;
BEGIN
    current_uid := auth.uid();
    IF current_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- Deleting from auth.users cascades to profiles, downloads, and issues
    DELETE FROM auth.users WHERE id = current_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.delete_user_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

-- ==============================================================================
-- 9. INITIAL SEED DATA (PROJECTS CATALOG)
-- ==============================================================================
INSERT INTO public.projects (name, description, full_details, image_url, download_url, category, is_active)
VALUES 
(
    'RootDeck Security Suite v2',
    'Comprehensive cyber security diagnostic toolkit and vulnerability scanner.',
    'The RootDeck Security Suite is an advanced lightweight penetration testing helper, network scanner, and automated endpoint auditor designed for ethical hackers and developers. It includes built-in packet telemetry, header audit tools, and encrypted logging facilities.',
    'https://picsum.photos/seed/rootdeck-sec/800/450',
    'https://github.com/Official-RootDeck/security-suite/releases/download/v2.0/RootDeck-Suite-v2.zip',
    'Security Kit',
    TRUE
),
(
    'Neural Cipher Toolkit',
    'Cryptographic utility and token generation tool with zero-knowledge primitives.',
    'Built with high-performance cryptographic algorithms, the Neural Cipher Toolkit provides AES-256-GCM file protection, salted PBKDF2 hashing benchmarks, and secure key derivation interfaces for modern web applications.',
    'https://picsum.photos/seed/cipher-tool/800/450',
    'https://github.com/Official-RootDeck/neural-cipher/releases/download/v1.4/NeuralCipher-v1.4.zip',
    'Cryptography',
    TRUE
),
(
    'Subdomain Recon Pro',
    'Fast concurrent DNS bruteforcer and certificate transparency log scraper.',
    'Quickly map external attack surfaces and discover hidden staging subdomains. Powered by multi-threaded asynchronous DNS resolution with custom wordlist support and automatic CSV/JSON reporting.',
    'https://picsum.photos/seed/recon-dns/800/450',
    'https://github.com/Official-RootDeck/subdomain-recon/releases/download/v3.1/SubdomainRecon-v3.1.zip',
    'Reconnaissance',
    TRUE
)
ON CONFLICT DO NOTHING;
