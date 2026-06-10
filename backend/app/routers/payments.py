from fastapi import APIRouter, Depends, Query, Request

from app.auth import get_current_admin, _detect_device
from app.database import get_db
from app.models.payment import (
    PaymentCreate, PaymentListResponse,
    PaymentMessageResponse, PaymentResponse, PaymentUpdate,
    PaymentTransactionResponse,
)
from app.services.payment import (
    archive_payment, create_payment,
    get_all_payments, get_payment_by_id,
    settle_payment, update_payment,
    delete_payment_permanently,
    get_payment_transactions,
)

router = APIRouter(prefix="/payments", tags=["payments"])


@router.get("", response_model=PaymentListResponse)
def list_payments(
    customer_id: str = Query(default="", description="Filter by customer UUID"),
    is_settled: bool | None = Query(default=None, description="true=settled, false=pending, omit=all"),
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
    archived: bool = Query(default=False),
    search: str = Query(default="", description="Search by customer name or mobile number"),
    _: str = Depends(get_current_admin),
):
    """List payments. UI label: 'Udhari'. Filter by pending/settled status and search term."""
    return get_all_payments(get_db(), customer_id=customer_id,
                            is_settled=is_settled, page=page,
                            limit=limit, archived=archived, search=search)


@router.get("/{payment_id}", response_model=PaymentResponse)
def get_payment(payment_id: str, _: str = Depends(get_current_admin)):
    """Get a single payment record."""
    return get_payment_by_id(get_db(), payment_id)


@router.post("", response_model=PaymentMessageResponse, status_code=201)
def add_payment(
    body: PaymentCreate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """
    Add a payment/udhari record.
    pending_amount is auto-computed as total_amount - paid_amount.
    If paid >= total, is_settled is set to true automatically.
    """
    return create_payment(get_db(), body, device=_detect_device(request))


@router.put("/{payment_id}", response_model=PaymentMessageResponse)
def edit_payment(
    payment_id: str,
    body: PaymentUpdate,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Update a payment. pending_amount is recomputed automatically."""
    return update_payment(get_db(), payment_id, body, device=_detect_device(request))


@router.patch("/{payment_id}/settle")
def settle(
    payment_id: str,
    request: Request,
    payment_mode: str = Query(default="Cash", description="Payment mode: CASH or ONLINE"),
    _: str = Depends(get_current_admin),
):
    """Mark udhari as fully paid. Sets paid_amount = total_amount, pending = 0."""
    return settle_payment(get_db(), payment_id, payment_mode=payment_mode, device=_detect_device(request))


@router.patch("/{payment_id}/archive")
def archive(
    payment_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Soft-delete a payment record."""
    return archive_payment(get_db(), payment_id, device=_detect_device(request))


@router.delete("/{payment_id}")
def delete_payment(
    payment_id: str,
    request: Request,
    _: str = Depends(get_current_admin),
):
    """Permanently delete a payment record."""
    return delete_payment_permanently(get_db(), payment_id, device=_detect_device(request))


@router.get("/{payment_id}/transactions", response_model=list[PaymentTransactionResponse])
def list_payment_transactions(
    payment_id: str,
    _: str = Depends(get_current_admin),
):
    """Get the transaction history log of additions and payments for a specific Udhari/Payment."""
    return get_payment_transactions(get_db(), payment_id)

