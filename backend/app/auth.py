from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel

from app.config import settings
from app.database import get_db

router = APIRouter(prefix="/auth", tags=["auth"])

# ---------------------------------------------------------------------------
# OAuth2 scheme — enables the Authorize 🔒 button in Swagger UI
# tokenUrl must match the actual login endpoint path
# ---------------------------------------------------------------------------
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------
class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _detect_device(request: Request) -> str:
    """Return 'mobile' or 'desktop' based on the User-Agent header."""
    ua = (request.headers.get("user-agent") or "").lower()
    if any(kw in ua for kw in ("mobile", "android", "iphone", "ipad")):
        return "mobile"
    return "desktop"


def _create_token(data: dict) -> str:
    """Create a signed JWT. Expiry is read from config — never hardcoded."""
    expire = datetime.now(timezone.utc) + timedelta(hours=settings.jwt_expire_hours)
    return jwt.encode(
        {**data, "exp": expire},
        settings.jwt_secret_key,
        algorithm="HS256",
    )


def _log_action(action: str, device: str) -> None:
    """Fire-and-forget activity log — never raises."""
    try:
        get_db().table("activity_logs").insert(
            {"action": action, "device": device}
        ).execute()
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Auth dependency — used by every protected route
# ---------------------------------------------------------------------------

def get_current_admin(token: str = Depends(oauth2_scheme)) -> str:
    """
    Verify JWT and return 'admin'.
    Using OAuth2PasswordBearer so Swagger Authorize button works out of the box.
    Raises 401 on any failure.
    """
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=["HS256"])
        sub: str | None = payload.get("sub")
        if sub != "admin":
            raise JWTError("Invalid subject")
        return sub
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/login", response_model=LoginResponse)
def login(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(),
):
    """
    Login with username + password.
    Uses OAuth2PasswordRequestForm so Swagger's Authorize dialog works directly.
    Returns a JWT valid for JWT_EXPIRE_HOURS hours (configured in .env).
    """
    # 1. Check username
    if form_data.username != settings.admin_username:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    # 2. Verify password using bcrypt.checkpw — constant-time comparison
    password_valid = bcrypt.checkpw(
        form_data.password.encode("utf-8"),
        settings.admin_password_hash.encode("utf-8"),
    )
    if not password_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    # 3. Issue token
    token = _create_token({"sub": "admin"})

    # 4. Log login event (non-blocking, never fails the request)
    _log_action("LOGIN", _detect_device(request))

    return LoginResponse(access_token=token)


@router.post("/logout")
def logout(request: Request, _: str = Depends(get_current_admin)):
    """
    Client must discard the token locally.
    Logs the logout event for audit trail.
    """
    _log_action("LOGOUT", _detect_device(request))
    return {"message": "Logged out successfully"}
