# AI Chatbot Engine — Technical Specification  
### XYLO Business Automation Suite

The AI Chatbot Engine is responsible for handling customer queries, internal business requests, and automation commands using natural-language understanding.  
This document outlines how the chatbot processes messages, detects intent, generates responses, and interacts with other XYLO modules.

---

# 🧠 1. Core Responsibilities

### ✔ Natural Language Understanding  
Interprets user input such as:
“What are today’s expenses?”
“Generate my balance sheet.”
“Tell me the status of order #104.”


### ✔ Business Query Handling  
- Daily revenue  
- Expense totals  
- Order tracking  
- Client information  

### ✔ Automation Command Execution  
- Generating reports  
- Triggering reminders  
- Scheduling tasks  

### ✔ Customer Support Queries  
- FAQs  
- Product information  
- Delivery updates  
- Complaint logging  

Subsystem folder:
backend/ai_chatbot/


---

# 🧩 2. Chatbot Pipeline (Message Flow)
User Query
↓
Text Preprocessing
↓
Intent Detection (Rule-based + ML)
↓
Entity Extraction (Amounts, Dates, Names)
↓
Dispatcher (Routes to correct module)
↓
Module Response (Accounting/Automation/API)
↓
Language Generator (Formatted reply)
↓
Final Chatbot Response


---

# 🧪 3. Intent Detection System

The chatbot uses a hybrid approach:

### A) **Rule-Based Pattern Matching**
Examples:
contains("balance sheet") → INTENT_FINANCIAL_REPORT
contains("profit") → INTENT_PROFIT_QUERY
contains("order") and contains("status") → INTENT_ORDER_STATUS
contains("payment reminder") → INTENT_SEND_REMINDER


### B) **ML-Based Classification (Optional Enhancement)**
A small ML model (like Logistic Regression or DistilBERT) can classify queries into:
- Finance  
- Sales  
- Inventory  
- Support  
- Automation  

This is optional but scalable.

---

# 🔍 4. Entity Extraction

Extracts:
- Amounts (₹12,000)  
- Dates (“yesterday”, “last month”)  
- Names (“Client Rohan”, “Order 102”)  
- Categories (“electricity bill”, “salary”)  

Techniques used:
- Regex patterns  
- Keyword lists  
- Lightweight NLP tokenization  
- Date parsers  

---

# 🔄 5. Dispatcher (Routing System)

The dispatcher decides which module handles the user’s intent.

Examples:

### Finance Query → Accounting Engine
“What are today’s profits?”

### Inventory Query → Automation Engine
“Check stock for item ‘Milk’”

### Automation Command → Scheduler
“Send me this report every Friday.”

### General Questions → FAQ Handler
“What are your store hours?”


---

# 📊 6. Response Generation

Once a module returns data, the chatbot formats a clean, friendly reply.

Example:
Today’s total expenses are ₹3,250.
Top categories: Electricity ₹1,000, Travel ₹900, Supplies ₹500.

Other output formats:
- Tables  
- Bullet lists  
- Short summaries  
- Step-by-step instructions  

---

# 🌐 7. Integration With API & Backend

The chatbot interacts with:

### ✔ Accounting Engine  
- Get ledger results  
- Fetch P&L  
- Retrieve balance sheet  

### ✔ Automation Engine  
- Trigger scheduled tasks  
- Send reminders  
- Fetch daily summaries  

### ✔ Database  
- User records  
- Transaction history  
- Order info  

---

# 📁 Subsystem Directory
backend/ai_chatbot/

Suggested internal files:
intent_detection.py
entity_extraction.py
dispatcher.py
response_generator.py
chatbot_core.py


---

# 🎯 Summary

The XYLO AI Chatbot Engine functions as an intelligent business assistant that can:
- Understand natural language  
- Answer customer and business queries  
- Generate financial information  
- Trigger automation  
- Assist with daily operations  

It acts as the **conversational interface** for the entire XYLO ecosystem.

