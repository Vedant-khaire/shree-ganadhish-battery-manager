from typing import Optional
from datetime import date
from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class CustomerCreate(BaseModel):
    name: str
    mobile: str
    vehicle_no: Optional[str] = None
    vehicle_type: Optional[str] = None
    area: Optional[str] = None
    pincode: Optional[str] = None
    purchase_type: str = "RETAIL"   # 'RETAIL' or 'SHOP'
    scrap_battery_pending: bool = False
    scrap_expected_value: float = 0.0
    payment_mode: Optional[str] = "Cash"
    scrap_payment_mode: Optional[str] = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name cannot be empty")
        return stripped

    @field_validator("mobile")
    @classmethod
    def validate_mobile(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped.isdigit() or len(stripped) != 10:
            raise ValueError("mobile must be exactly 10 digits (numbers only)")
        return stripped

    @field_validator("purchase_type")
    @classmethod
    def validate_purchase_type(cls, v: str) -> str:
        upper = v.strip().upper()
        if upper not in {"RETAIL", "SHOP"}:
            raise ValueError("purchase_type must be 'RETAIL' or 'SHOP'")
        return upper


class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    mobile: Optional[str] = None
    vehicle_no: Optional[str] = None
    vehicle_type: Optional[str] = None
    area: Optional[str] = None
    pincode: Optional[str] = None
    purchase_type: Optional[str] = None
    scrap_battery_pending: Optional[bool] = None
    scrap_received_date: Optional[date] = None
    scrap_expected_value: Optional[float] = None
    scrap_received_value: Optional[float] = None
    payment_mode: Optional[str] = None
    scrap_payment_mode: Optional[str] = None

    @field_validator("mobile")
    @classmethod
    def validate_mobile(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        if not stripped.isdigit() or len(stripped) != 10:
            raise ValueError("mobile must be exactly 10 digits (numbers only)")
        return stripped

    @field_validator("purchase_type")
    @classmethod
    def validate_purchase_type(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        upper = v.strip().upper()
        if upper not in {"RETAIL", "SHOP"}:
            raise ValueError("purchase_type must be 'RETAIL' or 'SHOP'")
        return upper


# ---------------------------------------------------------------------------
# Response model
# ---------------------------------------------------------------------------

class CustomerResponse(BaseModel):
    id: str
    name: str
    mobile: str
    vehicle_no: Optional[str]
    vehicle_type: Optional[str]
    area: Optional[str]
    pincode: Optional[str]
    purchase_type: str
    is_archived: bool
    created_at: str
    updated_at: Optional[str] = None
    scrap_battery_pending: bool = False
    scrap_received_date: Optional[str] = None
    scrap_expected_value: float = 0.0
    scrap_received_value: float = 0.0
    payment_mode: Optional[str] = "Cash"
    scrap_payment_mode: Optional[str] = None

    @classmethod
    def from_row(cls, row: dict) -> "CustomerResponse":
        return cls(
            id=str(row["id"]),
            name=row["name"],
            mobile=row["mobile"],
            vehicle_no=row.get("vehicle_no"),
            vehicle_type=row.get("vehicle_type"),
            area=row.get("area"),
            pincode=row.get("pincode"),
            purchase_type=row.get("purchase_type", "RETAIL"),
            is_archived=row.get("is_archived", False),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row["updated_at"]) if row.get("updated_at") else None,
            scrap_battery_pending=row.get("scrap_battery_pending", False),
            scrap_received_date=str(row["scrap_received_date"]) if row.get("scrap_received_date") else None,
            scrap_expected_value=float(row.get("scrap_expected_value", 0.0)),
            scrap_received_value=float(row.get("scrap_received_value", 0.0)),
            payment_mode=row.get("payment_mode", "Cash"),
            scrap_payment_mode=row.get("scrap_payment_mode"),
        )


# ---------------------------------------------------------------------------
# Wrapped response (message + data)
# ---------------------------------------------------------------------------

class CustomerMessageResponse(BaseModel):
    message: str
    data: CustomerResponse


# ---------------------------------------------------------------------------
# Paginated list response
# ---------------------------------------------------------------------------

class CustomerListResponse(BaseModel):
    data: list[CustomerResponse]
    total: int
    page: int
    limit: int


from pydantic import model_validator

class CustomerCombinedCreate(BaseModel):
    name: str
    mobile: str
    vehicle_no: Optional[str] = None
    vehicle_type: Optional[str] = None
    area: Optional[str] = None
    pincode: Optional[str] = None
    purchase_type: str = "RETAIL"
    payment_mode: Optional[str] = "Cash"
    scrap_payment_mode: Optional[str] = None

    # Battery fields
    battery_model: Optional[str] = None
    battery_serial_number: Optional[str] = None
    battery_warranty_months: Optional[int] = None
    battery_type: Optional[str] = None
    battery_notes: Optional[str] = None
    battery_sale_date: Optional[date] = None
    battery_service_reminder_interval_months: Optional[int] = 12
    battery_water_check_interval_months: Optional[int] = 6

    # Scrap fields
    scrap_battery_pending: bool = False
    scrap_expected_value: float = 0.0

    # Udhari fields
    has_udhari: bool = False
    payment_total_amount: Optional[float] = None
    payment_paid_amount: Optional[float] = None
    payment_method: Optional[str] = None
    payment_reminder_note: Optional[str] = None
    payment_due_date: Optional[str] = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name cannot be empty")
        return stripped

    @field_validator("mobile")
    @classmethod
    def validate_mobile(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped.isdigit() or len(stripped) != 10:
            raise ValueError("mobile must be exactly 10 digits (numbers only)")
        return stripped

    @model_validator(mode="after")
    def validate_combined(self) -> "CustomerCombinedCreate":
        if self.battery_model or self.battery_serial_number:
            if not self.battery_model:
                raise ValueError("Battery Model is required when registering a battery")
            if not self.battery_serial_number:
                raise ValueError("Battery Serial Number is required when registering a battery")
            if self.battery_warranty_months is None or self.battery_warranty_months < 0:
                raise ValueError("Warranty months must be a non-negative integer")
            if not self.battery_type:
                raise ValueError("Battery Type is required when registering a battery")
            
            # Normalization
            self.battery_model = self.battery_model.strip().upper()
            self.battery_serial_number = self.battery_serial_number.strip().upper()
            self.battery_type = self.battery_type.strip().upper()
            
        if self.has_udhari:
            if self.payment_total_amount is None or self.payment_total_amount <= 0:
                raise ValueError("Total Amount must be greater than 0 when udhari is enabled")
            if self.payment_paid_amount is None or self.payment_paid_amount < 0:
                raise ValueError("Paid Amount cannot be negative")
            if self.payment_paid_amount > self.payment_total_amount:
                raise ValueError("Paid Amount cannot exceed Total Amount")
                
        return self
