from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class ReminderCreate(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    customer_id: Optional[str] = None
    battery_id: Optional[str] = None
    customer_name: str
    mobile_number: str
    battery_model: Optional[str] = None
    battery_serial: Optional[str] = None
    battery_type: Optional[str] = None
    reminder_type: str  # 'WATER_CHECK', 'SERVICE', 'WARRANTY_EXPIRY', 'UDHARI'
    reminder_date: date
    warranty_expiry: Optional[date] = None
    notes: Optional[str] = None
    whatsapp_template: Optional[str] = None
    reminder_category: Optional[str] = 'BATTERY'
    linked_payment_id: Optional[str] = None
    recurring_interval_days: Optional[int] = 7
    stop_when_settled: Optional[bool] = True

    @field_validator("reminder_type")
    @classmethod
    def validate_reminder_type(cls, v: str) -> str:
        allowed = {"WATER_CHECK", "SERVICE", "WARRANTY_EXPIRY", "UDHARI", "UDHARI_RECOVERY"}
        upper = v.strip().upper()
        if upper not in allowed:
            raise ValueError(f"reminder_type must be one of: {allowed}")
        return upper


class ReminderUpdate(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    customer_name: Optional[str] = None
    mobile_number: Optional[str] = None
    battery_model: Optional[str] = None
    battery_serial: Optional[str] = None
    battery_type: Optional[str] = None
    reminder_date: Optional[date] = None
    warranty_expiry: Optional[date] = None
    is_completed: Optional[bool] = None
    notes: Optional[str] = None
    message_sent: Optional[bool] = None
    sent_at: Optional[datetime] = None
    whatsapp_template: Optional[str] = None
    whatsapp_delivery_status: Optional[str] = None
    whatsapp_message_id: Optional[str] = None


# ---------------------------------------------------------------------------
# Response model
# ---------------------------------------------------------------------------

class ReminderResponse(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    id: str
    customer_id: Optional[str]
    battery_id: Optional[str]
    customer_name: str
    mobile_number: str
    battery_model: Optional[str]
    battery_serial: Optional[str]
    battery_type: Optional[str]
    reminder_type: str
    reminder_date: str
    warranty_expiry: Optional[str]
    reminder_status: str
    message_sent: bool
    sent_at: Optional[str]
    is_completed: bool
    is_archived: bool
    notes: Optional[str]
    whatsapp_template: Optional[str]
    whatsapp_delivery_status: str
    whatsapp_message_id: Optional[str]
    created_at: str
    updated_at: Optional[str] = None
    reminder_category: Optional[str] = 'BATTERY'
    linked_payment_id: Optional[str] = None
    recurring_interval_days: Optional[int] = 7
    stop_when_settled: Optional[bool] = True

    @classmethod
    def from_row(cls, row: dict) -> "ReminderResponse":
        # Calculate reminder_status dynamically based on date rules
        is_completed = row.get("is_completed", False)
        reminder_date_str = str(row["reminder_date"])
        warranty_expiry_str = str(row["warranty_expiry"]) if row.get("warranty_expiry") else None

        status_val = "UPCOMING"
        if is_completed:
            status_val = "COMPLETED"
        else:
            today = date.today()
            rem_date = date.fromisoformat(reminder_date_str)
            if rem_date > today:
                status_val = "UPCOMING"
            elif rem_date == today:
                status_val = "DUE"
            else:  # rem_date < today
                if warranty_expiry_str:
                    expiry = date.fromisoformat(warranty_expiry_str)
                    if expiry < today:
                        status_val = "EXPIRED"
                    else:
                        status_val = "OVERDUE"
                else:
                    status_val = "OVERDUE"

        return cls(
            id=str(row["id"]),
            customer_id=str(row["customer_id"]) if row.get("customer_id") else None,
            battery_id=str(row["battery_id"]) if row.get("battery_id") else None,
            customer_name=row["customer_name"],
            mobile_number=row["mobile_number"],
            battery_model=row.get("battery_model"),
            battery_serial=row.get("battery_serial"),
            battery_type=row.get("battery_type"),
            reminder_type=row["reminder_type"],
            reminder_date=reminder_date_str,
            warranty_expiry=warranty_expiry_str,
            reminder_status=status_val,
            message_sent=row.get("message_sent", False),
            sent_at=str(row["sent_at"]) if row.get("sent_at") else None,
            is_completed=is_completed,
            is_archived=row.get("is_archived", False),
            notes=row.get("notes"),
            whatsapp_template=row.get("whatsapp_template"),
            whatsapp_delivery_status=row.get("whatsapp_delivery_status", "PENDING"),
            whatsapp_message_id=row.get("whatsapp_message_id"),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row["updated_at"]) if row.get("updated_at") else None,
            reminder_category=row.get("reminder_category", "BATTERY"),
            linked_payment_id=str(row["linked_payment_id"]) if row.get("linked_payment_id") else None,
            recurring_interval_days=row.get("recurring_interval_days", 7),
            stop_when_settled=row.get("stop_when_settled", True),
        )


class ReminderListResponse(BaseModel):
    data: list[ReminderResponse]
    total: int
    page: int
    limit: int


class ReminderStatsResponse(BaseModel):
    today_followups: int
    upcoming_expiry: int
    water_checks_due: int
    pending_service: int
    completed: int
