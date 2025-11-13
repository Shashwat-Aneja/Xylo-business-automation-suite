# AI ChatBox Component — XYLO Dashboard
### Intelligent Financial Assistant (Frontend UI Specification)

The **AI ChatBox** is the interactive assistant inside XYLO.  
It provides conversational access to:
- Profit & Loss summaries  
- Balance sheet snapshots  
- Trial balances  
- Financial insights  
- Automation triggers  
- Invoice queries  

This document defines the UI layout, state handling, API wiring, and interaction flow.

---

# 🎯 Goals

- Clean, minimal chat interface  
- Responsive (works on all screens)  
- Smooth animation for open/close  
- Supports message history  
- Works seamlessly with `/chatbot/message` API  
- Keyboard-friendly (Enter to send)  

---

# 🧩 Component Layout
+---------------------------------------------+
| AI Assistant (floating panel) |
+---------------------------------------------+
| Chat Header: |
| • Avatar icon |
| • “XYLO Assistant” title |
| • Close button (X) |
+---------------------------------------------+
| Message Window (scrollable) |
| • Chat bubbles (user + bot) |
| • Timestamps |
+---------------------------------------------+
| Input Area |
| • Text input field |
| • Send button |
+---------------------------------------------+

### Suggested dimensions:
- Width: 360–420px  
- Height: 70% of screen  
- Position: bottom-right floating panel  
- Z-index high enough to overlay dashboard  

---

# 🖌 Visual Style

### Colors:
- Background: white  
- Border: light grey #dcdcdc  
- Bot bubble: light blue #e5f1ff  
- User bubble: grey #f2f2f2  
- Input bar: white, box shadow  
- Icons: simple line icons  

### Typography:
- Font: Inter / Roboto  
- Sizes:
  - Header: 16–18px bold  
  - Message text: 14–15px  

---

# 📥 State Structure (Recommended)

```js
{
  isOpen: true,
  messages: [
    { sender: "bot", text: "Hello! How can I help you today?", ts: "10:20 AM" },
    { sender: "user", text: "Show me today's profit.", ts: "10:21 AM" }
  ],
  loading: false,
  sessionId: "session-uuid"
}
```
POST /chatbot/message
Example payload:
{
  "query": "What is my net profit today?",
  "session_id": "session-uuid"
}
Expected response:
{
  "status": "success",
  "data": {
    "reply": "Net profit for today is ₹4,120.",
    "intent": "INTENT_PROFIT"
  }
}
