from typing import Optional, List
from pydantic import BaseModel, field_validator


class ShopCreate(BaseModel):
    shop_name: str
    owner_name: str
    mobile: str
    address: Optional[str] = None
    initial_udhari: Optional[float] = 0.0


    @field_validator("shop_name", "owner_name", "mobile")
    @classmethod
    def validate_non_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("Field cannot be empty")
        return v.strip()


class ShopUpdate(BaseModel):
    shop_name: Optional[str] = None
    owner_name: Optional[str] = None
    mobile: Optional[str] = None
    address: Optional[str] = None


class ShopResponse(BaseModel):
    id: str
    shop_name: str
    owner_name: str
    mobile: str
    address: Optional[str]
    is_archived: bool
    created_at: str
    updated_at: Optional[str] = None
    total_purchases: Optional[int] = 0
    pending_udhari: Optional[float] = 0.0

    @classmethod
    def from_row(cls, row: dict) -> "ShopResponse":
        return cls(
            id=str(row["id"]),
            shop_name=row["shop_name"],
            owner_name=row["owner_name"],
            mobile=row["mobile"],
            address=row.get("address"),
            is_archived=row.get("is_archived", False),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row["updated_at"]) if row.get("updated_at") else None,
            total_purchases=int(row.get("total_purchases", 0)),
            pending_udhari=float(row.get("pending_udhari", 0.0)),
        )


class ShopPurchaseCreate(BaseModel):
    battery_model: str
    serial_number: str
    invoice_number: str = ""
    quantity: int = 1
    purchase_date: str
    amount: float
    udhari_amount: float = 0.0

    @field_validator("battery_model", "serial_number")
    @classmethod
    def validate_non_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("Field cannot be empty")
        return v.strip()

    @field_validator("quantity")
    @classmethod
    def validate_qty(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("quantity must be greater than 0")
        return v

    @field_validator("amount")
    @classmethod
    def validate_amount(cls, v: float) -> float:
        if v < 0:
            raise ValueError("amount cannot be negative")
        return round(v, 2)

    @field_validator("udhari_amount")
    @classmethod
    def validate_udhari(cls, v: float) -> float:
        if v < 0:
            raise ValueError("udhari_amount cannot be negative")
        return round(v, 2)


class ShopPurchaseResponse(BaseModel):
    id: str
    shop_id: str
    battery_model: str
    serial_number: str
    invoice_number: str
    quantity: int
    purchase_date: str
    amount: float
    udhari_amount: float
    created_at: str

    @classmethod
    def from_row(cls, row: dict) -> "ShopPurchaseResponse":
        return cls(
            id=str(row["id"]),
            shop_id=str(row["shop_id"]),
            battery_model=row["battery_model"],
            serial_number=row["serial_number"],
            invoice_number=row["invoice_number"],
            quantity=int(row.get("quantity", 1)),
            purchase_date=str(row.get("purchase_date", "")),
            amount=float(row.get("amount", 0.0)),
            udhari_amount=float(row.get("udhari_amount", 0.0)),
            created_at=str(row.get("created_at", "")),
        )


class ShopPaymentResponse(BaseModel):
    id: str
    shop_id: str
    total_amount: float
    paid_amount: float
    pending_amount: float
    is_settled: bool
    created_at: str

    @classmethod
    def from_row(cls, row: dict) -> "ShopPaymentResponse":
        return cls(
            id=str(row["id"]),
            shop_id=str(row["shop_id"]),
            total_amount=float(row.get("total_amount", 0.0)),
            paid_amount=float(row.get("paid_amount", 0.0)),
            pending_amount=float(row.get("pending_amount", 0.0)),
            is_settled=row.get("is_settled", False),
            created_at=str(row.get("created_at", "")),
        )


class ShopPaymentTransactionResponse(BaseModel):
    id: str
    payment_id: str
    shop_id: str
    transaction_type: str
    amount: float
    notes: Optional[str]
    created_at: str

    @classmethod
    def from_row(cls, row: dict) -> "ShopPaymentTransactionResponse":
        return cls(
            id=str(row["id"]),
            payment_id=str(row["payment_id"]),
            shop_id=str(row["shop_id"]),
            transaction_type=row["transaction_type"],
            amount=float(row.get("amount", 0.0)),
            notes=row.get("notes"),
            created_at=str(row.get("created_at", "")),
        )


class ShopDetailsResponse(BaseModel):
    shop: ShopResponse
    purchases: List[ShopPurchaseResponse]
    payment: Optional[ShopPaymentResponse] = None
    transactions: List[ShopPaymentTransactionResponse] = []
