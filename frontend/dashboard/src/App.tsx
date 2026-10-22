import { useMemo, useState } from "react";
import {
  Activity, ArrowDownLeft, ArrowDownRight, ArrowLeftRight, ArrowRight, ArrowUpRight,
  Bell, BookOpen, Bot, CalendarDays, Check, ChevronDown, CircleHelp, Command,
  Download, FileText, Filter, Gauge, LayoutDashboard, Menu, MoreHorizontal, Plus,
  Search, Settings2, Sparkles, TrendingUp, Wallet, X, Zap,
} from "lucide-react";

type Transaction = { id: number; name: string; category: string; date: string; amount: number; kind: "income" | "expense"; status: "Completed" | "Pending"; initials: string; color: string };
type Theme = "paper" | "void" | "terminal" | "dusk";

const initialTransactions: Transaction[] = [
  { id: 1, name: "Northstar Studio", category: "Client payment", date: "Today, 10:24 AM", amount: 48500, kind: "income", status: "Completed", initials: "NS", color: "lavender" },
  { id: 2, name: "Notion Labs", category: "Software & tools", date: "Today, 9:12 AM", amount: 840, kind: "expense", status: "Completed", initials: "N", color: "ink" },
  { id: 3, name: "Acme Retail Co.", category: "Client payment", date: "Yesterday", amount: 22500, kind: "income", status: "Pending", initials: "AC", color: "mint" },
  { id: 4, name: "AWS India", category: "Cloud infrastructure", date: "Yesterday", amount: 3240, kind: "expense", status: "Completed", initials: "A", color: "orange" },
  { id: 5, name: "Paper & Parcel", category: "Office supplies", date: "18 Oct 2026", amount: 1250, kind: "expense", status: "Completed", initials: "PP", color: "pink" },
];

const navigation = [
  { label: "Overview", icon: LayoutDashboard, group: "WORKSPACE" },
  { label: "Transactions", icon: ArrowLeftRight, group: "WORKSPACE" },
  { label: "Accounting", icon: BookOpen, group: "WORKSPACE" },
  { label: "Invoices", icon: FileText, group: "WORKSPACE" },
  { label: "Reports", icon: Activity, group: "INSIGHTS" },
  { label: "Automations", icon: Zap, group: "INSIGHTS" },
  { label: "Xylo AI", icon: Bot, group: "INSIGHTS" },
];

const currency = (value: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(value);
const shortCurrency = (value: number) => value >= 100000 ? `₹${(value / 100000).toFixed(1)}L` : value >= 1000 ? `₹${(value / 1000).toFixed(1)}k` : currency(value);

function App() {
  const [active, setActive] = useState("Overview");
  const [transactions, setTransactions] = useState(initialTransactions);
  const [query, setQuery] = useState("");
  const [theme, setTheme] = useState<Theme>("paper");
  const [showAdd, setShowAdd] = useState(false);
  const [showAssistant, setShowAssistant] = useState(false);
  const [mobileNav, setMobileNav] = useState(false);
  const [toast, setToast] = useState("");
  const [form, setForm] = useState({ name: "", amount: "", kind: "income" as "income" | "expense", category: "Client payment" });

  const totals = useMemo(() => transactions.reduce((acc, tx) => {
    acc[tx.kind] += tx.amount;
    return acc;
  }, { income: 0, expense: 0 }), [transactions]);

  const filteredTransactions = useMemo(() => transactions.filter(tx =>
    [tx.name, tx.category, tx.status, tx.kind].join(" ").toLowerCase().includes(query.toLowerCase())
  ), [transactions, query]);

  const notify = (message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2800);
  };

  const addTransaction = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const amount = Number(form.amount);
    if (!form.name.trim() || !Number.isFinite(amount) || amount <= 0) return;
    setTransactions(current => [{
      id: Date.now(), name: form.name.trim(), category: form.category, date: "Just now", amount,
      kind: form.kind, status: "Completed", initials: form.name.trim().slice(0, 2).toUpperCase(), color: "mint",
    }, ...current]);
    setForm({ name: "", amount: "", kind: "income", category: "Client payment" });
    setShowAdd(false);
    setActive("Transactions");
    notify("Transaction added to this demo session.");
  };

  const exportCsv = () => {
    const rows = [["Name", "Category", "Date", "Type", "Status", "Amount"], ...filteredTransactions.map(tx => [tx.name, tx.category, tx.date, tx.kind, tx.status, String(tx.amount)])];
    const csv = rows.map(row => row.map(cell => `"${cell.replaceAll('"', '""')}"`).join(",")).join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }));
    const anchor = document.createElement("a");
    anchor.href = url; anchor.download = "xylo-transactions.csv"; anchor.click();
    URL.revokeObjectURL(url);
    notify("CSV export prepared.");
  };

  const pageTitle = active === "Overview" ? "Good morning, Shashwat" : active;
  const pageDescription = active === "Overview"
    ? "Here’s what’s happening with your business today."
    : active === "Transactions" ? "Every rupee, accounted for. Review your recent activity."
    : `Your ${active.toLowerCase()} workspace, thoughtfully organized.`;

  return (
    <div className={`app-shell theme-${theme}`}>
      <aside className={`sidebar ${mobileNav ? "sidebar-open" : ""}`}>
        <button className="brand" onClick={() => { setActive("Overview"); setMobileNav(false); }} aria-label="Go to overview">
          <span className="brand-mark"><span /><span /><span /></span>
          <span className="brand-word">xylo<span className="brand-period">.</span><small>BUSINESS OS</small></span>
        </button>
        <button className="workspace-switcher" onClick={() => notify("Workspace switcher is ready for account setup.")}>
          <span className="workspace-avatar">S</span><span className="workspace-copy"><strong>Shashwat's workspace</strong><small>Free workspace</small></span><ChevronDown size={15} />
        </button>
        <div className="nav-scroll">
          {["WORKSPACE", "INSIGHTS"].map(group => (
            <div className="nav-group" key={group}>
              <p className="nav-label">{group}</p>
              {navigation.filter(item => item.group === group).map(item => {
                const Icon = item.icon;
                return <button key={item.label} className={`nav-item ${active === item.label ? "active" : ""}`} onClick={() => { setActive(item.label); setMobileNav(false); }}>
                  <Icon size={17} strokeWidth={1.8} /><span>{item.label}</span>
                  {item.label === "Xylo AI" && <span className="nav-new">NEW</span>}
                </button>;
              })}
            </div>
          ))}
        </div>
        <div className="sidebar-bottom">
          <div className="sidebar-tip"><span className="tip-icon"><Sparkles size={15} /></span><strong>A little more clarity.</strong><p>Your business, without the busywork.</p><button onClick={() => { setShowAssistant(true); setMobileNav(false); }}>Meet Xylo AI <ArrowRight size={13} /></button></div>
          <button className="nav-item" onClick={() => notify("Settings will be connected in a later phase.")}><Settings2 size={17} /><span>Settings</span></button>
          <div className="profile-row"><div className="profile-avatar">SA</div><div className="profile-copy"><strong>Shashwat Aneja</strong><small>Owner</small></div><MoreHorizontal size={18} /></div>
        </div>
      </aside>

      {mobileNav && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMobileNav(false)} />}
      <main className="main-area">
        <header className="topbar">
          <div className="topbar-left"><button className="icon-button mobile-menu" onClick={() => setMobileNav(!mobileNav)} aria-label="Toggle menu"><Menu size={19} /></button><span className="breadcrumb">Workspace</span><span className="crumb-slash">/</span><strong>{active}</strong></div>
          <div className="topbar-actions">
            <label className="search-box"><Search size={16} /><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search anything..." /><kbd><Command size={10} /> K</kbd></label>
            <button className="icon-button theme-button" title="Change atmosphere" onClick={() => setTheme(current => current === "paper" ? "void" : current === "void" ? "terminal" : current === "terminal" ? "dusk" : "paper")}><span className="theme-dot" /><span className="theme-name">{theme[0].toUpperCase() + theme.slice(1)}</span><ChevronDown size={13} /></button>
            <button className="icon-button notification-button" aria-label="Notifications" onClick={() => notify("You're all caught up.")}><Bell size={17} /><i /></button>
            <div className="topbar-avatar">SA</div>
          </div>
        </header>

        <div className="page-content">
          <section className="welcome-row">
            <div><div className="eyebrow"><span className="eyebrow-dot" /> THURSDAY, 22 OCTOBER 2026</div><h1>{pageTitle}<span className="title-period">.</span></h1><p>{pageDescription}</p></div>
            <div className="welcome-actions"><button className="button button-secondary" onClick={exportCsv}><Download size={15} /> Export</button><button className="button button-primary" onClick={() => setShowAdd(true)}><Plus size={16} /> Add transaction</button></div>
          </section>

          {active === "Overview" ? (
            <>
              <section className="metric-grid">
                <MetricCard title="Total revenue" value={currency(totals.income)} change="+12.8%" note="vs. last month" icon={<ArrowDownLeft size={17} />} accent="teal" />
                <MetricCard title="Total expenses" value={currency(totals.expense)} change="+4.2%" note="vs. last month" icon={<ArrowUpRight size={17} />} accent="coral" negative />
                <MetricCard title="Net profit" value={currency(totals.income - totals.expense)} change="+18.6%" note="vs. last month" icon={<TrendingUp size={17} />} accent="violet" />
                <MetricCard title="Cash on hand" value={currency(284650)} change="+8.1%" note="across 2 accounts" icon={<Wallet size={17} />} accent="amber" />
              </section>

              <section className="primary-grid">
                <div className="panel cashflow-panel">
                  <div className="panel-heading"><div><div className="panel-kicker">THE BIG PICTURE</div><h2>Cash flow</h2><p>Money in, money out, month by month.</p></div><button className="select-button" onClick={() => notify("Showing the last 6 months in this preview.")}>Last 6 months <ChevronDown size={14} /></button></div>
                  <div className="chart-legend"><span><i className="legend-dot income-dot" /> Income</span><span><i className="legend-dot expense-dot" /> Expenses</span><span className="chart-total">Net <strong>₹2.84L</strong></span></div>
                  <CashflowChart />
                  <div className="chart-footer"><span><span className="trend-up"><TrendingUp size={13} /> 14.6%</span> more cash retained</span><span>May – Oct 2026</span></div>
                </div>
                <div className="panel insight-panel">
                  <div className="panel-heading"><div><div className="panel-kicker">A MOMENT OF CLARITY</div><h2>Business pulse</h2></div><span className="pulse-icon"><Activity size={17} /></span></div>
                  <div className="pulse-score"><span>Looking healthy</span><strong>82<small>/100</small></strong></div>
                  <div className="pulse-meter"><span /></div>
                  <p className="pulse-description">You're keeping more of what you earn. Your expense ratio is trending in the right direction.</p>
                  <div className="insight-divider" />
                  <div className="insight-row"><span className="insight-symbol mint-symbol"><ArrowDownRight size={15} /></span><span><strong>Expense ratio</strong><small>Healthy range is below 60%</small></span><b>34.2%</b></div>
                  <div className="insight-row"><span className="insight-symbol violet-symbol"><CalendarDays size={15} /></span><span><strong>Next tax checkpoint</strong><small>Review your monthly records</small></span><b>7 days</b></div>
                  <button className="text-link" onClick={() => setActive("Reports")}>Explore business insights <ArrowRight size={14} /></button>
                </div>
              </section>

              <section className="lower-grid">
                <div className="panel transactions-panel">
                  <div className="panel-heading transaction-heading"><div><div className="panel-kicker">YOUR MONEY, IN MOTION</div><h2>Recent transactions</h2></div><button className="text-link" onClick={() => setActive("Transactions")}>View all <ArrowRight size={14} /></button></div>
                  <TransactionTable transactions={filteredTransactions.slice(0, 5)} />
                  <div className="table-bottom"><span>Showing {Math.min(filteredTransactions.length, 5)} of {filteredTransactions.length} transactions</span><button onClick={() => setActive("Transactions")}>See all activity <ArrowRight size={13} /></button></div>
                </div>
                <div className="panel tasks-panel">
                  <div className="panel-heading"><div><div className="panel-kicker">A CLEAR NEXT STEP</div><h2>On your radar</h2></div><button className="icon-button subtle-icon" onClick={() => notify("Task settings are coming soon.")}><MoreHorizontal size={18} /></button></div>
                  <div className="task-item"><span className="task-check"><Check size={12} /></span><div><strong>Reconcile October expenses</strong><small>Accounting · Today</small></div><span className="task-status status-today">Today</span></div>
                  <div className="task-item"><span className="task-check empty-check" /><div><strong>Send Acme's invoice</strong><small>Invoices · Due tomorrow</small></div><span className="task-status status-due">Due soon</span></div>
                  <div className="task-item"><span className="task-check empty-check" /><div><strong>Review monthly performance</strong><small>Reports · 29 Oct</small></div><span className="task-status">Planned</span></div>
                  <button className="task-add" onClick={() => notify("Task creation will be added with the operations module.")}><Plus size={14} /> Add a task</button>
                </div>
              </section>
            </>
          ) : active === "Transactions" ? (
            <section className="panel all-transactions"><div className="panel-heading"><div><div className="panel-kicker">LEDGER ACTIVITY</div><h2>All transactions</h2><p>Search, review, and export your recent business activity.</p></div><button className="button button-secondary" onClick={exportCsv}><Download size={15} /> Export CSV</button></div><div className="filter-strip"><span><Filter size={14} /> {filteredTransactions.length} results</span><span className="demo-label">DEMO DATA</span></div><TransactionTable transactions={filteredTransactions} /></section>
          ) : (
            <section className="module-placeholder panel"><div className="module-icon">{active === "Xylo AI" ? <Bot size={25} /> : active === "Automations" ? <Zap size={25} /> : active === "Reports" ? <Activity size={25} /> : active === "Invoices" ? <FileText size={25} /> : <BookOpen size={25} />}</div><div className="panel-kicker">THE NEXT CHAPTER</div><h2>{active === "Xylo AI" ? "A thoughtful assistant for your business." : active === "Automations" ? "Let the busywork take care of itself." : active === "Reports" ? "Your business, made legible." : active === "Invoices" ? "From paperwork to clarity." : "Every entry has a place."}</h2><p>{active === "Xylo AI" ? "Ask questions about your finances, find patterns, and get help with everyday operations. The assistant will connect to real business data after backend setup." : active === "Automations" ? "Build small, reliable workflows around the way your business works. Triggers, conditions, and actions will live here." : active === "Reports" ? "Explore profit and loss, balance sheets, trial balances, and business performance reports." : active === "Invoices" ? "Upload an invoice, review extracted details, and turn paperwork into structured records." : "Your chart of accounts, journals, ledgers, and reconciliation tools will be organized here."}</p><div className="module-status"><span /> Frontend preview · Backend connection pending</div><button className="button button-primary" onClick={() => active === "Xylo AI" ? setShowAssistant(true) : active === "Invoices" ? notify("Invoice uploads will be connected after backend setup.") : notify(`${active} module added to the build roadmap.`)}>{active === "Xylo AI" ? <><Sparkles size={15} /> Open assistant</> : <>Explore this module <ArrowRight size={15} /></>}</button></section>
          )}

          <footer className="page-footer"><span>Made for the business you're building. <span className="footer-heart">✳</span></span><span><i /> Preview environment <span className="footer-divider">·</span> Xylo v0.1</span></footer>
        </div>
      </main>

      {showAdd && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setShowAdd(false); }}><form className="modal-card" onSubmit={addTransaction}><div className="modal-heading"><div><div className="panel-kicker">RECORD AN ENTRY</div><h2>Add transaction</h2><p>This preview stores entries in memory only.</p></div><button type="button" className="icon-button" onClick={() => setShowAdd(false)} aria-label="Close"><X size={18} /></button></div><label className="field-label">Description<input required autoFocus placeholder="e.g. Client payment" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></label><label className="field-label">Amount (INR)<input required type="number" min="1" step="0.01" placeholder="0.00" value={form.amount} onChange={e => setForm({ ...form, amount: e.target.value })} /></label><div className="form-two"><label className="field-label">Entry type<select value={form.kind} onChange={e => setForm({ ...form, kind: e.target.value as "income" | "expense" })}><option value="income">Income</option><option value="expense">Expense</option></select></label><label className="field-label">Category<select value={form.category} onChange={e => setForm({ ...form, category: e.target.value })}><option>Client payment</option><option>Software & tools</option><option>Cloud infrastructure</option><option>Office supplies</option><option>Other</option></select></label></div><div className="modal-note"><CircleHelp size={15} /> Demo entries reset when you refresh. No financial records are saved.</div><div className="modal-actions"><button type="button" className="button button-secondary" onClick={() => setShowAdd(false)}>Cancel</button><button className="button button-primary" type="submit"><Plus size={15} /> Save transaction</button></div></form></div>}

      {showAssistant && <div className="assistant-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setShowAssistant(false); }}><section className="assistant-card"><div className="assistant-top"><span className="assistant-avatar"><Bot size={20} /></span><div><strong>Meet Xylo</strong><small><i /> Your business companion</small></div><button className="icon-button" onClick={() => setShowAssistant(false)} aria-label="Close assistant"><X size={18} /></button></div><div className="assistant-body"><div className="assistant-greeting"><span className="assistant-spark"><Sparkles size={18} /></span><h2>A little more clarity starts here.</h2><p>Ask a question, explore your numbers, or find your next step. Real-data answers will be enabled when the backend is connected.</p></div><div className="suggestion-list"><button onClick={() => { setShowAssistant(false); setActive("Reports"); }}>How is my business doing? <ArrowRight size={14} /></button><button onClick={() => { setShowAssistant(false); setActive("Transactions"); }}>Help me review my transactions <ArrowRight size={14} /></button><button onClick={() => { setShowAssistant(false); setActive("Automations"); }}>What can I automate? <ArrowRight size={14} /></button></div><form className="assistant-input" onSubmit={e => { e.preventDefault(); notify("AI responses will be enabled after model and backend setup."); }}><input placeholder="Ask Xylo anything..." /><button aria-label="Send message"><ArrowRight size={17} /></button></form><div className="assistant-disclaimer">Xylo AI preview · No external AI service connected</div></div></section></div>}

      {toast && <div className="toast"><span><Check size={14} /></span>{toast}</div>}
    </div>
  );
}

function MetricCard({ title, value, change, note, icon, accent, negative = false }: { title: string; value: string; change: string; note: string; icon: React.ReactNode; accent: string; negative?: boolean }) {
  return <article className="metric-card"><div className="metric-top"><span>{title}</span><span className={`metric-icon ${accent}`}>{icon}</span></div><div className="metric-value">{value}</div><div className="metric-foot"><span className={negative ? "metric-change neutral-change" : "metric-change"}>{change}</span><span>{note}</span></div><div className="metric-sparkline"><svg viewBox="0 0 100 25" preserveAspectRatio="none" aria-hidden="true"><path d={negative ? "M0 20 C10 15 14 18 23 14 S40 17 48 10 S64 17 74 8 S90 12 100 4" : "M0 20 C10 17 14 21 23 13 S40 18 48 8 S64 14 74 5 S90 10 100 2"} /></svg></div></article>;
}

function CashflowChart() {
  const bars = [
    { month: "May", income: 58, expense: 31 }, { month: "Jun", income: 72, expense: 39 },
    { month: "Jul", income: 63, expense: 34 }, { month: "Aug", income: 83, expense: 43 },
    { month: "Sep", income: 70, expense: 38 }, { month: "Oct", income: 93, expense: 42 },
  ];
  return <div className="cashflow-chart"><div className="chart-axis"><span>₹80k</span><span>₹60k</span><span>₹40k</span><span>₹20k</span><span>₹0</span></div><div className="chart-plot"><div className="chart-gridlines"><i /><i /><i /><i /><i /></div><div className="bar-groups">{bars.map(bar => <div className="bar-group" key={bar.month}><div className="bar-pair"><span className="bar-income" style={{ height: `${bar.income}%` }} /><span className="bar-expense" style={{ height: `${bar.expense}%` }} /></div><small>{bar.month}</small></div>)}</div></div></div>;
}

function TransactionTable({ transactions }: { transactions: Transaction[] }) {
  if (!transactions.length) return <div className="empty-state"><Search size={22} /><strong>No transactions found</strong><span>Try another search term.</span></div>;
  return <div className="table-scroll"><table className="transaction-table"><thead><tr><th>Transaction</th><th>Date</th><th>Status</th><th className="amount-cell">Amount</th></tr></thead><tbody>{transactions.map(tx => <tr key={tx.id}><td><div className="transaction-name"><span className={`transaction-avatar avatar-${tx.color}`}>{tx.initials}</span><span><strong>{tx.name}</strong><small>{tx.category}</small></span></div></td><td className="date-cell">{tx.date}</td><td><span className={`status-pill ${tx.status === "Completed" ? "completed" : "pending"}`}><i />{tx.status}</span></td><td className={`amount-cell amount-${tx.kind}`}>{tx.kind === "income" ? "+" : "−"}{currency(tx.amount)}</td></tr>)}</tbody></table></div>;
}

export default App;
