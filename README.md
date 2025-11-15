# XYLO – AI-Powered Business Automation System  
### Intelligent finance automation · OCR · Accounting engine · FastAPI backend

XYLO is an AI-assisted backend automation system built to simplify bookkeeping, invoices, reporting, reminders, and financial insights for small businesses.  
It is designed with a clean modular FastAPI backend and structured like a lightweight ERP system.

---

## ⭐ Key Features

### 📄 Invoice OCR
- Upload invoices (PDF/image)  
- Extract vendor, date, amount  
- Auto-create transactions  
- Auto-post journal entries  

### 💬 AI Chat Assistant
Ask natural questions like:
- “Show my expenses this month”  
- “Generate my daily summary”  
- “Has invoice #102 been paid?”

(ML-powered assistant planned)

### 📊 Financial Report Generator
Generates:
- Trial Balance  
- Profit & Loss  
- Balance Sheet  
- Daily Summary  

Formats supported: **PDF, CSV, JSON**

### ⚙ Automation Scheduler
- Daily summary reports  
- Weekly database backup  
- Overdue payment reminders  
- Interval-based tasks  

### 📘 Accounting Engine
- Double-entry bookkeeping  
- Ledger system  
- Chart of accounts  
- Journal entries  
- Reconciliation checks  

### 🚀 FastAPI Backend
- Modular routes  
- Adapter-based architecture  
- Clean utilities for PDF/OCR  
- Swagger API documentation  

---

## 🧩 System Architecture

```
XYLO/
│
├── backend/
│   ├── api/                 # FastAPI routes & controllers
│   ├── accounting_engine/   # Journals, ledgers, validation
│   ├── automation/          # Scheduler, reminders, invoice pipeline
│   ├── utils/               # PDF generator, CSV tools, helpers
│   └── database/            # SQLite models (future ORM)
│
├── docs/                    # Architecture + development docs
├── samples/                 # Demo invoices + generated reports
└── frontend/                # Future dashboard UI
```

---

## 📦 Installation

### 1. Clone
```bash
git clone https://github.com/Shashwat-Aneja/xylo
cd xylo
```

### 2. Create a Virtual Environment
**Windows**
```bash
python -m venv venv
venv\Scripts\activate
```

**Mac/Linux**
```bash
python3 -m venv venv
source venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install fastapi uvicorn reportlab python-dotenv
```

**Optional OCR support**
```bash
pip install pytesseract pillow
```

---

## ▶️ Running the Server
```bash
uvicorn backend.api.main:app --reload
```

Open API docs:  
http://127.0.0.1:8000/docs

---

## 🧪 Testing Core Features

### 1. Add Transaction
```bash
curl -X POST http://127.0.0.1:8000/accounting/add_transaction \
-H "Content-Type: application/json" \
-d "{\"date\":\"2025-01-01T00:00:00\",\"amount\":1200,\"description\":\"Test Sale\"}"
```

### 2. Generate Trial Balance  
```
GET /accounting/trial_balance
```

### 3. Upload Invoice  
```
POST /invoices/upload
```

### 4. AI Chat Assistant  
```
POST /chatbot/message
```

---

## 📊 Example Trial Balance Output
```json
{
  "assets": 1200,
  "liabilities": 0,
  "equity": 0,
  "difference": 1200
}
```

---

## ⚙ Automation Scheduler
Run automation tasks:

```bash
python backend/automation/scheduler.py
```

Tasks executed:
- Daily 10 PM summary  
- Weekly backup  
- Overdue reminders  

---

## 📘 Documentation
- `/docs/architecture/` — System diagrams  
- `/docs/dev_setup.md` — Development setup  
- `/docs/frontend/` — Dashboard planning  
- `/docs/automation/` — Task workflows  

---

## 🎯 Project Goals
- Real-world financial automation  
- Add ML-based assistant  
- Improve OCR accuracy  
- Build a full dashboard UI  
- Deploy a public demo