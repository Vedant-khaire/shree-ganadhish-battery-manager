from fastapi import HTTPException, status
from supabase import Client
from typing import Optional

from app.database import safe_execute
from app.models.shop import (
    ShopCreate, ShopUpdate, ShopResponse,
    ShopPurchaseCreate, ShopPurchaseResponse,
    ShopPaymentResponse, ShopPaymentTransactionResponse,
    ShopDetailsResponse, ShopOpeningBalanceCreate
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str) -> None:
    try:
        safe_execute(db.table("activity_logs").insert({"action": action, "device": device}))
    except Exception:
        pass


def _require_shop(db: Client, shop_id: str) -> dict:
    result = (
        safe_execute(db.table("shops")
        .select("*")
        .eq("id", shop_id)
        .single())
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Shop profile with ID {shop_id} not found",
        )
    return result.data


# ---------------------------------------------------------------------------
# Read Operations
# ---------------------------------------------------------------------------

def get_all_shops(
    db: Client,
    search: str = "",
    page: int = 1,
    limit: int = 20,
    filter_type: str = "ALL"
) -> dict:
    query = db.table("shops").select("*", count="exact")

    if filter_type == "ARCHIVED":
        query = query.eq("is_archived", True)
    else:
        query = query.eq("is_archived", False)
        
        # Pending Udhari filters
        if filter_type == "PENDING_UDHARI":
            pay_res = safe_execute(db.table("shop_payments").select("shop_id").eq("is_settled", False))
            pending_shop_ids = [p["shop_id"] for p in (pay_res.data or [])]
            if pending_shop_ids:
                query = query.in_("id", pending_shop_ids)
            else:
                return {"data": [], "total": 0, "page": page, "limit": limit}
        elif filter_type == "NO_PENDING_UDHARI":
            pay_res = safe_execute(db.table("shop_payments").select("shop_id").eq("is_settled", False))
            pending_shop_ids = [p["shop_id"] for p in (pay_res.data or [])]
            if pending_shop_ids:
                query = query.not_.in_("id", pending_shop_ids)

    if search:
        term = search.strip().replace(",", "").replace("%", "")
        if term:
            # Query shop_purchases for matching battery_model or serial_number
            pur_match = safe_execute(db.table("shop_purchases")\
                .select("shop_id")\
                .or_(f"battery_model.ilike.%{term}%,serial_number.ilike.%{term}%"))
            matching_shop_ids = list({str(p["shop_id"]) for p in (pur_match.data or []) if p.get("shop_id")})
            
            if matching_shop_ids:
                shop_ids_str = ",".join(matching_shop_ids)
                query = query.or_(f"shop_name.ilike.%{term}%,owner_name.ilike.%{term}%,mobile.ilike.%{term}%,id.in.({shop_ids_str})")
            else:
                query = query.or_(f"shop_name.ilike.%{term}%,owner_name.ilike.%{term}%,mobile.ilike.%{term}%")

    offset = (page - 1) * limit
    result = safe_execute(query.order("shop_name", desc=False).range(offset, offset + limit - 1))

    shops_list = result.data or []
    shop_ids = [str(r["id"]) for r in shops_list]
    
    # Computed fields default mapping
    pur_counts = {}
    pay_map = {}
    
    if shop_ids:
        # Count purchases
        pur_res = safe_execute(db.table("shop_purchases").select("shop_id").in_("shop_id", shop_ids))
        for p in (pur_res.data or []):
            sid = str(p["shop_id"])
            pur_counts[sid] = pur_counts.get(sid, 0) + 1
            
        # Get pending Udhari balances
        pay_res = safe_execute(db.table("shop_payments").select("shop_id, pending_amount").in_("shop_id", shop_ids))
        for p in (pay_res.data or []):
            sid = str(p["shop_id"])
            pay_map[sid] = float(p["pending_amount"])

    # Inject computed fields into the rows
    for r in shops_list:
        sid = str(r["id"])
        r["total_purchases"] = pur_counts.get(sid, 0)
        r["pending_udhari"] = pay_map.get(sid, 0.0)

    return {
        "data": [ShopResponse.from_row(r) for r in shops_list],
        "total": result.count or 0,
        "page": page,
        "limit": limit
    }


def get_shop_by_id(db: Client, shop_id: str) -> ShopResponse:
    row = _require_shop(db, shop_id)
    
    # Fetch computed fields
    pur_res = safe_execute(db.table("shop_purchases").select("id").eq("shop_id", shop_id))
    total_purchases = len(pur_res.data or [])
    
    pay_res = safe_execute(db.table("shop_payments").select("pending_amount").eq("shop_id", shop_id))
    pending_udhari = float(pay_res.data[0]["pending_amount"]) if pay_res.data else 0.0
    
    row["total_purchases"] = total_purchases
    row["pending_udhari"] = pending_udhari
    return ShopResponse.from_row(row)


def get_shop_details(db: Client, shop_id: str) -> dict:
    shop_row = _require_shop(db, shop_id)
    
    # 1. Fetch Purchases
    pur_res = (
        safe_execute(db.table("shop_purchases")
        .select("*")
        .eq("shop_id", shop_id)
        .order("purchase_date", desc=True))
    )
    purchases = [ShopPurchaseResponse.from_row(r) for r in (pur_res.data or [])]

    # 2. Fetch Consolidated Payment Ledger
    pay_res = (
        safe_execute(db.table("shop_payments")
        .select("*")
        .eq("shop_id", shop_id))
    )
    payment = ShopPaymentResponse.from_row(pay_res.data[0]) if pay_res.data else None

    # 3. Fetch Ledger Transactions History
    tx_res = (
        safe_execute(db.table("shop_payment_transactions")
        .select("*")
        .eq("shop_id", shop_id)
        .order("created_at", desc=True))
    )
    transactions = [ShopPaymentTransactionResponse.from_row(r) for r in (tx_res.data or [])]

    # Inject computed fields into shop_row
    shop_row["total_purchases"] = len(purchases)
    shop_row["pending_udhari"] = float(payment.pending_amount) if payment else 0.0

    return {
        "shop": ShopResponse.from_row(shop_row),
        "purchases": purchases,
        "payment": payment,
        "transactions": transactions
    }


# ---------------------------------------------------------------------------
# Write Operations
# ---------------------------------------------------------------------------

def create_shop(db: Client, data: ShopCreate, device: str = "desktop") -> dict:
    shop_name_clean = data.shop_name.strip()
    mobile_clean = data.mobile.strip()

    # Refinement 1: Duplicate Detection on Mobile (Primary) and Name
    existing_mobile = safe_execute(db.table("shops").select("*").eq("mobile", mobile_clean).eq("is_archived", False))
    if existing_mobile.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"SHOP_MOBILE_EXISTS:{existing_mobile.data[0]['id']}:{existing_mobile.data[0]['shop_name']}"
        )

    existing_name = safe_execute(db.table("shops").select("*").ilike("shop_name", shop_name_clean).eq("is_archived", False))
    if existing_name.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"SHOP_NAME_EXISTS:{existing_name.data[0]['id']}:{existing_name.data[0]['shop_name']}"
        )

    result = safe_execute(db.table("shops").insert({
        "shop_name": shop_name_clean,
        "owner_name": data.owner_name.strip(),
        "mobile": mobile_clean,
        "address": data.address.strip() if data.address else None,
        "is_archived": False
    }))

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create shop profile"
        )

    created = ShopResponse.from_row(result.data[0])
    
    # Handle Old Udhari (Initial outstanding balance)
    initial_udhari = getattr(data, "initial_udhari", 0.0) or 0.0
    if initial_udhari > 0.0:
        try:
            pay_res = safe_execute(db.table("shop_payments").insert({
                "shop_id": created.id,
                "total_amount": initial_udhari,
                "paid_amount": 0.0,
                "pending_amount": initial_udhari,
                "is_settled": False
            }))
            
            if pay_res.data:
                payment_id = pay_res.data[0]["id"]
                safe_execute(db.table("shop_payment_transactions").insert({
                    "payment_id": payment_id,
                    "shop_id": created.id,
                    "transaction_type": "ADDITION",
                    "amount": initial_udhari,
                    "notes": "Old Udhaari / Opening Balance"
                }))
                
                created.pending_udhari = initial_udhari
        except Exception as e:
            # Fallback for safety - do not crash shop creation if payment setup fails
            pass

    _log(db, f"SHOP_CREATED: {created.shop_name} ({created.mobile})", device)
    return {"message": "Shop profile created successfully", "data": created}



def update_shop(db: Client, shop_id: str, data: ShopUpdate, device: str = "desktop") -> dict:
    _require_shop(db, shop_id)
    updates = {k: v for k, v in data.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    # If mobile is updating, check duplicates
    if "mobile" in updates:
        mobile_clean = updates["mobile"].strip()
        existing = safe_execute(db.table("shops").select("*").eq("mobile", mobile_clean).neq("id", shop_id).eq("is_archived", False))
        if existing.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"SHOP_MOBILE_EXISTS:{existing.data[0]['id']}:{existing.data[0]['shop_name']}"
            )
        updates["mobile"] = mobile_clean

    # If shop_name is updating, check duplicates
    if "shop_name" in updates:
        name_clean = updates["shop_name"].strip()
        existing = safe_execute(db.table("shops").select("*").ilike("shop_name", name_clean).neq("id", shop_id).eq("is_archived", False))
        if existing.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"SHOP_NAME_EXISTS:{existing.data[0]['id']}:{existing.data[0]['shop_name']}"
            )
        updates["shop_name"] = name_clean

    updates["updated_at"] = "now()"
    result = safe_execute(db.table("shops").update(updates).eq("id", shop_id))
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update shop profile")

    updated = ShopResponse.from_row(result.data[0])
    _log(db, f"SHOP_UPDATED: {shop_id}", device)
    return {"message": "Shop profile updated successfully", "data": updated}


def archive_shop(db: Client, shop_id: str, archive: bool = True, device: str = "desktop") -> dict:
    _require_shop(db, shop_id)
    
    # If archiving, prevent if outstanding Udhari balance exists
    if archive:
        pay_res = safe_execute(db.table("shop_payments").select("pending_amount").eq("shop_id", shop_id))
        if pay_res.data:
            pending = float(pay_res.data[0]["pending_amount"])
            if pending > 0:
                raise HTTPException(
                    status_code=400,
                    detail=f"Cannot archive shop. Outstanding Udhari balance of ₹{pending} exists."
                )

    safe_execute(db.table("shops").update({"is_archived": archive, "updated_at": "now()"}).eq("id", shop_id))
    action = "SHOP_ARCHIVED" if archive else "SHOP_RESTORED"
    _log(db, f"{action}: {shop_id}", device)
    return {"message": f"Shop {'archived' if archive else 'restored'} successfully"}


def create_shop_purchase(db: Client, shop_id: str, data: ShopPurchaseCreate, device: str = "desktop") -> dict:
    # 0. Validate multiple serial numbers
    quantity = data.quantity
    serial_numbers = [sn.strip().upper() for sn in data.serial_numbers]

    if len(serial_numbers) != quantity:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Quantity ({quantity}) must exactly match the number of serial numbers provided ({len(serial_numbers)})."
        )

    if any(not sn for sn in serial_numbers):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty serial numbers are not allowed."
        )

    if len(set(serial_numbers)) != len(serial_numbers):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Duplicate serial numbers in the same purchase are not allowed."
        )

    # Validate database uniqueness case-insensitively
    for sn in serial_numbers:
        existing = safe_execute(db.table("battery_units").select("*").ilike("serial_number", sn))
        if existing.data:
            unit = existing.data[0]
            if unit["status"] != "AVAILABLE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Battery serial number '{sn}' has already been sold or registered (current status: {unit['status']})."
                )

    # 1. Verify and deduct stock from battery_stock if it exists in inventory
    model_upper = data.battery_model.strip().upper()
    stock_res = safe_execute(db.table("battery_stock").select("*").eq("model_name", model_upper).eq("is_archived", False))
    
    stock_item = None
    if stock_res.data:
        stock_item = stock_res.data[0]
        if stock_item["quantity"] < quantity:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Insufficient stock for model '{model_upper}'. Current stock is {stock_item['quantity']}, but {quantity} units requested."
            )

    # 2. Record purchase
    serial_str = ", ".join(serial_numbers)
    purchase_payload = {
        "shop_id": shop_id,
        "battery_model": model_upper,
        "serial_number": serial_str,
        "invoice_number": data.invoice_number.strip(),
        "quantity": quantity,
        "purchase_date": data.purchase_date,
        "amount": data.amount,
        "udhari_amount": data.udhari_amount,
        "payment_mode": data.payment_mode or "Cash",
    }
    pur_res = safe_execute(db.table("shop_purchases").insert(purchase_payload))
    if not pur_res.data:
        raise HTTPException(status_code=500, detail="Failed to record shop purchase")
    
    created_purchase = ShopPurchaseResponse.from_row(pur_res.data[0])
    purchase_id = created_purchase.id

    # 2.5 Update/Create battery_units and link them
    for sn in serial_numbers:
        existing = safe_execute(db.table("battery_units").select("*").ilike("serial_number", sn))
        if existing.data:
            unit = existing.data[0]
            safe_execute(db.table("battery_units").update({
                "status": "SOLD",
                "shop_purchase_id": purchase_id,
                "updated_at": "now()"
            }).eq("id", unit["id"]))
        else:
            b_type = stock_item["battery_type"] if stock_item else "4W"
            safe_execute(db.table("battery_units").insert({
                "model_name": model_upper,
                "battery_type": b_type,
                "serial_number": sn,
                "status": "SOLD",
                "purchase_date": data.purchase_date,
                "shop_purchase_id": purchase_id,
                "shop_source": None
            }))

    # 3. Decrement Stock (only if it exists in inventory)
    if stock_item is not None:
        new_qty = stock_item["quantity"] - quantity
        safe_execute(db.table("battery_stock").update({"quantity": new_qty, "updated_at": "now()"}).eq("id", stock_item["id"]))
        _log(db, f"STOCK_AUTO_DECREASED: {model_upper} (-{quantity}) due to shop purchase", device)

    # 4. Consolidated Udhari Balance Ledger (Refinement 5)
    if data.udhari_amount > 0:
        pay_res = safe_execute(db.table("shop_payments").select("*").eq("shop_id", shop_id))
        if pay_res.data:
            payment_row = pay_res.data[0]
            payment_id = payment_row["id"]
            new_total = float(payment_row["total_amount"]) + data.udhari_amount
            new_pending = float(payment_row["pending_amount"]) + data.udhari_amount
            is_settled = (new_pending == 0.0)

            safe_execute(db.table("shop_payments").update({
                "total_amount": new_total,
                "pending_amount": new_pending,
                "is_settled": is_settled,
                "updated_at": "now()"
            }).eq("id", payment_id))
        else:
            new_pay_res = safe_execute(db.table("shop_payments").insert({
                "shop_id": shop_id,
                "total_amount": data.udhari_amount,
                "paid_amount": 0.0,
                "pending_amount": data.udhari_amount,
                "is_settled": False
            }))
            payment_id = new_pay_res.data[0]["id"]

        # 5. Log Ledger Transaction separately
        safe_execute(db.table("shop_payment_transactions").insert({
            "payment_id": payment_id,
            "shop_id": shop_id,
            "transaction_type": "ADDITION",
            "amount": data.udhari_amount,
            "notes": f"Purchase addition: Model: {model_upper}, Invoice: {data.invoice_number}"
        }))

    _log(db, f"SHOP_PURCHASE_ADDED: Shop {shop_id} bought {quantity}x {model_upper}", device)
    return {"message": "Shop purchase recorded successfully", "data": created_purchase}



def settle_shop_payment(
    db: Client, shop_id: str, amount: float, notes: Optional[str] = None, payment_mode: str = "Cash", device: str = "desktop"
) -> dict:
    pay_res = safe_execute(db.table("shop_payments").select("*").eq("shop_id", shop_id))
    if not pay_res.data:
        raise HTTPException(status_code=400, detail="No outstanding payment ledger exists for this shop")

    payment_row = pay_res.data[0]
    payment_id = payment_row["id"]
    pending = float(payment_row["pending_amount"])

    if pending <= 0:
        raise HTTPException(status_code=400, detail="This shop does not have any pending Udhari balance")

    if amount <= 0:
        raise HTTPException(status_code=400, detail="Settlement amount must be greater than zero")

    if amount > pending:
        raise HTTPException(status_code=400, detail=f"Settlement amount (₹{amount}) cannot exceed outstanding balance (₹{pending})")

    new_paid = float(payment_row["paid_amount"]) + amount
    new_pending = round(pending - amount, 2)
    is_settled = (new_pending == 0.0)

    safe_execute(db.table("shop_payments").update({
        "paid_amount": new_paid,
        "pending_amount": new_pending,
        "is_settled": is_settled,
        "updated_at": "now()"
    }).eq("id", payment_id))

    # Log payment transaction
    safe_execute(db.table("shop_payment_transactions").insert({
        "payment_id": payment_id,
        "shop_id": shop_id,
        "transaction_type": "PAYMENT",
        "amount": amount,
        "notes": notes or "Udhari payment settlement",
        "payment_mode": payment_mode
    }))

    _log(db, f"SHOP_PAYMENT_SETTLED: Shop {shop_id} paid ₹{amount}", device)
    return {"message": "Payment logged successfully", "pending_amount": new_pending}


def delete_shop_permanently(db: Client, shop_id: str, device: str = "desktop") -> dict:
    # Safely block deletion if pending Udhari exists (Refinement 10)
    pay_res = safe_execute(db.table("shop_payments").select("pending_amount").eq("shop_id", shop_id))
    if pay_res.data:
        pending = float(pay_res.data[0]["pending_amount"])
        if pending > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot delete shop. Outstanding Udhari balance of ₹{pending} exists."
            )

    # Safe to delete - purge related entries first
    safe_execute(db.table("shop_payment_transactions").delete().eq("shop_id", shop_id))
    safe_execute(db.table("shop_payments").delete().eq("shop_id", shop_id))
    safe_execute(db.table("shop_purchases").delete().eq("shop_id", shop_id))
    safe_execute(db.table("shops").delete().eq("id", shop_id))

    _log(db, f"SHOP_PERMANENTLY_DELETED: {shop_id}", device)
    return {"message": "Shop permanently deleted successfully"}


def delete_shop_purchase(db: Client, shop_id: str, purchase_id: str, device: str = "desktop") -> dict:
    shop = _require_shop(db, shop_id)
    
    # 1. Fetch the purchase record
    pur_res = safe_execute(db.table("shop_purchases").select("*").eq("id", purchase_id).eq("shop_id", shop_id))
    if not pur_res.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Purchase entry not found"
        )
    purchase = pur_res.data[0]
    
    # 2. Restore stock if it was tracked in inventory
    model_upper = purchase["battery_model"].strip().upper()
    stock_res = safe_execute(db.table("battery_stock").select("*").eq("model_name", model_upper).eq("is_archived", False))
    if stock_res.data:
        stock_item = stock_res.data[0]
        new_qty = stock_item["quantity"] + int(purchase["quantity"])
        safe_execute(db.table("battery_stock").update({"quantity": new_qty, "updated_at": "now()"}).eq("id", stock_item["id"]))
        _log(db, f"STOCK_AUTO_INCREASED: {model_upper} (+{purchase['quantity']}) due to purchase return", device)

    # 3. Handle Udhari updates safely
    udhari_amount = float(purchase["udhari_amount"] or 0.0)
    if udhari_amount > 0:
        pay_res = safe_execute(db.table("shop_payments").select("*").eq("shop_id", shop_id))
        if pay_res.data:
            payment_row = pay_res.data[0]
            payment_id = payment_row["id"]
            total_amount = float(payment_row["total_amount"])
            paid_amount = float(payment_row["paid_amount"])
            pending_amount = float(payment_row["pending_amount"])
            
            new_total = round(total_amount - udhari_amount, 2)
            
            # Validation check to ensure payments don't exceed the new total
            if new_total < paid_amount:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="This purchase is linked to payment records. Please reverse/adjust the payment ledger before deleting this purchase."
                )
                
            new_pending = max(0.0, round(pending_amount - udhari_amount, 2))
            is_settled = (new_pending == 0.0)
            
            safe_execute(db.table("shop_payments").update({
                "total_amount": new_total,
                "pending_amount": new_pending,
                "is_settled": is_settled,
                "updated_at": "now()"
            }).eq("id", payment_id))
            
            # Find and delete the corresponding ADDITION transaction entry
            notes_prefix = f"Purchase addition: Model: {model_upper}"
            safe_execute(db.table("shop_payment_transactions")\
                .delete()\
                .eq("payment_id", payment_id)\
                .eq("transaction_type", "ADDITION")\
                .eq("amount", udhari_amount)\
                .like("notes", f"{notes_prefix}%"))

    # 3.5 Revert/unlink related battery units linked to this purchase
    safe_execute(db.table("battery_units").update({
        "status": "AVAILABLE",
        "shop_purchase_id": None,
        "updated_at": "now()"
    }).eq("shop_purchase_id", purchase_id))

    # 4. Delete the purchase record
    safe_execute(db.table("shop_purchases").delete().eq("id", purchase_id))

    
    # 5. Log detailed return audit trail
    log_text = (
        f"BATTERY_RETURNED:\n"
        f"Shop: {shop['shop_name']}\n"
        f"Battery Model: {purchase['battery_model']}\n"
        f"Serial Number: {purchase['serial_number']}\n"
        f"Quantity: {purchase['quantity']}\n"
        f"Reason: Returned To Inventory"
    )
    _log(db, log_text, device)
    
    return {"message": "Purchase entry deleted and stock restored successfully"}


def add_shop_opening_balance(db: Client, shop_id: str, data: ShopOpeningBalanceCreate, device: str = "desktop") -> dict:
    _require_shop(db, shop_id)
    
    # Determine the transaction amount sign based on transaction type
    amount = data.amount
    t_type = data.transaction_type.upper().strip()
    if t_type not in ("OPENING_BALANCE", "ADJUSTMENT_DEBIT", "ADJUSTMENT_CREDIT"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid transaction type"
        )
        
    if t_type == "ADJUSTMENT_CREDIT":
        amount = -abs(amount)
    elif t_type == "ADJUSTMENT_DEBIT":
        amount = abs(amount)
        
    if amount == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Amount cannot be zero"
        )
        
    # Check if a payment ledger exists
    pay_res = safe_execute(db.table("shop_payments").select("*").eq("shop_id", shop_id))
    if pay_res.data:
        payment_row = pay_res.data[0]
        payment_id = payment_row["id"]
        total_amount = float(payment_row["total_amount"])
        pending_amount = float(payment_row["pending_amount"])
        
        new_total = round(total_amount + amount, 2)
        new_pending = round(pending_amount + amount, 2)
        
        if new_pending < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Adjustment cannot make outstanding balance negative."
            )
            
        is_settled = (new_pending == 0.0)
        
        safe_execute(db.table("shop_payments").update({
            "total_amount": new_total,
            "pending_amount": new_pending,
            "is_settled": is_settled,
            "updated_at": "now()"
        }).eq("id", payment_id))
    else:
        if amount < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Initial balance or adjustment cannot be negative."
            )
            
        new_pay_res = safe_execute(db.table("shop_payments").insert({
            "shop_id": shop_id,
            "total_amount": amount,
            "paid_amount": 0.0,
            "pending_amount": amount,
            "is_settled": False
        }))
        payment_id = new_pay_res.data[0]["id"]
        
    # Insert ledger transaction history
    safe_execute(db.table("shop_payment_transactions").insert({
        "payment_id": payment_id,
        "shop_id": shop_id,
        "transaction_type": t_type,
        "amount": amount,
        "notes": data.notes or f"Manual ledger {t_type.lower().replace('_', ' ')}",
        "created_at": f"{data.date}T12:00:00+05:30"
    }))
    
    # Log activity
    log_action = "OPENING_BALANCE_ADDED" if t_type == "OPENING_BALANCE" else "ADJUSTMENT_ADDED"
    _log(db, f"{log_action}: {t_type.lower().replace('_', ' ')} of ₹{amount} added for shop {shop_id}", device)
    
    return {"message": f"{t_type.lower().replace('_', ' ')} recorded successfully"}
