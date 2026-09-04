-- =============================================================================
-- BlackLine Journal Certification Pilot — Index Definitions
-- =============================================================================
-- Version  : 2.0
-- Date     : 2026-08-22
-- Author   : Deeptirani Mishra
-- Source   : ARCHITECTURE.md sections 9.1–9.26
--
-- Naming convention: idx_<table_abbreviation>_<column(s)>
-- One index per relevant query pattern:
--   • FK lookups (avoid seq-scan on FK columns)
--   • Status filters (work-queue page loads, admin views)
--   • Period filters (journal grid filtered by journal_period)
--   • User lookups (ADID, email, username)
--   • Audit/date ordering (newest-first scans)
-- =============================================================================

-- =============================================================================
-- users
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_users_adid
    ON users(adid);

CREATE INDEX IF NOT EXISTS idx_users_email
    ON users(email);

CREATE INDEX IF NOT EXISTS idx_users_username
    ON users(username);

CREATE INDEX IF NOT EXISTS idx_users_status_active
    ON users(status, is_active);

-- =============================================================================
-- user_roles
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id
    ON user_roles(user_id, is_active);

CREATE INDEX IF NOT EXISTS idx_user_roles_role_code
    ON user_roles(role_code, is_active);

-- =============================================================================
-- user_session
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_user_session_user_id
    ON user_session(user_id);

CREATE INDEX IF NOT EXISTS idx_user_session_jti
    ON user_session(jwt_jti);

CREATE INDEX IF NOT EXISTS idx_user_session_active
    ON user_session(user_id, is_active, expires_at);

-- =============================================================================
-- jde_user_dependency_mapping
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_dep_preparer_adid
    ON jde_user_dependency_mapping(preparer_adid, is_active);

CREATE INDEX IF NOT EXISTS idx_dep_approver_adid
    ON jde_user_dependency_mapping(approver_adid, is_active);

CREATE INDEX IF NOT EXISTS idx_dep_company
    ON jde_user_dependency_mapping(company_code, is_active);

CREATE INDEX IF NOT EXISTS idx_dep_team_id
    ON jde_user_dependency_mapping(team_id);

-- =============================================================================
-- currency_conversion_rate
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_ccr_lookup
    ON currency_conversion_rate(from_currency, to_currency, effective_from, is_active);

-- =============================================================================
-- journal_file_load
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_file_load_uploaded_by
    ON journal_file_load(uploaded_by);

CREATE INDEX IF NOT EXISTS idx_file_load_status
    ON journal_file_load(status);

CREATE INDEX IF NOT EXISTS idx_file_load_uploaded_at
    ON journal_file_load(uploaded_at DESC);

-- =============================================================================
-- journal_header
-- =============================================================================
-- Period filter — primary work-queue query pattern (load all journals for a period)
CREATE INDEX IF NOT EXISTS idx_jh_period
    ON journal_header(journal_period);

-- Status filter — admin grid, work-queue filtering
CREATE INDEX IF NOT EXISTS idx_jh_status
    ON journal_header(status);

-- Combined period + status — most frequent work-queue WHERE clause
CREATE INDEX IF NOT EXISTS idx_jh_period_status
    ON journal_header(journal_period, status);

-- FK lookups on company / region / batch for admin filtering
CREATE INDEX IF NOT EXISTS idx_jh_company_code
    ON journal_header(company_code);

CREATE INDEX IF NOT EXISTS idx_jh_region
    ON journal_header(region);

-- Source file join
CREATE INDEX IF NOT EXISTS idx_jh_source_file_id
    ON journal_header(source_file_id);

-- Document number lookup (dedup check on upload)
CREATE INDEX IF NOT EXISTS idx_jh_document_number
    ON journal_header(document_number);

-- Preparer / approver / reviewer FK lookups (grid filters, queue routing)
CREATE INDEX IF NOT EXISTS idx_jh_preparer_user_id
    ON journal_header(preparer_user_id, status);

CREATE INDEX IF NOT EXISTS idx_jh_approver_user_id
    ON journal_header(approver_user_id, status);

CREATE INDEX IF NOT EXISTS idx_jh_reviewer_user_id
    ON journal_header(reviewer_user_id);

-- Team FK lookup
CREATE INDEX IF NOT EXISTS idx_jh_team_id
    ON journal_header(team_id);

-- BlackLine ID lookup (external ID search)
CREATE INDEX IF NOT EXISTS idx_jh_baxter_id
    ON journal_header(baxter_id);

-- Soft-delete / active filter
CREATE INDEX IF NOT EXISTS idx_jh_is_active
    ON journal_header(is_active);

-- Newest-first ordering (default grid sort)
CREATE INDEX IF NOT EXISTS idx_jh_created_at
    ON journal_header(created_at DESC);

-- =============================================================================
-- journal_line
-- =============================================================================
-- FK join from header (primary line fetch)
CREATE INDEX IF NOT EXISTS idx_jl_journal_id
    ON journal_line(journal_id);

-- FK join from file load (bulk line fetch after upload)
CREATE INDEX IF NOT EXISTS idx_jl_file_load_id
    ON journal_line(file_load_id);

-- Business unit / object account filter in line grid
CREATE INDEX IF NOT EXISTS idx_jl_business_unit
    ON journal_line(business_unit);

CREATE INDEX IF NOT EXISTS idx_jl_object_account
    ON journal_line(object_account);

-- =============================================================================
-- journal_assignment
-- =============================================================================
-- Work-queue: find all assignments for a user + role
CREATE INDEX IF NOT EXISTS idx_ja_user_role
    ON journal_assignment(assigned_user_id, role_code, assignment_status);

-- FK from journal_header
CREATE INDEX IF NOT EXISTS idx_ja_journal_id
    ON journal_assignment(journal_id);

-- Status filter (routing / transition checks)
CREATE INDEX IF NOT EXISTS idx_ja_assignment_status
    ON journal_assignment(assignment_status);

-- =============================================================================
-- journal_comment
-- =============================================================================
-- FK join from header (comment panel load)
CREATE INDEX IF NOT EXISTS idx_jcomment_journal_id
    ON journal_comment(journal_id);

-- Author lookup (audit queries)
CREATE INDEX IF NOT EXISTS idx_jcomment_created_by
    ON journal_comment(created_by);

-- =============================================================================
-- journal_comment_history
-- =============================================================================
-- The history dialog loads the whole trail for one journal, newest first.
CREATE INDEX IF NOT EXISTS idx_jchistory_journal_at
    ON journal_comment_history(journal_id, performed_at DESC);

-- Trail for a single comment
CREATE INDEX IF NOT EXISTS idx_jchistory_comment_id
    ON journal_comment_history(comment_id);

-- =============================================================================
-- journal_document
-- =============================================================================
-- FK join from header (document panel load)
CREATE INDEX IF NOT EXISTS idx_jdoc_journal_id
    ON journal_document(journal_id);

-- Uploader lookup
CREATE INDEX IF NOT EXISTS idx_jdoc_uploaded_by
    ON journal_document(uploaded_by);

-- =============================================================================
-- journal_hyperlink
-- =============================================================================
-- FK join from header
CREATE INDEX IF NOT EXISTS idx_jhlink_journal_id
    ON journal_hyperlink(journal_id);

-- =============================================================================
-- journal_certification
-- =============================================================================
-- FK join from header (Certification Details page)
CREATE INDEX IF NOT EXISTS idx_jcert_journal_id
    ON journal_certification(journal_id);

-- Actor lookup (who certified / rejected)
CREATE INDEX IF NOT EXISTS idx_jcert_performed_by
    ON journal_certification(performed_by);

-- Role + action filter (analytics: how many preparer certs vs approver certs)
CREATE INDEX IF NOT EXISTS idx_jcert_role_action
    ON journal_certification(role_code, action);

-- Date ordering (newest-first audit view)
CREATE INDEX IF NOT EXISTS idx_jcert_performed_at
    ON journal_certification(performed_at DESC);

-- =============================================================================
-- journal_audit_log
-- =============================================================================
-- FK from journal (full audit trail load)
CREATE INDEX IF NOT EXISTS idx_jal_journal_id
    ON journal_audit_log(journal_id);

-- FK from file load (file-level audit trail)
CREATE INDEX IF NOT EXISTS idx_jal_file_load_id
    ON journal_audit_log(file_load_id);

-- Action type filter (find all CLOSED events, etc.)
CREATE INDEX IF NOT EXISTS idx_jal_action_type
    ON journal_audit_log(action_type);

-- Actor lookup
CREATE INDEX IF NOT EXISTS idx_jal_performed_by
    ON journal_audit_log(performed_by);

-- Newest-first — audit log default ordering
CREATE INDEX IF NOT EXISTS idx_jal_created_at
    ON journal_audit_log(created_at DESC);

-- =============================================================================
-- certification_statement_config
-- =============================================================================
-- Active statement per role (single-row lookup on Journal Detail page load)
CREATE INDEX IF NOT EXISTS idx_csc_role_active
    ON certification_statement_config(role_code, is_active);

-- =============================================================================
-- notification_log
-- =============================================================================
-- Recipient notification feed
CREATE INDEX IF NOT EXISTS idx_nl_recipient_user_id
    ON notification_log(recipient_user_id, status);

-- Status sweep (background job marks PENDING → SENT)
CREATE INDEX IF NOT EXISTS idx_nl_status
    ON notification_log(status);

-- Journal FK (cancel/update notifications on status change)
CREATE INDEX IF NOT EXISTS idx_nl_journal_id
    ON notification_log(journal_id);

-- =============================================================================
-- ai_session_log
-- =============================================================================
-- User AI usage history
CREATE INDEX IF NOT EXISTS idx_ai_log_user_id
    ON ai_session_log(user_id);

-- Request type analytics (AI_FILTER vs AI_EXPORT volumes)
CREATE INDEX IF NOT EXISTS idx_ai_log_request_type
    ON ai_session_log(request_type);

-- Newest-first AI session history
CREATE INDEX IF NOT EXISTS idx_ai_log_created_at
    ON ai_session_log(created_at DESC);

-- =============================================================================
-- company_news
-- =============================================================================
-- Home page news card — active items sorted by date desc
CREATE INDEX IF NOT EXISTS idx_company_news_date
    ON company_news(news_date DESC, is_active);

CREATE INDEX IF NOT EXISTS idx_company_news_created_by
    ON company_news(created_by);

-- =============================================================================
-- user_module_permission
-- =============================================================================
-- User + role module grant check (authorization middleware)
CREATE INDEX IF NOT EXISTS idx_ump_user_role
    ON user_module_permission(user_id, role_code);

-- Module-level grant lookup (which users have JOURNAL_DOCUMENT access)
CREATE INDEX IF NOT EXISTS idx_ump_module_granted
    ON user_module_permission(module_code, is_granted);

-- =============================================================================
-- dependent_validation
-- =============================================================================
-- Validation rule lookup during journal upload parsing
CREATE INDEX IF NOT EXISTS idx_dv_field
    ON dependent_validation(field_name, field_value, is_deleted);

-- Dependent field lookup (reverse direction)
CREATE INDEX IF NOT EXISTS idx_dv_dependent_field
    ON dependent_validation(dependent_field_name, dependent_field_value, is_deleted);

-- =============================================================================
-- user_dashboard_config
-- =============================================================================
-- Fetch the active dashboard for a user (Home page load)
CREATE INDEX IF NOT EXISTS idx_udc_user_id
    ON user_dashboard_config(user_id, is_default);

-- =============================================================================
-- user_dashboard_cards  (AI v2)
-- =============================================================================
-- Fetch all cards for a user ordered by position
CREATE INDEX IF NOT EXISTS idx_udc_cards_user_pos
    ON user_dashboard_cards(user_id, position);

-- Fast lookup of visible cards only
CREATE INDEX IF NOT EXISTS idx_udc_cards_visible
    ON user_dashboard_cards(user_id, is_visible);

-- =============================================================================
-- MODULE: ACCOUNT RECONCILIATION (sections 10.1–10.12 in schema.sql)
-- =============================================================================

-- =============================================================================
-- account_file_load  (10.1)
-- =============================================================================
-- FK lookup: who uploaded the file (SYSTEM_ADMIN work queue)
CREATE INDEX IF NOT EXISTS idx_afl_uploaded_by
    ON account_file_load(uploaded_by);

-- Status filter: PENDING / PARSING / PARSE_SUCCESS etc.
CREATE INDEX IF NOT EXISTS idx_afl_status
    ON account_file_load(status);

-- Newest-first ordering (file history view)
CREATE INDEX IF NOT EXISTS idx_afl_uploaded_at
    ON account_file_load(uploaded_at DESC);

-- =============================================================================
-- account_reconciliation  (10.2)
-- =============================================================================
-- Period filter — primary work-queue query pattern
CREATE INDEX IF NOT EXISTS idx_ar_period
    ON account_reconciliation(period_label);

-- Status filter — admin grid, work-queue filtering
CREATE INDEX IF NOT EXISTS idx_ar_status
    ON account_reconciliation(status);

-- Combined period + status — most frequent work-queue WHERE clause
CREATE INDEX IF NOT EXISTS idx_ar_period_status
    ON account_reconciliation(period_label, status);

-- Company filter — admin filtering by company code
CREATE INDEX IF NOT EXISTS idx_ar_company
    ON account_reconciliation(company_code);

-- Region filter
CREATE INDEX IF NOT EXISTS idx_ar_region
    ON account_reconciliation(region);

-- Team FK lookup
CREATE INDEX IF NOT EXISTS idx_ar_team
    ON account_reconciliation(team_id);

-- Source file join (file-level drill-down)
CREATE INDEX IF NOT EXISTS idx_ar_source_file
    ON account_reconciliation(source_file_id);

-- Account number lookup (dedup check, search)
CREATE INDEX IF NOT EXISTS idx_ar_account_num
    ON account_reconciliation(account_number);

-- Entity lookup (entity-level drill-down)
CREATE INDEX IF NOT EXISTS idx_ar_entity
    ON account_reconciliation(entity_unique_id);

-- Preparer / approver FK lookups (queue routing)
CREATE INDEX IF NOT EXISTS idx_ar_preparer
    ON account_reconciliation(preparer_user_id, status);

CREATE INDEX IF NOT EXISTS idx_ar_approver
    ON account_reconciliation(approver_user_id, status);

-- Zero-balance / auto-cert filter
CREATE INDEX IF NOT EXISTS idx_ar_zero_balance
    ON account_reconciliation(is_zero_balance, status);

-- Soft-delete / active filter
CREATE INDEX IF NOT EXISTS idx_ar_active
    ON account_reconciliation(is_active);

-- Newest-first ordering (default grid sort)
CREATE INDEX IF NOT EXISTS idx_ar_created_at
    ON account_reconciliation(created_at DESC);

-- Fast SYSTEM_ADMIN unassigned queue
CREATE INDEX IF NOT EXISTS idx_ar_admin_queue
    ON account_reconciliation(status) WHERE status = 'NOT_ASSIGNED';

-- =============================================================================
-- account_recon_item  (10.3)
-- =============================================================================
-- FK join from reconciliation + active filter (item list load)
CREATE INDEX IF NOT EXISTS idx_ari_recon_id
    ON account_recon_item(reconciliation_id, is_active);

-- Author lookup (audit queries)
CREATE INDEX IF NOT EXISTS idx_ari_created_by
    ON account_recon_item(created_by);

-- =============================================================================
-- account_assignment  (10.4)
-- =============================================================================
-- Work-queue: find all assignments for a user + role
CREATE INDEX IF NOT EXISTS idx_aa_user_role
    ON account_assignment(assigned_user_id, role_code, assignment_status);

-- FK from account_reconciliation
CREATE INDEX IF NOT EXISTS idx_aa_recon_id
    ON account_assignment(reconciliation_id);

-- Status filter (routing / transition checks)
CREATE INDEX IF NOT EXISTS idx_aa_status
    ON account_assignment(assignment_status);

-- =============================================================================
-- account_comment  (10.5)
-- =============================================================================
-- FK join from reconciliation (comment panel load)
CREATE INDEX IF NOT EXISTS idx_ac_recon_id
    ON account_comment(reconciliation_id);

-- Author lookup (audit queries)
CREATE INDEX IF NOT EXISTS idx_ac_created_by
    ON account_comment(created_by);

-- =============================================================================
-- account_document  (10.6)
-- =============================================================================
-- FK join from reconciliation (document panel load)
CREATE INDEX IF NOT EXISTS idx_ad_recon_id
    ON account_document(reconciliation_id);

-- Uploader lookup
CREATE INDEX IF NOT EXISTS idx_ad_uploaded_by
    ON account_document(uploaded_by);

-- AI validation source flag (find the validation-source document quickly)
CREATE INDEX IF NOT EXISTS idx_ad_validation
    ON account_document(reconciliation_id, is_validation_source);

-- =============================================================================
-- account_hyperlink  (10.7)
-- =============================================================================
-- FK join from reconciliation
CREATE INDEX IF NOT EXISTS idx_ah_recon_id
    ON account_hyperlink(reconciliation_id);

-- =============================================================================
-- account_certification  (10.8)
-- =============================================================================
-- FK join from reconciliation (Certification Details page)
CREATE INDEX IF NOT EXISTS idx_acert_recon_id
    ON account_certification(reconciliation_id);

-- Actor lookup (who certified / rejected)
CREATE INDEX IF NOT EXISTS idx_acert_performed
    ON account_certification(performed_by);

-- Role + action filter (analytics)
CREATE INDEX IF NOT EXISTS idx_acert_role_action
    ON account_certification(role_code, action);

-- Date ordering (newest-first audit view)
CREATE INDEX IF NOT EXISTS idx_acert_at
    ON account_certification(performed_at DESC);

-- =============================================================================
-- account_audit_log  (10.9)
-- =============================================================================
-- FK from reconciliation (full audit trail load)
CREATE INDEX IF NOT EXISTS idx_aal_recon_id
    ON account_audit_log(reconciliation_id);

-- FK from file load (file-level audit trail)
CREATE INDEX IF NOT EXISTS idx_aal_file_load
    ON account_audit_log(file_load_id);

-- Action type filter (find all ZERO_BALANCE_SYSTEM_CERTIFIED events, etc.)
CREATE INDEX IF NOT EXISTS idx_aal_action_type
    ON account_audit_log(action_type);

-- Actor lookup
CREATE INDEX IF NOT EXISTS idx_aal_performed_by
    ON account_audit_log(performed_by);

-- Newest-first — audit log default ordering
CREATE INDEX IF NOT EXISTS idx_aal_created_at
    ON account_audit_log(created_at DESC);

-- =============================================================================
-- account_rule  (10.10)
-- =============================================================================
-- Rule type + active filter (evaluator lookup)
CREATE INDEX IF NOT EXISTS idx_arule_type
    ON account_rule(rule_type, is_active);

-- Active-only filter (rule engine startup)
CREATE INDEX IF NOT EXISTS idx_arule_active
    ON account_rule(is_active);

-- =============================================================================
-- account_rule_evaluation_log  (10.11)
-- =============================================================================
-- FK from account_rule (rule activity analytics)
CREATE INDEX IF NOT EXISTS idx_arel_rule_id
    ON account_rule_evaluation_log(rule_id);

-- Reconciliation reference (did this recon trigger a rule?)
CREATE INDEX IF NOT EXISTS idx_arel_record_ref
    ON account_rule_evaluation_log(record_ref);

-- Newest-first ordering
CREATE INDEX IF NOT EXISTS idx_arel_created_at
    ON account_rule_evaluation_log(created_at DESC);

-- =============================================================================
-- ai_validation_log  (10.12)
-- =============================================================================
-- Context lookup (JOURNAL or ACCOUNT, plus the context id)
CREATE INDEX IF NOT EXISTS idx_aiv_context
    ON ai_validation_log(context_type, context_id);

-- Who requested the validation
CREATE INDEX IF NOT EXISTS idx_aiv_requested_by
    ON ai_validation_log(requested_by);

-- Result status filter (PENDING sweep, ERROR analysis)
CREATE INDEX IF NOT EXISTS idx_aiv_result
    ON ai_validation_log(result_status);

-- Newest-first ordering
CREATE INDEX IF NOT EXISTS idx_aiv_created_at
    ON ai_validation_log(created_at DESC);

-- Source document lookup (tracing which upload triggered which validation)
CREATE INDEX IF NOT EXISTS idx_aiv_source_doc
    ON ai_validation_log(source_document_id);
