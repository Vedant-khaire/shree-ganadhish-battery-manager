from supabase import create_client, Client
from app.config import settings
import httpx
import httpcore
import time
import logging
import inspect

logger = logging.getLogger("app.database")

# Single Supabase client instance reused across all requests.
# Uses the service role key — full DB access, bypasses RLS.
# Security is enforced at the FastAPI layer (JWT auth dependency).
_client: Client | None = None


class DatabaseUnavailableException(Exception):
    """Exception raised when database connection drops and retries fail."""
    def __init__(self, message: str, original_exception: Exception | None = None):
        self.message = message
        self.original_exception = original_exception
        super().__init__(message)


def get_db() -> Client:
    """
    Returns the shared Supabase client, creating it on first call.
    Raises a clear ValueError immediately if credentials are missing.
    """
    global _client

    # Startup validation — fail loudly with a clear message
    if not settings.supabase_url:
        raise ValueError(
            "SUPABASE_URL is not set. "
            "Add it to your .env file and restart the server."
        )
    if not settings.supabase_service_key:
        raise ValueError(
            "SUPABASE_SERVICE_KEY is not set. "
            "Add it to your .env file and restart the server."
        )

    if _client is None:
        _client = create_client(settings.supabase_url, settings.supabase_service_key)

    return _client


def safe_execute(query, table_name: str = "unknown", endpoint_name: str = "unknown"):
    """
    Wrapper for executing Supabase queries with auto-retry and backoff.
    Catches connection drops and timeouts, raising DatabaseUnavailableException on final failure.
    """
    if endpoint_name == "unknown":
        try:
            # Inspect stack to find caller function name (1 level up)
            frame = inspect.currentframe()
            if frame and frame.f_back:
                endpoint_name = frame.f_back.f_code.co_name
        except Exception:
            pass

    if table_name == "unknown" and hasattr(query, "path"):
        try:
            path_str = getattr(query, "path", "")
            if path_str:
                table_name = path_str.strip("/")
        except Exception:
            pass

    max_retries = 5
    delays = [1, 2, 4, 8, 16]

    for attempt in range(max_retries + 1):
        try:
            return query.execute()
        except (
            httpx.RemoteProtocolError,
            httpx.ReadTimeout,
            httpx.ConnectTimeout,
            httpx.ReadError,
            httpx.ConnectError,
            httpcore.RemoteProtocolError,
            httpcore.ReadTimeout,
            httpcore.ConnectTimeout,
            httpcore.ReadError,
            httpcore.ConnectError,
        ) as exc:
            exc_type = type(exc).__name__
            retry_count = attempt + 1
            if attempt < max_retries:
                delay = delays[attempt]
                logger.warning(
                    f"Supabase connection lost. Retrying attempt {retry_count}/{max_retries} "
                    f"in {delay}s. Endpoint: {endpoint_name}, Table: {table_name}, "
                    f"Exception: {exc_type}"
                )
                time.sleep(delay)
            else:
                logger.error(
                    f"Supabase connection failed after {max_retries} retries. "
                    f"Endpoint: {endpoint_name}, Table: {table_name}, "
                    f"Exception: {exc_type}"
                )
                raise DatabaseUnavailableException(
                    "Database connection temporarily unavailable. Please retry.",
                    original_exception=exc
                )
