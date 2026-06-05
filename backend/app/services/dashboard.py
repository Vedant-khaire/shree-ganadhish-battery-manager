import datetime
from datetime import date, timedelta
from typing import Optional, List, Dict
from supabase import Client


def _parse_date(val) -> date:
    if not val:
        return date.today()
    try:
        return date.fromisoformat(str(val)[:10])
    except Exception:
        return date.today()


def get_dashboard_stats(
    db: Client,
    period: str = "this_month",
    vehicle_type: Optional[str] = None,
    purchase_type: Optional[str] = None,
) -> dict:
    """
    Returns highly detailed business analytics for Shree Ganadhish.
    Aggregates data efficiently using local Python grouping on lightweight selects,
    minimizing database network round-trips and loading speeds.
    """
    today = date.today()
    start_of_week = today - timedelta(days=today.weekday())  # Monday
    start_of_month = today.replace(day=1)
    start_of_year = today.replace(month=1, day=1)

    # Calculate period boundaries
    p_start = start_of_month
    p_end = today
    if period == "today":
        p_start = today
        p_end = today
    elif period == "this_week":
        p_start = start_of_week
        p_end = today
    elif period == "this_month":
        p_start = start_of_month
        p_end = today
    elif period == "this_year":
        p_start = start_of_year
        p_end = today

    # 1. Fetch Lightweight Core Data
    # A. Customers (active only)
    cust_res = db.table("customers").select("id, name, mobile, area, purchase_type, created_at, scrap_battery_pending, scrap_expected_value, scrap_received_value, scrap_received_date").eq("is_archived", False).execute()
    customers = cust_res.data or []

    # Apply customer filters first
    if purchase_type:
        customers = [c for c in customers if str(c.get("purchase_type")).upper() == purchase_type.upper()]

    cust_ids = {str(c["id"]) for c in customers}
    cust_map = {str(c["id"]): c for c in customers}

    # B. Batteries (active only)
    batt_res = db.table("batteries").select("id, customer_id, battery_type, model_number, sale_date, warranty_expiry, is_followed_up").eq("is_archived", False).execute()
    batteries = batt_res.data or []

    # Filter batteries by customer scope
    batteries = [b for b in batteries if str(b.get("customer_id")) in cust_ids]

    # Filter batteries by vehicle_type (battery_type)
    if vehicle_type:
        batteries = [b for b in batteries if str(b.get("battery_type")).upper() == vehicle_type.upper()]

    batt_ids = {str(b["id"]) for b in batteries}
    batt_map = {str(b["id"]): b for b in batteries}

    # C. Payments (active only)
    pay_res = db.table("payments").select("id, customer_id, battery_id, total_amount, paid_amount, pending_amount, is_settled, created_at").eq("is_archived", False).execute()
    payments = pay_res.data or []

    # Filter payments by customer and battery scope
    payments = [p for p in payments if str(p.get("customer_id")) in cust_ids]
    if vehicle_type:
        # If vehicle_type filter is active, only include payments linked to matching batteries
        payments = [p for p in payments if str(p.get("battery_id")) in batt_ids]

    # D. Stock (active only)
    stock_res = db.table("battery_stock").select("model_name, battery_type, quantity, low_stock_threshold").eq("is_archived", False).execute()
    stock_items = stock_res.data or []
    # Filter stock items if vehicle_type filter is active
    if vehicle_type:
        stock_items = [s for s in stock_items if str(s.get("battery_type")).upper() == vehicle_type.upper()]

    # E. Shops and Shop Purchases (wrapped in try-except for migration safety)
    shops_data = []
    shop_purchases_data = []
    shop_payments_data = []
    try:
        shops_res = db.table("shops").select("id, shop_name, owner_name, mobile, created_at").eq("is_archived", False).execute()
        shops_data = shops_res.data or []
        
        pur_res = db.table("shop_purchases").select("id, shop_id, battery_model, quantity, amount, udhari_amount, purchase_date").execute()
        shop_purchases_data = pur_res.data or []
        
        pay_res = db.table("shop_payments").select("id, shop_id, total_amount, paid_amount, pending_amount, is_settled").execute()
        shop_payments_data = pay_res.data or []
    except Exception:
        pass

    # ---------------------------------------------------------------------------
    # 2. Aggregations & Analytics
    # ---------------------------------------------------------------------------

    # A. Period Specific KPI Counts
    customers_added_today = sum(1 for c in customers if _parse_date(c["created_at"]) == today)
    customers_added_this_week = sum(1 for c in customers if _parse_date(c["created_at"]) >= start_of_week)
    customers_added_this_month = sum(1 for c in customers if _parse_date(c["created_at"]) >= start_of_month)

    batteries_sold_today = sum(1 for b in batteries if _parse_date(b["sale_date"]) == today)
    batteries_sold_this_week = sum(1 for b in batteries if _parse_date(b["sale_date"]) >= start_of_week)
    batteries_sold_this_month = sum(1 for b in batteries if _parse_date(b["sale_date"]) >= start_of_month)

    # Selected Period daily ledger aggregates (Sales, Collection, Pending)
    period_sales = 0.0
    period_collection = 0.0
    period_pending = 0.0
    for p in payments:
        p_date = _parse_date(p["created_at"])
        if p_start <= p_date <= p_end:
            period_sales += float(p.get("total_amount") or 0.0)
            period_collection += float(p.get("paid_amount") or 0.0)
            period_pending += float(p.get("pending_amount") or 0.0)

    # Overall Sales Analytics
    total_revenue = sum(float(p.get("total_amount") or 0.0) for p in payments)
    total_pending_udhari = sum(float(p.get("pending_amount") or 0.0) for p in payments)
    total_settled_amount = sum(float(p.get("paid_amount") or 0.0) for p in payments)

    # Today's Collections KPI
    today_collections = sum(float(p.get("paid_amount") or 0.0) for p in payments if _parse_date(p["created_at"]) == today)

    # B. Inventory Analytics
    total_stock_units = sum(int(s.get("quantity") or 0) for s in stock_items)
    total_stock_models = len(stock_items)
    low_stock_count = sum(1 for s in stock_items if 0 < int(s.get("quantity") or 0) <= int(s.get("low_stock_threshold") or 2))
    out_of_stock_count = sum(1 for s in stock_items if int(s.get("quantity") or 0) == 0)
    out_of_stock_models = [
        {"model_name": s["model_name"], "battery_type": s["battery_type"]}
        for s in stock_items if int(s.get("quantity") or 0) == 0
    ]

    # C. Top Selling Battery Models
    model_sales = {}
    for b in batteries:
        model = (b.get("model_number") or "").strip().upper()
        b_type = (b.get("battery_type") or "").strip().upper()
        if model:
            key = (model, b_type)
            model_sales[key] = model_sales.get(key, 0) + 1

    sorted_models = sorted(model_sales.items(), key=lambda x: x[1], reverse=True)
    top_selling_models = [
        {
            "model_name": k[0],
            "battery_type": k[1],
            "sales_count": count
        }
        for k, count in sorted_models[:5]
    ]

    most_sold_model = "N/A"
    if top_selling_models:
        most_sold_model = f"{top_selling_models[0]['model_name']} ({top_selling_models[0]['sales_count']} sold)"

    # D. Most Pending Customers (Top 5 Outstanding Udhari)
    cust_pending = {}
    for p in payments:
        cid = str(p["customer_id"])
        pending = float(p.get("pending_amount") or 0.0)
        if pending > 0:
            cust_pending[cid] = cust_pending.get(cid, 0.0) + pending

    sorted_pending = sorted(cust_pending.items(), key=lambda x: x[1], reverse=True)
    most_pending_customers = []
    for cid, amount in sorted_pending[:5]:
        c_info = cust_map.get(cid)
        if c_info:
            most_pending_customers.append({
                "customer_name": c_info["name"],
                "mobile_number": c_info["mobile"],
                "pending_amount": round(amount, 2)
            })

    # E. Warranty & Expiry follow-up
    active_guarantees = 0
    expiring_soon_30_days = 0
    expired_no_followup = 0

    for b in batteries:
        exp_date = _parse_date(b["warranty_expiry"])
        is_fup = b.get("is_followed_up", False)
        if exp_date >= today:
            active_guarantees += 1
            diff_days = (exp_date - today).days
            if diff_days <= 30:
                expiring_soon_30_days += 1
        else:
            if not is_fup:
                expired_no_followup += 1

    # F. Most Active Villages/Areas
    area_counts = {}
    for c in customers:
        area = (c.get("area") or "").strip().upper()
        if area:
            area_counts[area] = area_counts.get(area, 0) + 1

    sorted_areas = sorted(area_counts.items(), key=lambda x: x[1], reverse=True)
    most_active_areas = [
        {"area": area, "customer_count": count}
        for area, count in sorted_areas[:5]
    ]

    # G. Payments Summary Counts
    pending_payments_count = sum(1 for p in payments if not p.get("is_settled", False))
    settled_payments_count = sum(1 for p in payments if p.get("is_settled", False))

    # ---------------------------------------------------------------------------
    # 3. Monthly Trends for Visual Charts (Jan - Dec)
    # ---------------------------------------------------------------------------
    month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    monthly_sales_trend = {m: 0 for m in month_names}
    customer_growth_trend = {m: 0 for m in month_names}
    payment_collection_trend = {m: 0.0 for m in month_names}

    # Populate monthly sales
    for b in batteries:
        b_date = _parse_date(b["sale_date"])
        if b_date.year == today.year:
            m_name = month_names[b_date.month - 1]
            monthly_sales_trend[m_name] += 1

    # Populate customer growth
    for c in customers:
        c_date = _parse_date(c["created_at"])
        if c_date.year == today.year:
            m_name = month_names[c_date.month - 1]
            customer_growth_trend[m_name] += 1

    # Populate payments collection
    for p in payments:
        p_date = _parse_date(p["created_at"])
        if p_date.year == today.year:
            m_name = month_names[p_date.month - 1]
            payment_collection_trend[m_name] += float(p.get("paid_amount") or 0.0)

    # A. MoM sales growth calculation
    current_month_index = today.month - 1
    prev_month_index = (today.month - 2) % 12
    current_month_sales = monthly_sales_trend[month_names[current_month_index]]
    prev_month_sales = monthly_sales_trend[month_names[prev_month_index]]
    if prev_month_sales > 0:
        sales_growth_pct = round(((current_month_sales - prev_month_sales) / prev_month_sales) * 100, 1)
    else:
        sales_growth_pct = 100.0 if current_month_sales > 0 else 0.0

    # B. Repeat customers count
    cust_purchase_counts = {}
    for b in batteries:
        cid = str(b.get("customer_id"))
        cust_purchase_counts[cid] = cust_purchase_counts.get(cid, 0) + 1
    repeat_customers_count = sum(1 for count in cust_purchase_counts.values() if count > 1)

    # C. Average payment recovery time
    recovery_durations = []
    for p in payments:
        if p.get("is_settled") and p.get("updated_at") and p.get("created_at"):
            try:
                created = _parse_date(p["created_at"])
                updated = _parse_date(p["updated_at"])
                duration = (updated - created).days
                if duration >= 0:
                    recovery_durations.append(duration)
            except Exception:
                pass
    avg_payment_recovery_days = round(sum(recovery_durations) / len(recovery_durations), 1) if recovery_durations else 0.0

    # D. Service Reminders count
    try:
        rem_res = db.table("service_reminders")\
            .select("id, reminder_type, reminder_date, linked_payment_id, reminder_category, reminder_status")\
            .eq("is_completed", False)\
            .eq("is_archived", False)\
            .execute()
        reminders_list = rem_res.data or []
    except Exception:
        reminders_list = []
    
    today_str = today.isoformat()
    due_today_count = sum(1 for r in reminders_list if r.get("reminder_date") == today_str or r.get("reminder_status") == "DUE")
    overdue_count = sum(1 for r in reminders_list if r.get("reminder_status") == "OVERDUE")
    upcoming_warranty_expiry_count = sum(1 for r in reminders_list if r.get("reminder_type") == "WARRANTY_EXPIRY")
    pending_udhari_recovery_count = sum(1 for r in reminders_list if r.get("reminder_type") in ("UDHARI", "UDHARI_RECOVERY") or r.get("reminder_category") == "UDHARI")
    water_checks_due_count = sum(1 for r in reminders_list if r.get("reminder_type") == "WATER_CHECK")
    service_due_count = sum(1 for r in reminders_list if r.get("reminder_type") == "SERVICE")

    upcoming_service_reminders_count = service_due_count

    # Udhari Specific Metrics
    pending_udhari_cust_ids = {str(p["customer_id"]) for p in payments if float(p.get("pending_amount") or 0.0) > 0 and not p.get("is_settled", False)}
    total_pending_udhari_customers = len(pending_udhari_cust_ids)
    
    collection_efficiency_pct = (total_settled_amount / total_revenue) * 100 if total_revenue > 0 else 100.0
    
    weekly_recovery_due = 0.0
    overdue_collections = 0.0
    pay_pending_map = {str(p["id"]): float(p.get("pending_amount") or 0.0) for p in payments}
    
    today_dt = date.today()
    one_week_later = today_dt + timedelta(days=7)
    
    weekly_payments_seen = set()
    overdue_payments_seen = set()
    for r in reminders_list:
        if r.get("reminder_category") in ("UDHARI", "UDHARI_RECOVERY") or r.get("reminder_type") in ("UDHARI", "UDHARI_RECOVERY"):
            r_date_str = r.get("reminder_date")
            if r_date_str:
                try:
                    r_date = date.fromisoformat(r_date_str[:10])
                    p_id = str(r.get("linked_payment_id"))
                    p_pending = pay_pending_map.get(p_id, 0.0)
                    
                    if r_date < today_dt:
                        if p_id not in overdue_payments_seen:
                            overdue_collections += p_pending
                            overdue_payments_seen.add(p_id)
                    if today_dt <= r_date <= one_week_later:
                        if p_id not in weekly_payments_seen:
                            weekly_recovery_due += p_pending
                            weekly_payments_seen.add(p_id)
                except Exception:
                    pass

    # E. Fetch 10 most recent activity logs for dashboard timeline
    try:
        activity_res = db.table("activity_logs")\
            .select("action, created_at")\
            .order("created_at", desc=True)\
            .range(0, 9)\
            .execute()
        recent_activities = activity_res.data or []
    except Exception:
        recent_activities = []

    # Format trends for chart compatibility
    formatted_sales = [{"month": m, "value": monthly_sales_trend[m]} for m in month_names]
    formatted_growth = [{"month": m, "value": customer_growth_trend[m]} for m in month_names]
    formatted_collection = [{"month": m, "value": round(payment_collection_trend[m], 2)} for m in month_names]

    # ---------------------------------------------------------------------------
    # Shops and Retailers Aggregations
    # ---------------------------------------------------------------------------
    total_shops = len(shops_data)
    total_shop_udhari = sum(float(p["pending_amount"]) for p in shop_payments_data)
    highest_outstanding_shop_balance = max([float(p["pending_amount"]) for p in shop_payments_data], default=0.0)
    pending_udhari_shops_count = sum(1 for p in shop_payments_data if float(p["pending_amount"]) > 0)

    # Filter purchases by period
    period_shop_purchases = [
        p for p in shop_purchases_data 
        if p_start <= _parse_date(p["purchase_date"]) <= p_end
    ]
    total_shop_purchases_value = sum(float(p["amount"]) for p in period_shop_purchases)

    # Top Purchasing Shops
    shop_map = {str(s["id"]): s["shop_name"] for s in shops_data}
    shop_purchases_sum = {}
    for p in shop_purchases_data:
        sid = str(p["shop_id"])
        shop_purchases_sum[sid] = shop_purchases_sum.get(sid, 0.0) + float(p["amount"])

    top_purchasing_shops = []
    for sid, amt in shop_purchases_sum.items():
        if sid in shop_map:
            top_purchasing_shops.append({
                "shop_id": sid,
                "shop_name": shop_map[sid],
                "total_amount": round(amt, 2)
            })
    top_purchasing_shops.sort(key=lambda x: x["total_amount"], reverse=True)
    top_purchasing_shops = top_purchasing_shops[:5]

    # Top Pending Shops
    top_pending_shops = []
    for p in shop_payments_data:
        sid = str(p["shop_id"])
        pending_amt = float(p["pending_amount"])
        if pending_amt > 0 and sid in shop_map:
            top_pending_shops.append({
                "shop_id": sid,
                "shop_name": shop_map[sid],
                "pending_amount": round(pending_amt, 2)
            })
    top_pending_shops.sort(key=lambda x: x["pending_amount"], reverse=True)
    top_pending_shops = top_pending_shops[:5]

    # Scrap Battery Analytics
    pending_scrap_count = sum(1 for c in customers if c.get("scrap_battery_pending"))
    pending_scrap_value = sum(float(c.get("scrap_expected_value") or 0.0) for c in customers if c.get("scrap_battery_pending"))
    collected_scrap_value = sum(float(c.get("scrap_received_value") or 0.0) for c in customers if not c.get("scrap_battery_pending"))

    return {
        "recent_activities": recent_activities,
        "scrap_summary": {
            "pending_count": pending_scrap_count,
            "pending_value": round(pending_scrap_value, 2),
            "collected_value": round(collected_scrap_value, 2),
        },
        "smart_business_stats": {
            "avg_payment_recovery_days": avg_payment_recovery_days,
            "sales_growth_pct": sales_growth_pct,
            "repeat_customers_count": repeat_customers_count,
            "upcoming_service_reminders_count": upcoming_service_reminders_count,
            "total_pending_collections": round(total_pending_udhari, 2),
            "warranty_conversion_opportunities": expiring_soon_30_days
        },
        # Dynamic Period aggregates
        "period": period,
        "today_total_sales_amount": round(period_sales, 2),
        "today_total_collection": round(period_collection, 2),
        "today_total_pending": round(period_pending, 2),

        # Customer Analytics
        "customers": {
            "added_today": customers_added_today,
            "added_this_week": customers_added_this_week,
            "added_this_month": customers_added_this_month,
            "total_active": len(customers),
        },

        # Sales Analytics
        "sales": {
            "sold_today": batteries_sold_today,
            "sold_this_week": batteries_sold_this_week,
            "sold_this_month": batteries_sold_this_month,
            "total_revenue": round(total_revenue, 2),
            "total_pending_udhari": round(total_pending_udhari, 2),
            "total_settled_amount": round(total_settled_amount, 2),
            "most_sold_model": most_sold_model,
        },

        # Inventory Analytics
        "inventory": {
            "total_stock_units": total_stock_units,
            "total_stock_models": total_stock_models,
            "low_stock_count": low_stock_count,
            "out_of_stock_count": out_of_stock_count,
            "out_of_stock_models": out_of_stock_models,
        },

        # Warranty Analytics
        "warranty": {
            "active": active_guarantees,
            "expiring_soon_30_days": expiring_soon_30_days,
            "expired_no_followup": expired_no_followup,
        },

        # Payment Analytics
        "payments": {
            "today_collections": round(today_collections, 2),
            "pending_count": pending_payments_count,
            "settled_count": settled_payments_count,
            "total_pending_udhari_customers": total_pending_udhari_customers,
            "weekly_recovery_due": round(weekly_recovery_due, 2),
            "overdue_collections": round(overdue_collections, 2),
            "collection_efficiency_pct": round(collection_efficiency_pct, 1),
        },

        # Lists for Control Center Panels
        "top_selling_models": top_selling_models,
        "most_pending_customers": most_pending_customers,
        "most_active_areas": most_active_areas,

        # Chart Visual Trend Data
        "trends": {
            "monthly_sales_trend": formatted_sales,
            "customer_growth_trend": formatted_growth,
            "payment_collection_trend": formatted_collection,
        },

        # Reminders Summary
        "reminders_summary": {
            "due_today": due_today_count,
            "overdue": overdue_count,
            "upcoming_warranty_expiry": upcoming_warranty_expiry_count,
            "pending_udhari_recovery": pending_udhari_recovery_count,
            "water_checks_due": water_checks_due_count,
            "service_due": service_due_count
        },

        # Shops Analytics (Refinement 5 & 11)
        "shops": {
            "total_shops": total_shops,
            "total_shop_udhari": round(total_shop_udhari, 2),
            "highest_outstanding_shop_balance": round(highest_outstanding_shop_balance, 2),
            "total_shop_purchases_value": round(total_shop_purchases_value, 2),
            "top_purchasing_shops": top_purchasing_shops,
            "top_pending_shops": top_pending_shops,
            "pending_udhari_shops_count": pending_udhari_shops_count
        }
    }
