# backend/api/main.py
"""
XYLO — API Backend Starter (FastAPI)

A compact, professional API scaffold for XYLO.
This file exposes example endpoints for:
- auth (register/login)
- accounting (add transaction, get reports)
- automation triggers
- chatbot messaging
- invoice upload (stub)

Replace stub logic with real module calls (accounting_engine, automation, ai_chatbot).
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Depends
from pydantic import BaseModel, EmailStr
from typing import Optional, Any, Dict
from datetime import datetime
import uuid

app = FastAPI(title="XYLO API", version="0.1.0")


# -------------------------
# Models (Pydantic)
# -------------------------
class UserCreate(BaseModel):
    email: EmailStr
    name: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TransactionCreate(BaseModel):
    date: datetime
    amount: float
    currency: str = "INR"
    description: Optional[str] = None
    source: Optional[str] = "manual"  # e.g., invoice_upload, bank_import


class GenericResponse(BaseModel):
    status: str
    data: Optional[Any] = None
    timestamp: datetime


class ChatQuery(BaseModel):
    query: str
    session_id: Optional[str] = None


# -------------------------
# Simple in-memory demo storage (replace with DB)
# -------------------------
DEMO_USERS: Dict[str, dict] = {}
DEMO_TRANSACTIONS: Dict[str, dict] = {}


# -------------------------
# Auth Endpoints (stubs)
# -------------------------
@app.post("/auth/register", response_model=GenericResponse)
def register(user: UserCreate):
    # NOTE: Replace with secure password hashing + DB create
    if user.email in DEMO_USERS:
        raise HTTPException(status_code=400, detail="User already exists")
    user_id = str(uuid.uuid4())
    DEMO_USERS[user.email] = {"id": user_id, "email": user.email, "name": user.name}
    return GenericResponse(status="success", data={"user_id": user_id}, timestamp=datetime.utcnow())


@app.post("/auth/login", response_model=TokenResponse)
def login(user: UserCreate):
    # NOTE: Replace with proper auth and password check
    if user.email not in DEMO_USERS:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    # Return a dummy token for demo
    return TokenResponse(access_token=f"demo-token-{DEMO_USERS[user.email]['id']}")


@app.get("/auth/me", response_model=GenericResponse)
def me():
    # Stub: return demo user info
    sample = next(iter(DEMO_USERS.values()), None)
    return GenericResponse(status="success", data=sample, timestamp=datetime.utcnow())


# -------------------------
# Accounting Endpoints (stubs)
# -------------------------
@app.post("/accounting/add_transaction", response_model=GenericResponse)
def add_transaction(tx: TransactionCreate):
    tx_id = str(uuid.uuid4())
    DEMO_TRANSACTIONS[tx_id] = tx.dict()
    # In real system: call accounting_engine.create_journal_entries(...)
    return GenericResponse(status="success", data={"transaction_id": tx_id}, timestamp=datetime.utcnow())


@app.get("/accounting/trial_balance", response_model=GenericResponse)
def trial_balance():
    # Stub: return counts and simple totals for demo purposes
    total_tx = len(DEMO_TRANSACTIONS)
    total_amount = sum(t["amount"] for t in DEMO_TRANSACTIONS.values()) if total_tx else 0
    sample = {"total_transactions": total_tx, "total_amount": total_amount}
    return GenericResponse(status="success", data=sample, timestamp=datetime.utcnow())


@app.get("/accounting/profit_loss", response_model=GenericResponse)
def profit_loss():
    # Stub: placeholder — replace with accounting_engine.compute_pnl(...)
    return GenericResponse(status="success", data={"profit": 0.0, "revenue": 0.0, "expense": 0.0},
                           timestamp=datetime.utcnow())


# -------------------------
# Automation Endpoints (stubs)
# -------------------------
@app.post("/automation/run_daily_summary", response_model=GenericResponse)
def run_daily_summary():
    # In real system: schedule or kick off automation_engine.run_daily_summary()
    return GenericResponse(status="success", data={"message": "daily summary triggered"}, timestamp=datetime.utcnow())


@app.post("/automation/send_payment_reminder", response_model=GenericResponse)
def send_payment_reminder(invoice_reference: str):
    # In real system: automation_engine.send_payment_reminder(invoice_reference)
    return GenericResponse(status="success", data={"invoice": invoice_reference, "sent": True}, timestamp=datetime.utcnow())


# -------------------------
# Chatbot Endpoint (stub)
# -------------------------
@app.post("/chatbot/message", response_model=GenericResponse)
def chatbot_message(q: ChatQuery):
    # In real system: reply = ai_chatbot.handle_message(q.query, session_id=q.session_id)
    fake_reply = f"(demo) I understood: '{q.query}' — this is where the AI reply would be."
    return GenericResponse(status="success", data={"reply": fake_reply}, timestamp=datetime.utcnow())


# -------------------------
# Invoice Upload (stub)
# -------------------------
@app.post("/invoices/upload", response_model=GenericResponse)
async def upload_invoice(file: UploadFile = File(...)):
    # In real system:
    # 1. save file
    # 2. run invoice OCR/parser -> extract fields
    # 3. create transaction and journal entries
    file_info = {"filename": file.filename, "content_type": file.content_type}
    return GenericResponse(status="success", data={"uploaded": file_info}, timestamp=datetime.utcnow())


# -------------------------
# Health & Status
# -------------------------
@app.get("/health", response_model=GenericResponse)
def health():
    return GenericResponse(status="success", data={"status": "ok"}, timestamp=datetime.utcnow())

