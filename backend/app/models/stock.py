from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator


class StockCreate(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    model_name: str
    battery_type: str               # '2W', '4W', 'TRUCK', 'INVERTER'
    quantity: int = 0
    low_stock_threshold: int = 2

    @field_validator("model_name")
    @classmethod
    def validate_model_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("model_name cannot be empty")
        return v.strip().upper()

    @field_validator("battery_type")
    @classmethod
    def validate_battery_type(cls, v: str) -> str:
        allowed = {"2W", "4W", "TRUCK", "INVERTER"}
        upper = v.strip().upper()
        if upper not in allowed:
            raise ValueError(f"battery_type must be one of: {allowed}")
        return upper

    @field_validator("quantity", "low_stock_threshold")
    @classmethod
    def validate_non_negative(cls, v: int) -> int:
        if v < 0:
            raise ValueError("Value cannot be negative")
        return v


class StockUpdate(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    model_name: Optional[str] = None
    battery_type: Optional[str] = None
    quantity: Optional[int] = None
    low_stock_threshold: Optional[int] = None

    @field_validator("model_name")
    @classmethod
    def validate_model_name(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        if not v.strip():
            raise ValueError("model_name cannot be empty")
        return v.strip().upper()

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

    @field_validator("quantity", "low_stock_threshold")
    @classmethod
    def validate_non_negative(cls, v: Optional[int]) -> Optional[int]:
        if v is None:
            return v
        if v < 0:
            raise ValueError("Value cannot be negative")
        return v


class StockQuantityAdjust(BaseModel):
    quantity: int

    @field_validator("quantity")
    @classmethod
    def validate_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("quantity adjustment must be greater than 0")
        return v


class StockResponse(BaseModel):
    model_config = {
        "protected_namespaces": ()
    }

    id: str
    model_name: str
    battery_type: str
    quantity: int
    low_stock_threshold: int
    is_archived: bool
    created_at: str
    updated_at: str

    @classmethod
    def from_row(cls, row: dict) -> "StockResponse":
        return cls(
            id=str(row["id"]),
            model_name=row["model_name"],
            battery_type=row["battery_type"],
            quantity=row["quantity"],
            low_stock_threshold=row["low_stock_threshold"],
            is_archived=row.get("is_archived", False),
            created_at=str(row.get("created_at", "")),
            updated_at=str(row.get("updated_at", "")),
        )


class StockMessageResponse(BaseModel):
    message: str
    data: StockResponse


class StockListResponse(BaseModel):
    data: list[StockResponse]
    total: int
    page: int
    limit: int
