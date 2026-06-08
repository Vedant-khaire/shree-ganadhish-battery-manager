from fastapi import APIRouter, Depends, Query, Request

from app.auth import get_current_admin, _detect_device
from app.database import get_db
from app.models.shop import (
    ShopCreate, ShopUpdate, ShopResponse,
    ShopPurchaseCreate, ShopPurchaseResponse,
    ShopDetailsResponse, ShopOpeningBalanceCreate
)
from app.services.shop import (
    create_shop, get_all_shops, get_shop_by_id,
    get_shop_details, update_shop, archive_shop,
    create_shop_purchase, settle_shop_payment,
    delete_shop_permanently, delete_shop_purchase,
    add_shop_opening_balance
)

router = APIRouter(prefix="/shops", tags=["shops"])


@router.get("")
def list_shops(
    search: str = Query(default="", description="Search by shop name, owner name, or mobile"),
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
    filter_type: str = Query(default="ALL", description="ALL, ARCHIVED, PENDING_UDHARI, NO_PENDING_UDHARI"),
    _: str = Depends(get_current_admin),
):
    """List shops with pagination, search, and filters."""
    return get_all_shops(get_db(), search=search, page=page, limit=limit, filter_type=filter_type)


@router.get("/{shop_id}/details", response_model=ShopDetailsResponse)
def get_shop_details_endpoint(
    shop_id: str,
    _: str = Depends(get_current_admin),
):
    """Get shop details, purchases list, active payments, and transactions log."""
    return get_shop_details(get_db(), shop_id)


@router.get("/{shop_id}", response_model=ShopResponse)
def get_shop(
    shop_id: str,
    _: str = Depends(get_current_admin),
):
    """Get single shop profile details."""
    return get_shop_by_id(get_db(), shop_id)


@router.post("", status_code=201)
def add_shop(
    body: ShopCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Add a new shop profile."""
    return create_shop(get_db(), body, device=_detect_device(request))


@router.put("/{shop_id}")
def edit_shop(
    shop_id: str,
    body: ShopUpdate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Update shop profile details."""
    return update_shop(get_db(), shop_id, body, device=_detect_device(request))


@router.patch("/{shop_id}/archive")
def archive(
    shop_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Soft-delete/archive a shop profile."""
    return archive_shop(get_db(), shop_id, archive=True, device=_detect_device(request))


@router.patch("/{shop_id}/restore")
def restore(
    shop_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Restore an archived shop profile."""
    return archive_shop(get_db(), shop_id, archive=False, device=_detect_device(request))


@router.post("/{shop_id}/purchases", status_code=201)
def add_purchase(
    shop_id: str,
    body: ShopPurchaseCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Record a battery purchase for a shop."""
    return create_shop_purchase(get_db(), shop_id, body, device=_detect_device(request))


@router.post("/{shop_id}/settle")
def settle_payment(
    shop_id: str,
    request: Request,
    amount: float = Query(..., ge=0.01),
    notes: str = Query(default=None),
    _: str = Depends(get_current_admin),
):
    """Record a payment settlement towards outstanding Udhari."""
    return settle_shop_payment(get_db(), shop_id, amount, notes, device=_detect_device(request))


@router.delete("/{shop_id}")
def delete_shop(
    shop_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Hard-delete shop profile (blocks if pending Udhari exists)."""
    return delete_shop_permanently(get_db(), shop_id, device=_detect_device(request))


@router.delete("/{shop_id}/purchases/{purchase_id}")
def delete_purchase(
    shop_id: str,
    purchase_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Delete a battery purchase entry and restore stock."""
    return delete_shop_purchase(get_db(), shop_id, purchase_id, device=_detect_device(request))


@router.post("/{shop_id}/opening-balance", status_code=201)
def add_opening_balance(
    shop_id: str,
    body: ShopOpeningBalanceCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Add a previous outstanding balance or ledger adjustment."""
    return add_shop_opening_balance(get_db(), shop_id, body, device=_detect_device(request))

