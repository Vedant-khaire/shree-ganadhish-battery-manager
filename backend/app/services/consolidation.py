import logging
from supabase import Client

logger = logging.getLogger("uvicorn.error")

def merge_duplicate_customers_in_db(db: Client) -> None:
    """
    Finds customers with duplicate names (case-insensitive, trimmed).
    Merges their details, updates all referencing rows (batteries, payments, reminders, transactions)
    to point to the oldest (primary) customer, deletes the duplicates, and consolidates their unpaid payments.
    """
    logger.info("[CONSOLIDATION] Checking database for duplicate customers...")
    try:
        # Fetch all active customers
        cust_res = db.table("customers").select("*").eq("is_archived", False).execute()
        if not cust_res.data:
            logger.info("[CONSOLIDATION] No active customers found.")
            return

        # Group by name (trimmed and lowercased)
        grouped = {}
        for c in cust_res.data:
            name_key = c["name"].strip().lower()
            grouped.setdefault(name_key, []).append(c)

        consolidated_any = False

        for name_key, group in grouped.items():
            if len(group) < 2:
                continue

            consolidated_any = True
            # Sort by created_at ascending to treat the oldest as the primary customer
            group.sort(key=lambda x: x.get("created_at") or "")
            primary = group[0]
            primary_id = primary["id"]
            duplicates = group[1:]
            duplicate_ids = [d["id"] for d in duplicates]

            logger.info(
                f"[CONSOLIDATION] Found duplicate group for name '{primary['name']}': "
                f"Primary: {primary_id}, Duplicates: {duplicate_ids}"
            )

            # 1. Merge attributes into primary
            updates = {}
            for field in ["mobile", "vehicle_no", "vehicle_type", "area", "pincode", "purchase_type"]:
                if not primary.get(field):
                    # Find first duplicate that has this field
                    for d in duplicates:
                        if d.get(field):
                            updates[field] = d[field]
                            primary[field] = d[field] # Update local copy
                            break

            # Handle scrap battery fields
            scrap_pending = primary.get("scrap_battery_pending", False) or any(d.get("scrap_battery_pending", False) for d in duplicates)
            if scrap_pending != primary.get("scrap_battery_pending"):
                updates["scrap_battery_pending"] = scrap_pending
                primary["scrap_battery_pending"] = scrap_pending

            scrap_expected = max(float(primary.get("scrap_expected_value") or 0.0), *[float(d.get("scrap_expected_value") or 0.0) for d in duplicates])
            if scrap_expected != float(primary.get("scrap_expected_value") or 0.0):
                updates["scrap_expected_value"] = scrap_expected
                primary["scrap_expected_value"] = scrap_expected

            scrap_received = max(float(primary.get("scrap_received_value") or 0.0), *[float(d.get("scrap_received_value") or 0.0) for d in duplicates])
            if scrap_received != float(primary.get("scrap_received_value") or 0.0):
                updates["scrap_received_value"] = scrap_received
                primary["scrap_received_value"] = scrap_received

            if not primary.get("scrap_received_date"):
                for d in duplicates:
                    if d.get("scrap_received_date"):
                        updates["scrap_received_date"] = d["scrap_received_date"]
                        primary["scrap_received_date"] = d["scrap_received_date"]
                        break

            if updates:
                db.table("customers").update(updates).eq("id", primary_id).execute()
                logger.info(f"[CONSOLIDATION] Merged attributes for primary customer '{primary['name']}': {updates}")

            # 2. Update referencing tables for each duplicate customer
            for dup_id in duplicate_ids:
                # Update Batteries
                db.table("batteries").update({"customer_id": primary_id}).eq("customer_id", dup_id).execute()
                # Update Payments
                db.table("payments").update({"customer_id": primary_id}).eq("customer_id", dup_id).execute()
                # Update Reminders
                db.table("service_reminders").update({"customer_id": primary_id}).eq("customer_id", dup_id).execute()
                # Update Payment Transactions
                db.table("payment_transactions").update({"customer_id": primary_id}).eq("customer_id", dup_id).execute()

                # Delete duplicate customer
                db.table("customers").delete().eq("id", dup_id).execute()
                logger.info(f"[CONSOLIDATION] Merged and deleted duplicate customer record: {dup_id}")

            # 3. Consolidate unpaid payments for the primary customer
            unpaid_res = (
                db.table("payments")
                .select("*")
                .eq("customer_id", primary_id)
                .eq("is_settled", False)
                .eq("is_archived", False)
                .execute()
            )
            unpaid_payments = unpaid_res.data or []
            if len(unpaid_payments) > 1:
                # Sort unpaid payments by created_at ascending
                unpaid_payments.sort(key=lambda x: x.get("created_at") or "")
                primary_pay = unpaid_payments[0]
                primary_pay_id = primary_pay["id"]
                other_pays = unpaid_payments[1:]
                other_pay_ids = [p["id"] for p in other_pays]

                total_sum = sum(float(p["total_amount"]) for p in unpaid_payments)
                paid_sum = sum(float(p.get("paid_amount", 0.0)) for p in unpaid_payments)
                pending_sum = round(max(total_sum - paid_sum, 0.0), 2)
                is_settled = (pending_sum == 0.0)

                # Update primary payment with consolidated amounts
                db.table("payments").update({
                    "total_amount": total_sum,
                    "paid_amount": paid_sum,
                    "pending_amount": pending_sum,
                    "is_settled": is_settled
                }).eq("id", primary_pay_id).execute()

                logger.info(
                    f"[CONSOLIDATION] Consolidated unpaid payments for customer '{primary['name']}': "
                    f"Merged {other_pay_ids} into {primary_pay_id}. New pending: ₹{pending_sum}"
                )

                # Move transactions and reminders to primary payment
                for other_pay_id in other_pay_ids:
                    # Update Payment Transactions
                    db.table("payment_transactions").update({"payment_id": primary_pay_id}).eq("payment_id", other_pay_id).execute()
                    # Update Service Reminders
                    db.table("service_reminders").update({"linked_payment_id": primary_pay_id}).eq("linked_payment_id", other_pay_id).execute()
                    
                    # Delete duplicate payment record
                    db.table("payments").delete().eq("id", other_pay_id).execute()
                    logger.info(f"[CONSOLIDATION] Deleted consolidated payment record: {other_pay_id}")

                # Clean up and reschedule service reminders for the consolidated payment if not settled
                try:
                    # Cancel existing uncompleted udhari reminders for this payment to recreate fresh ones
                    db.table("service_reminders").delete().eq("linked_payment_id", primary_pay_id).eq("is_completed", False).execute()
                    if not is_settled:
                        from app.services.reminder import schedule_udhari_reminders
                        schedule_udhari_reminders(db, primary_pay_id)
                except Exception as ex:
                    logger.error(f"[CONSOLIDATION] Failed to reschedule reminders: {ex}")

        if consolidated_any:
            logger.info("[CONSOLIDATION] Finished merging duplicates successfully.")
        else:
            logger.info("[CONSOLIDATION] No duplicate customers found to merge.")

    except Exception as e:
        logger.error(f"[CONSOLIDATION] Error running customer merge: {e}", exc_info=True)
