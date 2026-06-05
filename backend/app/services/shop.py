from fastapi import HTTPException, status
from supabase import Client
from typing import Optional

from app.models.shop import (
    ShopCreate, ShopUpdate, ShopResponse,
    ShopPurchaseCreate, ShopPurchaseResponse,
    ShopPaymentResponse, ShopPaymentTransactionResponse,
    ShopDetailsResponse
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str) -> None:
    try:
        db.table("activity_logs").insert({"action": action, "device": device}).execute()
    except Exception:
        pass


def _require_shop(db: Client, shop_id: str) -> dict:
    result = (
        db.table("shops")
        .select("*")
        .eq("id", shop_id)
        .single()
        .execute()
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
            pay_res = db.table("shop_payments").select("shop_id").eq("is_settled", False).execute()
            pending_shop_ids = [p["shop_id"] for p in (pay_res.data or [])]
            if pending_shop_ids:
                query = query.in_("id", pending_shop_ids)
            else:
                return {"data": [], "total": 0, "page": page, "limit": limit}
        elif filter_type == "NO_PENDING_UDHARI":
            pay_res = db.table("shop_payments").select("shop_id").eq("is_settled", False).execute()
            pending_shop_ids = [p["shop_id"] for p in (pay_res.data or [])]
            if pending_shop_ids:
                query = query.not_.in_("id", pending_shop_ids)

    if search:
        term = search.strip().replace(",", "").replace("%", "")
        if term:
            # Query shop_purchases for matching battery_model or serial_number
            pur_match = db.table("shop_purchases")\
                .select("shop_id")\
                .or_(f"battery_model.ilike.%{term}%,serial_number.ilike.%{term}%")\
                .execute()
            matching_shop_ids = list({str(p["shop_id"]) for p in (pur_match.data or []) if p.get("shop_id")})
            
            if matching_shop_ids:
                shop_ids_str = ",".join(matching_shop_ids)
                query = query.or_(f"shop_name.ilike.%{term}%,owner_name.ilike.%{term}%,mobile.ilike.%{term}%,id.in.({shop_ids_str})")
            else:
                query = query.or_(f"shop_name.ilike.%{term}%,owner_name.ilike.%{term}%,mobile.ilike.%{term}%")

    offset = (page - 1) * limit
    result = query.order("shop_name", desc=False).range(offset, offset + limit - 1).execute()

    shops_list = result.data or []
    shop_ids = [str(r["id"]) for r in shops_list]
    
    # Computed fields default mapping
    pur_counts = {}
    pay_map = {}
    
    if shop_ids:
        # Count purchases
        pur_res = db.table("shop_purchases").select("shop_id").in_("shop_id", shop_ids).execute()
        for p in (pur_res.data or []):
            sid = str(p["shop_id"])
            pur_counts[sid] = pur_counts.get(sid, 0) + 1
            
        # Get pending Udhari balances
        pay_res = db.table("shop_payments").select("shop_id, pending_amount").in_("shop_id", shop_ids).execute()
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
    pur_res = db.table("shop_purchases").select("id").eq("shop_id", shop_id).execute()
    total_purchases = len(pur_res.data or [])
    
    pay_res = db.table("shop_payments").select("pending_amount").eq("shop_id", shop_id).execute()
    pending_udhari = float(pay_res.data[0]["pending_amount"]) if pay_res.data else 0.0
    
    row["total_purchases"] = total_purchases
    row["pending_udhari"] = pending_udhari
    return ShopResponse.from_row(row)


def get_shop_details(db: Client, shop_id: str) -> dict:
    shop_row = _require_shop(db, shop_id)
    
    # 1. Fetch Purchases
    pur_res = (
        db.table("shop_purchases")
        .select("*")
        .eq("shop_id", shop_id)
        .order("purchase_date", desc=True)
        .execute()
    )
    purchases = [ShopPurchaseResponse.from_row(r) for r in (pur_res.data or [])]

    # 2. Fetch Consolidated Payment Ledger
    pay_res = (
        db.table("shop_payments")
        .select("*")
        .eq("shop_id", shop_id)
        .execute()
    )
    payment = ShopPaymentResponse.from_row(pay_res.data[0]) if pay_res.data else None

    # 3. Fetch Ledger Transactions History
    tx_res = (
        db.table("shop_payment_transactions")
        .select("*")
        .eq("shop_id", shop_id)
        .order("created_at", desc=True)
        .execute()
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
    existing_mobile = db.table("shops").select("*").eq("mobile", mobile_clean).eq("is_archived", False).execute()
    if existing_mobile.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"SHOP_MOBILE_EXISTS:{existing_mobile.data[0]['id']}:{existing_mobile.data[0]['shop_name']}"
        )

    existing_name = db.table("shops").select("*").ilike("shop_name", shop_name_clean).eq("is_archived", False).execute()
    if existing_name.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"SHOP_NAME_EXISTS:{existing_name.data[0]['id']}:{existing_name.data[0]['shop_name']}"
        )

    result = db.table("shops").insert({
        "shop_name": shop_name_clean,
        "owner_name": data.owner_name.strip(),
        "mobile": mobile_clean,
        "address": data.address.strip() if data.address else None,
        "is_archived": False
    }).execute()

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create shop profile"
        )

    created = ShopResponse.from_row(result.data[0])
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
        existing = db.table("shops").select("*").eq("mobile", mobile_clean).neq("id", shop_id).eq("is_archived", False).execute()
        if existing.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"SHOP_MOBILE_EXISTS:{existing.data[0]['id']}:{existing.data[0]['shop_name']}"
            )
        updates["mobile"] = mobile_clean

    # If shop_name is updating, check duplicates
    if "shop_name" in updates:
        name_clean = updates["shop_name"].strip()
        existing = db.table("shops").select("*").ilike("shop_name", name_clean).neq("id", shop_id).eq("is_archived", False).execute()
        if existing.data:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"SHOP_NAME_EXISTS:{existing.data[0]['id']}:{existing.data[0]['shop_name']}"
            )
        updates["shop_name"] = name_clean

    updates["updated_at"] = "now()"
    result = db.table("shops").update(updates).eq("id", shop_id).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update shop profile")

    updated = ShopResponse.from_row(result.data[0])
    _log(db, f"SHOP_UPDATED: {shop_id}", device)
    return {"message": "Shop profile updated successfully", "data": updated}


def archive_shop(db: Client, shop_id: str, archive: bool = True, device: str = "desktop") -> dict:
    _require_shop(db, shop_id)
    
    # If archiving, prevent if outstanding Udhari balance exists
    if archive:
        pay_res = db.table("shop_payments").select("pending_amount").eq("shop_id", shop_id).execute()
        if pay_res.data:
            pending = float(pay_res.data[0]["pending_amount"])
            if pending > 0:
                raise HTTPException(
                    status_code=400,
                    detail=f"Cannot archive shop. Outstanding Udhari balance of ₹{pending} exists."
                )

    db.table("shops").update({"is_archived": archive, "updated_at": "now()"}).eq("id", shop_id).execute()
    action = "SHOP_ARCHIVED" if archive else "SHOP_RESTORED"
    _log(db, f"{action}: {shop_id}", device)
    return {"message": f"Shop {'archived' if archive else 'restored'} successfully"}


def create_shop_purchase(db: Client, shop_id: str, data: ShopPurchaseCreate, device: str = "desktop") -> dict:
    # 1. Verify and deduct stock from battery_stock (Refinement 4)
    model_upper = data.battery_model.strip().upper()
    stock_res = db.table("battery_stock").select("*").eq("model_name", model_upper).eq("is_archived", False).execute()
    if not stock_res.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Battery model '{model_upper}' does not exist in stock. Please add it to inventory first."
        )
    
    stock_item = stock_res.data[0]
    if stock_item["quantity"] < data.quantity:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient stock for model '{model_upper}'. Current stock is {stock_item['quantity']}, but {data.quantity} units requested."
        )

    # 2. Record purchase
    purchase_payload = {
        "shop_id": shop_id,
        "battery_model": model_upper,
        "serial_number": data.serial_number.strip(), # Mandatory (Refinement 2)
        "invoice_number": data.invoice_number.strip(), # Refinement 3
        "quantity": data.quantity,
        "purchase_date": data.purchase_date,
        "amount": data.amount,
        "udhari_amount": data.udhari_amount
    }
    pur_res = db.table("shop_purchases").insert(purchase_payload).execute()
    if not pur_res.data:
        raise HTTPException(status_code=500, detail="Failed to record shop purchase")
    
    created_purchase = ShopPurchaseResponse.from_row(pur_res.data[0])

    # 3. Decrement Stock
    new_qty = stock_item["quantity"] - data.quantity
    db.table("battery_stock").update({"quantity": new_qty, "updated_at": "now()"}).eq("id", stock_item["id"]).execute()
    _log(db, f"STOCK_AUTO_DECREASED: {model_upper} (-{data.quantity}) due to shop purchase", device)

    # 4. Consolidated Udhari Balance Ledger (Refinement 5)
    if data.udhari_amount > 0:
        pay_res = db.table("shop_payments").select("*").eq("shop_id", shop_id).execute()
        if pay_res.data:
            payment_row = pay_res.data[0]
            payment_id = payment_row["id"]
            new_total = float(payment_row["total_amount"]) + data.udhari_amount
            new_pending = float(payment_row["pending_amount"]) + data.udhari_amount
            is_settled = (new_pending == 0.0)

            db.table("shop_payments").update({
                "total_amount": new_total,
                "pending_amount": new_pending,
                "is_settled": is_settled,
                "updated_at": "now()"
            }).eq("id", payment_id).execute()
        else:
            new_pay_res = db.table("shop_payments").insert({
                "shop_id": shop_id,
                "total_amount": data.udhari_amount,
                "paid_amount": 0.0,
                "pending_amount": data.udhari_amount,
                "is_settled": False
            }).execute()
            payment_id = new_pay_res.data[0]["id"]

        # 5. Log Ledger Transaction separately
        db.table("shop_payment_transactions").insert({
            "payment_id": payment_id,
            "shop_id": shop_id,
            "transaction_type": "ADDITION",
            "amount": data.udhari_amount,
            "notes": f"Purchase addition: Model: {model_upper}, Invoice: {data.invoice_number}"
        }).execute()

    _log(db, f"SHOP_PURCHASE_ADDED: Shop {shop_id} bought {data.quantity}x {model_upper}", device)
    return {"message": "Shop purchase recorded successfully", "data": created_purchase}


def settle_shop_payment(
    db: Client, shop_id: str, amount: float, notes: Optional[str] = None, device: str = "desktop"
) -> dict:
    pay_res = db.table("shop_payments").select("*").eq("shop_id", shop_id).execute()
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

    db.table("shop_payments").update({
        "paid_amount": new_paid,
        "pending_amount": new_pending,
        "is_settled": is_settled,
        "updated_at": "now()"
    }).eq("id", payment_id).execute()

    # Log payment transaction
    db.table("shop_payment_transactions").insert({
        "payment_id": payment_id,
        "shop_id": shop_id,
        "transaction_type": "PAYMENT",
        "amount": amount,
        "notes": notes or "Udhari payment settlement"
    }).execute()

    _log(db, f"SHOP_PAYMENT_SETTLED: Shop {shop_id} paid ₹{amount}", device)
    return {"message": "Payment logged successfully", "pending_amount": new_pending}


def delete_shop_permanently(db: Client, shop_id: str, device: str = "desktop") -> dict:
    # Safely block deletion if pending Udhari exists (Refinement 10)
    pay_res = db.table("shop_payments").select("pending_amount").eq("shop_id", shop_id).execute()
    if pay_res.data:
        pending = float(pay_res.data[0]["pending_amount"])
        if pending > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot delete shop. Outstanding Udhari balance of ₹{pending} exists."
            )

    # Safe to delete - purge related entries first
    db.table("shop_payment_transactions").delete().eq("shop_id", shop_id).execute()
    db.table("shop_payments").delete().eq("shop_id", shop_id).execute()
    db.table("shop_purchases").delete().eq("shop_id", shop_id).execute()
    db.table("shops").delete().eq("id", shop_id).execute()

    _log(db, f"SHOP_PERMANENTLY_DELETED: {shop_id}", device)
    return {"message": "Shop permanently deleted successfully"}
