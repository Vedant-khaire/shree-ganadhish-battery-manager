from datetime import date, datetime, timedelta
from dateutil.relativedelta import relativedelta
from fastapi import HTTPException, status
from supabase import Client

from app.models.reminder import ReminderCreate, ReminderUpdate, ReminderResponse


# ---------------------------------------------------------------------------
# Helpers & Internal Logging
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str = "system") -> None:
    try:
        db.table("activity_logs").insert({"action": action, "device": device}).execute()
    except Exception:
        pass


def _require_reminder(db: Client, reminder_id: str) -> dict:
    result = (
        db.table("service_reminders")
        .select("*")
        .eq("id", reminder_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Reminder {reminder_id} not found",
        )
    return result.data


# ---------------------------------------------------------------------------
# Dynamic Render-at-Read Helper
# ---------------------------------------------------------------------------

def populate_rendered_templates(db: Client, rows: list) -> list:
    """
    Renders message template bodies on-the-fly dynamically.
    Ensures no templates are hardcoded or permanently stored inside database rows.
    """
    if not rows:
        return rows
    
    from app.services.template_engine import get_shop_settings, get_active_template, _replace_vars
    
    # 1. Fetch shop profile & active templates once to avoid N+1 queries
    shop = get_shop_settings(db)
    
    templates = {}
    for t_type in ("SERVICE_REMINDER", "WATER_CHECK", "WARRANTY_EXPIRY", "UDHARI_RECOVERY"):
        templates[t_type] = get_active_template(db, t_type)
        
    # Collect all unique payment IDs to fetch in a single query
    pay_ids = list({r["linked_payment_id"] for r in rows if r.get("linked_payment_id")})
    payments_map = {}
    if pay_ids:
        try:
            pay_res = db.table("payments").select("id, pending_amount").in_("id", pay_ids).execute()
            if pay_res.data:
                payments_map = {p["id"]: str(p["pending_amount"]) for p in pay_res.data}
        except Exception:
            pass
        
    for r in rows:
        r_type = r["reminder_type"]
        template_type = r_type
        if r_type == "SERVICE":
            template_type = "SERVICE_REMINDER"
            
        context = {
            "customer_name": r["customer_name"],
            "mobile_number": r["mobile_number"],
            "battery_model": r.get("battery_model") or "",
            "battery_serial": r.get("battery_serial") or "",
            "battery_type": r.get("battery_type") or "",
            "expiry_date": str(r["warranty_expiry"]) if r.get("warranty_expiry") else "",
            "pending_amount": ""
        }
        
        # If Udhari template type, get payment pending_amount dynamically from pre-fetched map
        if r_type == "UDHARI_RECOVERY" or r.get("reminder_category") == "UDHARI":
            pay_id = r.get("linked_payment_id")
            if pay_id and pay_id in payments_map:
                context["pending_amount"] = payments_map[pay_id]
                    
        # Render template body dynamically in memory using the pre-fetched templates and shop settings
        subj_tmpl, body_tmpl = templates.get(template_type, (None, ""))
        
        # Merge shop variables with customer context
        merged_context = {**shop, **context}
        rendered_body = _replace_vars(body_tmpl, merged_context) if body_tmpl else ""
        
        r["whatsapp_template"] = rendered_body
        
    return rows


# ---------------------------------------------------------------------------
# Status Sync Logic
# ---------------------------------------------------------------------------

def update_reminder_statuses(db: Client) -> None:
    """Syncs status field in database for uncompleted reminders based on date rules."""
    today = date.today().isoformat()

    # 1. Any uncompleted reminder where reminder_date > today -> UPCOMING
    db.table("service_reminders").update({"reminder_status": "UPCOMING"}).eq("is_completed", False).gt("reminder_date", today).execute()

    # 2. Any uncompleted reminder where reminder_date = today -> DUE
    db.table("service_reminders").update({"reminder_status": "DUE"}).eq("is_completed", False).eq("reminder_date", today).execute()

    # 3. Any uncompleted reminder where reminder_date < today and warranty has expired -> EXPIRED
    db.table("service_reminders").update({"reminder_status": "EXPIRED"}).eq("is_completed", False).lt("reminder_date", today).lt("warranty_expiry", today).execute()

    # 4. Any uncompleted reminder where reminder_date < today and warranty is not expired (or null) -> OVERDUE
    db.table("service_reminders").update({"reminder_status": "OVERDUE"}).eq("is_completed", False).lt("reminder_date", today).gte("warranty_expiry", today).execute()


# ---------------------------------------------------------------------------
# Auto-scheduling Rules
# ---------------------------------------------------------------------------

def schedule_reminders_for_battery(db: Client, battery: dict, customer: dict) -> list:
    """Automatically schedules service and warranty reminders with empty templates (render-at-dispatch)."""
    sale_date = date.fromisoformat(str(battery["sale_date"]))
    expiry_date = date.fromisoformat(str(battery["warranty_expiry"]))
    warranty_months = int(battery["warranty_months"])
    b_type = str(battery["battery_type"]).upper()

    reminders = []

    # 1. Custom Water Check Reminders (Inverter only)
    if b_type == "INVERTER":
        if "water_check_interval_months" in battery:
            water_interval = battery["water_check_interval_months"]
        else:
            water_interval = 6
        
        if water_interval and water_interval > 0:
            for m in range(water_interval, warranty_months + 1, water_interval):
                r_date = sale_date + relativedelta(months=m)
                reminders.append({
                    "type": "WATER_CHECK",
                    "date": r_date,
                    "note": f"Scheduled distilled water level check ({m}-month interval)."
                })

    # 2. Custom Service Reminders (All batteries)
    if "service_reminder_interval_months" in battery:
        service_interval = battery["service_reminder_interval_months"]
    else:
        service_interval = 12
        
    if service_interval and service_interval > 0:
        for m in range(service_interval, warranty_months + 1, service_interval):
            r_date = sale_date + relativedelta(months=m)
            reminders.append({
                "type": "SERVICE",
                "date": r_date,
                "note": f"Scheduled regular maintenance service check ({m}-month interval)."
            })

    # 3. Warranty Expiry Reminder (exactly 5 days before warranty expiry date)
    expiry_rem_date = expiry_date - timedelta(days=5)
    if expiry_rem_date > sale_date:
        reminders.append({
            "type": "WARRANTY_EXPIRY",
            "date": expiry_rem_date,
            "note": "Guarantee expiry warning (5 days before expiration)."
        })

    inserted_records = []
    today = date.today()

    for r in reminders:
        rem_date = r["date"]

        status_val = "UPCOMING"
        if rem_date > today:
            status_val = "UPCOMING"
        elif rem_date == today:
            status_val = "DUE"
        else:
            if expiry_date < today:
                status_val = "EXPIRED"
            else:
                status_val = "OVERDUE"

        payload = {
            "customer_id": battery["customer_id"],
            "battery_id": battery["id"],
            "customer_name": customer["name"],
            "mobile_number": customer["mobile"],
            "battery_model": battery.get("model_number") or "",
            "battery_serial": battery.get("serial_number") or "",
            "battery_type": b_type,
            "reminder_type": r["type"],
            "reminder_date": rem_date.isoformat(),
            "warranty_expiry": expiry_date.isoformat(),
            "reminder_status": status_val,
            "is_completed": False,
            "is_archived": False,
            "notes": r["note"],
            "whatsapp_template": None,  # Do not store pre-rendered text in DB
            "whatsapp_delivery_status": "PENDING"
        }

        res = db.table("service_reminders").insert(payload).execute()
        if res.data:
            inserted_records.append(res.data[0])

    return inserted_records


# ---------------------------------------------------------------------------
# Read Operations
# ---------------------------------------------------------------------------

def get_all_reminders(
    db: Client,
    search: str = "",
    status_filter: str = "",
    type_filter: str = "",
    page: int = 1,
    limit: int = 20,
    archived: bool = False,
) -> dict:
    """Query, filter, and paginate reminder records with dynamically prefilled messages."""
    try:
        update_reminder_statuses(db)
    except Exception:
        pass

    query = (
        db.table("service_reminders")
        .select("*", count="exact")
        .eq("is_archived", archived)
    )

    if status_filter:
        query = query.eq("reminder_status", status_filter.upper())

    if type_filter:
        tf = type_filter.upper()
        if tf == "WARRANTY":
            query = query.eq("reminder_type", "WARRANTY_EXPIRY")
        elif tf == "UDHARI" or tf == "UDHARI_RECOVERY":
            query = query.in_("reminder_type", ["UDHARI", "UDHARI_RECOVERY"])
        else:
            query = query.eq("reminder_type", tf)

    if search:
        term = search.strip()
        if term:
            query = query.or_(
                f"customer_name.ilike.%{term}%,"
                f"mobile_number.ilike.%{term}%,"
                f"battery_model.ilike.%{term}%,"
                f"battery_serial.ilike.%{term}%"
            )

    offset = (page - 1) * limit
    result = (
        query
        .order("reminder_date", desc=False)
        .range(offset, offset + limit - 1)
        .execute()
    )

    populated_rows = populate_rendered_templates(db, result.data or [])
    return {
        "data": [ReminderResponse.from_row(r) for r in populated_rows],
        "total": result.count or 0,
        "page": page,
        "limit": limit,
    }


def get_reminder_by_id(db: Client, reminder_id: str) -> ReminderResponse:
    row = _require_reminder(db, reminder_id)
    populated = populate_rendered_templates(db, [row])
    return ReminderResponse.from_row(populated[0])


def get_reminder_stats(db: Client) -> dict:
    """Returns analytics aggregates for the reminders dashboard."""
    try:
        update_reminder_statuses(db)
    except Exception:
        pass

    res_uncompleted = (
        db.table("service_reminders")
        .select("reminder_type, reminder_status")
        .eq("is_completed", False)
        .eq("is_archived", False)
        .execute()
    )

    res_completed = (
        db.table("service_reminders")
        .select("id", count="exact")
        .eq("is_completed", True)
        .eq("is_archived", False)
        .execute()
    )
    completed_count = res_completed.count or 0

    today_followups = 0
    upcoming_expiry = 0
    water_checks_due = 0
    pending_service = 0
    overdue_count = 0

    for r in (res_uncompleted.data or []):
        stat = r["reminder_status"]
        rtype = r["reminder_type"]

        if stat == "DUE":
            today_followups += 1
        elif stat == "OVERDUE":
            overdue_count += 1

        if rtype == "WARRANTY_EXPIRY":
            upcoming_expiry += 1
        elif rtype == "WATER_CHECK" and stat in ("DUE", "OVERDUE"):
            water_checks_due += 1
        elif rtype == "SERVICE" and stat in ("DUE", "OVERDUE"):
            pending_service += 1

    return {
        "today_followups": today_followups,
        "overdue_count": overdue_count,
        "upcoming_expiry": upcoming_expiry,
        "water_checks_due": water_checks_due,
        "pending_service": pending_service,
        "completed": completed_count
    }


# ---------------------------------------------------------------------------
# Write Operations
# ---------------------------------------------------------------------------

def create_manual_reminder(db: Client, data: ReminderCreate, device: str = "desktop") -> dict:
    payload = data.model_dump()
    
    if isinstance(payload.get("reminder_date"), date):
        payload["reminder_date"] = payload["reminder_date"].isoformat()
    if isinstance(payload.get("warranty_expiry"), date):
        payload["warranty_expiry"] = payload["warranty_expiry"].isoformat()

    today = date.today()
    rem_date = data.reminder_date
    status_val = "UPCOMING"
    if rem_date > today:
        status_val = "UPCOMING"
    elif rem_date == today:
        status_val = "DUE"
    else:
        if data.warranty_expiry and data.warranty_expiry < today:
            status_val = "EXPIRED"
        else:
            status_val = "OVERDUE"
            
    payload["reminder_status"] = status_val
    payload["is_completed"] = False
    payload["is_archived"] = False
    payload["whatsapp_template"] = None  # Force empty to ensure render-at-dispatch

    result = db.table("service_reminders").insert(payload).execute()
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create manual reminder",
        )

    # Populates before responding
    populated = populate_rendered_templates(db, result.data)
    created = ReminderResponse.from_row(populated[0])
    _log(db, f"REMINDER_MANUAL_CREATED: {created.customer_name}", device)
    return {"message": "Reminder created successfully", "data": created}


def update_reminder(db: Client, reminder_id: str, data: ReminderUpdate, device: str = "desktop") -> dict:
    current = _require_reminder(db, reminder_id)
    updates = {k: v for k, v in data.model_dump().items() if v is not None}
    
    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    if "reminder_date" in updates and isinstance(updates["reminder_date"], date):
        updates["reminder_date"] = updates["reminder_date"].isoformat()
    if "warranty_expiry" in updates and isinstance(updates["warranty_expiry"], date):
        updates["warranty_expiry"] = updates["warranty_expiry"].isoformat()
    if "sent_at" in updates and hasattr(updates["sent_at"], "isoformat"):
        updates["sent_at"] = updates["sent_at"].isoformat()

    result = db.table("service_reminders").update(updates).eq("id", reminder_id).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update reminder")

    try:
        update_reminder_statuses(db)
    except Exception:
        pass

    # Dynamic WhatsApp Sent log entry
    if updates.get("message_sent") is True and not current.get("message_sent"):
        try:
            from app.services.template_engine import log_message
            populated = populate_rendered_templates(db, [result.data[0]])
            body = populated[0].get("whatsapp_template") or ""
            log_message(
                db,
                customer_name=result.data[0]["customer_name"],
                mobile_number=result.data[0]["mobile_number"],
                channel="WHATSAPP",
                message_type=result.data[0]["reminder_type"],
                message_body=body,
                status="SENT"
            )
        except Exception:
            pass

    # If Udhari reminder is completed, schedule the next one dynamically
    if updates.get("is_completed") is True:
        try:
            category_val = result.data[0].get("reminder_category")
            type_val = result.data[0].get("reminder_type")
            if category_val in ("UDHARI", "UDHARI_RECOVERY") or type_val in ("UDHARI", "UDHARI_RECOVERY"):
                pay_id = result.data[0].get("linked_payment_id")
                if pay_id:
                    schedule_udhari_reminders(db, pay_id)
        except Exception:
            pass

    # Populates before responding
    populated = populate_rendered_templates(db, result.data)
    updated = ReminderResponse.from_row(populated[0])

    if updates.get("is_completed") is True:
        _log(db, f"REMINDER_COMPLETED: {reminder_id}", device)
    else:
        _log(db, f"REMINDER_UPDATED: {reminder_id}", device)
    return {"message": "Reminder updated successfully", "data": updated}


def delete_reminder_permanently(db: Client, reminder_id: str, device: str = "desktop") -> dict:
    _require_reminder(db, reminder_id)
    db.table("service_reminders").delete().eq("id", reminder_id).execute()
    _log(db, f"REMINDER_DELETED: {reminder_id}", device)
    return {"message": "Reminder permanently deleted successfully"}


def delete_all_reminders(db: Client, reminder_type: str = "", device: str = "desktop") -> dict:
    if reminder_type and reminder_type != "ALL":
        db.table("service_reminders").delete().eq("reminder_type", reminder_type).execute()
        message = f"All {reminder_type} reminders permanently deleted successfully"
        _log(db, f"ALL_REMINDERS_DELETED_BY_TYPE: {reminder_type}", device)
    else:
        db.table("service_reminders").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
        message = "All reminders permanently deleted successfully"
        _log(db, "ALL_REMINDERS_DELETED", device)
    return {"message": message}


def process_daily_reminders_batch(db: Client) -> dict:
    """
    Daily batch processor. Checks for uncompleted reminders and syncs their status columns dynamically.
    """
    try:
        update_reminder_statuses(db)
    except Exception:
        pass

    today = date.today().isoformat()
    _log(db, "DAILY_REMINDERS_BATCH_RUN")
    return {
        "date": today,
        "message": "Daily reminder statuses synced successfully."
    }


def schedule_udhari_reminders(db: Client, payment_id: str) -> None:
    """Schedules/regenerates Udhari collection reminders with empty templates (render-at-dispatch)."""
    pay_res = db.table("payments").select("*, customers(name, mobile)").eq("id", payment_id).single().execute()
    if not pay_res.data:
        return
    payment = pay_res.data

    if float(payment.get("pending_amount") or 0.0) <= 0 or payment.get("is_settled"):
        db.table("service_reminders").update({
            "is_completed": True,
            "notes": "Auto-completed: Payment settled"
        }).eq("linked_payment_id", payment_id).eq("is_completed", False).execute()
        return

    existing_res = db.table("service_reminders")\
        .select("reminder_date")\
        .eq("linked_payment_id", payment_id)\
        .eq("is_completed", False)\
        .order("reminder_date", desc=True)\
        .execute()

    uncompleted_reminders = existing_res.data or []
    uncompleted_count = len(uncompleted_reminders)

    if uncompleted_count >= 4:
        return

    created_at_str = payment.get("created_at") or date.today().isoformat()
    created_at_date = date.fromisoformat(created_at_str[:10])

    all_rem_res = db.table("service_reminders")\
        .select("reminder_date")\
        .eq("linked_payment_id", payment_id)\
        .order("reminder_date", desc=True)\
        .limit(1)\
        .execute()

    if all_rem_res.data:
        start_date = date.fromisoformat(all_rem_res.data[0]["reminder_date"])
    else:
        start_date = created_at_date

    reminders_to_create = 4 - uncompleted_count
    today = date.today()

    for i in range(1, reminders_to_create + 1):
        next_date = start_date + timedelta(days=7 * i)
        
        status_val = "UPCOMING"
        if next_date > today:
            status_val = "UPCOMING"
        elif next_date == today:
            status_val = "DUE"
        else:
            status_val = "OVERDUE"

        payload = {
            "customer_id": payment["customer_id"],
            "customer_name": payment["customers"]["name"],
            "mobile_number": payment["customers"]["mobile"],
            "reminder_type": "UDHARI_RECOVERY",
            "reminder_category": "UDHARI",
            "linked_payment_id": payment_id,
            "reminder_date": next_date.isoformat(),
            "reminder_status": status_val,
            "is_completed": False,
            "is_archived": False,
            "notes": f"Weekly Udhari recovery reminder ({next_date.isoformat()}).",
            "whatsapp_template": None,  # Dynamically rendered at read/dispatch time
            "whatsapp_delivery_status": "PENDING"
        }

        db.table("service_reminders").insert(payload).execute()
