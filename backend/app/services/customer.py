from fastapi import HTTPException, status
from supabase import Client

from app.models.customer import CustomerCreate, CustomerUpdate, CustomerResponse, CustomerCombinedCreate


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str) -> None:
    """Fire-and-forget activity log — never raises."""
    try:
        safe_execute(db.table("activity_logs").insert(
            {"action": action, "device": device}
        ))
    except Exception:
        pass


def _sanitize_search(term: str) -> str:
    """
    Remove characters that can break Supabase PostgREST OR query syntax.
    Commas are used as OR separators; percent signs conflict with ILIKE wildcards.
    """
    return term.strip().replace(",", "").replace("%", "").replace("(", "").replace(")", "")


def _require_customer(db: Client, customer_id: str) -> dict:
    """Fetch a non-archived customer by ID or raise 404."""
    result = (
        safe_execute(db.table("customers")
        .select("*")
        .eq("id", customer_id)
        .single())
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Customer {customer_id} not found",
        )
    return result.data


# ---------------------------------------------------------------------------
# Read operations
# ---------------------------------------------------------------------------

def get_all_customers(
    db: Client,
    search: str = "",
    page: int = 1,
    limit: int = 20,
    archived: bool = False,
    filter_type: str = "ALL",
) -> dict:
    """
    Return paginated customers.
    Supports multi-field search: name, mobile, vehicle_no.
    Search term is sanitized before use to prevent query injection.
    """
    query = (
        db.table("customers")
        .select("*", count="exact")
        .eq("is_archived", archived)
    )

    if filter_type == "SCRAP_PENDING":
        query = query.eq("scrap_battery_pending", True)
    elif filter_type == "ACTIVE_WARRANTIES":
        from datetime import date
        today_str = date.today().isoformat()
        batt_res = safe_execute(db.table("batteries").select("customer_id").gte("warranty_expiry", today_str).eq("is_archived", False))
        batt_cust_ids = list({str(b["customer_id"]) for b in (batt_res.data or [])})
        if batt_cust_ids:
            query = query.in_("id", batt_cust_ids)
        else:
            return {"data": [], "total": 0, "page": page, "limit": limit}
    elif filter_type == "PENDING_UDHARI":
        pay_res = safe_execute(db.table("payments").select("customer_id").eq("is_settled", False).eq("is_archived", False))
        pay_cust_ids = list({str(p["customer_id"]) for p in (pay_res.data or [])})
        if pay_cust_ids:
            query = query.in_("id", pay_cust_ids)
        else:
            return {"data": [], "total": 0, "page": page, "limit": limit}

    if search:
        term = _sanitize_search(search)
        if term:   # only apply if something remains after sanitization
            query = query.or_(
                f"name.ilike.%{term}%,"
                f"mobile.ilike.%{term}%,"
                f"vehicle_no.ilike.%{term}%"
            )

    offset = (page - 1) * limit
    result = (
        safe_execute(query
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1))
    )

    customers = [CustomerResponse.from_row(row) for row in (result.data or [])]
    return {"data": customers, "total": result.count or 0, "page": page, "limit": limit}


def get_customer_by_id(db: Client, customer_id: str) -> CustomerResponse:
    """Return a single customer by UUID."""
    return CustomerResponse.from_row(_require_customer(db, customer_id))


def get_customer_with_details(db: Client, customer_id: str) -> dict:
    """Return customer + their batteries + their payments."""
    customer = _require_customer(db, customer_id)

    batteries = (
        safe_execute(db.table("batteries")
        .select("*")
        .eq("customer_id", customer_id)
        .eq("is_archived", False)
        .order("sale_date", desc=True))
    ).data or []

    payments = (
        safe_execute(db.table("payments")
        .select("*")
        .eq("customer_id", customer_id)
        .eq("is_archived", False)
        .order("created_at", desc=True))
    ).data or []

    reminders = (
        safe_execute(db.table("service_reminders")
        .select("*")
        .eq("customer_id", customer_id)
        .eq("is_archived", False)
        .order("reminder_date", desc=False))
    ).data or []

    return {
        "customer": CustomerResponse.from_row(customer),
        "batteries": batteries,
        "payments": payments,
        "reminders": reminders,
    }


# ---------------------------------------------------------------------------
# Write operations
# ---------------------------------------------------------------------------

def create_customer(
    db: Client, data: CustomerCreate, device: str = "desktop"
) -> dict:
    """Insert a new customer, log the action, return message + data."""
    # Check if a customer with the same name already exists (case-insensitive, trimmed)
    name_stripped = data.name.strip()
    existing = (
        safe_execute(db.table("customers")
        .select("*")
        .ilike("name", name_stripped)
        .eq("is_archived", False))
    )
    if existing.data:
        customer_row = existing.data[0]
        customer_id = customer_row["id"]
        created = CustomerResponse.from_row(customer_row)
        
        # Merge/update details if they are provided and not present in DB
        updates = {}
        for field in ["mobile", "vehicle_no", "vehicle_type", "area", "pincode", "purchase_type"]:
            val = getattr(data, field, None)
            if val and not customer_row.get(field):
                updates[field] = val
                
        if updates:
            safe_execute(db.table("customers").update(updates).eq("id", customer_id))
            # Fetch updated row
            customer_row = safe_execute(db.table("customers").select("*").eq("id", customer_id).single()).data
            created = CustomerResponse.from_row(customer_row)
            
        _log(db, f"CUSTOMER_REUSED: Reused existing customer '{data.name}' ({customer_id})", device)
        return {"message": "Customer already exists, reusing existing record", "data": created}

    result = (
        safe_execute(db.table("customers")
        .insert(data.model_dump()))
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create customer",
        )
    created = CustomerResponse.from_row(result.data[0])
    _log(db, f"CUSTOMER_ADDED: {data.name} ({data.mobile})", device)
    return {"message": "Customer created successfully", "data": created}


def update_customer(
    db: Client, customer_id: str, data: CustomerUpdate, device: str = "desktop"
) -> dict:
    """Update allowed fields. Only sends non-None fields to DB."""
    _require_customer(db, customer_id)

    updates = {k: v for k, v in data.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields provided for update",
        )

    result = (
        safe_execute(db.table("customers")
        .update(updates)
        .eq("id", customer_id))
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update customer",
        )
    updated = CustomerResponse.from_row(result.data[0])
    _log(db, f"CUSTOMER_UPDATED: {customer_id}", device)
    return {"message": "Customer updated successfully", "data": updated}


def archive_customer(db: Client, customer_id: str, device: str = "desktop") -> dict:
    """Soft-delete: set is_archived = True."""
    _require_customer(db, customer_id)
    safe_execute(db.table("customers").update({"is_archived": True}).eq("id", customer_id))
    _log(db, f"CUSTOMER_ARCHIVED: {customer_id}", device)
    return {"message": "Customer archived successfully"}


def restore_customer(db: Client, customer_id: str, device: str = "desktop") -> dict:
    """Undo archive: set is_archived = False."""
    safe_execute(db.table("customers").update({"is_archived": False}).eq("id", customer_id))
    _log(db, f"CUSTOMER_RESTORED: {customer_id}", device)
    return {"message": "Customer restored successfully"}


def create_combined_customer(
    db: Client, data: CustomerCombinedCreate, device: str = "desktop"
) -> dict:
    from datetime import date
    from app.models.battery import BatteryCreate
    from app.models.payment import PaymentCreate
    from app.services.battery import create_battery
    from app.services.payment import create_payment

    # Check if a customer with the same name already exists (case-insensitive, trimmed)
    name_stripped = data.name.strip()
    existing = (
        safe_execute(db.table("customers")
        .select("*")
        .ilike("name", name_stripped)
        .eq("is_archived", False))
    )
    
    if existing.data:
        customer_row = existing.data[0]
        customer_id = customer_row["id"]
        created_customer = CustomerResponse.from_row(customer_row)
        
        # Merge/update details if they are provided and not present
        updates = {}
        for field in ["mobile", "vehicle_no", "vehicle_type", "area", "pincode", "purchase_type"]:
            val = getattr(data, field, None)
            if val and not customer_row.get(field):
                updates[field] = val
        
        # Scrap fields integration
        if data.scrap_battery_pending:
            updates["scrap_battery_pending"] = True
        if data.scrap_expected_value and float(data.scrap_expected_value) > float(customer_row.get("scrap_expected_value") or 0.0):
            updates["scrap_expected_value"] = float(data.scrap_expected_value)
            
        if updates:
            safe_execute(db.table("customers").update(updates).eq("id", customer_id))
            # Fetch updated row
            customer_row = safe_execute(db.table("customers").select("*").eq("id", customer_id).single()).data
            created_customer = CustomerResponse.from_row(customer_row)
    else:
        # 1. Insert customer
        customer_payload = {
            "name": data.name,
            "mobile": data.mobile,
            "vehicle_no": data.vehicle_no,
            "vehicle_type": data.vehicle_type,
            "area": data.area,
            "pincode": data.pincode,
            "purchase_type": data.purchase_type,
            "scrap_battery_pending": data.scrap_battery_pending,
            "scrap_expected_value": data.scrap_expected_value,
        }
        cust_res = safe_execute(db.table("customers").insert(customer_payload))
        if not cust_res.data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create customer record",
            )
        customer_row = cust_res.data[0]
        customer_id = customer_row["id"]
        created_customer = CustomerResponse.from_row(customer_row)

    created_battery = None
    created_payment = None

    # 2. Add battery if model is provided
    if data.battery_model:
        battery_create = BatteryCreate(
            customer_id=customer_id,
            battery_type=data.battery_type,
            model_number=data.battery_model,
            serial_number=data.battery_serial_number,
            sale_date=data.battery_sale_date or date.today(),
            warranty_months=data.battery_warranty_months,
            auto_reduce_stock=True,
            notes=data.battery_notes,
            service_reminder_interval_months=data.battery_service_reminder_interval_months,
            water_check_interval_months=data.battery_water_check_interval_months,
        )
        battery_res = create_battery(db, battery_create, device=device)
        created_battery = battery_res["data"]

    # 3. Add payment if provided
    if data.has_udhari:
        note_parts = []
        if data.payment_method:
            note_parts.append(f"[Method: {data.payment_method.strip()}]")
        if data.payment_due_date:
            note_parts.append(f"[Due: {data.payment_due_date.strip()}]")
        
        combined_note = " ".join(note_parts)
        if data.payment_reminder_note:
            combined_note = f"{combined_note} {data.payment_reminder_note.strip()}".strip()

        payment_create = PaymentCreate(
            customer_id=customer_id,
            battery_id=created_battery.id if created_battery else None,
            total_amount=data.payment_total_amount,
            paid_amount=data.payment_paid_amount or 0.0,
            reminder_note=combined_note or None,
        )
        payment_res = create_payment(db, payment_create, device=device)
        created_payment = payment_res["data"]

    _log(db, f"COMBINED_CUSTOMER_ADDED: {data.name} ({data.mobile})", device)
    
    return {
        "message": "Customer registered successfully",
        "data": {
            "customer": created_customer,
            "battery": created_battery,
            "payment": created_payment,
        }
    }


def delete_customer_permanently(db: Client, customer_id: str, device: str = "desktop") -> dict:
    """Hard-delete customer and all associated batteries and payments."""
    safe_execute(db.table("payments").delete().eq("customer_id", customer_id))
    safe_execute(db.table("batteries").delete().eq("customer_id", customer_id))
    safe_execute(db.table("customers").delete().eq("id", customer_id))
    _log(db, f"CUSTOMER_PERMANENTLY_DELETED: {customer_id}", device)
    return {"message": "Customer permanently deleted successfully"}
