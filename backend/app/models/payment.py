from typing import Optional
from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class PaymentCreate(BaseModel):
    customer_id: str
    battery_id: Optional[str] = None
    total_amount: float
    paid_amount: float = 0.0
    reminder_note: Optional[str] = None

    @field_validator("total_amount")
    @classmethod
    def validate_total(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("total_amount must be greater than 0")
        return round(v, 2)

    @field_validator("paid_amount")
    @classmethod
    def validate_paid(cls, v: float) -> float:
        if v < 0:
            raise ValueError("paid_amount cannot be negative")
        return round(v, 2)


class PaymentUpdate(BaseModel):
    total_amount: Optional[float] = None
    paid_amount: Optional[float] = None
    reminder_note: Optional[str] = None

    @field_validator("total_amount")
    @classmethod
    def validate_total(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and v <= 0:
            raise ValueError("total_amount must be greater than 0")
        return round(v, 2) if v is not None else v

    @field_validator("paid_amount")
    @classmethod
    def validate_paid(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and v < 0:
            raise ValueError("paid_amount cannot be negative")
        return round(v, 2) if v is not None else v


# ---------------------------------------------------------------------------
# Response model
# ---------------------------------------------------------------------------

class PaymentResponse(BaseModel):
    id: str
    customer_id: str
    battery_id: Optional[str]
    total_amount: float
    paid_amount: float
    pending_amount: float
    reminder_note: Optional[str]
    is_settled: bool
    is_archived: bool
    created_at: str
    updated_at: Optional[str] = None
    customer_name: Optional[str] = None
    customer_mobile: Optional[str] = None

    @classmethod
    def from_row(cls, row: dict) -> "PaymentResponse":
        cust = row.get("customer") or row.get("customers") or {}
        customer_name = cust.get("name")
        customer_mobile = cust.get("mobile")

        return cls(
            id=str(row["id"]),
            customer_id=str(row["customer_id"]),
            battery_id=str(row["battery_id"]) if row.get("battery_id") else None,
            total_amount=float(row.get("total_amount", 0)),
            paid_amount=float(row.get("paid_amount", 0)),
            pending_amount=float(row.get("pending_amount", 0)),
            reminder_note=row.get("reminder_note"),
            is_settled=row.get("is_settled", False),
            is_archived=row.get("is_archived", False),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row["updated_at"]) if row.get("updated_at") else None,
            customer_name=customer_name,
            customer_mobile=customer_mobile,
        )


class PaymentMessageResponse(BaseModel):
    message: str
    data: PaymentResponse


class PaymentListResponse(BaseModel):
    data: list[PaymentResponse]
    total: int
    page: int
    limit: int


class PaymentTransactionResponse(BaseModel):
    id: str
    payment_id: str
    customer_id: str
    transaction_type: str
    amount: float
    notes: Optional[str]
    created_at: str

    @classmethod
    def from_row(cls, row: dict) -> "PaymentTransactionResponse":
        return cls(
            id=str(row["id"]),
            payment_id=str(row["payment_id"]),
            customer_id=str(row["customer_id"]),
            transaction_type=row["transaction_type"],
            amount=float(row.get("amount", 0)),
            notes=row.get("notes"),
            created_at=str(row.get("created_at", "")),
        )

