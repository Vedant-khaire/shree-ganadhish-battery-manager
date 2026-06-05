from fastapi import APIRouter, Depends, Query, Request

from app.auth import get_current_admin, _detect_device
from app.database import get_db
from app.models.battery import (
    BatteryCreate, BatteryListResponse,
    BatteryMessageResponse, BatteryResponse, BatteryUpdate,
)
from app.services.battery import (
    archive_battery, create_battery,
    get_all_batteries, get_battery_by_id, update_battery,
    delete_battery_permanently,
)

router = APIRouter(prefix="/batteries", tags=["batteries"])


@router.get("", response_model=BatteryListResponse)
def list_batteries(
    search: str = Query(default="", description="Search by model number or serial number"),
    customer_id: str = Query(default="", description="Filter by customer UUID"),
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
    archived: bool = Query(default=False),
    _: str = Depends(get_current_admin),
):
    """List batteries. Optionally filter by customer or search by serial/model."""
    return get_all_batteries(get_db(), search=search, customer_id=customer_id,
                             page=page, limit=limit, archived=archived)


@router.get("/{battery_id}", response_model=BatteryResponse)
def get_battery(battery_id: str, _: str = Depends(get_current_admin)):
    """Get a single battery by ID."""
    return get_battery_by_id(get_db(), battery_id)


@router.post("", response_model=BatteryMessageResponse, status_code=201)
def add_battery(
    body: BatteryCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """
    Add a battery sale. warranty_expiry and warranty_reminder_date are
    auto-computed. Serial number is normalized (trim + uppercase).
    UI label: 'Add Guarantee Record'.
    """
    return create_battery(get_db(), body, device=_detect_device(request))


@router.put("/{battery_id}", response_model=BatteryMessageResponse)
def edit_battery(
    battery_id: str,
    body: BatteryUpdate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Update battery fields. Dates are recomputed if sale_date or warranty_months change."""
    return update_battery(get_db(), battery_id, body, device=_detect_device(request))


@router.patch("/{battery_id}/archive")
def archive(
    battery_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Soft-delete a battery record."""
    return archive_battery(get_db(), battery_id, device=_detect_device(request))


@router.delete("/{battery_id}")
def delete_battery(
    battery_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Permanently delete a battery record."""
    return delete_battery_permanently(get_db(), battery_id, device=_detect_device(request))
