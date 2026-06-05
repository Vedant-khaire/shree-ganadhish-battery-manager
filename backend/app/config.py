from pathlib import Path
from dotenv import load_dotenv
from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = BASE_DIR / ".env"

# Explicit dotenv load
load_dotenv(dotenv_path=ENV_PATH)

if not ENV_PATH.exists():
    raise ValueError(
        ".env file missing. Create backend/.env before starting server."
    )


class Settings(BaseSettings):
    admin_username: str
    admin_password_hash: str

    jwt_secret_key: str
    jwt_expire_hours: int = 24

    supabase_url: str
    supabase_service_key: str

    smtp_email: str = ""
    smtp_password: str = ""
    backup_receiver_email: str = ""

    enable_docs: bool = True

    cors_origins: str = "http://localhost:3000"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


settings = Settings()
