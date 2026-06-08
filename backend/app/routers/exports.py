import zipfile
from io import BytesIO
from datetime import date, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query, HTTPException, status
from fastapi.responses import Response
from pydantic import BaseModel
from supabase import Client

from app.auth import get_current_admin
from app.database import get_db
from app.services.export import generate_excel, archive_old_records
from app.services.email import send_backup_email

router = APIRouter(prefix="/exports", tags=["exports"])


class ArchiveRequest(BaseModel):
    action: str  # 'archive' or 'delete'
    year: int
    confirm_text: str


@router.get("/excel")
def export_excel(
    type: str = Query(
        default="all",
        description="What to export: 'customers', 'batteries', 'payments', 'stock', or 'all'",
    ),
    date_from: Optional[str] = Query(
        default=None,
        description="Start date filter (YYYY-MM-DD)",
    ),
    date_to: Optional[str] = Query(
        default=None,
        description="End date filter (YYYY-MM-DD)",
    ),
    year: Optional[int] = Query(
        default=None,
        description="Optional filter by year",
    ),
    month: Optional[int] = Query(
        default=None,
        description="Optional filter by month (requires year)",
    ),
    _: str = Depends(get_current_admin),
):
    """
    Download an Excel file.
    Includes Customers, Guarantee Records, Udhari, and/or Stock sheets.
    Apply date range filter or yearly/monthly filters.
    """
    # Calculate dates from year/month if provided
    if year:
        import calendar
        if month:
            # Monthly filter (e.g. 2026-05-01 to 2026-05-31)
            last_day = calendar.monthrange(year, month)[1]
            date_from = f"{year}-{month:02d}-01"
            date_to = f"{year}-{month:02d}-{last_day:02d}"
        else:
            # Yearly filter (e.g. 2026-01-01 to 2026-12-31)
            date_from = f"{year}-01-01"
            date_to = f"{year}-12-31"

    today = date.today().strftime("%Y-%m-%d")
    suffix = f"_{year}" if year else f"_{today}"
    if month and year:
        suffix = f"_{year}_{month:02d}"

    if type == "customers":
        filename = f"customers{suffix}.xlsx"
    elif type == "batteries":
        filename = f"guarantees{suffix}.xlsx"
    elif type == "payments":
        filename = f"udhari{suffix}.xlsx"
    elif type == "stock":
        filename = f"stock{suffix}.xlsx"
    elif type == "shops":
        filename = f"shops{suffix}.xlsx"
    elif type == "shop_purchases":
        filename = f"shop_purchases{suffix}.xlsx"
    else:
        filename = f"shree_ganadhish_export{suffix}.xlsx"

    excel_bytes = generate_excel(
        get_db(),
        export_type=type,
        date_from=date_from,
        date_to=date_to,
    )

    return Response(
        content=excel_bytes,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/backup")
def export_backup_zip(
    period: str = Query("yearly", description="'monthly' or 'yearly'"),
    year: int = Query(..., description="The year to generate backup for"),
    month: Optional[int] = Query(None, description="The month to generate backup for"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """
    Download a ZIP file containing Excel files for Customers, Batteries, Payments, Stock, and Reminders for the specified year/month.
    Generates backup fully in-memory to prevent using server storage.
    """
    period = period.strip().lower()
    date_from = None
    date_to = None
    import calendar

    if period == "monthly":
        if not month:
            raise HTTPException(status_code=400, detail="Month is required for monthly backup")
        last_day = calendar.monthrange(year, month)[1]
        date_from = f"{year}-{month:02d}-01"
        date_to = f"{year}-{month:02d}-{last_day:02d}"
        filename = f"shree_ganadhish_backup_{year}_{month:02d}.zip"
    else:
        date_from = f"{year}-01-01"
        date_to = f"{year}-12-31"
        filename = f"yearly_backup_{year}.zip"

    # Generate individual spreadsheets
    customers_excel = generate_excel(db, export_type="customers", date_from=date_from, date_to=date_to)
    guarantees_excel = generate_excel(db, export_type="batteries", date_from=date_from, date_to=date_to)
    udhari_excel = generate_excel(db, export_type="payments", date_from=date_from, date_to=date_to)
    stock_excel = generate_excel(db, export_type="stock", date_from=date_from, date_to=date_to)
    reminders_excel = generate_excel(db, export_type="reminders", date_from=date_from, date_to=date_to)
    
    # Wholesale shops spreadsheets
    shops_excel = generate_excel(db, export_type="shops", date_from=date_from, date_to=date_to)
    shop_purchases_excel = generate_excel(db, export_type="shop_purchases", date_from=date_from, date_to=date_to)
    shop_payments_excel = generate_excel(db, export_type="shop_payments", date_from=date_from, date_to=date_to)
    shop_txs_excel = generate_excel(db, export_type="shop_payment_transactions", date_from=date_from, date_to=date_to)
    activity_logs_excel = generate_excel(db, export_type="activity_logs", date_from=date_from, date_to=date_to)

    # Zip them in memory
    zip_buffer = BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        zip_file.writestr("customers.xlsx", customers_excel)
        zip_file.writestr("batteries.xlsx", guarantees_excel)
        zip_file.writestr("payments.xlsx", udhari_excel)
        zip_file.writestr("stock.xlsx", stock_excel)
        zip_file.writestr("reminders.xlsx", reminders_excel)
        zip_file.writestr("shops.xlsx", shops_excel)
        zip_file.writestr("shop_purchases.xlsx", shop_purchases_excel)
        zip_file.writestr("shop_payments.xlsx", shop_payments_excel)
        zip_file.writestr("shop_payment_transactions.xlsx", shop_txs_excel)
        zip_file.writestr("activity_logs.xlsx", activity_logs_excel)

    zip_bytes = zip_buffer.getvalue()

    return Response(
        content=zip_bytes,
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/archive")
def run_archive_cleanup(
    req: ArchiveRequest,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """
    Executes database archiving or deletion for records created in the target year.
    Requires typed confirmation matching 'DELETE {year} DATA' or 'ARCHIVE {year} DATA'.
    """
    action = req.action.strip().lower()
    if action not in ("archive", "delete"):
        raise HTTPException(status_code=400, detail="Action must be 'archive' or 'delete'")

    expected_confirm = f"{req.action.upper()} {req.year} DATA"
    if req.confirm_text.strip() != expected_confirm:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid confirmation text. Must type '{expected_confirm}' exactly.",
        )

    res = archive_old_records(db, req.year, action)
    return {
        "status": "success",
        "message": f"Successfully completed {action} for year {req.year}",
        "data": res,
    }


@router.get("/backup-status")
def read_backup_status(
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """Query activity_logs to get details of the most recent email backup."""
    try:
        result = (
            db.table("activity_logs")
            .select("*")
            .order("created_at", desc=True)
            .limit(1000)
            .execute()
        )
        
        last_backup = None
        recommended_next = None
        last_filename = None
        status_val = "warning"  # Default if no backup ever run
        
        # Filter in Python to avoid PostgREST/Cloudflare wildcard match bugs
        sent_backups = [
            row for row in (result.data or [])
            if row.get("action", "").startswith("EMAIL_BACKUP_SENT")
        ]
        
        if sent_backups:
            last_backup_str = sent_backups[0]["created_at"]
            last_backup = last_backup_str[:10]
            last_backup_date = date.fromisoformat(last_backup)
            # Recommending next backup in 30 days
            recommended_next_date = last_backup_date + timedelta(days=30)
            recommended_next = recommended_next_date.isoformat()
            
            # Find filename from log action: "EMAIL_BACKUP_SENT: filename"
            action_text = result.data[0].get("action", "")
            if ":" in action_text:
                last_filename = action_text.split(":", 1)[1].strip()
                
            # If the next recommended date is in the future, it's healthy
            if recommended_next_date >= date.today():
                status_val = "healthy"
            else:
                status_val = "warning"
        else:
            # Recommend backup today if never run
            recommended_next = date.today().isoformat()
            
        return {
            "last_backup_sent_date": last_backup,
            "recommended_next_backup_date": recommended_next,
            "last_backup_filename": last_filename,
            "status": status_val,
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to check backup status: {str(e)}"
        )


@router.post("/email-backup")
def trigger_email_backup(
    period: str = Query(..., description="'monthly' or 'yearly'"),
    year: int = Query(..., description="Target year for backup"),
    month: Optional[int] = Query(None, description="Target month for backup (required for monthly)"),
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """
    Generate Excel spreadsheets in-memory, attach as a ZIP archive,
    email to configured receiver, log activity, and return ZIP bytes.
    """
    import datetime
    import calendar

    # 1. Validation and Date Calculation
    period = period.strip().lower()
    if period not in ("monthly", "yearly"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Period must be either 'monthly' or 'yearly'"
        )

    date_from = None
    date_to = None

    if period == "monthly":
        if not month:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Month is required for a monthly backup"
            )
        last_day = calendar.monthrange(year, month)[1]
        date_from = f"{year}-{month:02d}-01"
        date_to = f"{year}-{month:02d}-{last_day:02d}"
        filename = f"shree_ganadhish_backup_{year}_{month:02d}.zip"
        period_label = f"{year}-{month:02d}"
    else:
        date_from = f"{year}-01-01"
        date_to = f"{year}-12-31"
        filename = f"yearly_backup_{year}.zip"
        period_label = f"{year}"

    # 2. Generate spreadsheets
    try:
        customers_excel = generate_excel(db, export_type="customers", date_from=date_from, date_to=date_to)
        batteries_excel = generate_excel(db, export_type="batteries", date_from=date_from, date_to=date_to)
        payments_excel = generate_excel(db, export_type="payments", date_from=date_from, date_to=date_to)
        stock_excel = generate_excel(db, export_type="stock", date_from=date_from, date_to=date_to)
        reminders_excel = generate_excel(db, export_type="reminders", date_from=date_from, date_to=date_to)
        
        # Wholesale shops spreadsheets
        shops_excel = generate_excel(db, export_type="shops", date_from=date_from, date_to=date_to)
        shop_purchases_excel = generate_excel(db, export_type="shop_purchases", date_from=date_from, date_to=date_to)
        shop_payments_excel = generate_excel(db, export_type="shop_payments", date_from=date_from, date_to=date_to)
        shop_txs_excel = generate_excel(db, export_type="shop_payment_transactions", date_from=date_from, date_to=date_to)
        activity_logs_excel = generate_excel(db, export_type="activity_logs", date_from=date_from, date_to=date_to)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Spreadsheet generation failed: {str(e)}"
        )

    # 3. ZIP in memory
    zip_buffer = BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        zip_file.writestr("customers.xlsx", customers_excel)
        zip_file.writestr("batteries.xlsx", batteries_excel)
        zip_file.writestr("payments.xlsx", payments_excel)
        zip_file.writestr("stock.xlsx", stock_excel)
        zip_file.writestr("reminders.xlsx", reminders_excel)
        zip_file.writestr("shops.xlsx", shops_excel)
        zip_file.writestr("shop_purchases.xlsx", shop_purchases_excel)
        zip_file.writestr("shop_payments.xlsx", shop_payments_excel)
        zip_file.writestr("shop_payment_transactions.xlsx", shop_txs_excel)
        zip_file.writestr("activity_logs.xlsx", activity_logs_excel)

    zip_bytes = zip_buffer.getvalue()

    # 4. Attachment safety size limit checks (20MB)
    zip_size_mb = len(zip_bytes) / (1024 * 1024)
    if zip_size_mb > 20:
        err_msg = f"Backup ZIP size ({zip_size_mb:.2f}MB) exceeds the 20MB safety limit."
        try:
            db.table("activity_logs").insert({
                "action": f"EMAIL_BACKUP_FAILED: {filename}",
                "device": "desktop"
            }).execute()
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=err_msg
        )

    # 5. Email send details setup (Rendered via template and shop settings)
    from app.services.template_engine import render_message, get_shop_settings

    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    context = {
        "period_label": period_label,
        "timestamp": timestamp
    }
    subject, body = render_message(db, "EMAIL_BACKUP", context)

    # Resolve receiver email from shop settings
    shop = get_shop_settings(db)
    recipient = shop.get("backup_email")

    # 6. Send backup email
    email_res = send_backup_email(zip_bytes, filename, subject, body, receiver_email=recipient)
    
    if not email_res["success"]:
        # Log failure
        try:
            db.table("activity_logs").insert({
                "action": f"EMAIL_BACKUP_FAILED: {filename}",
                "device": "desktop"
            }).execute()
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=email_res["error"]
        )

    # 7. Log success
    try:
        db.table("activity_logs").insert({
            "action": f"EMAIL_BACKUP_SENT: {filename}",
            "device": "desktop"
        }).execute()
    except Exception:
        pass

    return {
        "status": "success",
        "message": f"Backup email sent to {recipient}",
        "filename": filename
    }


@router.get("/shop-statement/{shop_id}")
def export_shop_statement(
    shop_id: str,
    db: Client = Depends(get_db),
    _: str = Depends(get_current_admin),
):
    """
    Download a multi-sheet statement of account for a single shop/retailer.
    Includes summary analytics, purchases history, and Udhari ledger transactions.
    """
    from app.services.export import generate_shop_statement_excel
    try:
        statement_bytes = generate_shop_statement_excel(db, shop_id)
        from app.services.shop import get_shop_by_id
        shop = get_shop_by_id(db, shop_id)
        # Clean shop name to be safe for header
        safe_name = "".join(c for c in shop.shop_name if c.isalnum() or c in (" ", "_", "-")).strip().replace(" ", "_")
        filename = f"statement_{safe_name}.xlsx"
        
        return Response(
            content=statement_bytes,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Statement generation failed: {str(e)}"
        )
