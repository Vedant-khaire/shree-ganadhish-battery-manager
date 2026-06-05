from fastapi import APIRouter, Depends, Query, Request

from app.auth import get_current_admin, _detect_device
from app.database import get_db
from app.models.customer import (
    CustomerCreate,
    CustomerListResponse,
    CustomerMessageResponse,
    CustomerResponse,
    CustomerUpdate,
    CustomerCombinedCreate,
)
from app.services.customer import (
    archive_customer,
    create_customer,
    get_all_customers,
    get_customer_by_id,
    get_customer_with_details,
    restore_customer,
    update_customer,
    create_combined_customer,
    delete_customer_permanently,
)

router = APIRouter(prefix="/customers", tags=["customers"])


@router.get("", response_model=CustomerListResponse)
def list_customers(
    search: str = Query(default="", description="Search by name, mobile, or vehicle number"),
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
    archived: bool = Query(default=False, description="true = list archived customers"),
    filter_type: str = Query(default="ALL", description="ALL, SCRAP_PENDING, ACTIVE_WARRANTIES, PENDING_UDHARI"),
    _: str = Depends(get_current_admin),
):
    """List customers with optional search and pagination."""
    return get_all_customers(get_db(), search=search, page=page, limit=limit, archived=archived, filter_type=filter_type)


@router.get("/{customer_id}/details")
def get_customer_details(
    customer_id: str,
    _: str = Depends(get_current_admin),
):
    """Return customer + linked batteries + linked payments."""
    return get_customer_with_details(get_db(), customer_id)


@router.get("/{customer_id}", response_model=CustomerResponse)
def get_customer(
    customer_id: str,
    _: str = Depends(get_current_admin),
):
    """Return a single customer by ID."""
    return get_customer_by_id(get_db(), customer_id)


@router.post("", response_model=CustomerMessageResponse, status_code=201)
def add_customer(
    body: CustomerCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Add a new customer."""
    return create_customer(get_db(), body, device=_detect_device(request))


@router.put("/{customer_id}", response_model=CustomerMessageResponse)
def edit_customer(
    customer_id: str,
    body: CustomerUpdate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Update customer fields (partial update — only send changed fields)."""
    return update_customer(get_db(), customer_id, body, device=_detect_device(request))


@router.patch("/{customer_id}/archive")
def archive(
    customer_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Soft-delete a customer (is_archived = true)."""
    return archive_customer(get_db(), customer_id, device=_detect_device(request))


@router.patch("/{customer_id}/restore")
def restore(
    customer_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Restore an archived customer."""
    return restore_customer(get_db(), customer_id, device=_detect_device(request))


@router.post("/combined", status_code=201)
def add_combined_customer(
    body: CustomerCombinedCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Add customer + battery + udhari in a single transaction."""
    return create_combined_customer(get_db(), body, device=_detect_device(request))


@router.delete("/{customer_id}")
def delete_customer(
    customer_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Permanently delete a customer record and their related files/data."""
    return delete_customer_permanently(get_db(), customer_id, device=_detect_device(request))
