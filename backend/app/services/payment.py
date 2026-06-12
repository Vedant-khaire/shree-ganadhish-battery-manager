from fastapi import HTTPException, status
from supabase import Client
from typing import Optional

from app.models.payment import PaymentCreate, PaymentUpdate, PaymentResponse


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str) -> None:
    try:
        db.table("activity_logs").insert({"action": action, "device": device}).execute()
    except Exception:
        pass


def _require_payment(db: Client, payment_id: str) -> dict:
    result = (
        db.table("payments")
        .select("*, customers(name, mobile)")
        .eq("id", payment_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Payment {payment_id} not found",
        )
    return result.data


def _calc_pending(total: float, paid: float) -> float:
    """Compute and clamp pending amount — never goes below 0."""
    return round(max(total - paid, 0.0), 2)


# ---------------------------------------------------------------------------
# Read operations
# ---------------------------------------------------------------------------

def get_all_payments(
    db: Client,
    customer_id: str = "",
    is_settled: bool | None = None,
    page: int = 1,
    limit: int = 20,
    archived: bool = False,
    search: str = "",
) -> dict:
    """List payments. Filter by customer, search term, and/or settled status."""
    if search:
        term = search.strip().replace(",", "").replace("%", "")
        # Filter payments by joined customer name/mobile using inner join filtering
        query = (
            db.table("payments")
            .select("*, customers!inner(name, mobile)", count="exact")
            .eq("is_archived", archived)
        )
        query = query.or_(f"customers.name.ilike.%{term}%,customers.mobile.ilike.%{term}%")
    else:
        query = (
            db.table("payments")
            .select("*, customers(name, mobile)", count="exact")
            .eq("is_archived", archived)
        )

    if customer_id:
        query = query.eq("customer_id", customer_id)

    if is_settled is not None:
        query = query.eq("is_settled", is_settled)

    offset = (page - 1) * limit
    result = (
        query
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )

    return {
        "data": [PaymentResponse.from_row(r) for r in (result.data or [])],
        "total": result.count or 0,
        "page": page,
        "limit": limit,
    }


def get_payment_by_id(db: Client, payment_id: str) -> PaymentResponse:
    return PaymentResponse.from_row(_require_payment(db, payment_id))


# ---------------------------------------------------------------------------
# Write operations
# ---------------------------------------------------------------------------

def _log_transaction(db: Client, payment_id: str, customer_id: str, t_type: str, amount: float, notes: str = None, payment_mode: str = None) -> None:
    try:
        payload = {
            "payment_id": payment_id,
            "customer_id": customer_id,
            "transaction_type": t_type,
            "amount": amount,
            "notes": notes
        }
        if payment_mode:
            payload["payment_mode"] = payment_mode
        db.table("payment_transactions").insert(payload).execute()
    except Exception:
        pass


def create_payment(
    db: Client, data: PaymentCreate, device: str = "desktop"
) -> dict:
    """
    Insert or consolidate payment. Auto-computes pending_amount = total - paid.
    Marks as settled immediately if paid_amount >= total_amount.
    """
    # Check for active unpaid payment for this customer to consolidate
    existing_unpaid = (
        db.table("payments")
        .select("*")
        .eq("customer_id", data.customer_id)
        .eq("is_settled", False)
        .eq("is_archived", False)
        .execute()
    )

    if existing_unpaid.data:
        existing = existing_unpaid.data[0]
        payment_id = existing["id"]
        
        new_total = float(existing["total_amount"]) + data.total_amount
        new_paid = float(existing.get("paid_amount", 0.0)) + data.paid_amount
        new_pending = _calc_pending(new_total, new_paid)
        is_settled = new_pending == 0.0

        updates = {
            "total_amount": new_total,
            "paid_amount": new_paid,
            "pending_amount": new_pending,
            "is_settled": is_settled,
        }
        if data.payment_mode:
            updates["payment_mode"] = data.payment_mode
        if data.battery_id and not existing.get("battery_id"):
            updates["battery_id"] = data.battery_id
        if data.reminder_note:
            updates["reminder_note"] = data.reminder_note

        result = db.table("payments").update(updates).eq("id", payment_id).execute()
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to update consolidated payment record")
        
        created = PaymentResponse.from_row(result.data[0])
        _log(db, f"PAYMENT_CONSOLIDATED: Added ₹{data.total_amount} for customer {data.customer_id}", device)

        # Log transactions
        _log_transaction(db, payment_id, data.customer_id, "ADDITION", data.total_amount, "Consolidated bill addition")
        if data.paid_amount > 0:
            _log_transaction(db, payment_id, data.customer_id, "PAYMENT", data.paid_amount, "Consolidated payment amount", payment_mode=data.payment_mode)

        # Sync/Schedule reminders
        try:
            from app.services.reminder import schedule_udhari_reminders
            if is_settled:
                db.table("service_reminders").update({
                    "is_completed": True,
                    "notes": "Auto-completed: Consolidated payment settled"
                }).eq("linked_payment_id", payment_id).eq("is_completed", False).execute()
            else:
                schedule_udhari_reminders(db, payment_id)
        except Exception:
            pass
            
        return {"message": "Payment consolidated successfully", "data": created}

    else:
        pending = _calc_pending(data.total_amount, data.paid_amount)
        is_settled = pending == 0.0

        payload = {
            **data.model_dump(),
            "pending_amount": pending,
            "is_settled": is_settled,
        }

        result = db.table("payments").insert(payload).execute()
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create payment record")

        created = PaymentResponse.from_row(result.data[0])
        payment_id = created.id
        
        _log(db, f"PAYMENT_ADDED: ₹{data.total_amount} for customer {data.customer_id}", device)

        # Log transactions
        _log_transaction(db, payment_id, data.customer_id, "ADDITION", data.total_amount, "Initial bill addition")
        if data.paid_amount > 0:
            _log_transaction(db, payment_id, data.customer_id, "PAYMENT", data.paid_amount, "Initial payment amount", payment_mode=data.payment_mode)

        # Schedule Udhari reminders
        if pending > 0:
            try:
                from app.services.reminder import schedule_udhari_reminders
                schedule_udhari_reminders(db, str(payment_id))
            except Exception:
                pass

        return {"message": "Payment added successfully", "data": created}


def update_payment(
    db: Client, payment_id: str, data: PaymentUpdate, device: str = "desktop"
) -> dict:
    """Update payment fields. Recomputes pending_amount automatically and logs transactions."""
    existing = _require_payment(db, payment_id)
    updates = {k: v for k, v in data.model_dump().items() if v is not None}

    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    # Recompute pending_amount with latest values
    total = updates.get("total_amount") or float(existing["total_amount"])
    paid = updates.get("paid_amount") or float(existing.get("paid_amount", 0))
    pending = _calc_pending(total, paid)
    updates["pending_amount"] = pending
    updates["is_settled"] = (pending == 0.0)

    # Log diff transactions
    diff_total = total - float(existing["total_amount"])
    if diff_total != 0:
        t_type = "ADDITION" if diff_total > 0 else "ADJUSTMENT"
        _log_transaction(db, payment_id, str(existing["customer_id"]), t_type, abs(diff_total), "Bill total adjustment")

    diff_paid = paid - float(existing.get("paid_amount", 0.0))
    if diff_paid != 0:
        t_type = "PAYMENT" if diff_paid > 0 else "ADJUSTMENT"
        _log_transaction(db, payment_id, str(existing["customer_id"]), t_type, abs(diff_paid), "Payment adjustment", payment_mode=data.payment_mode)

    result = db.table("payments").update(updates).eq("id", payment_id).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update payment")

    updated = PaymentResponse.from_row(result.data[0])
    _log(db, f"PAYMENT_UPDATED: {payment_id}", device)

    # Sync Udhari reminders
    try:
        from app.services.reminder import schedule_udhari_reminders
        if updated.is_settled:
            db.table("service_reminders").update({
                "is_completed": True,
                "notes": "Auto-completed: Payment updated to settled"
            }).eq("linked_payment_id", payment_id).eq("is_completed", False).execute()
        else:
            # Update pending amount in existing uncompleted reminders templates
            uncompleted_res = db.table("service_reminders").select("id").eq("linked_payment_id", payment_id).eq("is_completed", False).execute()
            if uncompleted_res.data:
                c_name = existing["customers"]["name"]
                pending_amount = float(updated.pending_amount)
                template_text = (
                    f"Namaste {c_name},\n"
                    f"Aapke battery account me ₹{pending_amount} baki hai.\n"
                    f"Kripaya payment clear kare.\n\n"
                    f"* Shree Ganadhish Battery"
                )
                for r in uncompleted_res.data:
                    db.table("service_reminders").update({
                        "whatsapp_template": template_text
                    }).eq("id", r["id"]).execute()
            # Top up reminders to 4
            schedule_udhari_reminders(db, payment_id)
    except Exception:
        pass

    return {"message": "Payment updated successfully", "data": updated}


def settle_payment(db: Client, payment_id: str, payment_mode: str, amount: Optional[float] = None, device: str = "desktop") -> dict:
    """Mark payment as settled (partially or fully) and log transaction."""
    existing = _require_payment(db, payment_id)

    if existing.get("is_settled"):
        raise HTTPException(status_code=400, detail="Payment is already settled")

    total = float(existing["total_amount"])
    pending = float(existing["pending_amount"])
    current_paid = float(existing["paid_amount"])

    # If amount is not specified, default to full pending amount
    if amount is None:
        pay_amount = pending
        is_full_settlement = True
    else:
        pay_amount = float(amount)
        if pay_amount <= 0:
            raise HTTPException(status_code=400, detail="Payment amount must be greater than zero")
        if pay_amount > pending + 0.01:
            raise HTTPException(status_code=400, detail="Payment amount exceeds pending amount")
        is_full_settlement = abs(pay_amount - pending) < 0.01

    new_paid = current_paid + pay_amount
    new_pending = max(0.0, total - new_paid)
    is_settled = is_full_settlement or (new_pending <= 0.01)

    if is_settled:
        new_pending = 0.0
        new_paid = total

    db.table("payments").update({
        "paid_amount": new_paid,
        "pending_amount": new_pending,
        "is_settled": is_settled,
        "payment_mode": payment_mode,
    }).eq("id", payment_id).execute()

    # Log payment transaction
    notes = "Full settlement payment" if is_settled else f"Partial payment towards outstanding Udhari balance"
    _log_transaction(db, payment_id, str(existing["customer_id"]), "PAYMENT", pay_amount, notes, payment_mode=payment_mode)

    # Settle all related reminders ONLY if fully settled
    if is_settled:
        try:
            db.table("service_reminders").update({
                "is_completed": True,
                "notes": "Auto-completed: Payment settled"
            }).eq("linked_payment_id", payment_id).eq("is_completed", False).execute()
        except Exception:
            pass

    action_msg = "PAYMENT_SETTLED" if is_settled else f"PAYMENT_PARTIAL_PAID: {pay_amount}"
    _log(db, f"{action_msg}: {payment_id}", device)
    return {"message": "Payment recorded successfully"}


def archive_payment(db: Client, payment_id: str, device: str = "desktop") -> dict:
    _require_payment(db, payment_id)
    db.table("payments").update({"is_archived": True}).eq("id", payment_id).execute()
    _log(db, f"PAYMENT_ARCHIVED: {payment_id}", device)
    return {"message": "Payment archived successfully"}


def delete_payment_permanently(db: Client, payment_id: str, device: str = "desktop") -> dict:
    """Hard-delete payment/udhari entry."""
    db.table("payments").delete().eq("id", payment_id).execute()
    _log(db, f"PAYMENT_PERMANENTLY_DELETED: {payment_id}", device)
    return {"message": "Payment permanently deleted successfully"}


def get_payment_transactions(db: Client, payment_id: str) -> list:
    """Get the transaction log of additions and settlements for a specific payment/udhari entry."""
    result = (
        db.table("payment_transactions")
        .select("*")
        .eq("payment_id", payment_id)
        .order("created_at", desc=True)
        .execute()
    )
    from app.models.payment import PaymentTransactionResponse
    return [PaymentTransactionResponse.from_row(row) for row in (result.data or [])]
