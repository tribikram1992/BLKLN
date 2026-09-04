-- =============================================================================
-- BlackLine Journal Certification Pilot — Full Database Schema
-- =============================================================================
-- Version  : 2.0
-- Date     : 2026-08-22
-- Author   : Deeptirani Mishra
-- Source   : ARCHITECTURE.md sections 9.1–9.26
--
-- Rules:
--   • No DELETE anywhere — use is_active = FALSE or soft-delete flags
--   • Immutable tables (journal_certification, journal_audit_log, ai_session_log)
--     have created_at only — no updated_at, no UPDATE, no DELETE ever
--   • All FK constraints are inline — tables ordered by dependency
--   • IF NOT EXISTS on every CREATE TABLE
-- =============================================================================

-- =============================================================================
-- 9.17  rejection_reason_master  (no dependencies — must precede journal_certification)
-- =============================================================================
CREATE TABLE IF NOT EXISTS rejection_reason_master (
    id              BIGSERIAL PRIMARY KEY,
    reason_code     VARCHAR(100) UNIQUE NOT NULL,
    reason_text     VARCHAR(500) NOT NULL,
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
-- Seed: MISSING_SUPPORT, INCORRECT_AMOUNT, INCORRECT_ACCOUNT,
--       INSUFFICIENT_COMMENT, OTHER

-- =============================================================================
-- 9.1  users
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id                          BIGSERIAL PRIMARY KEY,

    -- Identity
    user_id                     VARCHAR(100) UNIQUE NOT NULL,
    adid                        VARCHAR(100) UNIQUE,
    username                    VARCHAR(100) UNIQUE NOT NULL,

    -- Credentials
    password_hash               VARCHAR(500),
    api_key_hash                VARCHAR(500),
    api_key_created_at          TIMESTAMP WITH TIME ZONE,

    -- Profile
    first_name                  VARCHAR(100),
    last_name                   VARCHAR(100),
    display_name                VARCHAR(255) NOT NULL,
    email                       VARCHAR(255) UNIQUE,
    status                      VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    -- Values: ACTIVE | INACTIVE | LOCKED | SUSPENDED

    job_title                   VARCHAR(255),
    supervisor                  VARCHAR(100),           -- free-text supervisor name or ADID
    supervisor_user_id          VARCHAR(100),           -- FK added below after table create
    phone                       VARCHAR(50),
    preferred_timezone          VARCHAR(100) NOT NULL DEFAULT 'UTC',
    user_annual_hours           NUMERIC(8, 2),

    -- Auth / SSO
    auth_provider               VARCHAR(50) NOT NULL DEFAULT 'LOCAL',
    sso_subject                 VARCHAR(255),
    active_role_code            VARCHAR(50),                -- current active role; FK added below

    -- Feature flags (per-user overrides confirmed from 1.24.34 AM screenshot)
    require_journal_reviewer    BOOLEAN NOT NULL DEFAULT FALSE,
    user_mentions_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
    allow_edit_journal_config   BOOLEAN NOT NULL DEFAULT FALSE,
    allow_edit_ic_config        BOOLEAN NOT NULL DEFAULT FALSE,
    allow_adhoc_matching        BOOLEAN NOT NULL DEFAULT FALSE,
    allow_ic_settlement         BOOLEAN NOT NULL DEFAULT FALSE,

    -- Lifecycle
    is_active                   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Self-referencing FK applied after table creation (DO block makes it idempotent)
DO $$ BEGIN
    ALTER TABLE users
        ADD CONSTRAINT fk_users_supervisor
        FOREIGN KEY (supervisor_user_id) REFERENCES users(user_id)
        DEFERRABLE INITIALLY DEFERRED;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =============================================================================
-- 9.2  roles
-- =============================================================================
CREATE TABLE IF NOT EXISTS roles (
    id              BIGSERIAL PRIMARY KEY,
    role_code       VARCHAR(50) UNIQUE NOT NULL,
    role_name       VARCHAR(100) NOT NULL,
    ui_display_name VARCHAR(150) NOT NULL,
    badge_color     VARCHAR(20) DEFAULT '#555555',
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
-- Seed: PREPARER, APPROVER, REVIEWER, FINANCIAL_REVIEWER, ACCOUNT_REVIEWER,
--       FINANCIAL_MANAGER, ACCOUNT_MANAGER, INTERNAL_AUDITOR, EXECUTIVE, CFO,
--       EXTERNAL_AUDITOR, LOCAL_ADMIN, BUSINESS_ADMIN, SYSTEM_ADMIN, CONSULTANT,
--       API_ACCESS

-- FK for users.active_role_code → roles (applied after roles table is created, DO block makes it idempotent)
DO $$ BEGIN
    ALTER TABLE users
        ADD CONSTRAINT fk_users_active_role
        FOREIGN KEY (active_role_code) REFERENCES roles(role_code);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =============================================================================
-- 9.3  user_roles
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_roles (
    id          BIGSERIAL PRIMARY KEY,
    user_id     VARCHAR(100) NOT NULL REFERENCES users(user_id),
    role_code   VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    granted_by  VARCHAR(100) REFERENCES users(user_id),
    granted_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, role_code)
);

-- =============================================================================
-- 9.4  user_session
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_session (
    id               BIGSERIAL PRIMARY KEY,
    session_id       VARCHAR(200) UNIQUE NOT NULL,
    user_id          VARCHAR(100) NOT NULL REFERENCES users(user_id),
    active_role_code VARCHAR(50)  REFERENCES roles(role_code),
    jwt_jti          VARCHAR(200) UNIQUE,
    login_at         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_activity_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at       TIMESTAMP WITH TIME ZONE,
    ip_address       VARCHAR(50),
    user_agent       TEXT,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.5  teams
-- =============================================================================
CREATE TABLE IF NOT EXISTS teams (
    id          BIGSERIAL PRIMARY KEY,
    team_id     VARCHAR(100) UNIQUE NOT NULL,
    team_name   VARCHAR(255) NOT NULL,
    company_code VARCHAR(50),
    region      VARCHAR(100),
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.6  role_external_mapping
-- =============================================================================
CREATE TABLE IF NOT EXISTS role_external_mapping (
    id                              BIGSERIAL PRIMARY KEY,
    mapping_id                      VARCHAR(100) UNIQUE NOT NULL,
    external_role_code              VARCHAR(100) NOT NULL,
    normalized_external_role_code   VARCHAR(100) NOT NULL,
    internal_role_code              VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    source_system                   VARCHAR(100) NOT NULL DEFAULT 'JDE',
    description                     TEXT,
    is_active                       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(external_role_code, source_system)
);
-- Seed: BLPREPARER → PREPARER, BLAPPROVER → APPROVER

-- =============================================================================
-- 9.7  jde_user_dependency_mapping
-- =============================================================================
CREATE TABLE IF NOT EXISTS jde_user_dependency_mapping (
    id                  BIGSERIAL PRIMARY KEY,
    dependency_id       VARCHAR(100) UNIQUE NOT NULL,
    preparer_adid       VARCHAR(100) NOT NULL,
    preparer_user_id    VARCHAR(100) REFERENCES users(user_id),
    preparer_role_code  VARCHAR(100) NOT NULL DEFAULT 'BLPREPARER',
    approver_adid       VARCHAR(100) NOT NULL,
    approver_user_id    VARCHAR(100) REFERENCES users(user_id),
    approver_role_code  VARCHAR(100) NOT NULL DEFAULT 'BLAPPROVER',
    company_code        VARCHAR(50),
    region              VARCHAR(100),
    team_id             VARCHAR(100) REFERENCES teams(team_id),
    effective_from      DATE,
    effective_to        DATE,
    source_system       VARCHAR(100) NOT NULL DEFAULT 'JDE',
    source_file_name    VARCHAR(500),
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_jde_diff_adid CHECK (preparer_adid <> approver_adid),
    CONSTRAINT chk_jde_diff_user CHECK (
        preparer_user_id IS NULL
        OR approver_user_id IS NULL
        OR preparer_user_id <> approver_user_id
    )
);

-- =============================================================================
-- 9.18  currency_conversion_rate  (no dependencies)
-- =============================================================================
CREATE TABLE IF NOT EXISTS currency_conversion_rate (
    id               BIGSERIAL PRIMARY KEY,
    rate_id          VARCHAR(100) UNIQUE NOT NULL,
    from_currency    VARCHAR(10) NOT NULL,
    to_currency      VARCHAR(10) NOT NULL DEFAULT 'USD',
    conversion_rate  NUMERIC(18, 8) NOT NULL,
    effective_from   DATE NOT NULL,
    effective_to     DATE,
    source_system    VARCHAR(100) NOT NULL DEFAULT 'CONFIG_SEED',
    source_file_name VARCHAR(500),
    load_batch_id    VARCHAR(100),
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(from_currency, to_currency, effective_from)
);
-- Seeded from currency data.txt — no UI upload for this table
-- SYSTEM_ADMIN can view. No edit/delete via UI.

-- =============================================================================
-- 9.8  journal_file_load
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_file_load (
    id                    BIGSERIAL PRIMARY KEY,
    file_load_id          VARCHAR(100) UNIQUE NOT NULL,
    original_file_name    VARCHAR(500) NOT NULL,
    file_extension        VARCHAR(50),
    mime_type             VARCHAR(255),
    file_size_bytes       BIGINT,
    file_hash_sha256      VARCHAR(64),
    file_content          BYTEA NOT NULL,
    source_type           VARCHAR(50) NOT NULL DEFAULT 'MANUAL_UPLOAD',
    delimiter             VARCHAR(20) NOT NULL DEFAULT 'TAB',
    expected_column_count INTEGER NOT NULL DEFAULT 27,
    total_rows            INTEGER NOT NULL DEFAULT 0,
    valid_rows            INTEGER NOT NULL DEFAULT 0,
    invalid_rows          INTEGER NOT NULL DEFAULT 0,
    journals_created      INTEGER NOT NULL DEFAULT 0,
    status                VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    -- Values: PENDING | UPLOADING | PARSING | PARSE_SUCCESS | PARSE_FAILED | ASSIGNMENT_FAILED
    error_message         TEXT,
    parse_errors_json     JSONB,
    uploaded_by           VARCHAR(100) REFERENCES users(user_id),
    uploaded_role         VARCHAR(50)  REFERENCES roles(role_code),
    uploaded_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    processed_at          TIMESTAMP WITH TIME ZONE,
    created_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.9  journal_header
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_header (
    id                      BIGSERIAL PRIMARY KEY,

    -- Primary key used in application
    journal_id              VARCHAR(100) UNIQUE NOT NULL,

    -- Source file link
    source_file_id          VARCHAR(100) NOT NULL REFERENCES journal_file_load(file_load_id),

    -- ── From JDE source file (27-col format) ──────────────────────────────
    document_type           VARCHAR(50)  NOT NULL,
    document_number         VARCHAR(100) NOT NULL,
    gl_date                 DATE         NOT NULL,
    journal_period          VARCHAR(7)   NOT NULL,     -- MM/YYYY format
    period_number           INTEGER,
    fiscal_year             INTEGER,
    batch_id                VARCHAR(100),              -- col 6: BatchNumber (display as Batch ID)
    batch_date              DATE,
    ledger_type             VARCHAR(50),
    reverse_or_void         VARCHAR(50),
    company_code            VARCHAR(50),
    batch_type              VARCHAR(50),
    currency                VARCHAR(10),
    exchange_rate           NUMERIC(18, 8) DEFAULT 0,
    region                  VARCHAR(100),

    -- ── Computed / application-level amounts ──────────────────────────────
    bl_currency_rate_usd    NUMERIC(18, 8) DEFAULT 1,  -- BL currency rate to USD
    total_debit             NUMERIC(18, 2) NOT NULL DEFAULT 0,
    total_credit            NUMERIC(18, 2) NOT NULL DEFAULT 0,
    total_debit_usd         NUMERIC(18, 2) NOT NULL DEFAULT 0,
    total_credit_usd        NUMERIC(18, 2) NOT NULL DEFAULT 0,

    -- ── Denormalized display columns (27-col grid) ────────────────────────
    baxter_id            VARCHAR(100),              -- External BlackLine identifier (e.g. BX_1511900)
    template                VARCHAR(255) NOT NULL DEFAULT 'Generic',
    team_id                 VARCHAR(100) REFERENCES teams(team_id),
    posting_status          VARCHAR(100),
    header_status_display   VARCHAR(255),
    final_certification_state VARCHAR(100),
    is_completed            BOOLEAN NOT NULL DEFAULT FALSE,

    -- Denormalized user references (populated on assignment — avoids JOIN for grid)
    preparer_user_id        VARCHAR(100) REFERENCES users(user_id),
    approver_user_id        VARCHAR(100) REFERENCES users(user_id),
    reviewer_user_id        VARCHAR(100) REFERENCES users(user_id),

    -- Presence flags (updated by comment/document service on each insert)
    has_comments            BOOLEAN NOT NULL DEFAULT FALSE,
    has_documents           BOOLEAN NOT NULL DEFAULT FALSE,

    -- ── Workflow status (6-status FSM) ───────────────────────────────────
    -- NOT_PREPARED  → admin validates → PREPARED
    -- PREPARED      → preparer certifies → CERTIFIED
    -- CERTIFIED     → approver approves → APPROVED (terminal)
    --               → approver rejects  → REJECTED (preparer re-certifies)
    --               → preparer decertifies → DECERTIFIED (preparer re-certifies)
    -- REJECTED / DECERTIFIED → preparer certifies → CERTIFIED
    status                  VARCHAR(50) NOT NULL DEFAULT 'NOT_PREPARED',
    CONSTRAINT chk_jh_status CHECK (
        status IN (
            'NOT_PREPARED',
            'PREPARED',
            'CERTIFIED',
            'APPROVED',
            'REJECTED',
            'DECERTIFIED'
        )
    ),

    -- ── Lifecycle ─────────────────────────────────────────────────────────
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_by              VARCHAR(100) REFERENCES users(user_id),
    created_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    closed_at               TIMESTAMP WITH TIME ZONE,

    UNIQUE(document_type, document_number, fiscal_year, batch_id, company_code, currency, ledger_type)
);

-- =============================================================================
-- 9.10  journal_line
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_line (
    id                  BIGSERIAL PRIMARY KEY,
    journal_line_id     VARCHAR(100) UNIQUE NOT NULL,
    journal_id          VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    file_load_id        VARCHAR(100) NOT NULL REFERENCES journal_file_load(file_load_id),

    -- ── From 27-col source file ───────────────────────────────────────────
    source_row_number   INTEGER NOT NULL,
    je_line_number      INTEGER,
    business_unit       VARCHAR(100),
    object_account      VARCHAR(100),
    subsidiary          VARCHAR(100),
    subledger           VARCHAR(100),
    subledger_type      VARCHAR(50),
    amount              NUMERIC(18, 2) NOT NULL DEFAULT 0,
    amount_usd          NUMERIC(18, 2) NOT NULL DEFAULT 0,
    explanation_1       VARCHAR(500),
    explanation_2       VARCHAR(500),
    gl_post_status      VARCHAR(50),
    asset_number        VARCHAR(100),
    last_modified_by    VARCHAR(255),
    account_description VARCHAR(500),
    preparer_adid       VARCHAR(100),           -- from source file col 10, for audit
    region              VARCHAR(100),
    raw_line            TEXT,                   -- original raw row for audit

    -- ── Account-level metadata (Phase 2+ — from account master lookup) ────
    account_number          VARCHAR(100),
    account_manager         VARCHAR(255),
    account_reviewer        VARCHAR(255),
    account_managed_by_user VARCHAR(255),
    internal_auditor        VARCHAR(255),

    -- ── Intercompany amounts (Phase 3+) ───────────────────────────────────
    amount_ic           NUMERIC(18, 2),         -- Amount I/C
    amount_ic_jde       NUMERIC(18, 2),         -- Amount I/C JDE
    gross_amount        NUMERIC(18, 2),
    gross_amount_jde    NUMERIC(18, 2),
    ic_line_reference   VARCHAR(255),           -- I/C Line Reference

    -- ── Tax fields (Phase 3+) ─────────────────────────────────────────────
    tax_amount          NUMERIC(18, 2),
    tax_amount_jde      NUMERIC(18, 2),
    tax_area            VARCHAR(100),
    tax_expl            VARCHAR(100),
    tax_rate            NUMERIC(10, 4),
    taxable_amount      NUMERIC(18, 2),
    non_taxable_amount  NUMERIC(18, 2),

    -- ── Line-level currency (Phase 2+) ────────────────────────────────────
    line_company_code   VARCHAR(50),
    line_currency       VARCHAR(10),
    line_exchange_rate  NUMERIC(18, 8),
    line_number         INTEGER,
    sub_ledger          VARCHAR(100),
    sub_ledger_type     VARCHAR(50),
    reference_2         VARCHAR(255),           -- Reference 2 / Council ID

    -- ── Workflow certification stamps ─────────────────────────────────────
    prepared_by_user    VARCHAR(255),
    prepared_date       TIMESTAMP WITH TIME ZONE,
    approved_by_user    VARCHAR(255),
    approved_date       TIMESTAMP WITH TIME ZONE,
    reviewed_by_user    VARCHAR(255),
    reviewed_date       TIMESTAMP WITH TIME ZONE,

    -- ── Lifecycle ─────────────────────────────────────────────────────────
    is_selected         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(journal_id, source_row_number)
);

-- =============================================================================
-- 9.11  journal_assignment
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_assignment (
    id                BIGSERIAL PRIMARY KEY,
    assignment_id     VARCHAR(100) UNIQUE NOT NULL,
    journal_id        VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    role_code         VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    assigned_user_id  VARCHAR(100) NOT NULL REFERENCES users(user_id),
    sequence_number   INTEGER NOT NULL,
    assignment_status VARCHAR(50) NOT NULL DEFAULT 'ASSIGNED',
    -- Values: ASSIGNED | IN_PROGRESS | COMPLETED | REJECTED | SKIPPED | REOPENED
    assigned_by       VARCHAR(100) REFERENCES users(user_id),
    assigned_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    activated_at      TIMESTAMP WITH TIME ZONE,
    started_at        TIMESTAMP WITH TIME ZONE,
    completed_at      TIMESTAMP WITH TIME ZONE,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(journal_id, role_code),
    UNIQUE(journal_id, sequence_number)
);

-- ── Segregation of duties ───────────────────────────────────────────────────
-- One person must never hold both the PREPARER and APPROVER assignment on the
-- same journal: they could prepare it, switch to their approver role, and
-- approve their own work.
--
-- This cannot be a CHECK constraint — the rule spans two rows of this table —
-- so it is a trigger. jde_user_dependency_mapping already carries an equivalent
-- CHECK (chk_jde_diff_user), but that only governs the default pairing used at
-- upload time; a direct or corrected assignment bypassed it entirely.
CREATE OR REPLACE FUNCTION enforce_assignment_sod()
RETURNS TRIGGER AS $$
DECLARE
    conflicting_role VARCHAR(50);
BEGIN
    IF NEW.role_code NOT IN ('PREPARER', 'APPROVER') THEN
        RETURN NEW;
    END IF;

    SELECT ja.role_code INTO conflicting_role
    FROM journal_assignment ja
    WHERE ja.journal_id       = NEW.journal_id
      AND ja.assigned_user_id = NEW.assigned_user_id
      AND ja.role_code        <> NEW.role_code
      AND ja.role_code IN ('PREPARER', 'APPROVER')
      AND ja.id               <> COALESCE(NEW.id, -1)
    LIMIT 1;

    IF conflicting_role IS NOT NULL THEN
        RAISE EXCEPTION
            'Segregation of duties: user % is already the % on journal % and cannot also be the %',
            NEW.assigned_user_id, conflicting_role, NEW.journal_id, NEW.role_code
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_journal_assignment_sod ON journal_assignment;
CREATE TRIGGER trg_journal_assignment_sod
    BEFORE INSERT OR UPDATE ON journal_assignment
    FOR EACH ROW EXECUTE FUNCTION enforce_assignment_sod();

-- =============================================================================
-- 9.12  journal_comment
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_comment (
    id           BIGSERIAL PRIMARY KEY,
    comment_id   VARCHAR(100) UNIQUE NOT NULL,
    journal_id   VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    comment_text TEXT NOT NULL,
    comment_type VARCHAR(50)  NOT NULL DEFAULT 'GENERAL',
    -- Values: GENERAL | REJECTION | SYSTEM
    role_code    VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    created_by   VARCHAR(100) NOT NULL REFERENCES users(user_id),
    -- comment_text holds the CURRENT text. Editing overwrites it and appends a
    -- row to journal_comment_history, so the live thread shows only the latest
    -- wording while the full trail stays auditable.
    is_edited    BOOLEAN      NOT NULL DEFAULT FALSE,
    edited_at    TIMESTAMP WITH TIME ZONE,

    -- The journal's FSM status when this comment was written.
    --
    -- A comment is editable only while the journal is STILL in that status. Once
    -- the journal advances — certified, approved, rejected, decertified — the
    -- comment becomes part of the record of a stage that has closed, and
    -- rewording it afterwards would misrepresent what was said at the point of
    -- the decision. Authorship alone is not a sufficient rule: a journal
    -- rejected back to its preparer would otherwise let them rewrite the
    -- comments the approver had already acted on.
    journal_status_at_creation VARCHAR(50),
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.12b  journal_comment_history   (append-only audit trail for comments)
-- =============================================================================
-- One row per action. CREATE stores the original text as new_text with
-- old_text NULL; EDIT stores both sides of the change.
--
-- performed_by_role is captured at the moment of the action, not read back from
-- the user later: a user may hold several roles and switch between them, so the
-- role that made the edit must be frozen into the record.
--
-- Append-only: never UPDATE or DELETE. This is the evidence the live thread
-- deliberately hides.
CREATE TABLE IF NOT EXISTS journal_comment_history (
    id                       BIGSERIAL PRIMARY KEY,
    history_id               VARCHAR(100) UNIQUE NOT NULL,
    comment_id               VARCHAR(100) NOT NULL REFERENCES journal_comment(comment_id),
    journal_id               VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    action                   VARCHAR(20)  NOT NULL,
    old_text                 TEXT,
    new_text                 TEXT         NOT NULL,
    performed_by             VARCHAR(100) NOT NULL REFERENCES users(user_id),
    performed_by_display_name VARCHAR(255),
    performed_by_role        VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    performed_at             TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at               TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    -- NO updated_at — history rows are immutable
    CONSTRAINT chk_jch_action CHECK (action IN ('CREATED', 'EDITED')),
    -- A CREATED row has nothing before it; an EDITED row must record what it replaced.
    CONSTRAINT chk_jch_old_text CHECK (
        (action = 'CREATED' AND old_text IS NULL)
        OR (action = 'EDITED' AND old_text IS NOT NULL)
    )
);

-- =============================================================================
-- 9.13  journal_document
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_document (
    id                  BIGSERIAL PRIMARY KEY,
    document_id         VARCHAR(100) UNIQUE NOT NULL,
    journal_id          VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    original_file_name  VARCHAR(500) NOT NULL,
    file_extension      VARCHAR(50),
    mime_type           VARCHAR(255),
    file_size_bytes     BIGINT,
    file_hash_sha256    VARCHAR(64),
    file_content        BYTEA NOT NULL,         -- Phase 1: DB storage
    s3_key              VARCHAR(1000),          -- Phase 2: S3 key (nullable)
    description         TEXT,
    uploaded_by         VARCHAR(100) NOT NULL REFERENCES users(user_id),
    uploaded_role       VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    uploaded_at         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    status              VARCHAR(50)  NOT NULL DEFAULT 'ACTIVE',
    -- Values: ACTIVE only (no deletion ever)
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.14  journal_hyperlink
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_hyperlink (
    id           BIGSERIAL PRIMARY KEY,
    hyperlink_id VARCHAR(100) UNIQUE NOT NULL,
    journal_id   VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    url          TEXT NOT NULL,
    display_text VARCHAR(500),
    description  TEXT,
    added_by     VARCHAR(100) NOT NULL REFERENCES users(user_id),
    added_role   VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.15  journal_certification  (IMMUTABLE — no updated_at)
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_certification (
    id                      BIGSERIAL PRIMARY KEY,
    certification_id        VARCHAR(100) UNIQUE NOT NULL,
    journal_id              VARCHAR(100) NOT NULL REFERENCES journal_header(journal_id),
    assignment_id           VARCHAR(100) REFERENCES journal_assignment(assignment_id),
    role_code               VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    action                  VARCHAR(50)  NOT NULL,
    -- Values: CERTIFY | REJECT | DECERTIFY | SYSTEM_CERTIFY
    certification_status    VARCHAR(50)  NOT NULL,
    -- Values: CERTIFIED | REJECTED | DECERTIFIED | SYSTEM_CERTIFIED | APPROVED
    certification_statement TEXT,
    comments                TEXT,
    reason_code             VARCHAR(100) REFERENCES rejection_reason_master(reason_code),
    rejection_reason_text   TEXT,
    is_bulk                 BOOLEAN NOT NULL DEFAULT FALSE,
    performed_by            VARCHAR(100) NOT NULL REFERENCES users(user_id),
    performed_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    -- NO updated_at — certification records are IMMUTABLE FOREVER
);

-- =============================================================================
-- 9.16  journal_audit_log  (IMMUTABLE — no updated_at)
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_audit_log (
    id             BIGSERIAL PRIMARY KEY,
    audit_id       VARCHAR(100) UNIQUE NOT NULL,
    journal_id     VARCHAR(100) REFERENCES journal_header(journal_id),
    file_load_id   VARCHAR(100) REFERENCES journal_file_load(file_load_id),
    action_type    VARCHAR(100) NOT NULL,
    -- e.g. FILE_UPLOADED, FILE_PARSED, JOURNAL_CREATED, ASSIGNMENT_CREATED,
    --      PREPARER_CERTIFIED, APPROVER_CERTIFIED, APPROVER_REJECTED,
    --      DECERTIFIED, CLOSED
    old_status     VARCHAR(50),
    new_status     VARCHAR(50),
    performed_by   VARCHAR(100) REFERENCES users(user_id),
    performed_role VARCHAR(50)  REFERENCES roles(role_code),
    message        TEXT,
    metadata_json  JSONB,
    correlation_id VARCHAR(100),
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    -- NO updated_at — audit records are IMMUTABLE FOREVER
);

-- =============================================================================
-- 9.19  certification_statement_config
-- =============================================================================
CREATE TABLE IF NOT EXISTS certification_statement_config (
    id             BIGSERIAL PRIMARY KEY,
    statement_id   VARCHAR(100) UNIQUE NOT NULL,
    role_code      VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    -- module discriminator: 'JOURNAL' for journal certification statements,
    -- 'ACCOUNT' for account reconciliation statements.  Default 'JOURNAL'
    -- preserves existing rows seeded before this column was added.
    module         VARCHAR(50)  NOT NULL DEFAULT 'JOURNAL',
    statement_text TEXT NOT NULL,
    policy_number  VARCHAR(100),
    policy_url     TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    effective_from DATE,
    effective_to   DATE,
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
-- One active statement per (role_code, module) at a time (enforced at application layer)
-- Upgrade path: if schema.sql is re-run against an existing DB the ADD COLUMN IF NOT EXISTS
-- below is a no-op on a fresh DB (column already exists) and adds the column on upgrade.
ALTER TABLE certification_statement_config
    ADD COLUMN IF NOT EXISTS module VARCHAR(50) NOT NULL DEFAULT 'JOURNAL';

-- =============================================================================
-- 9.20  notification_log
-- =============================================================================
CREATE TABLE IF NOT EXISTS notification_log (
    id                  BIGSERIAL PRIMARY KEY,
    notification_id     VARCHAR(100) UNIQUE NOT NULL,
    journal_id          VARCHAR(100) REFERENCES journal_header(journal_id),
    recipient_user_id   VARCHAR(100) NOT NULL REFERENCES users(user_id),
    recipient_email     VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,
    -- Values: JOURNAL_ASSIGNED | PREPARER_CERTIFIED | APPROVER_CERTIFIED |
    --         APPROVER_REJECTED | REVIEWER_REQUIRED
    subject             VARCHAR(500),
    body_text           TEXT,
    status              VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    -- Values: PENDING | SENT | READ | FAILED
    sent_at             TIMESTAMP WITH TIME ZONE,
    read_at             TIMESTAMP WITH TIME ZONE,
    error_message       TEXT,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.21  ai_session_log  (IMMUTABLE append-only audit — no updated_at)
-- =============================================================================
CREATE TABLE IF NOT EXISTS ai_session_log (
    id            BIGSERIAL PRIMARY KEY,
    session_id    VARCHAR(100) UNIQUE NOT NULL,
    user_id       VARCHAR(100) NOT NULL REFERENCES users(user_id),
    request_type  VARCHAR(50)  NOT NULL,
    -- Values: AI_FILTER | AI_EXPORT
    user_query    TEXT NOT NULL,
    parsed_result JSONB,
    model_used    VARCHAR(100),
    tokens_used   INTEGER,
    latency_ms    INTEGER,
    status        VARCHAR(50) NOT NULL DEFAULT 'SUCCESS',
    -- Values: SUCCESS | ERROR | TIMEOUT
    error_message TEXT,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    -- NO updated_at — AI session log is immutable
);

-- =============================================================================
-- 9.22  app_config
-- =============================================================================
CREATE TABLE IF NOT EXISTS app_config (
    id           BIGSERIAL PRIMARY KEY,
    config_key   VARCHAR(255) UNIQUE NOT NULL,
    config_value TEXT NOT NULL,
    config_type  VARCHAR(50) NOT NULL DEFAULT 'STRING',
    -- Values: STRING | INTEGER | BOOLEAN | JSON
    description  TEXT,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 9.23  company_news  (NEW — confirmed from screenshots 1.03.45 AM, 1.06.25 AM)
-- =============================================================================
CREATE TABLE IF NOT EXISTS company_news (
    id         BIGSERIAL PRIMARY KEY,
    news_id    VARCHAR(100) UNIQUE NOT NULL,
    news_date  DATE NOT NULL,
    headline   VARCHAR(500) NOT NULL,
    body_text  TEXT,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,   -- soft-hide; never DELETE
    created_by VARCHAR(100) NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
-- Visible: all authenticated roles on Home > My Work > Company News card
-- Edit:    BUSINESS_ADMIN, SYSTEM_ADMIN (Add News Item on Home Admin page)

-- =============================================================================
-- 9.24  user_module_permission  (NEW — confirmed from screenshot 1.24.12 AM)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_module_permission (
    id         BIGSERIAL PRIMARY KEY,
    user_id    VARCHAR(100) NOT NULL REFERENCES users(user_id),
    role_code  VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    module_code VARCHAR(50) NOT NULL,
    -- Values: ACCOUNT | CONSOLIDATIONS | JOURNAL_DOCUMENT | MATCH |
    --         TASK | VARIANCE_ANALYSIS | INTERCOMPANY
    is_granted BOOLEAN NOT NULL DEFAULT FALSE,
    granted_by VARCHAR(100) REFERENCES users(user_id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, role_code, module_code)
);
-- Phase 1 note: only JOURNAL_DOCUMENT drives access control. Other module
-- columns render as informational in the 16-role × 7-module grid.

-- =============================================================================
-- 9.25  dependent_validation  (NEW — confirmed from screenshots 1.06.47 AM, 1.07.14 AM)
-- =============================================================================
CREATE TABLE IF NOT EXISTS dependent_validation (
    id                    BIGSERIAL PRIMARY KEY,
    validation_id         VARCHAR(100) UNIQUE NOT NULL,
    field_name            VARCHAR(255) NOT NULL,       -- Name column
    field_value           VARCHAR(500) NOT NULL,       -- Value column
    dependent_field_name  VARCHAR(255) NOT NULL,       -- Dependent Name column
    dependent_field_value VARCHAR(500) NOT NULL,       -- Dependent Value column
    is_deleted            BOOLEAN NOT NULL DEFAULT FALSE,  -- Deleted column (soft-delete)
    source_system         VARCHAR(100) NOT NULL DEFAULT 'SEED',
    source_file_name      VARCHAR(500),
    created_by            VARCHAR(100) REFERENCES users(user_id),
    created_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
-- No hard DELETE — set is_deleted = TRUE to remove from active validation
-- View: SYSTEM_ADMIN only (admin settings area, /admin/dependent-validation)

-- =============================================================================
-- 9.26  user_dashboard_config  (NEW — confirmed from screenshots 1.08.21 AM – 1.08.57 AM)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_dashboard_config (
    id             BIGSERIAL PRIMARY KEY,
    config_id      VARCHAR(100) UNIQUE NOT NULL,
    user_id        VARCHAR(100) NOT NULL REFERENCES users(user_id),
    dashboard_name VARCHAR(255) NOT NULL DEFAULT 'My Dashboard',
    is_default     BOOLEAN NOT NULL DEFAULT FALSE,  -- the active dashboard for this user
    layout_json    JSONB NOT NULL,
    -- Layout structure: [{card_key, x, y, w, h, visible}]
    -- card_key values: company_news | recon_status | past_due_recs | task_cert_status |
    --                  tasks_due | intercompany_cert_status | journal_cert_status |
    --                  unreconciled_balance | prior_period_recs | open_adjustments
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
-- One is_default = TRUE per user at a time (enforced at application layer)
-- If no row exists for a user: serve the built-in 9-card default layout
-- No deletion: set is_default = FALSE to switch to another layout

-- =============================================================================
-- 9.27  role_capabilities  (NEW — required for /api/v1/config/role-permissions)
-- =============================================================================
-- Maps each role_code to the UI capabilities it is permitted to exercise.
-- The frontend fetches this table via GET /api/v1/config/role-permissions
-- (cached 10 min) to decide which action buttons to render on the certify page.
-- Missing this table = no action buttons anywhere in the app.
CREATE TABLE IF NOT EXISTS role_capabilities (
    role_code   VARCHAR(50)  NOT NULL REFERENCES roles(role_code) ON DELETE CASCADE,
    capability  VARCHAR(100) NOT NULL,
    -- Capability values (must match frontend constants/rolePermissions.ts):
    --   certify_as_preparer | certify_as_approver | add_comment | add_document
    --   add_hyperlink | view_all_journals | upload_file | manage_users | decertify
    --   validate_journal
    -- validate_journal: admin moves NOT_PREPARED → PREPARED. Mirrors the
    -- ADMIN_ROLES check in services/journal_service.validate_journal(), which
    -- is the actual authority; the UI must not be stricter than the API.
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    PRIMARY KEY (role_code, capability)
);

-- =============================================================================
-- 9.28  user_dashboard_cards  (AI v2 — per-user custom dashboard cards)
-- =============================================================================
-- Stores built-in status cards and AI-created custom cards for each user.
-- Built-in cards: is_default=TRUE, cannot be deleted, position is user-defined.
-- Custom cards: is_default=FALSE, AI-created, user can delete.
-- Card config_json for status cards: {"status": "REJECTED", "filters": {...}}
-- Card config_json for custom: {"status": "...", "currency": "AUD", ...}
CREATE TABLE IF NOT EXISTS user_dashboard_cards (
    card_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      VARCHAR(50)  NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    card_type    VARCHAR(50)  NOT NULL CHECK (card_type IN ('status_count', 'custom')),
    label        VARCHAR(100) NOT NULL,
    icon         VARCHAR(50),
    color        VARCHAR(20),
    config_json  JSONB        NOT NULL DEFAULT '{}',
    position     INTEGER      NOT NULL DEFAULT 0,
    is_default   BOOLEAN      NOT NULL DEFAULT FALSE,
    is_visible   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- One set of default cards per user; position updated on drag-reorder
-- If no cards exist for a user, the UI seeds the FSM defaults on first load

-- =============================================================================
-- ══ MODULE: ACCOUNT RECONCILIATION (module 2 of 8) ══
-- Source of truth: Docs/New Requirement.md appendix (lines 3166–3659).
-- The appendix is AUTHORITATIVE and supersedes prose sections 19–22 where
-- they disagree.  Table prefix: account_*.  Mirrors journal_* conventions:
--   • Business-key FKs only (user_id, role_code, team_id, reconciliation_id,
--     file_load_id) — never surrogate BIGSERIAL PKs across module tables.
--   • IF NOT EXISTS on every CREATE TABLE.
--   • Mutable tables: created_at + updated_at (both NOT NULL DEFAULT NOW()).
--   • Immutable tables (account_certification, account_audit_log,
--     account_rule_evaluation_log, ai_validation_log): created_at only —
--     no updated_at, no UPDATE, no DELETE ever.
--   • Soft-delete via is_active/status; no physical deletes anywhere.
--   • account_rule / account_rule_evaluation_log follow the generic
--     cross-module rule-engine pattern (Appendix §4).  Zero-balance
--     auto-cert is rule #1 (rule_id=ZERO_BAL_NO_ACTIVITY,
--     rule_type=ZERO_BALANCE_AUTO_CERT) — not a bespoke table.
-- IMPORTANT: All indexes for this module live in backend/sql/indexes.sql.
--            Each table below has a comment naming its indexes there.
-- =============================================================================

-- =============================================================================
-- 10.1  account_file_load
--       Mirrors journal_file_load.  One uploaded Accounts text file = one batch.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_file_load (
    id                      BIGSERIAL PRIMARY KEY,
    file_load_id            VARCHAR(100) UNIQUE NOT NULL,
    original_file_name      VARCHAR(500) NOT NULL,
    file_extension          VARCHAR(50),
    mime_type               VARCHAR(255),
    file_size_bytes         BIGINT,
    file_hash_sha256        VARCHAR(64),
    file_content            BYTEA NOT NULL,
    -- Parser configuration
    source_type             VARCHAR(50)  NOT NULL DEFAULT 'MANUAL_UPLOAD',
    delimiter               VARCHAR(20)  NOT NULL DEFAULT 'TAB',
    expected_column_count   INTEGER      NOT NULL DEFAULT 22,
    period_end_date         DATE,
    -- Parse counters
    total_rows              INTEGER      NOT NULL DEFAULT 0,
    valid_rows              INTEGER      NOT NULL DEFAULT 0,
    invalid_rows            INTEGER      NOT NULL DEFAULT 0,
    accounts_created        INTEGER      NOT NULL DEFAULT 0,
    system_certified_count  INTEGER      NOT NULL DEFAULT 0,
    -- Lifecycle status: PENDING | UPLOADING | PARSING | PARSE_SUCCESS |
    --                   PARSE_FAILED | ASSIGNMENT_FAILED
    status                  VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    error_message           TEXT,
    parse_errors_json       JSONB,
    uploaded_by             VARCHAR(100) REFERENCES users(user_id),
    uploaded_role           VARCHAR(50)  REFERENCES roles(role_code),
    uploaded_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    processed_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- Indexes: backend/sql/indexes.sql → idx_afl_uploaded_by, idx_afl_status,
--          idx_afl_uploaded_at

-- =============================================================================
-- 10.2  account_reconciliation  (reconciliation header — mirrors journal_header)
--       One row per account per period.  Lands in the SYSTEM_ADMIN queue after
--       upload (NOT_ASSIGNED) unless zero-balance/no-activity, in which case
--       it is auto-certified (SYSTEM_CERTIFIED).  7-status FSM.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_reconciliation (
    id                         BIGSERIAL PRIMARY KEY,
    reconciliation_id          VARCHAR(100) UNIQUE NOT NULL,
    source_file_id             VARCHAR(100) NOT NULL
                                   REFERENCES account_file_load(file_load_id),

    -- ── From Accounts import file (BL_Accounts_Import_Template, AR-03) ──────
    entity_unique_id           VARCHAR(100) NOT NULL,
    account_number             VARCHAR(100) NOT NULL,
    key3                       VARCHAR(50),
    key4                       VARCHAR(50),
    key5                       VARCHAR(50),
    key6                       VARCHAR(50),
    key7                       VARCHAR(50),
    key8                       VARCHAR(50),
    key9                       VARCHAR(50),
    key10                      VARCHAR(50),
    account_description        VARCHAR(500),
    account_reference          VARCHAR(50),
    assignment_type            VARCHAR(10),           -- 'A' = Account Reconciliation
    account_type               VARCHAR(50),
    active_account             BOOLEAN NOT NULL DEFAULT TRUE,
    activity_in_period         BOOLEAN NOT NULL DEFAULT FALSE,  -- auto-cert driver
    alternate_currency         VARCHAR(10),
    account_currency           VARCHAR(10),
    period_end_date            DATE NOT NULL,
    period_label               VARCHAR(7),                      -- MM/YYYY (denormalized)

    -- ── Balances ─────────────────────────────────────────────────────────────
    gl_reporting_balance       NUMERIC(20, 2),
    gl_alternate_balance       NUMERIC(20, 2),
    -- gl_account_balance is nullable: a blank balance in the source file is a real
    -- business value ("null balance"), not a data error.  The zero-balance rule's
    -- treat_null_as_zero predicate depends on distinguishing NULL from 0.
    gl_account_balance         NUMERIC(20, 2),
    gl_account_balance_usd     NUMERIC(20, 2),
    bl_currency_rate_usd       NUMERIC(18, 8) DEFAULT 1,

    -- ── Computed / Admin-set-once-at-assignment fields ────────────────────────
    -- account_name: colA..colI joined with '-', blanks preserved as empty positions
    account_name               VARCHAR(500),
    risk_rating                VARCHAR(20)  NOT NULL DEFAULT 'NONE',
    -- reconciliation_frequency: stored/selectable now; not enforced until
    -- FREQUENCY_QUEUE_FILTER rule is activated (decision log #8)
    reconciliation_frequency   VARCHAR(20)  NOT NULL DEFAULT 'MONTHLY',
    -- alternate_currency_display: always 'USD', sourced from app_config;
    -- never taken from the file's own column
    alternate_currency_display VARCHAR(10)  NOT NULL DEFAULT 'USD',

    -- ── Denormalized display / grouping ──────────────────────────────────────
    company_code               VARCHAR(50),
    region                     VARCHAR(100),
    team_id                    VARCHAR(100) REFERENCES teams(team_id),
    template                   VARCHAR(255) NOT NULL DEFAULT 'Account Reconciliation',
    header_status_display      VARCHAR(255),
    final_certification_state  VARCHAR(100),
    is_completed               BOOLEAN NOT NULL DEFAULT FALSE,

    -- ── Assignment (populated by System Admin — manual assignment) ────────────
    preparer_user_id           VARCHAR(100) REFERENCES users(user_id),
    approver_user_id           VARCHAR(100) REFERENCES users(user_id),
    reviewer_user_id           VARCHAR(100) REFERENCES users(user_id),

    -- ── Presence flags (updated by item/comment/document services) ────────────
    has_items                  BOOLEAN NOT NULL DEFAULT FALSE,
    has_comments               BOOLEAN NOT NULL DEFAULT FALSE,
    has_documents              BOOLEAN NOT NULL DEFAULT FALSE,

    -- ── Workflow status (7-status FSM, AR-04 §4.1–4.2) ───────────────────────
    -- NOT_ASSIGNED     : parsed, sitting in SYSTEM_ADMIN queue (unassigned)
    -- NOT_PREPARED     : admin assigned preparer+approver, awaiting preparer
    -- PREPARED         : preparer certified, awaiting approver
    -- APPROVED         : approver approved (terminal)
    -- REJECTED         : approver rejected; preparer must re-certify
    -- DECERTIFIED      : preparer retracted; preparer must re-certify
    -- SYSTEM_CERTIFIED : zero-balance / no-activity auto-certification (terminal)
    status                     VARCHAR(50) NOT NULL DEFAULT 'NOT_ASSIGNED',
    is_zero_balance            BOOLEAN NOT NULL DEFAULT FALSE,
    auto_cert_rule_id          VARCHAR(100),  -- account_rule.rule_id that fired, if any

    CONSTRAINT chk_ar_status CHECK (
        status IN (
            'NOT_ASSIGNED','NOT_PREPARED','PREPARED','APPROVED',
            'REJECTED','DECERTIFIED','SYSTEM_CERTIFIED'
        )
    ),
    -- Header-level SoD: preparer and approver must be different people.
    -- Row-level SoD across account_assignment rows is enforced by
    -- trg_account_assignment_sod below (a CHECK constraint cannot see other rows).
    CONSTRAINT chk_ar_diff_user CHECK (
        preparer_user_id IS NULL
        OR approver_user_id IS NULL
        OR preparer_user_id <> approver_user_id
    ),
    CONSTRAINT chk_ar_risk_rating CHECK (
        risk_rating IN ('NONE','LOW','MEDIUM','HIGH')
    ),
    CONSTRAINT chk_ar_frequency CHECK (
        reconciliation_frequency IN ('MONTHLY','QUARTERLY','ANNUAL')
    ),

    -- ── Lifecycle ────────────────────────────────────────────────────────────
    is_active                  BOOLEAN NOT NULL DEFAULT TRUE,
    created_by                 VARCHAR(100) REFERENCES users(user_id),
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at                  TIMESTAMPTZ,

    -- One reconciliation per account per entity per period
    UNIQUE(entity_unique_id, account_number, period_end_date, account_currency)
);
-- Indexes: backend/sql/indexes.sql → idx_ar_period, idx_ar_status,
--          idx_ar_period_status, idx_ar_company, idx_ar_region, idx_ar_team,
--          idx_ar_source_file, idx_ar_account_num, idx_ar_entity,
--          idx_ar_preparer, idx_ar_approver, idx_ar_zero_balance,
--          idx_ar_active, idx_ar_created_at, idx_ar_admin_queue

-- =============================================================================
-- 10.3  account_recon_item
--       Items added by the Preparer (reconciling lines: description, amount,
--       aging, etc.) — analogue of Journal Detail 'Items'.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_recon_item (
    id                       BIGSERIAL PRIMARY KEY,
    item_id                  VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id        VARCHAR(100) NOT NULL
                                 REFERENCES account_reconciliation(reconciliation_id),
    line_number              INTEGER NOT NULL,
    item_type                VARCHAR(50) NOT NULL DEFAULT 'RECONCILING_ITEM',
    -- Values: RECONCILING_ITEM | ADJUSTMENT | SUPPORTING_BALANCE | OTHER
    item_description         VARCHAR(1000),
    item_reference           VARCHAR(255),
    item_amount              NUMERIC(20, 2) NOT NULL DEFAULT 0,
    item_amount_usd          NUMERIC(20, 2) NOT NULL DEFAULT 0,
    item_currency            VARCHAR(10),
    item_date                DATE,
    aging_bucket             VARCHAR(50),   -- e.g. 0-30 | 31-60 | 61-90 | 90+
    is_required_adjustment   BOOLEAN NOT NULL DEFAULT FALSE,
    is_active                BOOLEAN NOT NULL DEFAULT TRUE,  -- soft-delete only
    created_by               VARCHAR(100) NOT NULL REFERENCES users(user_id),
    created_role             VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(reconciliation_id, line_number)
);
-- Indexes: backend/sql/indexes.sql → idx_ari_recon_id, idx_ari_created_by

-- =============================================================================
-- 10.4  account_assignment  (mirrors journal_assignment)
--       Row-level SoD is enforced by trg_account_assignment_sod immediately
--       below this table.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_assignment (
    id                BIGSERIAL PRIMARY KEY,
    assignment_id     VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id VARCHAR(100) NOT NULL
                          REFERENCES account_reconciliation(reconciliation_id),
    role_code         VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    assigned_user_id  VARCHAR(100) NOT NULL REFERENCES users(user_id),
    sequence_number   INTEGER NOT NULL,
    assignment_status VARCHAR(50) NOT NULL DEFAULT 'ASSIGNED',
    -- Values: ASSIGNED | IN_PROGRESS | COMPLETED | REJECTED | SKIPPED | REOPENED
    assigned_by       VARCHAR(100) REFERENCES users(user_id),
    assigned_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at      TIMESTAMPTZ,
    started_at        TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(reconciliation_id, role_code),
    UNIQUE(reconciliation_id, sequence_number)
);

-- ── Segregation of duties (row-level) ─────────────────────────────────────────
-- One person must never hold both the PREPARER and APPROVER assignment on the
-- same reconciliation.  This cannot be a CHECK constraint because the rule
-- spans two rows of this table, so it is a trigger.  The header-level CHECK
-- (chk_ar_diff_user on account_reconciliation) only governs the denormalized
-- preparer_user_id / approver_user_id columns; this trigger covers direct
-- assignments that bypass or correct that pairing.
CREATE OR REPLACE FUNCTION enforce_account_assignment_sod()
RETURNS TRIGGER AS $$
DECLARE
    conflicting_role VARCHAR(50);
BEGIN
    IF NEW.role_code NOT IN ('PREPARER', 'APPROVER') THEN
        RETURN NEW;
    END IF;

    SELECT aa.role_code INTO conflicting_role
    FROM account_assignment aa
    WHERE aa.reconciliation_id = NEW.reconciliation_id
      AND aa.assigned_user_id  = NEW.assigned_user_id
      AND aa.role_code         <> NEW.role_code
      AND aa.role_code IN ('PREPARER', 'APPROVER')
      AND aa.id                <> COALESCE(NEW.id, -1)
    LIMIT 1;

    IF conflicting_role IS NOT NULL THEN
        RAISE EXCEPTION
            'Segregation of duties: user % is already the % on reconciliation % and cannot also be the %',
            NEW.assigned_user_id, conflicting_role, NEW.reconciliation_id, NEW.role_code
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_account_assignment_sod ON account_assignment;
CREATE TRIGGER trg_account_assignment_sod
    BEFORE INSERT OR UPDATE ON account_assignment
    FOR EACH ROW EXECUTE FUNCTION enforce_account_assignment_sod();

-- Indexes: backend/sql/indexes.sql → idx_aa_user_role, idx_aa_recon_id,
--          idx_aa_status

-- =============================================================================
-- 10.5  account_comment  (mirrors journal_comment)
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_comment (
    id                       BIGSERIAL PRIMARY KEY,
    comment_id               VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id        VARCHAR(100) NOT NULL
                                 REFERENCES account_reconciliation(reconciliation_id),
    comment_text             TEXT NOT NULL,
    comment_type             VARCHAR(50) NOT NULL DEFAULT 'GENERAL',
    -- Values: GENERAL | REJECTION | SYSTEM
    role_code                VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    created_by               VARCHAR(100) NOT NULL REFERENCES users(user_id),
    is_edited                BOOLEAN NOT NULL DEFAULT FALSE,
    edited_at                TIMESTAMPTZ,
    recon_status_at_creation VARCHAR(50),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Indexes: backend/sql/indexes.sql → idx_ac_recon_id, idx_ac_created_by

-- =============================================================================
-- 10.6  account_document  (mirrors journal_document — supporting documents)
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_document (
    id                    BIGSERIAL PRIMARY KEY,
    document_id           VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id     VARCHAR(100) NOT NULL
                              REFERENCES account_reconciliation(reconciliation_id),
    original_file_name    VARCHAR(500) NOT NULL,
    file_extension        VARCHAR(50),
    mime_type             VARCHAR(255),
    file_size_bytes       BIGINT,
    file_hash_sha256      VARCHAR(64),
    file_content          BYTEA NOT NULL,     -- Phase 1: DB storage
    s3_key                VARCHAR(1000),       -- Phase 2: S3 (nullable)
    description           TEXT,
    is_validation_source  BOOLEAN NOT NULL DEFAULT FALSE,  -- AI Excel-vs-screen source flag
    uploaded_by           VARCHAR(100) NOT NULL REFERENCES users(user_id),
    uploaded_role         VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    uploaded_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    status                VARCHAR(50)  NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE only, no delete
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- Indexes: backend/sql/indexes.sql → idx_ad_recon_id, idx_ad_uploaded_by,
--          idx_ad_validation

-- =============================================================================
-- 10.7  account_hyperlink  (mirrors journal_hyperlink)
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_hyperlink (
    id                BIGSERIAL PRIMARY KEY,
    hyperlink_id      VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id VARCHAR(100) NOT NULL
                          REFERENCES account_reconciliation(reconciliation_id),
    url               TEXT NOT NULL,
    display_text      VARCHAR(500),
    description       TEXT,
    added_by          VARCHAR(100) NOT NULL REFERENCES users(user_id),
    added_role        VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Indexes: backend/sql/indexes.sql → idx_ah_recon_id

-- =============================================================================
-- 10.8  account_certification  (IMMUTABLE — mirrors journal_certification)
--       Records every certify/approve/reject/decertify AND the zero-balance
--       SYSTEM_CERTIFY action.  Reuses rejection_reason_master + statement config.
--       NO updated_at — certification records are IMMUTABLE FOREVER.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_certification (
    id                    BIGSERIAL PRIMARY KEY,
    certification_id      VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id     VARCHAR(100) NOT NULL
                              REFERENCES account_reconciliation(reconciliation_id),
    assignment_id         VARCHAR(100) REFERENCES account_assignment(assignment_id),
    role_code             VARCHAR(50)  NOT NULL REFERENCES roles(role_code),
    action                VARCHAR(50)  NOT NULL,
    -- Values: CERTIFY | APPROVE | REJECT | DECERTIFY | SYSTEM_CERTIFY
    certification_status  VARCHAR(50)  NOT NULL,
    -- Values: PREPARED | APPROVED | REJECTED | DECERTIFIED | SYSTEM_CERTIFIED
    certification_statement TEXT,
    comments              TEXT,
    reason_code           VARCHAR(100) REFERENCES rejection_reason_master(reason_code),
    rejection_reason_text TEXT,
    is_system             BOOLEAN NOT NULL DEFAULT FALSE,  -- TRUE for SYSTEM_CERTIFY
    is_bulk               BOOLEAN NOT NULL DEFAULT FALSE,
    performed_by          VARCHAR(100) REFERENCES users(user_id),  -- NULL when system
    performed_by_display  VARCHAR(255),                            -- 'System' when auto
    performed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — certification records are IMMUTABLE FOREVER
);
-- Indexes: backend/sql/indexes.sql → idx_acert_recon_id, idx_acert_performed,
--          idx_acert_role_action, idx_acert_at

-- =============================================================================
-- 10.9  account_audit_log  (IMMUTABLE — mirrors journal_audit_log)
--       NO updated_at — audit records are IMMUTABLE FOREVER.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_audit_log (
    id                BIGSERIAL PRIMARY KEY,
    audit_id          VARCHAR(100) UNIQUE NOT NULL,
    reconciliation_id VARCHAR(100) REFERENCES account_reconciliation(reconciliation_id),
    file_load_id      VARCHAR(100) REFERENCES account_file_load(file_load_id),
    action_type       VARCHAR(100) NOT NULL,
    -- e.g. FILE_UPLOADED, FILE_PARSED, RECON_CREATED, ZERO_BALANCE_SYSTEM_CERTIFIED,
    --      ASSIGNMENT_CREATED, PREPARER_CERTIFIED, APPROVER_APPROVED,
    --      APPROVER_REJECTED, DECERTIFIED, ITEM_ADDED, DOCUMENT_ADDED,
    --      AI_VALIDATION_RUN, CLOSED
    old_status        VARCHAR(50),
    new_status        VARCHAR(50),
    performed_by      VARCHAR(100) REFERENCES users(user_id),
    performed_role    VARCHAR(50)  REFERENCES roles(role_code),
    message           TEXT,
    metadata_json     JSONB,
    correlation_id    VARCHAR(100),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — audit records are IMMUTABLE FOREVER
);
-- Indexes: backend/sql/indexes.sql → idx_aal_recon_id, idx_aal_file_load,
--          idx_aal_action_type, idx_aal_performed_by, idx_aal_created_at

-- =============================================================================
-- 10.10  account_rule
--        Generic cross-module business-rule pattern (Appendix §4).
--        Zero-balance auto-cert (rule_id=ZERO_BAL_NO_ACTIVITY,
--        rule_type=ZERO_BALANCE_AUTO_CERT) is rule #1 — NOT a bespoke
--        account_zero_balance_rule table.  Predicate config lives in
--        scope_json, e.g.:
--          {"require_zero_balance":true,"treat_null_as_zero":true,
--           "require_no_activity":true,"zero_tolerance":0,
--           "applies_to_assignment_type":"A"}.
--        Future rules are added as rows + a small evaluator function — never
--        a new table.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_rule (
    id             BIGSERIAL PRIMARY KEY,
    rule_id        VARCHAR(100) UNIQUE NOT NULL,
    rule_type      VARCHAR(100) NOT NULL,
    -- e.g. 'ZERO_BALANCE_AUTO_CERT', 'FREQUENCY_QUEUE_FILTER'
    rule_name      VARCHAR(255) NOT NULL,
    description    TEXT,
    scope_json     JSONB,
    -- {"roles":[...],"pages":[...],"company_codes":[...], <predicate config>}
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    effective_from DATE,
    effective_to   DATE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Indexes: backend/sql/indexes.sql → idx_arule_type, idx_arule_active

-- =============================================================================
-- 10.11  account_rule_evaluation_log  (IMMUTABLE)
--        One row per rule evaluation.  record_ref holds the reconciliation_id
--        on which the rule fired.
--        NO updated_at — evaluation log records are IMMUTABLE FOREVER.
-- =============================================================================
CREATE TABLE IF NOT EXISTS account_rule_evaluation_log (
    id          BIGSERIAL PRIMARY KEY,
    eval_id     VARCHAR(100) UNIQUE NOT NULL,
    rule_id     VARCHAR(100) NOT NULL REFERENCES account_rule(rule_id),
    record_ref  VARCHAR(100) NOT NULL,  -- reconciliation_id the rule fired on
    outcome     VARCHAR(50)  NOT NULL,  -- e.g. 'SYSTEM_CERTIFIED', 'SKIPPED', 'FLAGGED'
    detail_json JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — evaluation log records are IMMUTABLE FOREVER
);
-- Indexes: backend/sql/indexes.sql → idx_arel_rule_id, idx_arel_record_ref,
--          idx_arel_created_at

-- =============================================================================
-- 10.12  ai_validation_log  (IMMUTABLE append-only audit)
--        AI Excel-vs-Screen Discrepancy Validation — used on BOTH the Journal
--        Details page and the Account Reconciliation Details page.
--        context_type discriminates JOURNAL vs ACCOUNT so one table serves
--        both detail pages.  Per ArchitecturePlanV2.md §5.2: NOT a new AI
--        subsystem — two additional tools folded into the existing agent loop.
--        DATA GOVERNANCE: the AI never mutates financial data and never
--        receives raw ledgers — all arithmetic/normalisation happens
--        server-side; the model receives only minimized, pre-computed
--        discrepancy descriptors.
--        source_document_id is a polymorphic reference (not a FK): it holds
--        journal_document.document_id OR account_document.document_id
--        depending on context_type.
--        NO updated_at — immutable, like ai_session_log.
-- =============================================================================
CREATE TABLE IF NOT EXISTS ai_validation_log (
    id                  BIGSERIAL PRIMARY KEY,
    validation_id       VARCHAR(100) UNIQUE NOT NULL,

    -- What was validated
    context_type        VARCHAR(50)  NOT NULL,   -- JOURNAL | ACCOUNT
    context_id          VARCHAR(100) NOT NULL,   -- journal_id or reconciliation_id

    -- Source of the "truth" file the user uploaded to be checked
    -- (polymorphic — not a FK; see table comment above)
    source_document_id  VARCHAR(100),
    source_file_name    VARCHAR(500),
    source_file_hash    VARCHAR(64),

    -- AI request / response metadata (NO raw financial values persisted here)
    requested_by        VARCHAR(100) NOT NULL REFERENCES users(user_id),
    requested_role      VARCHAR(50)  REFERENCES roles(role_code),
    model_used          VARCHAR(100),
    tokens_used         INTEGER,
    latency_ms          INTEGER,

    -- Result summary (arithmetic done server-side; AI classifies only)
    rows_compared       INTEGER NOT NULL DEFAULT 0,
    fields_compared     INTEGER NOT NULL DEFAULT 0,
    match_count         INTEGER NOT NULL DEFAULT 0,
    discrepancy_count   INTEGER NOT NULL DEFAULT 0,
    result_status       VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    -- Values: PENDING | MATCH | DISCREPANCIES_FOUND | ERROR | TIMEOUT | DECLINED

    -- Structured, minimized discrepancy payload for UI rendering:
    -- [{ field, screen_value, file_value, row_ref, severity, note }]
    discrepancies_json  JSONB,
    error_message       TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — immutable, like ai_session_log
);
-- Indexes: backend/sql/indexes.sql → idx_aiv_context, idx_aiv_requested_by,
--          idx_aiv_result, idx_aiv_created_at, idx_aiv_source_doc
