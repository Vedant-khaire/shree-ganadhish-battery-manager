from supabase import create_client, Client
from app.config import settings

# Single Supabase client instance reused across all requests.
# Uses the service role key — full DB access, bypasses RLS.
# Security is enforced at the FastAPI layer (JWT auth dependency).
_client: Client | None = None


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
