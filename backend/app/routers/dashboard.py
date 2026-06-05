from typing import Optional
from fastapi import APIRouter, Depends, Query
from app.auth import get_current_admin
from app.database import get_db
from app.services.dashboard import get_dashboard_stats

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/stats")
def dashboard_stats(
    period: str = Query(default="this_month", description="Today, this_week, this_month, this_year"),
    vehicle_type: Optional[str] = Query(default=None, description="Filter by vehicle/battery type"),
    purchase_type: Optional[str] = Query(default=None, description="Filter by customer account type"),
    db = Depends(get_db),
    _: str = Depends(get_current_admin)
):
    """
    Returns rich business analytics and trends for the dashboard.
    Supports period, vehicle type, and customer purchase type filtering.
    """
    return get_dashboard_stats(
        db,
        period=period,
        vehicle_type=vehicle_type,
        purchase_type=purchase_type,
    )
