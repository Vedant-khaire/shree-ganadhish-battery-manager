# Shree Ganadhish Auto Electric & Battery Services
## Complete Business Management Super Dashboard & SMART Reminder System

This project is a premium business management system designed for **Shree Ganadhish Auto Electric & Battery Services**. It features a modern, responsive single-page architecture built with **FastAPI (Python)** on the backend and **Flutter Web** on the frontend, using **Supabase** for database services.

---

## 📂 Project Structure

* **[`/frontend`](file:///c:/Users/vedan/OneDrive/Desktop/Shree%20Ganadhish/frontend)**: Flutter Web Application containing the Cinematic Super Dashboard, Customer Workspace, Stock Ledger, Payments Tracker, and PWA config.
* **[`/backend`](file:///c:/Users/vedan/OneDrive/Desktop/Shree%20Ganadhish/backend)**: Python FastAPI app handling database orchestration, security layer, analytics aggregates, Excel sheets generation, and backup zips.

---

## ⚡ Key Architecture & Features

### 1. Cinematic Super Dashboard & Analytics
* **Gradient Hero Panel**: Welcome card featuring localized dates, active periods, and an interactive reporting chip-set.
* **10 KPI Ticker Grid**: Realtime roll-up counters for Total Customers, Daily Sales ledger, Collections, Pending Udhari, Repeat Customers, Low Stock alerts, and Expiring Guarantees.
* **FlChart Visuals**: Custom-drawn line and bar charts illustrating Mom sales growth rates and monthly collection trends.
* **GLOW Warning Banners**: Pulse animations highlighting critical out-of-stock models and overdue udhari payments.

### 2. SMART Reminder System & WhatsApp Integration
* **Auto-Scheduling Engine**: Generates reminders on battery sale registrations:
  * *Inverter Batteries*: Water checks (every 6 months) and annual maintenance checks.
  * *Vehicle Batteries*: Annual maintenance checks.
  * *All Batteries*: Expiry warnings 30 days before guarantee periods end.
* **WhatsApp Follow-up buttons**: Launch pre-filled, URL-encoded templates pointing to `https://api.whatsapp.com/send` to bypass expensive SMS API costs, working universally on mobile and desktop web browser endpoints.
* **Reminders List Workspace**: Added directly into the **Customer Details Page**, enabling one-stop operational support (Add custom reminders, toggle completion, send WhatsApp alerts, delete old alerts).

### 3. SMART Weekly Udhari Recovery Reminder System
* **Weekly Debt Tracking**: Auto-schedules recurring follow-ups every 7 days for any customer with outstanding balances (`pending_amount > 0` and `is_settled = false`).
* **Supabase Free-Tier Safe**: Limits database row storage by keeping a maximum of 4 uncompleted upcoming reminders at any time. Reschedules subsequent weeks dynamically when one is completed.
* **Instant Settlement Flow**: Marking a payment settled triggers cascading DB updates that automatically complete outstanding Udhari reminders and stop future reminder generation.
* **Red Glow Warnings & Prioritization**: Overdue collections float to the top of list views with custom sorting and display a RED glowing warning outline to catch the shop owner's attention.
* **Direct Mark Paid Trigger**: Added one-click settlement shortcuts on both mobile cards and desktop tables redirecting to the payment settlement confirmations.

### 4. Long-Term Storage Safeguards & Pruning
* **Pruning Rules**: Automatically purges system-level `activity_logs` older than 90 days on backup and cleanup triggers, ensuring Supabase free-tier limits are never breached.
* **Udhari Retention Policy**: Auto-deletes completed Udhari reminders older than 60 days to optimize storage.
* **Reminder Retention Lifecycle Policy**: Restricts reminder deletion unless:
  * Associated battery warranty has expired.
  * All scheduled reminder cycles are completed.
  * No future reminder schedules exist.
  * The activity log is older than 6 months.
* **In-Memory Exporter**: Zips Excel sheets (`customers.xlsx`, `guarantees.xlsx`, `udhari.xlsx`, `stock.xlsx`, and `reminders.xlsx`) in-memory, bypassing server disk write limits.

### 5. Premium UI/UX & Mobile Optimizations
* **Dark Mode Toggler**: AppBar-based switch that dynamically shifts brightness configurations, storing preferences inside local web storage.
* **PWA Install Support**: Captured `beforeinstallprompt` event inside `index.html` allowing desktop and mobile browsers to download and install the workspace natively as a standalone app.
* **Responsive Performance**: Heavy shadows and glassmorphism blurs are turned off dynamically on mobile browser viewports (widths `< 700px`) to prevent rendering lag.
* **Zero Warnings & Clean Analyzer**: Zero compiler errors and warnings under `flutter analyze` ensuring optimal compilation speeds.

---

## 🚀 Running the Project Locally

### 1. Backend Service
1. Navigate to `/backend`.
2. Install dependencies: `pip install -r requirements.txt`.
3. Set environment parameters in a `.env` file (Supabase credentials, JWT secrets).
4. Run fastapi server: `uvicorn app.main:app --reload --port 8000`.

### 2. Frontend client
1. Navigate to `/frontend`.
2. Compile and run: `flutter run -d chrome --dart-define=API_URL=http://localhost:8000/api/v1`.
