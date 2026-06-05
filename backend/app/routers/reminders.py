from fastapi import APIRouter, Depends, Query, Header, status
from supabase import Client

from app.database import get_db
from app.auth import get_current_admin
from app.models.reminder import (
    ReminderCreate,
    ReminderUpdate,
    ReminderResponse,
    ReminderListResponse,
    ReminderStatsResponse
)
from app.services.reminder import (
    get_all_reminders,
    get_reminder_by_id,
    get_reminder_stats,
    create_manual_reminder,
    update_reminder,
    delete_reminder_permanently,
    process_daily_reminders_batch
)

router = APIRouter(prefix="/reminders", tags=["reminders"])


@router.get("", response_model=ReminderListResponse)
def list_reminders(
    search: str = Query("", description="Search by customer name, mobile, model, or serial"),
    status_filter: str = Query("", alias="status", description="Filter by status (UPCOMING, DUE, OVERDUE, COMPLETED, EXPIRED)"),
    type_filter: str = Query("", alias="type", description="Filter by reminder type (WATER_CHECK, SERVICE, WARRANTY, UDHARI)"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1),
    archived: bool = Query(False),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return get_all_reminders(
        db, search=search, status_filter=status_filter, type_filter=type_filter, page=page, limit=limit, archived=archived
    )


@router.get("/stats", response_model=ReminderStatsResponse)
def read_reminder_stats(
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return get_reminder_stats(db)


@router.get("/{reminder_id}", response_model=ReminderResponse)
def read_reminder(
    reminder_id: str,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    return get_reminder_by_id(db, reminder_id)


@router.post("", response_model=dict, status_code=status.HTTP_201_CREATED)
def create_reminder(
    data: ReminderCreate,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    res = create_manual_reminder(db, data, device=x_device_type)
    return res


@router.put("/{reminder_id}", response_model=dict)
def update_reminder_item(
    reminder_id: str,
    data: ReminderUpdate,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    res = update_reminder(db, reminder_id, data, device=x_device_type)
    return res


@router.delete("/{reminder_id}", response_model=dict)
def delete_reminder(
    reminder_id: str,
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    res = delete_reminder_permanently(db, reminder_id, device=x_device_type)
    return res


@router.get("/{reminder_id}/render-message")
def render_reminder_message(
    reminder_id: str,
    channel: str = Query("whatsapp", description="The communication channel: whatsapp or sms"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """
    Renders the active message template for a specific reminder dynamically.
    Injects variables (customer_name, battery_model, pending_amount, etc.) and shop settings.
    """
    from app.services.reminder import _require_reminder
    from app.services.template_engine import render_message
    
    row = _require_reminder(db, reminder_id)
    r_type = row["reminder_type"]
    
    # Map reminder_type to template_type
    base_type = r_type
    if r_type == "SERVICE":
        base_type = "SERVICE_REMINDER"
        
    if channel.lower() == "sms":
        template_type = f"SMS_{base_type}"
    else:
        template_type = base_type
        
    context = {
        "customer_name": row["customer_name"],
        "mobile_number": row["mobile_number"],
        "battery_model": row.get("battery_model") or "",
        "battery_serial": row.get("battery_serial") or "",
        "battery_type": row.get("battery_type") or "",
        "expiry_date": str(row["warranty_expiry"]) if row.get("warranty_expiry") else "",
        "pending_amount": ""
    }
    
    if r_type == "UDHARI_RECOVERY" or row.get("reminder_category") == "UDHARI":
        pay_id = row.get("linked_payment_id")
        if pay_id:
            try:
                p_res = db.table("payments").select("pending_amount").eq("id", pay_id).single().execute()
                if p_res.data:
                    context["pending_amount"] = str(p_res.data["pending_amount"])
            except Exception:
                pass

    _, rendered_body = render_message(db, template_type, context)
    return {
        "channel": channel.upper(),
        "template_type": template_type,
        "message_body": rendered_body
    }


@router.delete("", response_model=dict)
def delete_all_reminders_route(
    reminder_type: str = Query("", alias="type", description="Optional filter by type to delete"),
    x_device_type: str = Header("desktop"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    from app.services.reminder import delete_all_reminders
    res = delete_all_reminders(db, reminder_type=reminder_type, device=x_device_type)
    return res



@router.post("/trigger-daily", response_model=dict)
def run_daily_batch(
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """Manually triggers the daily reminder check batch process."""
    return process_daily_reminders_batch(db)
