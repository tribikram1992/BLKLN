"""
Settings and configuration for the Journal Certification Platform backend.

Loads all configuration at startup from environment variables.
Validates that required values are present before the application starts.
All other modules import from here. Nothing reads os.environ directly.
"""

from dotenv import load_dotenv
load_dotenv()

import os
from pathlib import Path
from dataclasses import dataclass
from functools import lru_cache

# ============================================================================
# Load .env file based on environment
# ============================================================================

env = os.environ.get("ENV", "development")
if env == "production":
    env_file = Path(__file__).parent.parent / ".env.prod"
else:
    env_file = Path(__file__).parent.parent / ".env.local"

load_dotenv(env_file)

# ============================================================================
# Environment Variable Helper Functions
# ============================================================================

def _require_env(name: str) -> str:
    """
    Reads a required environment variable. Raises clearly if missing.
    
    Args:
        name: Environment variable name
        
    Returns:
        Environment variable value
        
    Raises:
        EnvironmentError: If variable is not set
    """
    value = os.environ.get(name)
    if not value:
        raise EnvironmentError(
            f"Required environment variable '{name}' is not set.\n"
            f"Copy ENV_TEMPLATE.md to .env.local and fill in the required value.\n"
            f"See ENV_VARIABLES_MINIMAL.md for configuration details."
        )
    return value


def _optional_env(name: str, default: str = "") -> str:
    """
    Reads an optional environment variable with a default value.
    
    Args:
        name: Environment variable name
        default: Default value if not set
        
    Returns:
        Environment variable value or default
    """
    return os.environ.get(name, default)


def _parse_list_env(name: str, default: str = "") -> list[str]:
    """
    Parses a comma-separated environment variable into a list.
    
    Args:
        name: Environment variable name
        default: Default comma-separated string if not set
        
    Returns:
        List of values from environment or default
    """
    value = os.environ.get(name, default)
    if not value:
        return []
    
    return [item.strip() for item in value.split(",") if item.strip()]


# ============================================================================
# Configuration Dataclasses
# ============================================================================

@dataclass
class DatabaseSettings:
    """Database connection configuration."""
    url: str
    echo: bool
    pool_size: int
    max_overflow: int


@dataclass
class JWTSettings:
    """JWT authentication configuration."""
    secret_key: str
    algorithm: str
    expiration_hours: int
    refresh_expiration_days: int


@dataclass
class SessionSettings:
    """Session management configuration."""
    expiration_hours: int
    inactivity_timeout_minutes: int


@dataclass
class SecuritySettings:
    """Security and policy configuration."""
    password_min_length: int
    max_login_attempts: int
    lockout_duration_minutes: int


@dataclass
class FileUploadSettings:
    """File upload configuration."""
    max_file_size_mb: int


@dataclass
class PaginationSettings:
    """Pagination defaults."""
    default_page_size: int
    max_page_size: int


@dataclass
class ServerSettings:
    """Backend server configuration."""
    host: str
    port: int


@dataclass
class FrontendSettings:
    """Frontend application configuration."""
    host: str
    port: int


@dataclass
class APISettings:
    """API and environment configuration."""
    node_env: str
    api_base_url: str


@dataclass
class CORSSettings:
    """CORS configuration."""
    origins: list[str]


@dataclass
class LoggingSettings:
    """Logging configuration."""
    level: str
    format: str


@dataclass
class FeatureFlags:
    """Feature flags."""
    enable_audit_logging: bool
    enable_notifications: bool
    enable_email_notifications: bool


@dataclass
class Settings:
    """Complete application settings."""
    app_name: str
    app_version: str
    env: str
    debug: bool
    database: DatabaseSettings
    jwt: JWTSettings
    session: SessionSettings
    security: SecuritySettings
    file_upload: FileUploadSettings
    pagination: PaginationSettings
    server: ServerSettings
    frontend: FrontendSettings
    api: APISettings
    cors: CORSSettings
    logging: LoggingSettings
    features: FeatureFlags


# ============================================================================
# Settings Factory
# ============================================================================

def load_settings() -> Settings:
    """
    Load and validate all configuration.
    
    Raises:
        EnvironmentError: If any required environment variable is missing
        
    Returns:
        Settings: Fully validated settings object
    """
    
    database = DatabaseSettings(
        url=_require_env("DATABASE_URL"),
        echo=_optional_env("DATABASE_ECHO", "False") == "True",
        pool_size=int(_optional_env("DATABASE_POOL_SIZE", "20")),
        max_overflow=int(_optional_env("DATABASE_MAX_OVERFLOW", "40")),
    )
    
    jwt = JWTSettings(
        secret_key=_require_env("JWT_SECRET_KEY"),
        algorithm=_optional_env("JWT_ALGORITHM", "HS256"),
        expiration_hours=int(_optional_env("JWT_EXPIRATION_HOURS", "24")),
        refresh_expiration_days=int(_optional_env("JWT_REFRESH_EXPIRATION_DAYS", "7")),
    )
    
    session = SessionSettings(
        expiration_hours=int(_optional_env("SESSION_EXPIRATION_HOURS", "24")),
        inactivity_timeout_minutes=int(_optional_env("SESSION_INACTIVITY_TIMEOUT_MINUTES", "30")),
    )
    
    security = SecuritySettings(
        password_min_length=int(_optional_env("PASSWORD_MIN_LENGTH", "8")),
        max_login_attempts=int(_optional_env("MAX_LOGIN_ATTEMPTS", "5")),
        lockout_duration_minutes=int(_optional_env("LOCKOUT_DURATION_MINUTES", "15")),
    )
    
    file_upload = FileUploadSettings(
        max_file_size_mb=int(_optional_env("MAX_UPLOAD_FILE_SIZE_MB", "100")),
    )
    
    pagination = PaginationSettings(
        default_page_size=int(_optional_env("DEFAULT_PAGE_SIZE", "50")),
        max_page_size=int(_optional_env("MAX_PAGE_SIZE", "1000")),
    )
    
    server = ServerSettings(
        host=_require_env("BACKEND_HOST"),
        port=int(_require_env("BACKEND_PORT")),
    )
    
    frontend = FrontendSettings(
        host=_require_env("FRONTEND_HOST"),
        port=int(_require_env("FRONTEND_PORT")),
    )
    
    api = APISettings(
        node_env=_require_env("NODE_ENV"),
        api_base_url=_require_env("NEXT_PUBLIC_API_BASE_URL"),
    )
    
    cors = CORSSettings(
        origins=_parse_list_env("CORS_ORIGINS"),
    )
    
    logging_settings = LoggingSettings(
        level=_optional_env("LOG_LEVEL", "INFO"),
        format=_optional_env("LOG_FORMAT", "json"),
    )
    
    features = FeatureFlags(
        enable_audit_logging=_optional_env("ENABLE_AUDIT_LOGGING", "True") == "True",
        enable_notifications=_optional_env("ENABLE_NOTIFICATIONS", "True") == "True",
        enable_email_notifications=_optional_env("ENABLE_EMAIL_NOTIFICATIONS", "False") == "True",
    )
    
    return Settings(
        app_name="Journal Certification Platform",
        app_version="1.0.0",
        env=_optional_env("ENV", "development"),
        debug=_optional_env("DEBUG", "True") == "True",
        database=database,
        jwt=jwt,
        session=session,
        security=security,
        file_upload=file_upload,
        pagination=pagination,
        server=server,
        frontend=frontend,
        api=api,
        cors=cors,
        logging=logging_settings,
        features=features,
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """
    Get application settings (cached singleton).
    
    Returns:
        Settings: Cached settings object
    """
    return load_settings()
