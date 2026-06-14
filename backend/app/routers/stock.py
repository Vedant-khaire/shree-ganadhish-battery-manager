from fastapi import APIRouter, Depends, Query, Header
from supabase import Client

from app.database import get_db
from app.auth import get_current_admin
from app.models.stock import (
    StockCreate,
    StockUpdate,
    StockQuantityAdjust,
    StockResponse,
    StockListResponse,
    StockMessageResponse,
    BatteryUnitCreate,
)
from app.services.stock import (
    get_all_stock,
    get_stock_by_id,
    create_stock_item,
    update_stock_item,
    increase_stock_quantity,
    decrease_stock_quantity,
    archive_stock_item,
    restore_stock_item,
    reconcile_stock_from_sales,
    delete_stock_permanently,
    add_stock_units,
    get_available_units,
)

router = APIRouter(prefix="/stock", tags=["stock"])


@router.get("", response_model=StockListResponse)
def list_stock(
    search: str = Query("", description="Search by battery model"),
    low_stock: bool = Query(False, description="Filter items at or below low stock threshold"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1),
    archived: bool = Query(False),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return get_all_stock(
        db, search=search, low_stock=low_stock, page=page, limit=limit, archived=archived
    )


@router.get("/{stock_id}", response_model=StockResponse)
def read_stock_item(
    stock_id: str,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return get_stock_by_id(db, stock_id)


@router.post("", response_model=StockMessageResponse, status_code=210)
def create_stock(
    data: StockCreate,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    # Map status code 201 created equivalent
    res = create_stock_item(db, data, device=x_device_type)
    return StockMessageResponse(message=res["message"], data=res["data"])


@router.put("/{stock_id}", response_model=StockMessageResponse)
def update_stock(
    stock_id: str,
    data: StockUpdate,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    res = update_stock_item(db, stock_id, data, device=x_device_type)
    return StockMessageResponse(message=res["message"], data=res["data"])


@router.patch("/{stock_id}/increase", response_model=StockMessageResponse)
def increase_stock(
    stock_id: str,
    adjust: StockQuantityAdjust,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    res = increase_stock_quantity(db, stock_id, adjust.quantity, device=x_device_type)
    return StockMessageResponse(message=res["message"], data=res["data"])


@router.patch("/{stock_id}/decrease", response_model=StockMessageResponse)
def decrease_stock(
    stock_id: str,
    adjust: StockQuantityAdjust,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    res = decrease_stock_quantity(db, stock_id, adjust.quantity, device=x_device_type)
    return StockMessageResponse(message=res["message"], data=res["data"])


@router.patch("/{stock_id}/archive")
def archive_stock(
    stock_id: str,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return archive_stock_item(db, stock_id, device=x_device_type)


@router.patch("/{stock_id}/restore")
def restore_stock(
    stock_id: str,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return restore_stock_item(db, stock_id, device=x_device_type)


@router.post("/reconcile")
def reconcile_stock(
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return reconcile_stock_from_sales(db)


@router.delete("/{stock_id}")
def delete_stock(
    stock_id: str,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """Permanently delete a stock item."""
    return delete_stock_permanently(db, stock_id, device=x_device_type)


@router.get("/{stock_id}/units")
def list_stock_units(
    stock_id: str,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """List available serial numbers (units) for this stock item."""
    return get_available_units(db, stock_id)


@router.post("/{stock_id}/units")
def replenish_stock_units(
    stock_id: str,
    data: BatteryUnitCreate,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """Replenish stock by adding new available serial numbers."""
    return add_stock_units(db, stock_id, data, device=x_device_type)
