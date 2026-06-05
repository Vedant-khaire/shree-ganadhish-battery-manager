from datetime import date
from dateutil.relativedelta import relativedelta
from fastapi import HTTPException, status
from supabase import Client

from app.models.battery import BatteryCreate, BatteryUpdate, BatteryResponse


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str) -> None:
    try:
        db.table("activity_logs").insert({"action": action, "device": device}).execute()
    except Exception:
        pass


def _sanitize_search(term: str) -> str:
    return term.strip().replace(",", "").replace("%", "").replace("(", "").replace(")", "")


def _compute_dates(sale_date: date, warranty_months: int) -> tuple[date, date]:
    """
    Returns (warranty_expiry, warranty_reminder_date).
    - warranty_expiry        = sale_date + warranty_months
    - warranty_reminder_date = sale_date + exactly 12 months (always fixed)

    UI displays these as "Guarantee Expiry" and "Guarantee Reminder Date".
    """
    expiry = sale_date + relativedelta(months=warranty_months)
    reminder = sale_date + relativedelta(months=12)
    return expiry, reminder


def _require_battery(db: Client, battery_id: str) -> dict:
    result = (
        db.table("batteries")
        .select("*")
        .eq("id", battery_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Battery {battery_id} not found",
        )
    return result.data


# ---------------------------------------------------------------------------
# Read operations
# ---------------------------------------------------------------------------

def get_all_batteries(
    db: Client,
    search: str = "",
    customer_id: str = "",
    page: int = 1,
    limit: int = 20,
    archived: bool = False,
) -> dict:
    """Search batteries by model_number or serial_number. Filter by customer."""
    query = (
        db.table("batteries")
        .select("*", count="exact")
        .eq("is_archived", archived)
    )

    if customer_id:
        query = query.eq("customer_id", customer_id)

    if search:
        term = _sanitize_search(search)
        if term:
            query = query.or_(
                f"model_number.ilike.%{term}%,"
                f"serial_number.ilike.%{term}%"
            )

    offset = (page - 1) * limit
    result = (
        query
        .order("sale_date", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )

    return {
        "data": [BatteryResponse.from_row(r) for r in (result.data or [])],
        "total": result.count or 0,
        "page": page,
        "limit": limit,
    }


def get_battery_by_id(db: Client, battery_id: str) -> BatteryResponse:
    return BatteryResponse.from_row(_require_battery(db, battery_id))


# ---------------------------------------------------------------------------
# Write operations
# ---------------------------------------------------------------------------

def create_battery(
    db: Client, data: BatteryCreate, device: str = "desktop"
) -> dict:
    """
    Insert battery. Auto-computes warranty_expiry and warranty_reminder_date.
    Serial number is already normalized by Pydantic validator.
    """
    expiry, reminder = _compute_dates(data.sale_date, data.warranty_months)

    # Exclude auto_reduce_stock from database insertion payload
    dump = data.model_dump()
    auto_reduce = dump.pop("auto_reduce_stock", True)

    payload = {
        **dump,
        "sale_date": data.sale_date.isoformat(),
        "warranty_expiry": expiry.isoformat(),
        "warranty_reminder_date": reminder.isoformat(),
    }

    result = db.table("batteries").insert(payload).execute()
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create battery record",
        )

    # Auto-reduce stock if requested and a matching model exists
    if auto_reduce and data.model_number:
        try:
            model_name = data.model_number.strip().upper()
            b_type = data.battery_type.strip().upper()
            
            stock_res = (
                db.table("battery_stock")
                .select("*")
                .eq("model_name", model_name)
                .eq("battery_type", b_type)
                .eq("is_archived", False)
                .execute()
            )
            
            if stock_res.data:
                stock_row = stock_res.data[0]
                current_qty = stock_row["quantity"]
                if current_qty > 0:
                    new_qty = current_qty - 1
                    db.table("battery_stock").update({"quantity": new_qty, "updated_at": "now()"}).eq("id", stock_row["id"]).execute()
                    _log(db, f"STOCK_AUTO_DECREASED: {model_name} ({b_type})", device)
        except Exception:
            # Do NOT fail battery registration if stock reduction fails
            pass

    # Auto-schedule reminders for the battery
    try:
        from app.services.reminder import schedule_reminders_for_battery
        cust_res = db.table("customers").select("*").eq("id", data.customer_id).single().execute()
        if cust_res.data:
            schedule_reminders_for_battery(db, result.data[0], cust_res.data)
    except Exception:
        # Do NOT fail battery registration if reminder scheduling fails
        pass

    created = BatteryResponse.from_row(result.data[0])
    _log(db, f"BATTERY_ADDED: {data.serial_number or data.model_number}", device)
    return {"message": "Battery added successfully", "data": created}


def update_battery(
    db: Client, battery_id: str, data: BatteryUpdate, device: str = "desktop"
) -> dict:
    """
    Update battery fields. Recomputes dates if sale_date or warranty_months change.
    """
    existing = _require_battery(db, battery_id)
    updates = {k: v for k, v in data.model_dump().items() if v is not None}

    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    # Detect if any reminder-triggering fields changed:
    trigger_fields = ["sale_date", "warranty_months", "service_reminder_interval_months", "water_check_interval_months", "battery_type"]
    any_trigger_changed = False
    for f in trigger_fields:
        if f in updates:
            val_existing = existing.get(f)
            val_new = updates[f]
            if f == "sale_date" and val_existing:
                val_new_str = val_new.isoformat() if hasattr(val_new, "isoformat") else str(val_new)
                val_existing_str = str(val_existing)[:10]
                if val_new_str != val_existing_str:
                    any_trigger_changed = True
            else:
                if str(val_new) != str(val_existing):
                    any_trigger_changed = True

    # Recompute dates if either sale_date or warranty_months changed
    if "sale_date" in updates or "warranty_months" in updates:
        sale_date = updates.get("sale_date") or date.fromisoformat(str(existing["sale_date"]))
        warranty_months = updates.get("warranty_months") or existing["warranty_months"]
        if isinstance(sale_date, str):
            sale_date = date.fromisoformat(sale_date)
        expiry, reminder = _compute_dates(sale_date, warranty_months)
        updates["warranty_expiry"] = expiry.isoformat()
        updates["warranty_reminder_date"] = reminder.isoformat()

    # Serialize date fields to ISO strings for Supabase
    if "sale_date" in updates and isinstance(updates["sale_date"], date):
        updates["sale_date"] = updates["sale_date"].isoformat()

    result = db.table("batteries").update(updates).eq("id", battery_id).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update battery")

    if any_trigger_changed:
        try:
            # Delete uncompleted reminders
            db.table("service_reminders").delete().eq("battery_id", battery_id).eq("is_completed", False).execute()
            
            # Fetch customer to supply to the scheduling function
            cust_res = db.table("customers").select("*").eq("id", result.data[0]["customer_id"]).single().execute()
            if cust_res.data:
                from app.services.reminder import schedule_reminders_for_battery
                schedule_reminders_for_battery(db, result.data[0], cust_res.data)
        except Exception:
            pass

    updated = BatteryResponse.from_row(result.data[0])
    _log(db, f"BATTERY_UPDATED: {battery_id}", device)
    return {"message": "Battery updated successfully", "data": updated}


def archive_battery(db: Client, battery_id: str, device: str = "desktop") -> dict:
    _require_battery(db, battery_id)
    db.table("batteries").update({"is_archived": True}).eq("id", battery_id).execute()
    _log(db, f"BATTERY_ARCHIVED: {battery_id}", device)
    return {"message": "Battery archived successfully"}


def delete_battery_permanently(db: Client, battery_id: str, device: str = "desktop") -> dict:
    """Hard-delete battery and all associated payments."""
    db.table("payments").delete().eq("battery_id", battery_id).execute()
    db.table("batteries").delete().eq("id", battery_id).execute()
    _log(db, f"BATTERY_PERMANENTLY_DELETED: {battery_id}", device)
    return {"message": "Battery permanently deleted successfully"}
