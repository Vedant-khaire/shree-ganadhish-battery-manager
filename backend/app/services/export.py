from datetime import date
import datetime
from io import BytesIO
from typing import Optional

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
from supabase import Client


# ---------------------------------------------------------------------------
# Styling constants
# ---------------------------------------------------------------------------
HEADER_FONT = Font(bold=True, color="FFFFFF")
HEADER_FILL = PatternFill(fill_type="solid", fgColor="1E3A5F")  # dark navy
CENTER = Alignment(horizontal="center")


def _style_header_row(ws, col_count: int) -> None:
    for col in range(1, col_count + 1):
        cell = ws.cell(row=1, column=col)
        cell.font = HEADER_FONT
        cell.fill = HEADER_FILL
        cell.alignment = CENTER


def _auto_width(ws) -> None:
    for col in ws.columns:
        max_len = max((len(str(cell.value or "")) for cell in col), default=10)
        ws.column_dimensions[get_column_letter(col[0].column)].width = min(max_len + 4, 40)


# ---------------------------------------------------------------------------
# Sheet builders
# ---------------------------------------------------------------------------

def _build_customers_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Name", "Mobile", "Vehicle No", "Vehicle Type",
        "Area", "Pincode", "Purchase Type", "Payment Mode",
        "Battery Type", "Battery Model", "Serial Number",
        "Sale Date", "Guarantee Months", "Guarantee Expiry",
        "Scrap Payout Mode", "Scrap Payment Date", "Created At",
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        batteries = r.get("batteries") or []
        if not batteries:
            ws.append([
                r.get("name", ""),
                r.get("mobile", ""),
                r.get("vehicle_no", ""),
                r.get("vehicle_type", ""),
                r.get("area", ""),
                r.get("pincode", ""),
                r.get("purchase_type", ""),
                r.get("payment_mode") or "N/A",
                "N/A", "N/A", "N/A", "N/A", "N/A", "N/A",
                r.get("scrap_payment_mode") or "N/A",
                str(r.get("scrap_received_date", ""))[:10] if r.get("scrap_received_date") else "N/A",
                str(r.get("created_at", ""))[:10],
            ])
        else:
            for b in batteries:
                ws.append([
                    r.get("name", ""),
                    r.get("mobile", ""),
                    r.get("vehicle_no", ""),
                    r.get("vehicle_type", ""),
                    r.get("area", ""),
                    r.get("pincode", ""),
                    r.get("purchase_type", ""),
                    r.get("payment_mode") or "N/A",
                    b.get("battery_type", "") or "N/A",
                    b.get("model_name") or b.get("model_number", "") or "N/A",
                    b.get("serial_number", "") or "N/A",
                    str(b.get("sale_date", ""))[:10] if b.get("sale_date") else "N/A",
                    b.get("warranty_months", "") or "N/A",
                    str(b.get("warranty_expiry", ""))[:10] if b.get("warranty_expiry") else "N/A",
                    r.get("scrap_payment_mode") or "N/A",
                    str(r.get("scrap_received_date", ""))[:10] if r.get("scrap_received_date") else "N/A",
                    str(r.get("created_at", ""))[:10],
                ])
    _auto_width(ws)


def _build_batteries_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Customer Name", "Mobile", "Battery Type", "Model Number", "Serial Number",
        "Sale Date", "Guarantee Months", "Guarantee Expiry",
        "Total Amount (₹)", "Paid Amount (₹)", "Pending Amount (₹)", "Settled",
        "Payment Mode", "Payment Date", "Created At",
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        customer = r.get("customers") or {}
        payments_list = r.get("payments") or []
        payment = payments_list[0] if payments_list else {}
        
        ws.append([
            customer.get("name", ""),
            customer.get("mobile", ""),
            r.get("battery_type", ""),
            r.get("model_number", ""),
            r.get("serial_number", ""),
            str(r.get("sale_date", ""))[:10],
            r.get("warranty_months", ""),
            str(r.get("warranty_expiry", ""))[:10],
            float(payment.get("total_amount") or 0.0) if payment else 0.0,
            float(payment.get("paid_amount") or 0.0) if payment else 0.0,
            float(payment.get("pending_amount") or 0.0) if payment else 0.0,
            "Yes" if payment.get("is_settled") else ("No" if payment else "N/A"),
            payment.get("payment_mode") or customer.get("payment_mode") or "N/A",
            str(payment.get("updated_at") or payment.get("created_at", ""))[:10] if payment and (payment.get("is_settled") or float(payment.get("paid_amount", 0.0)) > 0) else "N/A",
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_payments_sheet(ws, rows: list[dict]) -> None:
    # UI label: "Udhari" — backend field: payments
    headers = [
        "Customer Name", "Mobile", "Vehicle No", "Vehicle Type",
        "Battery Type/Model", "Serial Number", "Total Amount (₹)",
        "Paid Amount (₹)", "Pending Amount (₹)",
        "Reminder Note", "Settled", "Payment Mode", "Payment Date", "Created At",
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        customer = r.get("customers") or {}
        battery = r.get("batteries") or {}
        battery_model = f"{battery.get('battery_type', '')} {battery.get('model_number', '')}".strip()
        
        ws.append([
            customer.get("name", ""),
            customer.get("mobile", ""),
            customer.get("vehicle_no", ""),
            customer.get("vehicle_type", ""),
            battery_model or "N/A",
            battery.get("serial_number") or "N/A",
            float(r.get("total_amount", 0.0)),
            float(r.get("paid_amount", 0.0)),
            float(r.get("pending_amount", 0.0)),
            r.get("reminder_note", ""),
            "Yes" if r.get("is_settled") else "No",
            r.get("payment_mode") or "N/A",
            str(r.get("updated_at") or r.get("created_at", ""))[:10] if r.get("is_settled") or float(r.get("paid_amount", 0)) > 0 else "N/A",
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_stock_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Model Name", "Battery Type", "Quantity", "Low Stock Threshold",
        "Status", "Created At",
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        qty = r.get("quantity", 0)
        threshold = r.get("low_stock_threshold", 2)
        if qty == 0:
            status = "OUT OF STOCK"
        elif qty <= threshold:
            status = "LOW STOCK"
        else:
            status = "IN STOCK"

        ws.append([
            r.get("model_name", ""),
            r.get("battery_type", ""),
            qty,
            threshold,
            status,
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_reminders_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Customer Name", "Mobile Number", "Battery Model", "Serial Number",
        "Battery Type", "Reminder Type", "Reminder Date", "Status",
        "Message Sent", "Sent At", "Completed", "Notes", "Created At",
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        ws.append([
            r.get("customer_name", ""),
            r.get("mobile_number", ""),
            r.get("battery_model", ""),
            r.get("battery_serial", ""),
            r.get("battery_type", ""),
            r.get("reminder_type", ""),
            str(r.get("reminder_date", ""))[:10],
            r.get("reminder_status", ""),
            "Yes" if r.get("message_sent") else "No",
            str(r.get("sent_at", ""))[:10] if r.get("sent_at") else "",
            "Yes" if r.get("is_completed") else "No",
            r.get("notes", ""),
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_shops_sheet(ws, rows: list[dict]) -> None:
    headers = ["Shop Name", "Owner Name", "Mobile Number", "Address", "Created At"]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        ws.append([
            r.get("shop_name", ""),
            r.get("owner_name", ""),
            r.get("mobile", ""),
            r.get("address", ""),
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_shop_purchases_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Shop Name", "Owner Name", "Mobile", "Battery Model", "Serial Number", "Invoice Number",
        "Quantity", "Purchase Date", "Amount (₹)", "Udhari Amount (₹)", "Payment Mode", "Created At"
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        shop = r.get("shops") or {}
        ws.append([
            shop.get("shop_name", ""),
            shop.get("owner_name", ""),
            shop.get("mobile", ""),
            r.get("battery_model", ""),
            r.get("serial_number", ""),
            r.get("invoice_number", ""),
            int(r.get("quantity", 1)),
            str(r.get("purchase_date", ""))[:10],
            float(r.get("amount", 0.0)),
            float(r.get("udhari_amount", 0.0)),
            r.get("payment_mode") or "N/A",
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_shop_payments_sheet(ws, rows: list[dict]) -> None:
    headers = ["Shop Name", "Total Amount (₹)", "Paid Amount (₹)", "Pending Amount (₹)", "Settled", "Created At"]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        shop = r.get("shops") or {}
        ws.append([
            shop.get("shop_name", ""),
            float(r.get("total_amount", 0.0)),
            float(r.get("paid_amount", 0.0)),
            float(r.get("pending_amount", 0.0)),
            "Yes" if r.get("is_settled") else "No",
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_shop_payment_transactions_sheet(ws, rows: list[dict]) -> None:
    headers = ["Shop Name", "Transaction Type", "Amount (₹)", "Notes", "Payment Mode", "Payment Date", "Created At"]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        shop = r.get("shops") or {}
        ws.append([
            shop.get("shop_name", ""),
            r.get("transaction_type", ""),
            float(r.get("amount", 0.0)),
            r.get("notes") or "",
            r.get("payment_mode") or "N/A",
            str(r.get("created_at", ""))[:10],
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_customer_transactions_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Customer Name", "Mobile", "Transaction Type", "Amount (₹)",
        "Battery Model", "Serial Number", "Notes", "Payment Mode", "Payment Date", "Created At"
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        customer = r.get("customers") or {}
        payment = r.get("payments") or {}
        battery = payment.get("batteries") or {}
        battery_model = f"{battery.get('battery_type', '')} {battery.get('model_number', '')}".strip()
        
        ws.append([
            customer.get("name", ""),
            customer.get("mobile", ""),
            r.get("transaction_type", ""),
            float(r.get("amount", 0.0)),
            battery_model or "N/A",
            battery.get("serial_number") or "N/A",
            r.get("notes") or "",
            r.get("payment_mode") or "N/A",
            str(r.get("created_at", ""))[:10],
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_scrap_payments_sheet(ws, rows: list[dict]) -> None:
    headers = [
        "Customer Name", "Mobile", "Expected Scrap Value (₹)", "Received Scrap Value (₹)",
        "Payment Mode", "Payment Date", "Registered Battery (Model/Serial)", "Created At"
    ]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        batteries = r.get("batteries") or []
        battery_desc_list = []
        for b in batteries:
            model = b.get("model_number") or b.get("model_name") or ""
            serial = b.get("serial_number") or ""
            battery_desc_list.append(f"{model} ({serial})".strip())
        battery_desc = ", ".join(battery_desc_list) if battery_desc_list else "N/A"

        ws.append([
            r.get("name", ""),
            r.get("mobile", ""),
            float(r.get("scrap_expected_value", 0.0)),
            float(r.get("scrap_received_value", 0.0)),
            r.get("scrap_payment_mode") or "N/A",
            str(r.get("scrap_received_date", ""))[:10] if r.get("scrap_received_date") else "N/A",
            battery_desc,
            str(r.get("created_at", ""))[:10],
        ])
    _auto_width(ws)


def _build_activity_logs_sheet(ws, rows: list[dict]) -> None:
    headers = ["Action", "Device", "Created At"]
    ws.append(headers)
    _style_header_row(ws, len(headers))

    for r in rows:
        ws.append([
            r.get("action", ""),
            r.get("device", ""),
            str(r.get("created_at", ""))[:19],
        ])
    _auto_width(ws)


# ---------------------------------------------------------------------------
# Public export function
# ---------------------------------------------------------------------------

def generate_excel(
    db: Client,
    export_type: str = "all",    # 'customers', 'batteries', 'payments', 'stock', 'reminders', or 'all'
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> bytes:
    """
    Generate an Excel workbook and return raw bytes for HTTP response.
    export_type controls which sheet(s) are included.
    date_from / date_to filter by created_at or target dates (ISO date strings: YYYY-MM-DD).
    """
    wb = openpyxl.Workbook()
    wb.remove(wb.active)  # remove default empty sheet

    def _date_filter(query, col: str = "created_at"):
        if date_from:
            query = query.gte(col, f"{date_from}T00:00:00")
        if date_to:
            query = query.lte(col, f"{date_to}T23:59:59")
        return query

    if export_type in ("customers", "all"):
        q = db.table("customers").select("*, batteries(*)").eq("is_archived", False)
        q = _date_filter(q)
        rows = q.order("created_at", desc=False).execute().data or []
        ws = wb.create_sheet("Customers")
        _build_customers_sheet(ws, rows)

    if export_type in ("batteries", "all"):
        q = db.table("batteries").select("*, customers(*), payments(*)").eq("is_archived", False)
        q = _date_filter(q, "sale_date")
        rows = q.order("sale_date", desc=False).execute().data or []
        ws = wb.create_sheet("Guarantee Records")  # UI label
        _build_batteries_sheet(ws, rows)

    if export_type in ("payments", "all"):
        q = db.table("payments").select("*, customers(*), batteries(*)").eq("is_archived", False)
        q = _date_filter(q)
        rows = q.order("created_at", desc=False).execute().data or []
        ws = wb.create_sheet("Udhari")   # UI label
        _build_payments_sheet(ws, rows)

    if export_type in ("stock", "all"):
        q = db.table("battery_stock").select("*").eq("is_archived", False)
        q = _date_filter(q)
        rows = q.order("model_name", desc=False).execute().data or []
        ws = wb.create_sheet("Stock")
        _build_stock_sheet(ws, rows)

    if export_type in ("reminders", "all"):
        q = db.table("service_reminders").select("*").eq("is_archived", False)
        q = _date_filter(q, "reminder_date")
        rows = q.order("reminder_date", desc=False).execute().data or []
        ws = wb.create_sheet("Reminders")
        _build_reminders_sheet(ws, rows)

    if export_type == "shops":
        q = db.table("shops").select("*").eq("is_archived", False)
        q = _date_filter(q)
        rows = q.order("shop_name", desc=False).execute().data or []
        ws = wb.create_sheet("Shops")
        _build_shops_sheet(ws, rows)

    if export_type == "shop_purchases":
        q = db.table("shop_purchases").select("*, shops(shop_name, owner_name, mobile)").execute()
        rows = q.data or []
        if date_from or date_to:
            filtered = []
            for r in rows:
                p_date = r.get("purchase_date", "")
                if date_from and p_date < date_from:
                    continue
                if date_to and p_date > date_to:
                    continue
                filtered.append(r)
            rows = filtered
        ws = wb.create_sheet("Shop Purchases")
        _build_shop_purchases_sheet(ws, rows)

    if export_type == "shop_payments":
        q = db.table("shop_payments").select("*, shops(shop_name)").execute()
        rows = q.data or []
        ws = wb.create_sheet("Shop Payments")
        _build_shop_payments_sheet(ws, rows)

    if export_type == "shop_payment_transactions":
        q = db.table("shop_payment_transactions").select("*, shops(shop_name)").execute()
        rows = q.data or []
        ws = wb.create_sheet("Shop Transactions")
        _build_shop_payment_transactions_sheet(ws, rows)

    if export_type == "activity_logs":
        q = db.table("activity_logs").select("*").execute()
        rows = q.data or []
        ws = wb.create_sheet("Activity Logs")
        _build_activity_logs_sheet(ws, rows)

    if export_type in ("customer_payment_transactions", "all"):
        q = db.table("payment_transactions").select("*, customers(*), payments(*, batteries(*))")
        if date_from:
            q = q.gte("created_at", f"{date_from}T00:00:00")
        if date_to:
            q = q.lte("created_at", f"{date_to}T23:59:59")
        rows = q.order("created_at", desc=False).execute().data or []
        ws = wb.create_sheet("Customer Transactions")
        _build_customer_transactions_sheet(ws, rows)

    if export_type in ("scrap_payments", "all"):
        q = db.table("customers").select("*, batteries(*)").eq("is_archived", False).not_.is_("scrap_received_date", "null")
        if date_from:
            q = q.gte("scrap_received_date", date_from)
        if date_to:
            q = q.lte("scrap_received_date", date_to)
        rows = q.order("scrap_received_date", desc=False).execute().data or []
        ws = wb.create_sheet("Scrap Payments")
        _build_scrap_payments_sheet(ws, rows)

    if not wb.sheetnames:
        raise ValueError(f"Unknown export_type: '{export_type}'")

    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()


def generate_shop_statement_excel(db: Client, shop_id: str) -> bytes:
    """
    Generates a multi-sheet financial statement workbook for a single Shop/Retailer.
    Includes Profile details, summary card values, purchase records, and Udhari payment transactions.
    """
    wb = openpyxl.Workbook()
    wb.remove(wb.active)  # remove default sheet

    # Import locally to avoid circular dependencies
    from app.services.shop import get_shop_details
    details = get_shop_details(db, shop_id)
    shop = details["shop"]
    purchases = details["purchases"]
    payment = details["payment"]
    transactions = details["transactions"]

    # 1. Summary Statement
    ws_summary = wb.create_sheet("Statement Summary")
    
    ws_summary.append(["SHREE GANADHISH BATTERY SERVICES"])
    ws_summary.append(["SHOP STATEMENT OF ACCOUNT"])
    ws_summary.append([])
    
    ws_summary.append(["Shop Name:", shop.shop_name])
    ws_summary.append(["Owner Name:", shop.owner_name])
    ws_summary.append(["Mobile Number:", shop.mobile])
    ws_summary.append(["Address:", shop.address or "N/A"])
    ws_summary.append([])

    total_pur = sum(float(p.amount) for p in purchases)
    total_udhari = float(payment.total_amount) if payment else 0.0
    paid_udhari = float(payment.paid_amount) if payment else 0.0
    pending_udhari = float(payment.pending_amount) if payment else 0.0

    ws_summary.append(["FINANCIAL SUMMARY"])
    ws_summary.append(["Total Purchase Value:", total_pur])
    ws_summary.append(["Total Udhari Accumulation:", total_udhari])
    ws_summary.append(["Total Udhari Paid:", paid_udhari])
    ws_summary.append(["Outstanding Udhari Balance:", pending_udhari])
    
    # Summary Sheet Styles
    ws_summary["A1"].font = Font(bold=True, size=14, color="1E3A5F")
    ws_summary["A2"].font = Font(bold=True, size=12)
    ws_summary["A9"].font = Font(bold=True, size=12, color="1E3A5F")
    for row in range(10, 14):
        ws_summary[f"A{row}"].font = Font(bold=True)
        cell = ws_summary[f"B{row}"]
        cell.number_format = '"₹"#,##0.00'
        cell.alignment = Alignment(horizontal="right")
    
    _auto_width(ws_summary)

    # 2. Purchases History
    ws_purchases = wb.create_sheet("Purchase History")
    p_headers = ["Purchase Date", "Battery Model", "Serial Number", "Invoice Number", "Quantity", "Amount (₹)", "Udhari Amount (₹)", "Payment Mode"]
    ws_purchases.append(p_headers)
    _style_header_row(ws_purchases, len(p_headers))
    for p in purchases:
        ws_purchases.append([
            str(p.purchase_date)[:10],
            p.battery_model,
            p.serial_number,
            p.invoice_number,
            p.quantity,
            float(p.amount),
            float(p.udhari_amount),
            p.payment_mode or "N/A"
        ])
    
    # Format amount columns
    for row in range(2, len(purchases) + 2):
        ws_purchases.cell(row=row, column=6).number_format = '"₹"#,##0.00'
        ws_purchases.cell(row=row, column=7).number_format = '"₹"#,##0.00'
    _auto_width(ws_purchases)

    # 3. Udhari Ledger Transaction History
    ws_payments = wb.create_sheet("Udhari Transaction History")
    t_headers = ["Transaction Date", "Transaction Type", "Amount (₹)", "Notes", "Payment Mode", "Payment Date"]
    ws_payments.append(t_headers)
    _style_header_row(ws_payments, len(t_headers))
    for t in transactions:
        ws_payments.append([
            str(t.created_at)[:10],
            t.transaction_type,
            float(t.amount),
            t.notes or "",
            t.payment_mode or "N/A",
            str(t.created_at)[:10],
        ])
        
    for row in range(2, len(transactions) + 2):
        ws_payments.cell(row=row, column=3).number_format = '"₹"#,##0.00'
    _auto_width(ws_payments)

    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()


def archive_old_records(db: Client, year: int, action: str) -> dict:
    """
    Implements Day 9 & Day 10 Smart Cleanup Logic:
    - action: 'archive' (set is_archived = True) or 'delete' (permanently delete)
    - year: target year (archives/deletes data from that year or before)
    
    Protections:
    - DO NOT archive/delete active warranties (warranty_expiry >= today).
    - DO NOT archive/delete pending udhari (payments where is_settled = False).
    - DO NOT archive/delete customers who have pending udhari or active warranties.
    - DO NOT archive/delete reminders if:
        * warranty is still active
        * future reminder exists
        * reminder status is pending/uncompleted
        * customer has active service cycle
    """
    today = datetime.date.today().isoformat()
    ninety_days_ago = (datetime.date.today() - datetime.timedelta(days=90)).isoformat()
    six_months_ago = (datetime.date.today() - datetime.timedelta(days=180)).isoformat()
    
    # Automatically prune activity logs older than 90 days (LIGHTWEIGHT ACTIVITY FEED POLICY)
    try:
        db.table("activity_logs").delete().lt("created_at", f"{ninety_days_ago}T00:00:00+00:00").execute()
    except Exception:
        pass

    # Prune activity logs to retain only important business events
    try:
        logs_res = db.table("activity_logs").select("id, action").execute()
        important_prefixes = (
            "BATTERY_ADDED", "PAYMENT_ADDED", "STOCK_ADJUSTED",
            "STOCK_INCREASED", "STOCK_DECREASED", "STOCK_AUTO_DECREASED",
            "REMINDER_COMPLETED", "EMAIL_BACKUP_SENT", "EMAIL_BACKUP_FAILED",
            "BATTERY_RETURNED", "SHOP_PURCHASE_DELETED", "OPENING_BALANCE_ADDED",
            "ADJUSTMENT_ADDED"
        )
        to_delete = []
        for log in (logs_res.data or []):
            action_str = log.get("action", "") or ""
            if not any(action_str.startswith(pref) for pref in important_prefixes):
                to_delete.append(log["id"])
        
        if to_delete:
            for i in range(0, len(to_delete), 100):
                chunk = to_delete[i:i+100]
                db.table("activity_logs").delete().in_("id", chunk).execute()
    except Exception:
        pass

    # Auto-delete completed reminders older than 90 days to prevent table growth
    try:
        ninety_days_ago = (datetime.date.today() - datetime.timedelta(days=90)).isoformat()
        db.table("service_reminders").delete()\
            .eq("is_completed", True)\
            .lt("reminder_date", ninety_days_ago)\
            .execute()
    except Exception:
        pass

    
    # 1. Fetch protected customer IDs (due to active warranties or pending payments)
    # A. Customers with active warranties
    active_b_res = db.table("batteries").select("customer_id").gte("warranty_expiry", today).eq("is_archived", False).execute()
    active_b_cust_ids = {str(row["customer_id"]) for row in (active_b_res.data or [])}
    
    # B. Customers with pending payments
    pending_p_res = db.table("payments").select("customer_id").eq("is_settled", False).eq("is_archived", False).execute()
    pending_p_cust_ids = {str(row["customer_id"]) for row in (pending_p_res.data or [])}
    
    # C. Reminders check for active service cycles / future / pending reminders
    rem_status_res = db.table("service_reminders")\
        .select("battery_id, customer_id, is_completed, reminder_date, warranty_expiry")\
        .execute()
    
    protected_batteries_rems = set()
    protected_customers_rems = set()
    for row in (rem_status_res.data or []):
        bid = str(row.get("battery_id")) if row.get("battery_id") else None
        cid = str(row.get("customer_id")) if row.get("customer_id") else None
        is_comp = row.get("is_completed", False)
        rem_d = str(row.get("reminder_date", ""))[:10]
        w_exp = str(row.get("warranty_expiry", ""))[:10] if row.get("warranty_expiry") else ""
        
        # Check active warranty
        w_active = w_exp >= today if w_exp else False
        # Check future reminder
        rem_future = rem_d > today if rem_d else False
        # Check pending reminder
        rem_pending = not is_comp
        
        if bid and (w_active or rem_future or rem_pending):
            protected_batteries_rems.add(bid)
        if cid and (w_active or rem_future or rem_pending):
            protected_customers_rems.add(cid)

    # Combined protected customer set (warranties + payments + reminders active service cycle)
    protected_cust_ids = active_b_cust_ids.union(pending_p_cust_ids).union(protected_customers_rems)
    
    # Define date range for target year: up to the end of that year (YYYY-12-31)
    end_date = f"{year}-12-31"
    
    # Initialize count counters
    payments_processed = 0
    batteries_processed = 0
    customers_processed = 0
    reminders_processed = 0
    
    if action == "archive":
        # 1. Archive settled payments created in target year or before
        target_payments = db.table("payments")\
            .select("id")\
            .lte("created_at", f"{end_date}T23:59:59+00:00")\
            .eq("is_settled", True)\
            .eq("is_archived", False)\
            .execute()
        target_payment_ids = [str(r["id"]) for r in (target_payments.data or [])]
        if target_payment_ids:
            db.table("payments").update({"is_archived": True}).in_("id", target_payment_ids).execute()
            payments_processed = len(target_payment_ids)
            
        # 2. Archive expired batteries sold in target year or before
        target_batteries = db.table("batteries")\
            .select("id")\
            .lte("sale_date", end_date)\
            .lt("warranty_expiry", today)\
            .eq("is_archived", False)\
            .execute()
        target_battery_ids = [str(r["id"]) for r in (target_batteries.data or [])]
        if target_battery_ids:
            db.table("batteries").update({"is_archived": True}).in_("id", target_battery_ids).execute()
            batteries_processed = len(target_battery_ids)
            
        # 3. Archive inactive customers created in target year or before
        target_customers = db.table("customers")\
            .select("id")\
            .lte("created_at", f"{end_date}T23:59:59+00:00")\
            .eq("is_archived", False)\
            .execute()
        target_customer_ids = [str(r["id"]) for r in (target_customers.data or [])]
        unprotected_customer_ids = [cid for cid in target_customer_ids if cid not in protected_cust_ids]
        if unprotected_customer_ids:
            db.table("customers").update({"is_archived": True}).in_("id", unprotected_customer_ids).execute()
            customers_processed = len(unprotected_customer_ids)

        # 4. Archive eligible completed reminders falling in target year or before (older than 90 days)
        target_reminders = db.table("service_reminders")\
            .select("id, reminder_date")\
            .lte("reminder_date", end_date)\
            .eq("is_completed", True)\
            .eq("is_archived", False)\
            .execute()
        eligible_reminder_ids = []
        for r in (target_reminders.data or []):
            rid = str(r["id"])
            r_date = str(r["reminder_date"])[:10]
            if r_date < ninety_days_ago:
                eligible_reminder_ids.append(rid)
                
        if eligible_reminder_ids:
            db.table("service_reminders").update({"is_archived": True}).in_("id", eligible_reminder_ids).execute()
            reminders_processed = len(eligible_reminder_ids)
            
    elif action == "delete":
        # 1. Delete settled payments created in target year or before
        target_payments = db.table("payments")\
            .select("id")\
            .lte("created_at", f"{end_date}T23:59:59+00:00")\
            .eq("is_settled", True)\
            .execute()
        target_payment_ids = [str(r["id"]) for r in (target_payments.data or [])]
        if target_payment_ids:
            db.table("payments").delete().in_("id", target_payment_ids).execute()
            payments_processed = len(target_payment_ids)
            
        # 2. Delete expired batteries sold in target year or before
        target_batteries = db.table("batteries")\
            .select("id")\
            .lte("sale_date", end_date)\
            .lt("warranty_expiry", today)\
            .execute()
        target_battery_ids = [str(r["id"]) for r in (target_batteries.data or [])]
        if target_battery_ids:
            ref_payments = db.table("payments").select("battery_id").in_("battery_id", target_battery_ids).execute()
            ref_battery_ids = {str(row["battery_id"]) for row in (ref_payments.data or []) if row.get("battery_id")}
            safe_battery_ids = [bid for bid in target_battery_ids if bid not in ref_battery_ids]
            if safe_battery_ids:
                db.table("batteries").delete().in_("id", safe_battery_ids).execute()
                batteries_processed = len(safe_battery_ids)
                
        # 3. Delete inactive customers created in target year or before
        target_customers = db.table("customers")\
            .select("id")\
            .lte("created_at", f"{end_date}T23:59:59+00:00")\
            .execute()
        target_customer_ids = [str(r["id"]) for r in (target_customers.data or [])]
        unprotected_customer_ids = [cid for cid in target_customer_ids if cid not in protected_cust_ids]
        if unprotected_customer_ids:
            ref_batteries = db.table("batteries").select("customer_id").in_("customer_id", unprotected_customer_ids).execute()
            ref_cust_ids = {str(row["customer_id"]) for row in (ref_batteries.data or [])}
            safe_cust_ids = [cid for cid in unprotected_customer_ids if cid not in ref_cust_ids]
            if safe_cust_ids:
                db.table("customers").delete().in_("id", safe_cust_ids).execute()
                customers_processed = len(safe_cust_ids)

        # 4. Delete eligible completed reminders falling in target year or before (older than 90 days)
        target_reminders = db.table("service_reminders")\
            .select("id, reminder_date")\
            .lte("reminder_date", end_date)\
            .eq("is_completed", True)\
            .execute()
        eligible_reminder_ids = []
        for r in (target_reminders.data or []):
            rid = str(r["id"])
            r_date = str(r["reminder_date"])[:10]
            if r_date < ninety_days_ago:
                eligible_reminder_ids.append(rid)
                
        if eligible_reminder_ids:
            db.table("service_reminders").delete().in_("id", eligible_reminder_ids).execute()
            reminders_processed = len(eligible_reminder_ids)

    return {
        "payments_count": payments_processed,
        "batteries_count": batteries_processed,
        "customers_count": customers_processed,
        "reminders_count": reminders_processed,
    }
