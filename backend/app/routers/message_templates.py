from fastapi import APIRouter, Depends, HTTPException, Query, status
from typing import Optional, List
from supabase import Client
from app.database import get_db
from app.auth import get_current_admin
from app.models.message_template import (
    MessageTemplateUpdate,
    MessageTemplateResponse,
    MessageTemplateVersionResponse,
    MessageLogResponse,
    MessageLogListResponse,
    ShopSettingsUpdate,
    ShopSettingsResponse
)
from app.services.template_engine import (
    render_message,
    log_message,
    get_shop_settings,
    DEFAULT_TEMPLATES
)
import urllib.parse

router = APIRouter(
    prefix="/message-templates",
    tags=["Message Templates & Settings"],
)


# ---------------------------------------------------------------------------
# Message Template Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=List[MessageTemplateResponse])
def list_templates(db: Client = Depends(get_db), _: str = Depends(get_current_admin)):
    """Retrieve all message templates from the database."""
    res = db.table("message_templates").select("*").order("template_name", desc=False).execute()
    return [MessageTemplateResponse.from_row(row) for row in (res.data or [])]


# ---------------------------------------------------------------------------
# Message Logs Endpoints
# ---------------------------------------------------------------------------

@router.get("/logs", response_model=MessageLogListResponse)
def list_message_logs(
    channel: Optional[str] = Query(None, description="Filter by channel: WHATSAPP, SMS, EMAIL"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin)
):
    """Retrieve permanent archived log registries of outgoing dispatches."""
    query = db.table("message_logs").select("*", count="exact")
    if channel:
        query = query.eq("channel", channel.upper())

    offset = (page - 1) * limit
    res = query.order("sent_at", desc=True).range(offset, offset + limit - 1).execute()
    
    return {
        "data": [MessageLogResponse.from_row(row) for row in (res.data or [])],
        "total": res.count or 0,
        "page": page,
        "limit": limit
    }


# ---------------------------------------------------------------------------
# Shop Settings Endpoints
# ---------------------------------------------------------------------------

@router.get("/shop-settings", response_model=ShopSettingsResponse)
def read_shop_settings(db: Client = Depends(get_db), _: str = Depends(get_current_admin)):
    """Retrieve the single active shop profile configuration."""
    row = get_shop_settings(db)
    return ShopSettingsResponse.from_row(row)


@router.put("/shop-settings", response_model=ShopSettingsResponse)
def update_shop_settings(
    data: ShopSettingsUpdate,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin)
):
    """Update primary business profile settings (Name, Address, Mobile, backup email, etc.)."""
    updates = {k: v for k, v in data.model_dump().items() if v is not None}
    if not updates:
        row = get_shop_settings(db)
        return ShopSettingsResponse.from_row(row)

    res = db.table("shop_settings")\
        .update(updates)\
        .eq("id", "00000000-0000-0000-0000-000000000001")\
        .execute()
    if not res.data:
        raise HTTPException(status_code=500, detail="Failed to update shop settings")

    return ShopSettingsResponse.from_row(res.data[0])


# ---------------------------------------------------------------------------
# Message Template Endpoints (Dynamic/ID routes last)
# ---------------------------------------------------------------------------

@router.get("/{template_id}", response_model=MessageTemplateResponse)
def get_template(template_id: str, db: Client = Depends(get_db), _: str = Depends(get_current_admin)):
    """Retrieve single template details."""
    res = db.table("message_templates").select("*").eq("id", template_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Template not found")
    return MessageTemplateResponse.from_row(res.data[0])


@router.put("/{template_id}", response_model=MessageTemplateResponse)
def update_template(
    template_id: str,
    data: MessageTemplateUpdate,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin)
):
    """
    Update message template contents. Automatically tracks versioning:
    copies the previous configuration to history before updating.
    """
    # 1. Fetch current template state
    current_res = db.table("message_templates").select("*").eq("id", template_id).execute()
    if not current_res.data:
        raise HTTPException(status_code=404, detail="Template not found")
    current = current_res.data[0]

    updates = {}
    is_text_changed = False

    if data.is_active is not None:
        updates["is_active"] = data.is_active

    if data.message_subject is not None and data.message_subject != current.get("message_subject"):
        updates["message_subject"] = data.message_subject
        is_text_changed = True

    if data.message_body is not None and data.message_body != current["message_body"]:
        updates["message_body"] = data.message_body
        is_text_changed = True

    if not updates:
        return MessageTemplateResponse.from_row(current)

    # 2. If subject or body changed, store version history
    if is_text_changed:
        version_payload = {
            "template_id": template_id,
            "version_no": current["version_no"],
            "message_subject": current.get("message_subject"),
            "message_body": current["message_body"]
        }
        db.table("message_template_versions").insert(version_payload).execute()
        
        # Increment version number
        updates["version_no"] = current["version_no"] + 1

    # 3. Update active template in database
    update_res = db.table("message_templates").update(updates).eq("id", template_id).execute()
    if not update_res.data:
        raise HTTPException(status_code=500, detail="Failed to update template")

    return MessageTemplateResponse.from_row(update_res.data[0])


@router.get("/{template_id}/versions", response_model=List[MessageTemplateVersionResponse])
def get_template_versions(template_id: str, db: Client = Depends(get_db), _: str = Depends(get_current_admin)):
    """Retrieve version history log for a template."""
    res = db.table("message_template_versions")\
        .select("*")\
        .eq("template_id", template_id)\
        .order("version_no", desc=True)\
        .execute()
    return [MessageTemplateVersionResponse.from_row(row) for row in (res.data or [])]


@router.post("/{template_id}/restore", response_model=MessageTemplateResponse)
def restore_template(
    template_id: str,
    version_no: Optional[int] = Query(None, description="The version number to restore. If null/negative, restores default."),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin)
):
    """
    Restore template. Can restore to a previous database version
    or revert to the original factory default.
    """
    current_res = db.table("message_templates").select("*").eq("id", template_id).execute()
    if not current_res.data:
        raise HTTPException(status_code=404, detail="Template not found")
    current = current_res.data[0]

    restored_subject = None
    restored_body = ""

    if version_no is not None and version_no > 0:
        # Restore specific database version
        ver_res = db.table("message_template_versions")\
            .select("*")\
            .eq("template_id", template_id)\
            .eq("version_no", version_no)\
            .execute()
        if not ver_res.data:
            raise HTTPException(status_code=404, detail=f"Version {version_no} not found for this template")
        restored_subject = ver_res.data[0].get("message_subject")
        restored_body = ver_res.data[0]["message_body"]
    else:
        # Restore factory defaults
        default_pair = DEFAULT_TEMPLATES.get(current["template_type"])
        if not default_pair:
            raise HTTPException(status_code=400, detail="No factory default available for this template type")
        restored_subject, restored_body = default_pair

    # Save current config to history before restoring
    version_payload = {
        "template_id": template_id,
        "version_no": current["version_no"],
        "message_subject": current.get("message_subject"),
        "message_body": current["message_body"]
    }
    db.table("message_template_versions").insert(version_payload).execute()

    # Update template
    updates = {
        "message_subject": restored_subject,
        "message_body": restored_body,
        "version_no": current["version_no"] + 1
    }
    update_res = db.table("message_templates").update(updates).eq("id", template_id).execute()
    if not update_res.data:
        raise HTTPException(status_code=500, detail="Failed to restore template")

    return MessageTemplateResponse.from_row(update_res.data[0])


@router.post("/{template_id}/test")
def send_test_message(
    template_id: str,
    channel: str = Query(..., description="Only WHATSAPP is supported"),
    mobile_number: str = Query(..., description="Mobile number to receive test"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin)
):
    """
    Generates template preview with mock details and runs a test dispatch.
    Only WhatsApp is supported. SMS has been removed.
    """
    if channel.upper() != "WHATSAPP":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="SMS channel is disabled. Only WHATSAPP is supported."
        )

    current_res = db.table("message_templates").select("template_type").eq("id", template_id).execute()
    if not current_res.data:
        raise HTTPException(status_code=404, detail="Template not found")
    t_type = current_res.data[0]["template_type"]

    # Mock parameters context
    mock_context = {
        "customer_name": "Vedant Khaire (Test)",
        "mobile_number": mobile_number,
        "battery_model": "AMARON-AAM-PR-00050",
        "battery_serial": "AM20260601T",
        "battery_type": "INVERTER",
        "expiry_date": "2028-12-31",
        "pending_amount": "1250",
        "period_label": "2026-06",
        "timestamp": "2026-06-01 12:00:00"
    }

    # Render body
    _, rendered_body = render_message(db, t_type, mock_context)
    
    clean_mobile = mobile_number.replace("+", "").replace(" ", "")
    phone = f"91{clean_mobile}" if len(clean_mobile) == 10 else clean_mobile

    encoded_text = urllib.parse.quote(rendered_body)
    whatsapp_url = f"https://api.whatsapp.com/send?phone={phone}&text={encoded_text}"
    
    # Log mock dispatch
    log_message(db, "Test User", mobile_number, "WHATSAPP", t_type, rendered_body, "TEST_SENT")
    
    return {
        "channel": "WHATSAPP",
        "message_body": rendered_body,
        "whatsapp_url": whatsapp_url,
        "status": "success",
        "info": "WhatsApp test link generated. Copy the text or launch URL."
    }
