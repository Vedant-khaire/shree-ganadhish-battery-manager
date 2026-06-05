from fastapi import HTTPException, status
from supabase import Client

from app.models.stock import StockCreate, StockUpdate, StockResponse


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _log(db: Client, action: str, device: str) -> None:
    try:
        db.table("activity_logs").insert({"action": action, "device": device}).execute()
    except Exception:
        pass


def _require_stock(db: Client, stock_id: str) -> dict:
    result = (
        db.table("battery_stock")
        .select("*")
        .eq("id", stock_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Stock item with ID {stock_id} not found",
        )
    return result.data


# ---------------------------------------------------------------------------
# Read Operations
# ---------------------------------------------------------------------------

def get_all_stock(
    db: Client,
    search: str = "",
    low_stock: bool = False,
    page: int = 1,
    limit: int = 20,
    archived: bool = False,
) -> dict:
    """Search stock by model name. Optionally filter low stock or archived."""
    query = (
        db.table("battery_stock")
        .select("*", count="exact")
        .eq("is_archived", archived)
    )

    if search:
        term = search.strip().replace(",", "").replace("%", "").upper()
        if term:
            query = query.ilike("model_name", f"%{term}%")

    # Fetch all data to perform low-stock threshold comparison if low_stock filter is enabled
    # Since Supabase Postgrest doesn't allow column-to-column comparison natively (e.g. quantity <= low_stock_threshold),
    # we can retrieve and filter locally, or perform a manual filter if the dataset is small.
    # Because it is an MVP and datasets are small, doing local filtering is robust and simple.
    result = query.execute()
    data = result.data or []
    
    if low_stock:
        data = [r for r in data if r["quantity"] <= r["low_stock_threshold"]]

    total = len(data)
    
    # Paginate manually if filtered locally
    offset = (page - 1) * limit
    paginated_data = data[offset:offset + limit]

    return {
        "data": [StockResponse.from_row(r) for r in paginated_data],
        "total": total,
        "page": page,
        "limit": limit,
    }


def get_stock_by_id(db: Client, stock_id: str) -> StockResponse:
    return StockResponse.from_row(_require_stock(db, stock_id))


# ---------------------------------------------------------------------------
# Write Operations
# ---------------------------------------------------------------------------

def create_stock_item(
    db: Client, data: StockCreate, device: str = "desktop"
) -> dict:
    """Create a new stock item. Normalizes model name and checks duplicates."""
    model_name = data.model_name.strip().upper()
    battery_type = data.battery_type.strip().upper()

    # Check for existing duplicate entry
    existing = (
        db.table("battery_stock")
        .select("*")
        .eq("model_name", model_name)
        .eq("battery_type", battery_type)
        .execute()
    )

    if existing.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Stock item for model '{model_name}' and type '{battery_type}' already exists.",
        )

    payload = {
        "model_name": model_name,
        "battery_type": battery_type,
        "quantity": data.quantity,
        "low_stock_threshold": data.low_stock_threshold,
        "is_archived": False,
    }

    result = db.table("battery_stock").insert(payload).execute()
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create stock record",
        )

    created = StockResponse.from_row(result.data[0])
    _log(db, f"STOCK_CREATED: {model_name} ({battery_type})", device)
    return {"message": "Stock item created successfully", "data": created}


def update_stock_item(
    db: Client, stock_id: str, data: StockUpdate, device: str = "desktop"
) -> dict:
    """Update stock configuration details."""
    _require_stock(db, stock_id)
    updates = {k: v for k, v in data.model_dump().items() if v is not None}

    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    # If model_name or battery_type is changing, check for duplicates
    if "model_name" in updates or "battery_type" in updates:
        existing_row = _require_stock(db, stock_id)
        model_name = updates.get("model_name", existing_row["model_name"]).strip().upper()
        battery_type = updates.get("battery_type", existing_row["battery_type"]).strip().upper()

        duplicate = (
            db.table("battery_stock")
            .select("*")
            .eq("model_name", model_name)
            .eq("battery_type", battery_type)
            .neq("id", stock_id)
            .execute()
        )
        if duplicate.data:
            raise HTTPException(
                status_code=400,
                detail=f"Another stock item with model '{model_name}' and type '{battery_type}' already exists.",
            )
        
        updates["model_name"] = model_name
        updates["battery_type"] = battery_type

    updates["updated_at"] = "now()"

    result = db.table("battery_stock").update(updates).eq("id", stock_id).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update stock item")

    updated = StockResponse.from_row(result.data[0])
    _log(db, f"STOCK_UPDATED: {stock_id}", device)
    return {"message": "Stock item updated successfully", "data": updated}


def increase_stock_quantity(
    db: Client, stock_id: str, amount: int, device: str = "desktop"
) -> dict:
    """Increase current stock units by a specified amount."""
    row = _require_stock(db, stock_id)
    new_quantity = row["quantity"] + amount

    result = (
        db.table("battery_stock")
        .update({"quantity": new_quantity, "updated_at": "now()"})
        .eq("id", stock_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to increase stock quantity")

    updated = StockResponse.from_row(result.data[0])
    _log(db, f"STOCK_INCREASED: {row['model_name']} (+{amount})", device)
    return {"message": "Stock quantity increased successfully", "data": updated}


def decrease_stock_quantity(
    db: Client, stock_id: str, amount: int, device: str = "desktop"
) -> dict:
    """Decrease current stock units by a specified amount. Cannot go below 0."""
    row = _require_stock(db, stock_id)
    new_quantity = row["quantity"] - amount

    if new_quantity < 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot reduce stock below 0. Current stock is {row['quantity']}.",
        )

    result = (
        db.table("battery_stock")
        .update({"quantity": new_quantity, "updated_at": "now()"})
        .eq("id", stock_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to decrease stock quantity")

    updated = StockResponse.from_row(result.data[0])
    _log(db, f"STOCK_DECREASED: {row['model_name']} (-{amount})", device)
    return {"message": "Stock quantity decreased successfully", "data": updated}


def archive_stock_item(db: Client, stock_id: str, device: str = "desktop") -> dict:
    row = _require_stock(db, stock_id)
    db.table("battery_stock").update({"is_archived": True, "updated_at": "now()"}).eq("id", stock_id).execute()
    _log(db, f"STOCK_ARCHIVED: {row['model_name']}", device)
    return {"message": "Stock item archived successfully"}


def restore_stock_item(db: Client, stock_id: str, device: str = "desktop") -> dict:
    row = _require_stock(db, stock_id)
    db.table("battery_stock").update({"is_archived": False, "updated_at": "now()"}).eq("id", stock_id).execute()
    _log(db, f"STOCK_RESTORED: {row['model_name']}", device)
    return {"message": "Stock item restored successfully"}


def delete_stock_permanently(db: Client, stock_id: str, device: str = "desktop") -> dict:
    """Hard-delete stock item."""
    row = _require_stock(db, stock_id)
    db.table("battery_stock").delete().eq("id", stock_id).execute()
    _log(db, f"STOCK_PERMANENTLY_DELETED: {row['model_name']}", device)
    return {"message": "Stock item permanently deleted successfully"}


# ---------------------------------------------------------------------------
# Reconciliation Operation
# ---------------------------------------------------------------------------

def reconcile_stock_from_sales(db: Client) -> dict:
    """
    Exposes a utility that groups customer battery sales by model number & type,
    allowing comparison and manual recalculations.
    """
    # 1. Fetch active customer battery registrations
    sales = (
        db.table("batteries")
        .select("model_number, battery_type")
        .eq("is_archived", False)
        .execute()
    )

    data = sales.data or []
    grouped_sales = {}

    for s in data:
        model = (s.get("model_number") or "").strip().upper()
        b_type = (s.get("battery_type") or "").strip().upper()
        if not model:
            continue
        key = (model, b_type)
        grouped_sales[key] = grouped_sales.get(key, 0) + 1

    reconciliation_list = []
    for (model, b_type), sales_count in grouped_sales.items():
        reconciliation_list.append({
            "model_name": model,
            "battery_type": b_type,
            "sales_count": sales_count
        })

    return {
        "status": "success",
        "reconciliation": reconciliation_list
    }
