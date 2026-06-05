# Shree Ganadhish Battery Manager API — Backend

Backend REST API for **Shree Ganadhish Auto Ele & Battery Services** built with FastAPI, PostgreSQL (via Supabase Client), and Pydantic Settings.

---

## 1. Prerequisites
* Python 3.11+
* Supabase Account & Database Reference

---

## 2. Local Setup

### Step A: Clone and Configure Environment
1. Navigate to the backend folder:
   ```bash
   cd backend
   ```
2. Create a virtual environment and activate it:
   ```bash
   python -m venv venv
   # On Windows:
   venv\Scripts\activate
   # On macOS/Linux:
   source venv/bin/activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Generate an admin password bcrypt hash:
   ```bash
   python scripts/hash_password.py
   # Enter your password and copy the generated hash.
   ```
5. Create a `.env` file in `backend/.env` matching the template:
   ```env
   # Admin Credentials
   ADMIN_USERNAME=admin
   ADMIN_PASSWORD_HASH=your_bcrypt_hash_here

   # JWT Config
   JWT_SECRET_KEY=your_generated_32_character_hex_key
   JWT_EXPIRE_HOURS=8

   # Supabase Credentials
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_SERVICE_KEY=your-supabase-service-role-key

   # Email Backup Configuration (SMTP)
   SMTP_EMAIL=your-gmail-address@gmail.com
   SMTP_PASSWORD=your-gmail-app-password
   BACKUP_RECEIVER_EMAIL=recipient-email-address@gmail.com

   # CORS Configuration (Optional, defaults to '*')
   CORS_ORIGINS=http://localhost:8080,https://shree-ganadhish.vercel.app
   ```

### Step B: Database Migration
1. Log in to your **Supabase Dashboard**.
2. Open the **SQL Editor** on your Supabase project.
3. Paste and run the initial schema queries located in [001_initial_schema.sql](file:///c:/Users/vedan/OneDrive/Desktop/Shree%20Ganadhish/backend/db/migrations/001_initial_schema.sql).
4. Run the stock table schema queries in [002_stock.sql](file:///c:/Users/vedan/OneDrive/Desktop/Shree%20Ganadhish/backend/db/migrations/002_stock.sql).
5. Run the triggers and functions in [002_updated_at_and_triggers.sql](file:///c:/Users/vedan/OneDrive/Desktop/Shree%20Ganadhish/backend/db/migrations/002_updated_at_and_triggers.sql).
6. Run the analytics and follow-up tracking support in [003_analytics.sql](file:///c:/Users/vedan/OneDrive/Desktop/Shree%20Ganadhish/backend/db/migrations/003_analytics.sql).

---

## 3. REST API Endpoints
All endpoints are prefixed under `/api/v1` and require a valid Admin Bearer JWT token:

### Stock & Inventory Management
* **List Stock**: `GET /stock`
  * Parameters: `search` (filter by model name), `low_stock` (true/false), `archived` (true/false), `page`, `limit`
* **Create Stock Item**: `POST /stock`
* **Get Stock Item**: `GET /stock/{stock_id}`
* **Update Stock Config**: `PUT /stock/{stock_id}`
* **Increment Quantity**: `PATCH /stock/{stock_id}/increase`
* **Decrement Quantity**: `PATCH /stock/{stock_id}/decrease`
* **Archive Stock Item**: `PATCH /stock/{stock_id}/archive`
* **Restore Stock Item**: `PATCH /stock/{stock_id}/restore`
* **Reconcile Quantities**: `POST /stock/reconcile`

### Business Analytics & Dashboard (New)
* **Get Rich Dashboard Stats**: `GET /dashboard/stats`
  * Parameters: `period` (today, this_week, this_month, this_year), `vehicle_type` (2W/4W/TRUCK/INVERTER), `purchase_type` (RETAIL/SHOP)
  * Returns detailed ledger aggregates, KPI counters, top sold models, most pending udhari customers, out of stock count/lists, warranty follow-up alerts, and month-wise trend arrays (sales, growth, collections) for fl_chart.

### Exports, Backup & Cleanup (New)
* **Custom Excel Export**: `GET /exports/excel`
  * Parameters: `type` (all, customers, batteries, payments, stock), `date_from`, `date_to`, `year`, `month`
* **Download Yearly ZIP Backup**: `GET /exports/backup`
  * Parameters: `year` (int)
  * Returns an in-memory generated ZIP containing separate reports for the specified year.
* **Get Cloud Email Backup Status**: `GET /exports/backup-status`
  * Returns metadata about the last successful email backup date, next recommended backup date (30-day projection), and status.
* **Trigger Cloud Email Backup**: `POST /exports/email-backup`
  * Parameters: `year` (int), `month` (optional int)
  * Generates an in-memory ZIP package containing `customers.xlsx`, `batteries.xlsx`, `payments.xlsx`, `stock.xlsx`, and `reminders.xlsx`. Emails it to the store recipient, writes a log event in `activity_logs`, and returns the ZIP bytes to download locally.
* **Smart Archiving & Cleanup**: `POST /exports/archive`
  * Body: `{"action": "archive" | "delete", "year": year, "confirm_text": "typed_confirmation"}`
  * Enforces Smart Protections: Active guarantees, customers with pending balances, and active batteries are ignored automatically to prevent critical business data loss.

---

## 4. Run Commands

### Development Mode (with hot-reload)
```bash
uvicorn app.main:app --reload
```
API Documentation will be interactive at:
* Swagger UI: http://localhost:8000/docs
* ReDoc: http://localhost:8000/redoc

### Production Mode
```bash
python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

---

## 5. Railway Deployment Readiness
The app is fully prepared for one-click deployment on **Railway**:
1. **Dynamic Port Binding**: Auto-binds to `$PORT` set by Railway environment variables when run using the standard uvicorn entry point.
2. **CORS Env Var Support**: Configure `CORS_ORIGINS` to specify allowed frontend URLs, protecting the database from unauthorized cross-origin requests.
3. **Admin session tracking**: Uses a single secure JWT validation scheme.

---

## 6. Cloud Email Backup System Setup & Configuration

This section provides configuration guidelines for setting up the secure email backup system.

### A. Gmail SMTP App Password Setup (Gmail App Passwords only)
For security, Google does not allow logging into third-party apps directly with your primary password. Instead, you must generate an **App Password**:
1. Log in to your Google Account.
2. Go to **Security** settings.
3. Enable **2-Step Verification** (required to use App Passwords).
4. Under 2-Step Verification settings, scroll down to **App passwords**.
5. Create a new App Password:
   - Select **App**: Choose `Other (custom name)` and enter `Shree Ganadhish Manager`.
   - Click **Generate**.
6. Copy the 16-character code (e.g. `asxgbgfbojccduwv`). **Do not include spaces.**
7. Paste this code into your `.env` configuration under `SMTP_PASSWORD`.

### B. Railway Environment Variables Setup
To host the backend in production using Railway, configure the following environment variables in the Railway console:
- `SUPABASE_URL`: Your Supabase REST API URL.
- `SUPABASE_SERVICE_KEY`: Your Supabase Service Role API key.
- `ADMIN_USERNAME`: Your chosen admin username.
- `ADMIN_PASSWORD_HASH`: Your bcrypt hash generated using `hash_password.py`.
- `JWT_SECRET_KEY`: A secure 32-character hex string.
- `SMTP_EMAIL`: `shreeganadhishbattery@gmail.com`
- `SMTP_PASSWORD`: `asxgbgfbojccduwv`
- `BACKUP_RECEIVER_EMAIL`: `shreeganadhishbattery@gmail.com`

### C. Troubleshooting Steps
- **SMTP Authentication Error**: Verify that the Gmail address matches the account you generated the App Password on. Also double check that the App Password does not contain spaces.
- **Connection Timeout**: Ensure that network requests are not blocked by standard firewalls. Port `587` with TLS is standard and generally allowed on platforms like Railway.
- **Large ZIP Files**: We enforce a **20MB attachment safety limit**. If your database grows extremely large, select the `monthly` backup period instead of `yearly` to reduce the ZIP size.

