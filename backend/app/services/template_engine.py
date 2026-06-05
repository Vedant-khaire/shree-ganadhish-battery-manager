from supabase import Client
from typing import Optional, Tuple, Dict, Any

# ---------------------------------------------------------------------------
# Default Fallback Templates (Factory settings)
# ---------------------------------------------------------------------------
DEFAULT_TEMPLATES = {
    "SERVICE_REMINDER": (
        None,
        "Hello {customer_name}, your battery {battery_model} (Serial: {battery_serial}) is due for its scheduled maintenance checkup. Please bring your battery/vehicle to {shop_name} for a quick service check. Contact: {shop_mobile}"
    ),
    "WATER_CHECK": (
        None,
        "Hello {customer_name}, this is a friendly reminder from {shop_name} to check the distilled water levels of your Inverter battery {battery_model}. Checking regularly ensures long battery life! Contact: {shop_mobile}"
    ),
    "WARRANTY_EXPIRY": (
        None,
        "Hello {customer_name}, please note that the guarantee period of your battery {battery_model} (Serial: {battery_serial}) will expire in 5 days on {expiry_date}. Contact {shop_name} at {shop_mobile} for any queries."
    ),
    "UDHARI_RECOVERY": (
        None,
        "Namaste {customer_name},\nAapke battery account me ₹{pending_amount} baki hai.\nKripaya payment clear kare.\n\n* {shop_name} ({shop_mobile})"
    ),
    "SMS_SERVICE_REMINDER": (
        None,
        "Hello {customer_name}, battery {battery_model} (Serial: {battery_serial}) due for service checkup. Please bring to {shop_name}. Contact {shop_mobile}"
    ),
    "SMS_WATER_CHECK": (
        None,
        "Hello {customer_name}, please check distilled water level of Inverter battery {battery_model}. Shree Ganadhish Battery. Contact {shop_mobile}"
    ),
    "SMS_WARRANTY_EXPIRY": (
        None,
        "Hello {customer_name}, battery {battery_model} (Serial: {battery_serial}) warranty expires in 5 days on {expiry_date}. Contact {shop_name} at {shop_mobile}"
    ),
    "SMS_UDHARI_RECOVERY": (
        None,
        "Namaste {customer_name}, Aapke battery account me Rs. {pending_amount} pending baki hai. Kripaya payment clear kare. - {shop_name}"
    ),
    "EMAIL_BACKUP": (
        "{shop_name} Backup - {period_label}",
        "{shop_name} Battery Management Backup\n\nThis backup was generated automatically.\n\nIncluded:\n- Customers\n- Batteries\n- Payments\n- Stock\n- Reminders\n\nGenerated At: {timestamp}\n\nPlease store this backup securely."
    )
}

DEFAULT_SHOP_SETTINGS = {
    "shop_name": "Shree Ganadhish Battery Services",
    "shop_address": "Pune, Maharashtra, India",
    "shop_mobile": "9730911213",
    "whatsapp_number": "9730911213",
    "gst_number": "",
    "logo_url": "",
    "backup_email": "shreeganadhishbattery@gmail.com",
    "sms_sender_name": "SGABPL"
}


def get_shop_settings(db: Client) -> Dict[str, Any]:
    """Retrieves single shop settings record from database, falling back to defaults if not found."""
    try:
        res = db.table("shop_settings").select("*").eq("id", "00000000-0000-0000-0000-000000000001").execute()
        if res.data:
            return res.data[0]
    except Exception:
        pass
    return DEFAULT_SHOP_SETTINGS


def get_active_template(db: Client, template_type: str) -> Tuple[Optional[str], str]:
    """Queries database for the active message template of a given type, falling back to static defaults."""
    try:
        res = db.table("message_templates")\
            .select("message_subject, message_body")\
            .eq("template_type", template_type.upper())\
            .eq("is_active", True)\
            .execute()
        if res.data:
            return res.data[0].get("message_subject"), res.data[0]["message_body"]
    except Exception:
        pass
    return DEFAULT_TEMPLATES.get(template_type.upper(), (None, ""))


def _replace_vars(text: str, context: Dict[str, Any]) -> str:
    """Helper method to format brackets variables securely without causing KeyError."""
    rendered = text
    for key, val in context.items():
        placeholder = f"{{{key}}}"
        str_val = str(val) if val is not None else ""
        rendered = rendered.replace(placeholder, str_val)
    return rendered


def render_message(db: Client, template_type: str, context: Dict[str, Any]) -> Tuple[Optional[str], str]:
    """Retrieves active templates & shop settings, merging fields to render final subject and body dispatches."""
    subj_tmpl, body_tmpl = get_active_template(db, template_type)
    shop = get_shop_settings(db)
    
    # Merge shop variables with customer context (context takes precedence)
    merged_context = {**shop, **context}
    
    rendered_subj = _replace_vars(subj_tmpl, merged_context) if subj_tmpl else None
    rendered_body = _replace_vars(body_tmpl, merged_context)
    
    return rendered_subj, rendered_body


def log_message(
    db: Client,
    customer_name: str,
    mobile_number: str,
    channel: str,
    message_type: str,
    message_body: str,
    status: str = "SENT",
    provider_id: Optional[str] = None
) -> dict:
    """Inserts a permanent record of the outgoing message into the message_logs table."""
    try:
        payload = {
            "customer_name": customer_name,
            "mobile_number": mobile_number,
            "channel": channel.upper(),
            "message_type": message_type,
            "message_body": message_body,
            "status": status,
            "provider_id": provider_id
        }
        res = db.table("message_logs").insert(payload).execute()
        if res.data:
            return res.data[0]
    except Exception:
        pass
    return {}
