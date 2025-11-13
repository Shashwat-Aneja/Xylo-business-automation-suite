# Accounting Engine — Technical Specification  
### XYLO Business Automation Suite

The Accounting Engine is the core subsystem responsible for generating financial statements and maintaining the books of accounts automatically.  
This document explains the logic, calculations, and rules behind the system.

---

# 🧩 1. Core Responsibilities

### ✔ Journal Entry Generation  
Converts raw transactions into structured journal entries with:
- Date  
- Description  
- Debit account  
- Credit account  
- Amount  

### ✔ Ledger Posting  
Automatically updates:
- Asset accounts  
- Liability accounts  
- Income accounts  
- Expense accounts  
- Equity accounts  

### ✔ Trial Balance  
Automatically computes:
- Total debits  
- Total credits  
- Detects mismatches  
- Validates ledger integrity  

### ✔ Financial Statement Generation
The system generates:
- **Profit & Loss Statement**  
- **Balance Sheet**  
- **Cash Flow Summary**  
- **Expense Breakdown Report**  

---

# 🧮 2. Account Classification Rules

Every transaction is classified under one of the five standard accounting heads:
-Assets
-Liabilities
-Capital (Equity)
-Income
-Expenses

### Classification Logic:
If description contains ["purchase", "electricity", "rent"] → Expense
If description contains ["sale", "revenue"] → Income
If transaction refers to partner deposits → Capital
If transaction mentions loans → Liability
If transaction stores value (cash, bank, stock) → Asset


---

# 🔄 3. Debit–Credit Rule Engine

The rule engine follows the universal accounting principles:

### ✔ Asset ↑  → Debit  
### ✔ Asset ↓  → Credit  
### ✔ Expense ↑ → Debit  
### ✔ Expense ↓ → Credit  
### ✔ Income ↑  → Credit  
### ✔ Income ↓  → Debit  
### ✔ Liability ↑ → Credit  
### ✔ Liability ↓ → Debit  
### ✔ Capital ↑ → Credit  

Example:
Bought furniture for ₹5,000
→ Debit: Furniture (Asset)
→ Credit: Cash/Bank


---

# ⚙️ 4. Ledger Posting Logic

Each journal entry automatically updates two ledger accounts:
Ledger[DebitAccount].add(debitAmount)
Ledger[CreditAccount].subtract(creditAmount)


Ledger structure:
Account Name
Date | Description | Debit | Credit | Balance


---

# 🧾 5. Trial Balance Computation

Algorithm:

1. Sum of all ledger debits  
2. Sum of all ledger credits  
3. Must satisfy:  
4. If difference detected → flag error

---

# 📊 6. Profit & Loss Calculation
Profit = (Total Income) – (Total Expenses)
Includes:
- Direct income  
- Operating expenses  
- Non-operating adjustments  

---

# 🧱 7. Balance Sheet Calculation

### Assets
- Cash  
- Bank  
- Inventory  
- Receivables  

### Liabilities
- Loans  
- Payables  

### Equity
Capital + Retained Profit

Final rule:
Assets = Liabilities + Equity


---

# 📤 8. Report Generation Pipeline
Transactions → Journal Entries → Ledgers → Trial Balance → Financial Statements

Reports exported as:
- JSON  
- CSV  
- PDF (optional)  

---

# 📁 Subsystem Directory
backend/accounting_engine/


---

# 🧠 Summary

The XYLO Accounting Engine is a complete automated bookkeeping system that:
- Understands accounting rules  
- Creates journal entries  
- Maintains ledgers  
- Generates financial reports  
- Ensures debit–credit accuracy  

It represents one of the core innovations of the XYLO platform.
