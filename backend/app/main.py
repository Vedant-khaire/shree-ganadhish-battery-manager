from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer

from app.config import settings
from app.auth import router as auth_router
from app.routers.customers import router as customers_router
from app.routers.batteries import router as batteries_router
from app.routers.payments import router as payments_router
from app.routers.dashboard import router as dashboard_router
from app.routers.exports import router as exports_router
from app.routers.stock import router as stock_router
from app.routers.reminders import router as reminders_router
from app.routers.message_templates import router as message_templates_router
from app.routers.shops import router as shops_router

# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Shree Ganadhish Battery Manager API",
    description=(
        "Backend API for Shree Ganadhish Auto Ele & Battery Services. "
        "Handles customer management, battery sales, guarantee tracking, "
        "and udhari management."
    ),
    version="1.0.0",
    docs_url="/docs" if settings.enable_docs else None,
    redoc_url="/redoc" if settings.enable_docs else None,
    openapi_url="/openapi.json" if settings.enable_docs else None,
)

# ---------------------------------------------------------------------------
# CORS Configuration
# ---------------------------------------------------------------------------
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
allow_origins = ["*"] if "*" in origins else origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Routers — all prefixed under /api/v1
# ---------------------------------------------------------------------------
app.include_router(auth_router,      prefix="/api/v1")
app.include_router(customers_router, prefix="/api/v1")
app.include_router(batteries_router, prefix="/api/v1")
app.include_router(payments_router,  prefix="/api/v1")
app.include_router(dashboard_router, prefix="/api/v1")
app.include_router(exports_router,   prefix="/api/v1")
app.include_router(stock_router,     prefix="/api/v1")
app.include_router(reminders_router, prefix="/api/v1")
app.include_router(message_templates_router, prefix="/api/v1")
app.include_router(shops_router,     prefix="/api/v1")


# ---------------------------------------------------------------------------
# Health check — both paths active for development flexibility
# ---------------------------------------------------------------------------
def _health_payload() -> dict:
    return {
        "status": "ok",
        "service": "Shree Ganadhish Battery Manager API",
        "version": "1.0.0",
    }


@app.get("/api/health", tags=["health"])
def health():
    """Short-form health check."""
    return _health_payload()


@app.get("/api/v1/health", tags=["health"])
def health_v1():
    """Versioned health check."""
    return _health_payload()


@app.on_event("startup")
def startup_event():
    try:
        from app.database import get_db
        from app.services.consolidation import merge_duplicate_customers_in_db
        db = get_db()
        merge_duplicate_customers_in_db(db)
    except Exception as e:
        import logging
        logger = logging.getLogger("uvicorn.error")
        logger.error(f"Startup consolidation failed: {e}")


if __name__ == "__main__":
    import uvicorn
    import os
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("app.main:app", host="0.0.0.0", port=port, reload=False)
