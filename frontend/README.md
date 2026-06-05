# Shree Ganadhish Battery Manager Client — Frontend

Flutter Web management interface for **Shree Ganadhish Auto Ele & Battery Services** featuring a responsive dashboard, customer directory, guarantee tracking registry, outstanding payment ledgers, and a lightweight stock/inventory management module.

---

## 1. Prerequisites
* Flutter SDK (3.19.0+ recommended)
* Target web platform enabled (`flutter config --enable-web`)

---

## 2. Environment Configuration
The frontend application uses `--dart-define` to inject configuration variables during compile time. This removes hardcoded endpoints, enabling dynamic environment builds.

### Config Options
* `API_URL`: Base REST url for backend REST endpoints (default: `http://localhost:8000/api/v1`).

---

## 3. Key Modules & Features

### Business Control Center & Dashboard (New)
The Day 9 **Business Analytics** control center includes:
* **Dynamic Analytics Filters**: Interactive header with filter dropdowns for Period (`Today`, `This Week`, `This Month`, `This Year`), Vehicle/Battery Type (`All`, `2W`, `4W`, `TRUCK`, `INVERTER`), and Purchase Type (`All`, `RETAIL`, `SHOP`).
* **Daily Ledger Summary**: Displays Sales Value generated, Cash Collections made, and Outstanding Pending balances for the selected period.
* **Alert Badges**: Prominent RED critical badge displaying Out-of-Stock count and model list.
* **Visual Activity Charts**: Employs `fl_chart` to render month-wise Bar/Line visual indicators for Monthly Sales, Customer Growth, and Cash Collections, featuring empty-data handling placeholders if stats are 0.
* **Insight & Follow-up Panels**: Displays Top 5 Selling Models, Highest Pending Udhari customers, Coverage areas/villages, and Expiry follow-up checklists.

### Cloud Email Backups & Safe Cleanup Workspace (New)
The **Exports Page** has been redesigned into a comprehensive administrative Backup & Cleanup workspace:
* **Secure Cloud & Email Backup**: Compiles a ZIP archive containing all business worksheets (`customers.xlsx`, `batteries.xlsx`, `payments.xlsx`, `stock.xlsx`, `reminders.xlsx`) fully in-memory, emails it to the configured address via TLS SMTP, and triggers a local browser download copy at the same time.
* **Monthly / Yearly Selector**: Offers interactive toggles to target either Monthly or Yearly scopes.
* **SaaS Metadata Panel**: Highlights the `Last Backup Sent` date, the `Recommended Next Backup` date, and displays prominent status badges (`ACTION REQUIRED` vs `UP TO DATE`).
* **Yearly Zip Backup**: Downloads a yearly consolidated database ZIP file locally (includes reminders).
* **Smart Cleanup Safeguards**: Auto-ignores/preserves active warranties, customers with pending balances, and active battery registries to prevent business data loss.
* **Confirmation Safety**: Requires typing `DELETE {year} DATA` (or `ARCHIVE {year} DATA`) exactly to prevent accidental cleanup clicks.

### Stock & Inventory Management (Day 8)
* **Current Inventory Tracking**: Catalog battery models and types.
* **Optimistic Rollback Safety**: Manual quantity adjustment updates UI instantly, rolling back automatically if the API fails.
* **Auto-reduce Stock on Sale**: Registering a customer battery sale decrements matching inventory stock by 1 automatically (if quantity > 0).

---

## 4. Run Commands

### Run Locally (Development)
```bash
cd frontend
flutter run -d chrome --dart-define=API_URL=http://localhost:8000/api/v1
```

### Build for Production Release
Builds are optimized for deployment, path-based navigation Urls are enabled (no hash `#` character), and console logs are stripped out.
```bash
flutter build web --release --dart-define=API_URL=https://your-backend-url.railway.app/api/v1
```

---

## 5. Vercel Web Deployment
To host the compiled web client on Vercel:
1. Initialize a Git repository inside the `frontend` folder or workspace.
2. In your **Vercel Project Dashboard**, set the build configurations:
   * **Framework Preset**: `Other`
   * **Build Command**: `flutter/bin/flutter build web --release --dart-define=API_URL=https://your-backend-url.railway.app/api/v1`
   * **Output Directory**: `build/web`
3. Add a `vercel.json` file inside the root build folder to redirect all route paths to `index.html` (necessary for path-based routing success):
   ```json
   {
     "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
   }
   ```

---

## 6. Secure Backup Center Usage Instructions

The administrative backup workspace is accessible from the **Exports** tab in the side menu.

### A. How to Send Backups to Email
1. Click **Exports** in the side navigation drawer.
2. Under the **Secure Backup Control Center**, toggle between **Monthly Backup** and **Yearly Backup**.
3. Select the target **Year** (and **Month** if you selected Monthly) from the dropdown selectors.
4. Click the **Send Backup to Email** button.
5. The application will show a progress spinner overlay. Upon completion:
   - The backup ZIP file is compiled in-memory on the backend and emailed directly to `shreeganadhishbattery@gmail.com`.
   - The ZIP file is simultaneously triggered for local browser download to your computer.
   - The metadata panel will refresh, displaying the latest backup file name under `LAST BACKUP FILENAME`, updating the last sent timestamp, and rendering a green `UP TO DATE` status badge.
   - If the operation succeeds, the card will display a **green success glow animation**.

### B. How to Download Local Backups Only
If you want to save a copy locally without triggering a backup email:
1. Select the desired period, month, and year.
2. Click the **Download ZIP Only** button.
3. The server will package the spreadsheet data in-memory and return it directly to your browser for saving. (No email is dispatched and no backup event is logged under `EMAIL_BACKUP_SENT`).

