from datetime import date
from typing import Optional
from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class BatteryCreate(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    customer_id: str
    battery_type: str           # '2W', '4W', 'TRUCK', 'INVERTER'
    model_number: Optional[str] = None
    serial_number: Optional[str] = None
    sale_date: date
    warranty_months: int        # e.g. 12, 24, 36
    auto_reduce_stock: bool = True
    notes: Optional[str] = None
    service_reminder_interval_months: Optional[int] = None
    water_check_interval_months: Optional[int] = None

    @field_validator("battery_type")
    @classmethod
    def validate_battery_type(cls, v: str) -> str:
        allowed = {"2W", "4W", "TRUCK", "INVERTER"}
        upper = v.strip().upper()
        if upper not in allowed:
            raise ValueError(f"battery_type must be one of: {allowed}")
        return upper

    @field_validator("warranty_months")
    @classmethod
    def validate_warranty_months(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("warranty_months must be a positive integer")
        return v

    @field_validator("serial_number")
    @classmethod
    def normalize_serial(cls, v: Optional[str]) -> Optional[str]:
        """Trim and uppercase serial number before storing."""
        if v is None:
            return v
        normalized = v.strip().upper()
        return normalized if normalized else None


class BatteryUpdate(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    battery_type: Optional[str] = None
    model_number: Optional[str] = None
    serial_number: Optional[str] = None
    sale_date: Optional[date] = None
    warranty_months: Optional[int] = None
    notes: Optional[str] = None
    is_followed_up: Optional[bool] = None
    service_reminder_interval_months: Optional[int] = None
    water_check_interval_months: Optional[int] = None

    @field_validator("battery_type")
    @classmethod
    def validate_battery_type(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        allowed = {"2W", "4W", "TRUCK", "INVERTER"}
        upper = v.strip().upper()
        if upper not in allowed:
            raise ValueError(f"battery_type must be one of: {allowed}")
        return upper

    @field_validator("serial_number")
    @classmethod
    def normalize_serial(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        normalized = v.strip().upper()
        return normalized if normalized else None


# ---------------------------------------------------------------------------
# Response model
# NOTE: UI/PDF/exports show "Guarantee" — backend fields stay warranty_*
# ---------------------------------------------------------------------------

class BatteryResponse(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    id: str
    customer_id: str
    battery_type: str
    model_number: Optional[str]
    serial_number: Optional[str]
    sale_date: str
    warranty_months: int
    warranty_expiry: str        # UI label: "Guarantee Expiry"
    warranty_reminder_date: str # UI label: "Guarantee Reminder Date"
    invoice_image_url: Optional[str]
    notes: Optional[str] = None
    is_archived: bool
    is_followed_up: bool = False
    created_at: str
    updated_at: Optional[str] = None
    service_reminder_interval_months: Optional[int] = None
    water_check_interval_months: Optional[int] = None

    @classmethod
    def from_row(cls, row: dict) -> "BatteryResponse":
        return cls(
            id=str(row["id"]),
            customer_id=str(row["customer_id"]),
            battery_type=row["battery_type"],
            model_number=row.get("model_number"),
            serial_number=row.get("serial_number"),
            sale_date=str(row["sale_date"]),
            warranty_months=row["warranty_months"],
            warranty_expiry=str(row["warranty_expiry"]),
            warranty_reminder_date=str(row["warranty_reminder_date"]),
            invoice_image_url=row.get("invoice_image_url"),
            notes=row.get("notes"),
            is_archived=row.get("is_archived", False),
            is_followed_up=row.get("is_followed_up", False),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row["updated_at"]) if row.get("updated_at") else None,
            service_reminder_interval_months=row.get("service_reminder_interval_months"),
            water_check_interval_months=row.get("water_check_interval_months"),
        )


class BatteryMessageResponse(BaseModel):
    message: str
    data: BatteryResponse


class BatteryListResponse(BaseModel):
    data: list[BatteryResponse]
    total: int
    page: int
    limit: int
