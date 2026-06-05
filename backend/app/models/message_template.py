from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Message Template Models
# ---------------------------------------------------------------------------

class MessageTemplateUpdate(BaseModel):
    message_subject: Optional[str] = None
    message_body: Optional[str] = None
    is_active: Optional[bool] = None


class MessageTemplateResponse(BaseModel):
    id: str
    template_name: str
    template_type: str
    message_subject: Optional[str]
    message_body: str
    is_active: bool
    version_no: int
    created_at: str
    updated_at: str

    @classmethod
    def from_row(cls, row: dict) -> "MessageTemplateResponse":
        return cls(
            id=str(row["id"]),
            template_name=row["template_name"],
            template_type=row["template_type"],
            message_subject=row.get("message_subject"),
            message_body=row["message_body"],
            is_active=row.get("is_active", True),
            version_no=row.get("version_no", 1),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row.get("updated_at", ""))
        )


class MessageTemplateVersionResponse(BaseModel):
    id: str
    template_id: str
    version_no: int
    message_subject: Optional[str]
    message_body: str
    created_at: str

    @classmethod
    def from_row(cls, row: dict) -> "MessageTemplateVersionResponse":
        return cls(
            id=str(row["id"]),
            template_id=str(row["template_id"]),
            version_no=row["version_no"],
            message_subject=row.get("message_subject"),
            message_body=row["message_body"],
            created_at=str(row.get("created_at", ""))
        )


# ---------------------------------------------------------------------------
# Message Log Models
# ---------------------------------------------------------------------------

class MessageLogCreate(BaseModel):
    customer_name: str
    mobile_number: str
    channel: str  # 'SMS', 'WHATSAPP', 'EMAIL'
    message_type: str
    message_body: str
    status: str = "SENT"
    provider_id: Optional[str] = None

    @field_validator("channel")
    @classmethod
    def validate_channel(cls, v: str) -> str:
        allowed = {"SMS", "WHATSAPP", "EMAIL"}
        upper = v.strip().upper()
        if upper not in allowed:
            raise ValueError(f"channel must be one of: {allowed}")
        return upper


class MessageLogResponse(BaseModel):
    id: str
    customer_name: str
    mobile_number: str
    channel: str
    message_type: str
    message_body: str
    status: str
    sent_at: str
    provider_id: Optional[str]

    @classmethod
    def from_row(cls, row: dict) -> "MessageLogResponse":
        return cls(
            id=str(row["id"]),
            customer_name=row["customer_name"],
            mobile_number=row["mobile_number"],
            channel=row["channel"],
            message_type=row["message_type"],
            message_body=row["message_body"],
            status=row["status"],
            sent_at=str(row.get("sent_at", "")),
            provider_id=row.get("provider_id")
        )


class MessageLogListResponse(BaseModel):
    data: List[MessageLogResponse]
    total: int
    page: int
    limit: int


# ---------------------------------------------------------------------------
# Shop Settings Models
# ---------------------------------------------------------------------------

class ShopSettingsUpdate(BaseModel):
    shop_name: Optional[str] = None
    shop_address: Optional[str] = None
    shop_mobile: Optional[str] = None
    whatsapp_number: Optional[str] = None
    gst_number: Optional[str] = None
    logo_url: Optional[str] = None
    backup_email: Optional[str] = None
    sms_sender_name: Optional[str] = None


class ShopSettingsResponse(BaseModel):
    id: str
    shop_name: str
    shop_address: str
    shop_mobile: str
    whatsapp_number: str
    gst_number: Optional[str]
    logo_url: Optional[str]
    backup_email: str
    sms_sender_name: str
    created_at: str
    updated_at: str

    @classmethod
    def from_row(cls, row: dict) -> "ShopSettingsResponse":
        return cls(
            id=str(row["id"]),
            shop_name=row["shop_name"],
            shop_address=row["shop_address"],
            shop_mobile=row["shop_mobile"],
            whatsapp_number=row["whatsapp_number"],
            gst_number=row.get("gst_number"),
            logo_url=row.get("logo_url"),
            backup_email=row["backup_email"],
            sms_sender_name=row["sms_sender_name"],
            created_at=str(row.get("created_at", "")),
            updated_at=str(row.get("updated_at", ""))
        )
