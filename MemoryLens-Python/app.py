"""
MemoryLens AI — Python / Streamlit Edition
==========================================
Upload bills, prescriptions, tickets, receipts, exam notices and more.
AI extracts all fields. Zero mock data — only real AI output is shown.
Missing fields are flagged as "Could not extract".

Run with:
    pip install -r requirements.txt
    streamlit run app.py
"""

import streamlit as st
import json
import sqlite3
import os
import base64
import uuid
import re
import requests
from datetime import datetime, date, timedelta
from pathlib import Path
from io import BytesIO

# ── Optional heavy deps (graceful fallback) ─────────────────────────────────
try:
    import google.generativeai as genai
    GEMINI_OK = True
except ImportError:
    GEMINI_OK = False

try:
    from openai import OpenAI
    OPENAI_OK = True
except ImportError:
    OPENAI_OK = False

try:
    from PIL import Image
    PIL_OK = True
except ImportError:
    PIL_OK = False

# ── Constants ────────────────────────────────────────────────────────────────
APP_DIR     = Path(__file__).parent
DATA_DIR    = APP_DIR / "data"
DB_PATH     = DATA_DIR / "memorylens.db"
SETTINGS_F  = DATA_DIR / "settings.json"
DATA_DIR.mkdir(exist_ok=True)

CATEGORIES  = ["bill","prescription","ticket","receipt","exam","notice","other"]
CAT_ICONS   = {"bill":"💸","prescription":"💊","ticket":"🎫","receipt":"🧾",
               "exam":"📋","notice":"📢","other":"📄"}
CAT_COLORS  = {"bill":"#FF6B6B","prescription":"#4ECDC4","ticket":"#45B7D1",
               "receipt":"#96CEB4","exam":"#FFEAA7","notice":"#DDA0DD","other":"#B0C4DE"}

# ── Page config (must be first Streamlit call) ───────────────────────────────
st.set_page_config(
    page_title="MemoryLens AI",
    page_icon="🧠",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Custom CSS ───────────────────────────────────────────────────────────────
st.markdown("""
<style>
/* ── Google Fonts ── */
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');

/* ── Root Variables ── */
:root {
    --bg:        #0D0D1A;
    --surface:   #1A1A2E;
    --card:      #16213E;
    --card2:     #0F3460;
    --primary:   #6C63FF;
    --secondary: #03DAC6;
    --accent:    #FF6584;
    --text:      #E8E8F0;
    --muted:     #8888A8;
    --border:    rgba(255,255,255,0.08);
    --glass:     rgba(255,255,255,0.04);
    --radius:    16px;
    --shadow:    0 8px 32px rgba(0,0,0,0.4);
}

/* ── Global ── */
html, body, [class*="css"] {
    font-family: 'Inter', sans-serif !important;
    background-color: var(--bg) !important;
    color: var(--text) !important;
}
.stApp { background-color: var(--bg) !important; }

/* ── Sidebar ── */
[data-testid="stSidebar"] {
    background: linear-gradient(180deg, var(--surface) 0%, var(--card) 100%) !important;
    border-right: 1px solid var(--border);
}
[data-testid="stSidebar"] .stRadio label {
    color: var(--text) !important;
    font-weight: 500;
}

/* ── Cards / Containers ── */
.ml-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px 24px;
    margin-bottom: 16px;
    box-shadow: var(--shadow);
    transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.ml-card:hover { transform: translateY(-2px); box-shadow: 0 12px 40px rgba(0,0,0,0.5); }
.ml-card-glass {
    background: rgba(108,99,255,0.08);
    border: 1px solid rgba(108,99,255,0.25);
    border-radius: var(--radius);
    padding: 20px 24px;
    margin-bottom: 16px;
    backdrop-filter: blur(12px);
}

/* ── KPI Metric Cards ── */
.metric-card {
    background: linear-gradient(135deg, var(--card) 0%, var(--card2) 100%);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 24px;
    text-align: center;
    box-shadow: var(--shadow);
    position: relative;
    overflow: hidden;
}
.metric-card::before {
    content: '';
    position: absolute;
    top: -50%;
    left: -50%;
    width: 200%;
    height: 200%;
    background: radial-gradient(circle, rgba(108,99,255,0.05) 0%, transparent 70%);
    pointer-events: none;
}
.metric-num  { font-size: 2.8rem; font-weight: 800; line-height: 1; margin-bottom: 6px; }
.metric-label{ font-size: 0.8rem; color: var(--muted); text-transform: uppercase; letter-spacing: 1px; font-weight: 600; }

/* ── Badge pill ── */
.badge {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 0.72rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}
.badge-warn { background: rgba(255,214,0,0.15); color: #FFD600; border: 1px solid rgba(255,214,0,0.3); }
.badge-ok   { background: rgba(3,218,198,0.15);  color: #03DAC6; border: 1px solid rgba(3,218,198,0.3); }
.badge-err  { background: rgba(255,100,100,0.15); color: #FF6B6B; border: 1px solid rgba(255,100,100,0.3); }

/* ── Field display ── */
.field-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 0;
    border-bottom: 1px solid var(--border);
}
.field-row:last-child { border-bottom: none; }
.field-key   { color: var(--muted); font-size: 0.82rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
.field-val   { color: var(--text); font-size: 0.95rem; font-weight: 500; text-align: right; }
.field-miss  { color: #FF6B6B; font-size: 0.82rem; font-style: italic; }

/* ── Section header ── */
.section-header {
    font-size: 1.4rem;
    font-weight: 700;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    margin-bottom: 4px;
}
.section-sub { color: var(--muted); font-size: 0.85rem; margin-bottom: 20px; }

/* ── Hero banner ── */
.hero {
    background: linear-gradient(135deg, rgba(108,99,255,0.15) 0%, rgba(3,218,198,0.08) 100%);
    border: 1px solid rgba(108,99,255,0.2);
    border-radius: 20px;
    padding: 32px 36px;
    margin-bottom: 28px;
    position: relative;
    overflow: hidden;
}
.hero::after {
    content: '🧠';
    position: absolute;
    right: 24px;
    top: 50%;
    transform: translateY(-50%);
    font-size: 5rem;
    opacity: 0.15;
}
.hero-title { font-size: 2rem; font-weight: 800; margin: 0 0 8px 0; }
.hero-sub   { color: var(--muted); font-size: 1rem; margin: 0; }

/* ── Upload zone ── */
[data-testid="stFileUploader"] {
    background: rgba(108,99,255,0.05) !important;
    border: 2px dashed rgba(108,99,255,0.4) !important;
    border-radius: var(--radius) !important;
    padding: 12px !important;
}
[data-testid="stFileUploader"]:hover {
    border-color: var(--primary) !important;
    background: rgba(108,99,255,0.08) !important;
}

/* ── Buttons ── */
.stButton > button {
    background: linear-gradient(135deg, var(--primary), #8B5CF6) !important;
    color: white !important;
    border: none !important;
    border-radius: 10px !important;
    font-weight: 600 !important;
    font-family: 'Inter', sans-serif !important;
    padding: 10px 24px !important;
    transition: all 0.2s ease !important;
    box-shadow: 0 4px 15px rgba(108,99,255,0.3) !important;
}
.stButton > button:hover {
    transform: translateY(-1px) !important;
    box-shadow: 0 6px 20px rgba(108,99,255,0.45) !important;
}

/* ── Inputs & Selects ── */
.stTextInput input, .stSelectbox select, .stTextArea textarea {
    background: var(--surface) !important;
    border: 1px solid var(--border) !important;
    border-radius: 10px !important;
    color: var(--text) !important;
    font-family: 'Inter', sans-serif !important;
}
.stTextInput input:focus, .stTextArea textarea:focus {
    border-color: var(--primary) !important;
    box-shadow: 0 0 0 2px rgba(108,99,255,0.2) !important;
}

/* ── Scrollbar ── */
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: var(--bg); }
::-webkit-scrollbar-thumb { background: rgba(108,99,255,0.4); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--primary); }

/* ── Document list item ── */
.doc-item {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 14px 18px;
    margin-bottom: 10px;
    cursor: pointer;
    transition: all 0.2s ease;
    display: flex;
    align-items: center;
    gap: 14px;
}
.doc-item:hover {
    border-color: rgba(108,99,255,0.4);
    background: rgba(108,99,255,0.06);
    transform: translateX(3px);
}
.doc-icon { font-size: 1.8rem; }
.doc-title { font-weight: 600; font-size: 0.95rem; }
.doc-meta  { font-size: 0.78rem; color: var(--muted); margin-top: 2px; }

/* ── Spinner override ── */
.stSpinner > div { border-top-color: var(--primary) !important; }

/* ── Divider ── */
hr { border-color: var(--border) !important; margin: 20px 0 !important; }

/* ── Info / Warning / Error boxes ── */
.stAlert { border-radius: 12px !important; border-left-width: 4px !important; }

/* ── Sidebar logo area ── */
.sidebar-logo {
    text-align: center;
    padding: 20px 0 10px 0;
    font-size: 2rem;
    font-weight: 800;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
}
.sidebar-version { text-align: center; color: var(--muted); font-size: 0.7rem; margin-bottom: 20px; }
</style>
""", unsafe_allow_html=True)


# ══════════════════════════════════════════════════════════════════════════════
#  DATABASE
# ══════════════════════════════════════════════════════════════════════════════

def get_db():
    conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id           TEXT PRIMARY KEY,
            category     TEXT NOT NULL,
            display_title TEXT,
            ai_summary   TEXT,
            raw_text     TEXT,
            fields_json  TEXT,
            unextracted  TEXT,
            file_name    TEXT,
            file_type    TEXT,
            created_at   TEXT NOT NULL,
            reminder_at  TEXT
        )
    """)
    conn.commit()
    conn.close()

init_db()


# ══════════════════════════════════════════════════════════════════════════════
#  SETTINGS
# ══════════════════════════════════════════════════════════════════════════════

def load_settings() -> dict:
    if SETTINGS_F.exists():
        try:
            return json.loads(SETTINGS_F.read_text())
        except Exception:
            pass
    return {"provider": "gemini", "gemini_key": "", "openai_key": "", "groq_key": "",
            "groq_model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "custom_url": "", "custom_model": "", "custom_key": ""}

def save_settings(s: dict):
    SETTINGS_F.write_text(json.dumps(s, indent=2))

def get_settings() -> dict:
    if "settings" not in st.session_state:
        st.session_state["settings"] = load_settings()
    return st.session_state["settings"]


# ══════════════════════════════════════════════════════════════════════════════
#  AI PROVIDERS
# ══════════════════════════════════════════════════════════════════════════════

EXTRACTION_PROMPT = """You are an expert document analysis AI. Analyze the document image and extract all relevant information.

Return ONLY a valid JSON object (no markdown, no code fences, no explanation) with this exact structure:

{
  "category": "<one of: bill, prescription, ticket, receipt, exam, notice, other>",
  "raw_text": "<full verbatim text found in the document>",
  "summary": "<one sentence summary of what this document is>",
  "fields": {
    <all key-value pairs relevant to the document category, see below>
  }
}

FIELD RULES BY CATEGORY:
- bill:         vendor, amount (number), currency, due_date (YYYY-MM-DD), account_number, bill_period
- prescription: medicine_name, dosage, expiry_date (YYYY-MM-DD), doctor_name, patient_name, refills
- ticket:       event_name, event_date (YYYY-MM-DD), venue, seat_number, price (number), currency, organizer
- receipt:      store_name, total_amount (number), currency, purchase_date (YYYY-MM-DD), items (array of strings), payment_method
- exam:         subject, exam_date (YYYY-MM-DD), venue, student_name, exam_code, duration
- notice:       title, issued_by, issued_date (YYYY-MM-DD), deadline_date (YYYY-MM-DD), reference_number
- other:        title, description, date (YYYY-MM-DD), issuer

CRITICAL RULES:
1. For any field you CANNOT determine from the document, use JSON null — NEVER guess or fabricate.
2. Dates MUST be in ISO 8601 format (YYYY-MM-DD). If you see partial dates (e.g. "March 2024"), return null.
3. Numeric values (amount, price, total_amount) must be numbers, not strings.
4. Return ONLY the raw JSON. No markdown formatting.
"""

def call_gemini(api_key: str, image_bytes: bytes, mime_type: str) -> str:
    if not GEMINI_OK:
        raise RuntimeError("google-generativeai not installed. Run: pip install google-generativeai")
    genai.configure(api_key=api_key)
    model = genai.GenerativeModel("gemini-1.5-flash")
    img_part = {"mime_type": mime_type, "data": image_bytes}
    response = model.generate_content([EXTRACTION_PROMPT, img_part])
    return response.text

def call_openai(api_key: str, image_bytes: bytes, mime_type: str, model: str = "gpt-4o") -> str:
    if not OPENAI_OK:
        raise RuntimeError("openai not installed. Run: pip install openai")
    client = OpenAI(api_key=api_key)
    b64 = base64.b64encode(image_bytes).decode()
    response = client.chat.completions.create(
        model=model,
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": EXTRACTION_PROMPT},
                {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}},
            ],
        }],
        max_tokens=2000,
    )
    return response.choices[0].message.content

def call_groq(api_key: str, image_bytes: bytes, mime_type: str, model: str) -> str:
    if not OPENAI_OK:
        raise RuntimeError("openai not installed. Run: pip install openai")
    client = OpenAI(api_key=api_key, base_url="https://api.groq.com/openai/v1")
    b64 = base64.b64encode(image_bytes).decode()
    response = client.chat.completions.create(
        model=model,
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": EXTRACTION_PROMPT},
                {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}},
            ],
        }],
        max_tokens=2000,
    )
    return response.choices[0].message.content

def call_custom(base_url: str, api_key: str, model: str, image_bytes: bytes, mime_type: str) -> str:
    if not OPENAI_OK:
        raise RuntimeError("openai not installed. Run: pip install openai")
    client = OpenAI(api_key=api_key, base_url=base_url)
    b64 = base64.b64encode(image_bytes).decode()
    response = client.chat.completions.create(
        model=model,
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": EXTRACTION_PROMPT},
                {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}},
            ],
        }],
        max_tokens=2000,
    )
    return response.choices[0].message.content

def run_extraction(image_bytes: bytes, mime_type: str) -> str:
    """Dispatch to the configured AI provider and return raw text."""
    s = get_settings()
    provider = s.get("provider", "gemini")

    if provider == "gemini":
        key = s.get("gemini_key", "").strip()
        if not key:
            raise ValueError("Gemini API key not set. Go to ⚙ Settings to add it.")
        return call_gemini(key, image_bytes, mime_type)

    elif provider == "openai":
        key = s.get("openai_key", "").strip()
        if not key:
            raise ValueError("OpenAI API key not set. Go to ⚙ Settings to add it.")
        return call_openai(key, image_bytes, mime_type)

    elif provider == "groq":
        key = s.get("groq_key", "").strip()
        if not key:
            raise ValueError("Groq API key not set. Go to ⚙ Settings to add it.")
        model = s.get("groq_model", "meta-llama/llama-4-scout-17b-16e-instruct")
        return call_groq(key, image_bytes, mime_type, model)

    elif provider == "custom":
        base_url = s.get("custom_url", "").strip()
        model    = s.get("custom_model", "").strip()
        key      = s.get("custom_key", "").strip()
        if not base_url or not model:
            raise ValueError("Custom provider URL / model not configured in Settings.")
        return call_custom(base_url, key, model, image_bytes, mime_type)

    else:
        raise ValueError(f"Unknown provider: {provider}")


# ══════════════════════════════════════════════════════════════════════════════
#  EXTRACTION SERVICE
# ══════════════════════════════════════════════════════════════════════════════

def _safe_date(val) -> str | None:
    if val is None:
        return None
    try:
        dt = datetime.fromisoformat(str(val))
        return dt.strftime("%Y-%m-%d")
    except Exception:
        return None

def _safe_num(val) -> float | None:
    if val is None:
        return None
    try:
        return float(val)
    except Exception:
        return None

def strip_fences(text: str) -> str:
    """Remove markdown code fences from AI output."""
    text = text.strip()
    text = re.sub(r"^```[a-z]*\n?", "", text)
    text = re.sub(r"```$", "", text)
    return text.strip()

def parse_ai_response(raw_text: str, file_name: str) -> dict:
    """
    Parse the AI JSON response into a structured document dict.
    Fields that cannot be parsed are recorded in 'unextracted'.
    """
    cleaned = strip_fences(raw_text)

    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError as e:
        raise ValueError(f"AI returned invalid JSON: {e}\n\nRaw output:\n{cleaned[:500]}")

    category     = str(data.get("category", "other")).lower()
    if category not in CATEGORIES:
        category = "other"

    raw_t    = data.get("raw_text") or ""
    summary  = data.get("summary") or ""
    fields_in = data.get("fields") or {}

    parsed_fields = {}
    unextracted   = []

    # ── Define expected fields per category ──────────────────────────────────
    STRING_FIELDS = {
        "bill":         ["vendor","currency","account_number","bill_period"],
        "prescription": ["medicine_name","dosage","doctor_name","patient_name","refills"],
        "ticket":       ["event_name","venue","seat_number","currency","organizer"],
        "receipt":      ["store_name","currency","payment_method"],
        "exam":         ["subject","venue","student_name","exam_code","duration"],
        "notice":       ["title","issued_by","reference_number"],
        "other":        ["title","description","issuer"],
    }
    DATE_FIELDS = {
        "bill":         ["due_date"],
        "prescription": ["expiry_date"],
        "ticket":       ["event_date"],
        "receipt":      ["purchase_date"],
        "exam":         ["exam_date"],
        "notice":       ["issued_date","deadline_date"],
        "other":        ["date"],
    }
    NUM_FIELDS = {
        "bill":         ["amount"],
        "prescription": [],
        "ticket":       ["price"],
        "receipt":      ["total_amount"],
        "exam":         [],
        "notice":       [],
        "other":        [],
    }
    LIST_FIELDS = {
        "receipt": ["items"],
    }

    cat = category
    for key in STRING_FIELDS.get(cat, []):
        v = fields_in.get(key)
        if v is not None and str(v).strip():
            parsed_fields[key] = str(v).strip()
        else:
            unextracted.append(key)

    for key in DATE_FIELDS.get(cat, []):
        v = _safe_date(fields_in.get(key))
        if v:
            parsed_fields[key] = v
        else:
            unextracted.append(key)

    for key in NUM_FIELDS.get(cat, []):
        v = _safe_num(fields_in.get(key))
        if v is not None:
            parsed_fields[key] = v
        else:
            unextracted.append(key)

    for key in LIST_FIELDS.get(cat, []):
        v = fields_in.get(key)
        if isinstance(v, list) and v:
            parsed_fields[key] = v
        else:
            unextracted.append(key)

    # ── Build display title ───────────────────────────────────────────────────
    title_map = {
        "bill":         parsed_fields.get("vendor") or "Bill",
        "prescription": parsed_fields.get("medicine_name") or "Prescription",
        "ticket":       parsed_fields.get("event_name") or "Ticket",
        "receipt":      parsed_fields.get("store_name") or "Receipt",
        "exam":         parsed_fields.get("subject") or "Exam",
        "notice":       parsed_fields.get("title") or "Notice",
        "other":        parsed_fields.get("title") or file_name,
    }
    display_title = title_map.get(cat, file_name)

    # ── Primary date ─────────────────────────────────────────────────────────
    primary_date = None
    for dk in DATE_FIELDS.get(cat, []):
        if dk in parsed_fields:
            primary_date = parsed_fields[dk]
            break

    return {
        "id":            str(uuid.uuid4()),
        "category":      category,
        "display_title": display_title,
        "ai_summary":    summary,
        "raw_text":      raw_t,
        "fields":        parsed_fields,
        "unextracted":   unextracted,
        "file_name":     file_name,
        "primary_date":  primary_date,
        "created_at":    datetime.now().isoformat(),
    }


# ══════════════════════════════════════════════════════════════════════════════
#  STORAGE SERVICE
# ══════════════════════════════════════════════════════════════════════════════

def save_document(doc: dict, reminder_at: str | None = None):
    conn = get_db()
    conn.execute("""
        INSERT OR REPLACE INTO documents
        (id, category, display_title, ai_summary, raw_text, fields_json,
         unextracted, file_name, file_type, created_at, reminder_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
    """, (
        doc["id"], doc["category"], doc["display_title"], doc["ai_summary"],
        doc["raw_text"], json.dumps(doc["fields"]), json.dumps(doc["unextracted"]),
        doc.get("file_name",""), doc.get("file_type",""),
        doc["created_at"], reminder_at,
    ))
    conn.commit()
    conn.close()

def load_documents(search: str = "", category: str = "All") -> list[dict]:
    conn = get_db()
    q = "SELECT * FROM documents WHERE 1=1"
    params = []
    if category != "All":
        q += " AND category = ?"
        params.append(category.lower())
    if search:
        q += " AND (display_title LIKE ? OR ai_summary LIKE ? OR raw_text LIKE ?)"
        s = f"%{search}%"
        params += [s, s, s]
    q += " ORDER BY created_at DESC"
    rows = conn.execute(q, params).fetchall()
    conn.close()
    result = []
    for r in rows:
        d = dict(r)
        d["fields"]      = json.loads(d.get("fields_json") or "{}")
        d["unextracted"] = json.loads(d.get("unextracted") or "[]")
        result.append(d)
    return result

def delete_document(doc_id: str):
    conn = get_db()
    conn.execute("DELETE FROM documents WHERE id = ?", (doc_id,))
    conn.commit()
    conn.close()

def get_stats() -> dict:
    conn = get_db()
    total   = conn.execute("SELECT COUNT(*) FROM documents").fetchone()[0]
    by_cat  = conn.execute(
        "SELECT category, COUNT(*) as cnt FROM documents GROUP BY category"
    ).fetchall()
    upcoming = conn.execute(
        "SELECT COUNT(*) FROM documents WHERE reminder_at IS NOT NULL AND reminder_at >= ?",
        (datetime.now().isoformat(),)
    ).fetchone()[0]
    conn.close()
    cats = {r["category"]: r["cnt"] for r in by_cat}
    return {"total": total, "by_category": cats, "upcoming_reminders": upcoming}


# ══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def card(content_html: str, css_class: str = "ml-card"):
    st.markdown(f'<div class="{css_class}">{content_html}</div>', unsafe_allow_html=True)

def metric_card(num, label: str, color: str = "#6C63FF"):
    st.markdown(f"""
    <div class="metric-card">
        <div class="metric-num" style="color:{color}">{num}</div>
        <div class="metric-label">{label}</div>
    </div>
    """, unsafe_allow_html=True)

def badge(text: str, kind: str = "ok"):
    return f'<span class="badge badge-{kind}">{text}</span>'

def render_field(key: str, value, unit: str = "") -> str:
    label = key.replace("_", " ").title()
    if value is None or value == "":
        return f"""<div class="field-row">
            <span class="field-key">{label}</span>
            <span class="field-miss">⚠ Could not extract</span>
        </div>"""
    disp = str(value)
    if isinstance(value, list):
        disp = ", ".join(str(x) for x in value)
    if unit:
        disp = f"{disp} {unit}"
    return f"""<div class="field-row">
        <span class="field-key">{label}</span>
        <span class="field-val">{disp}</span>
    </div>"""

def render_document_card(doc: dict, show_delete: bool = True):
    cat   = doc["category"]
    icon  = CAT_ICONS.get(cat, "📄")
    color = CAT_COLORS.get(cat, "#B0C4DE")
    title = doc.get("display_title") or doc.get("file_name") or "Document"
    created = doc.get("created_at", "")[:10]
    summary = doc.get("ai_summary") or ""
    unex  = doc.get("unextracted") or []
    fields = doc.get("fields") or {}

    st.markdown(f"""
    <div class="ml-card">
        <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px;">
            <span style="font-size:2rem">{icon}</span>
            <div style="flex:1">
                <div style="font-weight:700;font-size:1.05rem">{title}</div>
                <div style="color:var(--muted);font-size:0.8rem;margin-top:2px">
                    <span style="background:rgba(255,255,255,0.06);padding:2px 8px;border-radius:6px;
                                 color:{color};font-weight:600;font-size:0.72rem;text-transform:uppercase">
                        {cat}
                    </span>
                    &nbsp;·&nbsp;{created}
                </div>
            </div>
        </div>
        {f'<div style="color:var(--muted);font-size:0.87rem;margin-bottom:14px;line-height:1.5">{summary}</div>' if summary else ''}
        {"".join(render_field(k, v) for k, v in fields.items())}
        {f'<div style="margin-top:10px;font-size:0.78rem;color:#FF6B6B"><b>⚠ Could not extract:</b> {", ".join(unex)}</div>' if unex else ""}
    </div>
    """, unsafe_allow_html=True)

    if show_delete:
        if st.button(f"🗑 Delete", key=f"del_{doc['id']}"):
            delete_document(doc["id"])
            st.success("Document deleted.")
            st.rerun()


# ══════════════════════════════════════════════════════════════════════════════
#  PAGES
# ══════════════════════════════════════════════════════════════════════════════

def page_dashboard():
    st.markdown('<div class="hero"><div class="hero-title">🧠 MemoryLens AI</div>'
                '<p class="hero-sub">Your AI-powered personal document memory — '
                'bills, prescriptions, tickets, exams and more.</p></div>',
                unsafe_allow_html=True)

    stats = get_stats()

    # ── KPI row ──────────────────────────────────────────────────────────────
    c1, c2, c3, c4 = st.columns(4)
    with c1: metric_card(stats["total"],              "Total Documents",    "#6C63FF")
    with c2: metric_card(stats["by_category"].get("bill",0),       "Bills",   "#FF6B6B")
    with c3: metric_card(stats["by_category"].get("prescription",0),"Rx",     "#4ECDC4")
    with c4: metric_card(stats["upcoming_reminders"], "Upcoming Reminders", "#FFD600")

    st.markdown("<br>", unsafe_allow_html=True)

    col_left, col_right = st.columns([3, 2])

    with col_left:
        st.markdown('<div class="section-header">Recent Documents</div>'
                    '<div class="section-sub">Your latest captured documents</div>',
                    unsafe_allow_html=True)
        docs = load_documents()[:6]
        if not docs:
            st.markdown("""
            <div class="ml-card" style="text-align:center;padding:40px;color:var(--muted)">
                <div style="font-size:3rem;margin-bottom:12px">📂</div>
                <div style="font-weight:600">No documents yet</div>
                <div style="font-size:0.85rem;margin-top:6px">
                    Go to <b>Capture</b> to upload your first document
                </div>
            </div>
            """, unsafe_allow_html=True)
        else:
            for doc in docs:
                render_document_card(doc, show_delete=False)

    with col_right:
        st.markdown('<div class="section-header">Category Breakdown</div>'
                    '<div class="section-sub">Documents by type</div>',
                    unsafe_allow_html=True)
        by_cat = stats["by_category"]
        total  = max(stats["total"], 1)
        if not by_cat:
            st.info("No documents captured yet.")
        else:
            for cat in CATEGORIES:
                count = by_cat.get(cat, 0)
                if count == 0:
                    continue
                pct   = count / total * 100
                color = CAT_COLORS.get(cat, "#B0C4DE")
                icon  = CAT_ICONS.get(cat, "📄")
                st.markdown(f"""
                <div class="ml-card" style="padding:14px 18px;margin-bottom:8px">
                    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
                        <span style="font-weight:600">{icon} {cat.title()}</span>
                        <span style="color:{color};font-weight:700">{count}</span>
                    </div>
                    <div style="background:rgba(255,255,255,0.06);border-radius:4px;height:6px">
                        <div style="background:{color};border-radius:4px;height:6px;width:{pct:.1f}%"></div>
                    </div>
                </div>
                """, unsafe_allow_html=True)

        # ── Upcoming reminders ────────────────────────────────────────────
        st.markdown('<br><div class="section-header">Upcoming Reminders</div>'
                    '<div class="section-sub">Dates to watch</div>',
                    unsafe_allow_html=True)
        conn = get_db()
        reminders = conn.execute(
            "SELECT display_title, category, reminder_at FROM documents "
            "WHERE reminder_at IS NOT NULL AND reminder_at >= ? "
            "ORDER BY reminder_at LIMIT 5",
            (datetime.now().isoformat(),)
        ).fetchall()
        conn.close()

        if not reminders:
            st.markdown('<div class="ml-card" style="color:var(--muted);text-align:center;padding:20px">'
                        'No upcoming reminders</div>', unsafe_allow_html=True)
        else:
            for r in reminders:
                icon = CAT_ICONS.get(r["category"], "📄")
                dt   = r["reminder_at"][:10]
                st.markdown(f"""
                <div class="ml-card" style="padding:12px 16px;margin-bottom:8px;
                     display:flex;justify-content:space-between;align-items:center">
                    <span>{icon} <b>{r["display_title"]}</b></span>
                    <span style="color:#FFD600;font-size:0.82rem;font-weight:600">📅 {dt}</span>
                </div>
                """, unsafe_allow_html=True)


def page_capture():
    st.markdown('<div class="section-header">📤 Capture Document</div>'
                '<div class="section-sub">Upload a photo, scan, or PDF page — AI extracts everything automatically</div>',
                unsafe_allow_html=True)

    s = get_settings()
    provider = s.get("provider", "gemini")
    key_field = f"{provider}_key"
    has_key   = bool(s.get(key_field, "").strip()) if provider != "custom" else bool(s.get("custom_url","").strip())

    if not has_key:
        st.warning(f"⚠ No API key configured for **{provider.title()}**. "
                   "Go to **⚙ Settings** to add your key and start extracting documents.")
        st.markdown("""
        <div class="ml-card-glass" style="margin-top:12px">
            <b>🔑 Supported providers:</b><br><br>
            <ul style="color:var(--muted);margin:0">
                <li>Google Gemini (recommended — free tier available)</li>
                <li>OpenAI GPT-4o</li>
                <li>Groq (Llama 4 Scout — fast & free tier)</li>
                <li>Custom OpenAI-compatible endpoint</li>
            </ul>
            <br>Your API keys are stored <b>only on this device</b> — never transmitted to any third party.
        </div>
        """, unsafe_allow_html=True)
        return

    uploaded = st.file_uploader(
        "Drop your document here",
        type=["png","jpg","jpeg","webp","gif","bmp","pdf"],
        help="Supported: images (PNG, JPG, WEBP, GIF, BMP). PDF support coming soon.",
        label_visibility="collapsed",
    )

    if uploaded is None:
        st.markdown("""
        <div style="text-align:center;padding:40px;color:var(--muted)">
            <div style="font-size:4rem;margin-bottom:16px">🖼️</div>
            <div style="font-size:1.1rem;font-weight:600">Drag & drop a document image</div>
            <div style="font-size:0.85rem;margin-top:8px">PNG · JPG · WEBP · GIF · BMP</div>
        </div>
        """, unsafe_allow_html=True)
        return

    col_img, col_result = st.columns([1, 2])

    with col_img:
        st.markdown('<div class="section-header" style="font-size:1rem">Preview</div>', unsafe_allow_html=True)
        file_bytes = uploaded.read()
        mime_type  = uploaded.type
        file_name  = uploaded.name

        if PIL_OK and not mime_type.endswith("/pdf"):
            try:
                img = Image.open(BytesIO(file_bytes))
                st.image(img, use_container_width=True)
            except Exception:
                st.warning("Could not preview image.")
        else:
            st.info(f"📄 {file_name} ({len(file_bytes)//1024} KB)")

    with col_result:
        st.markdown('<div class="section-header" style="font-size:1rem">AI Extraction</div>', unsafe_allow_html=True)

        if st.button("🚀 Analyze with AI", use_container_width=True):
            with st.spinner("🤖 AI is reading your document..."):
                try:
                    raw_ai   = run_extraction(file_bytes, mime_type)
                    doc      = parse_ai_response(raw_ai, file_name)
                    doc["file_type"] = mime_type
                    st.session_state["last_doc"]    = doc
                    st.session_state["show_review"] = True
                except Exception as e:
                    st.error(f"❌ Extraction failed: {e}")
                    st.session_state.pop("last_doc", None)
                    st.session_state.pop("show_review", None)

    if st.session_state.get("show_review") and "last_doc" in st.session_state:
        doc = st.session_state["last_doc"]
        st.markdown("---")
        st.markdown('<div class="section-header">Review & Save</div>', unsafe_allow_html=True)

        r1, r2 = st.columns([2, 1])

        with r1:
            # ── Summary ──────────────────────────────────────────────────
            st.markdown(f"""
            <div class="ml-card-glass">
                <div style="font-size:0.78rem;color:var(--muted);font-weight:600;
                            text-transform:uppercase;letter-spacing:1px;margin-bottom:8px">AI Summary</div>
                <div style="line-height:1.6">{doc.get("ai_summary","—")}</div>
            </div>
            """, unsafe_allow_html=True)

            # ── Fields ───────────────────────────────────────────────────
            fields = doc.get("fields", {})
            unex   = doc.get("unextracted", [])
            all_keys = list(fields.keys()) + unex

            html_rows = ""
            for key in fields:
                html_rows += render_field(key, fields[key])
            for key in unex:
                html_rows += render_field(key, None)

            cat   = doc["category"]
            color = CAT_COLORS.get(cat, "#B0C4DE")
            icon  = CAT_ICONS.get(cat, "📄")

            st.markdown(f"""
            <div class="ml-card">
                <div style="display:flex;align-items:center;gap:10px;margin-bottom:16px">
                    <span style="font-size:1.8rem">{icon}</span>
                    <div>
                        <div style="font-weight:700">{doc.get("display_title","Document")}</div>
                        <span style="color:{color};font-size:0.75rem;font-weight:700;text-transform:uppercase">{cat}</span>
                    </div>
                </div>
                {html_rows}
            </div>
            """, unsafe_allow_html=True)

        with r2:
            st.markdown("**Set a reminder** (optional)")
            reminder_date = st.date_input(
                "Reminder date",
                value=None,
                min_value=date.today(),
                key="reminder_date",
                label_visibility="collapsed",
            )
            reminder_time = st.time_input("Reminder time", value=None, key="reminder_time",
                                          label_visibility="collapsed")

            st.markdown("<br>", unsafe_allow_html=True)

            if st.button("💾 Save Document", use_container_width=True):
                reminder_at = None
                if reminder_date:
                    t = reminder_time if reminder_time else datetime.now().time()
                    reminder_at = datetime.combine(reminder_date, t).isoformat()

                save_document(doc, reminder_at)
                st.success("✅ Document saved successfully!")
                st.session_state.pop("last_doc", None)
                st.session_state.pop("show_review", None)
                st.balloons()

            if st.button("❌ Discard", use_container_width=True):
                st.session_state.pop("last_doc", None)
                st.session_state.pop("show_review", None)
                st.rerun()

            # ── Raw text expander ────────────────────────────────────────
            with st.expander("🔍 Raw extracted text"):
                st.text_area("", doc.get("raw_text",""), height=200,
                             disabled=True, label_visibility="collapsed")


def page_search():
    st.markdown('<div class="section-header">🔍 Search Documents</div>'
                '<div class="section-sub">Find any document by keyword, date, or category</div>',
                unsafe_allow_html=True)

    c1, c2 = st.columns([3, 1])
    with c1:
        query = st.text_input("Search", placeholder="Search by vendor, medicine, event, subject…",
                               label_visibility="collapsed")
    with c2:
        cat_filter = st.selectbox("Category", ["All"] + [c.title() for c in CATEGORIES],
                                   label_visibility="collapsed")

    docs = load_documents(search=query, category=cat_filter)

    st.markdown(f"""
    <div style="color:var(--muted);font-size:0.85rem;margin:8px 0 20px 0">
        {len(docs)} document{"s" if len(docs) != 1 else ""} found
        {f'· filtered by <b>{cat_filter}</b>' if cat_filter != "All" else ""}
        {f'· matching <b>"{query}"</b>' if query else ""}
    </div>
    """, unsafe_allow_html=True)

    if not docs:
        st.markdown("""
        <div class="ml-card" style="text-align:center;padding:40px;color:var(--muted)">
            <div style="font-size:3rem;margin-bottom:12px">🔎</div>
            <div style="font-weight:600">No documents match your search</div>
            <div style="font-size:0.85rem;margin-top:6px">Try a different keyword or category</div>
        </div>
        """, unsafe_allow_html=True)
        return

    for doc in docs:
        render_document_card(doc, show_delete=True)


def page_settings():
    st.markdown('<div class="section-header">⚙ Settings & API Keys</div>'
                '<div class="section-sub">Configure your AI provider. Keys are saved locally on this device only.</div>',
                unsafe_allow_html=True)

    s = get_settings()

    st.markdown("""
    <div class="ml-card-glass" style="margin-bottom:20px">
        🔒 <b>Privacy guarantee:</b> Your API keys are stored in a local file on this machine
        (<code>data/settings.json</code>). They are never sent to any server other than the AI
        provider you choose directly from your browser/machine.
    </div>
    """, unsafe_allow_html=True)

    # ── Provider selection ────────────────────────────────────────────────────
    PROVIDERS = {
        "gemini": "🟣 Google Gemini (gemini-1.5-flash) — Recommended",
        "openai": "🟢 OpenAI GPT-4o",
        "groq":   "🔵 Groq (Llama 4 Scout) — Fast & Free",
        "custom": "⚙ Custom OpenAI-compatible endpoint",
    }
    provider = st.selectbox(
        "AI Provider",
        list(PROVIDERS.keys()),
        format_func=lambda k: PROVIDERS[k],
        index=list(PROVIDERS.keys()).index(s.get("provider","gemini")),
    )
    s["provider"] = provider

    st.markdown("---")

    # ── Provider-specific config ──────────────────────────────────────────────
    if provider == "gemini":
        st.markdown("**Google Gemini API Key**")
        key = st.text_input("Gemini Key", value=s.get("gemini_key",""),
                            type="password", placeholder="AIza…",
                            label_visibility="collapsed")
        s["gemini_key"] = key
        st.markdown("[Get a free Gemini API key →](https://aistudio.google.com/app/apikey)",
                    unsafe_allow_html=False)

    elif provider == "openai":
        st.markdown("**OpenAI API Key**")
        key = st.text_input("OpenAI Key", value=s.get("openai_key",""),
                            type="password", placeholder="sk-…",
                            label_visibility="collapsed")
        s["openai_key"] = key
        st.markdown("[Get an OpenAI API key →](https://platform.openai.com/api-keys)",
                    unsafe_allow_html=False)

    elif provider == "groq":
        st.markdown("**Groq API Key**")
        key = st.text_input("Groq Key", value=s.get("groq_key",""),
                            type="password", placeholder="gsk_…",
                            label_visibility="collapsed")
        s["groq_key"] = key
        model = st.text_input("Groq Model", value=s.get("groq_model",
                              "meta-llama/llama-4-scout-17b-16e-instruct"))
        s["groq_model"] = model
        st.markdown("[Get a free Groq API key →](https://console.groq.com/keys)",
                    unsafe_allow_html=False)

    elif provider == "custom":
        st.markdown("**Custom OpenAI-compatible Endpoint**")
        c1, c2 = st.columns(2)
        with c1:
            url = st.text_input("Base URL", value=s.get("custom_url",""),
                                placeholder="https://your-api.com/v1")
            s["custom_url"] = url
        with c2:
            model = st.text_input("Model Name", value=s.get("custom_model",""),
                                  placeholder="e.g. llava-1.5")
            s["custom_model"] = model
        key = st.text_input("API Key (optional)", value=s.get("custom_key",""),
                            type="password", placeholder="Leave blank if not required")
        s["custom_key"] = key

    st.markdown("<br>", unsafe_allow_html=True)

    if st.button("💾 Save Settings", use_container_width=False):
        save_settings(s)
        st.session_state["settings"] = s
        st.success("✅ Settings saved!")

    # ── Data management ───────────────────────────────────────────────────────
    st.markdown("---")
    st.markdown('<div class="section-header" style="font-size:1.1rem">🗃 Data Management</div>',
                unsafe_allow_html=True)
    st.markdown(f"Documents stored at: `{DB_PATH}`")

    stats = get_stats()
    st.markdown(f"**{stats['total']}** documents stored locally.")

    with st.expander("⚠ Danger Zone — Delete All Data"):
        st.warning("This will permanently delete ALL your captured documents. This cannot be undone.")
        if st.button("🗑 Delete All Documents", type="secondary"):
            conn = get_db()
            conn.execute("DELETE FROM documents")
            conn.commit()
            conn.close()
            st.success("All documents deleted.")
            st.rerun()


# ══════════════════════════════════════════════════════════════════════════════
#  SIDEBAR + ROUTING
# ══════════════════════════════════════════════════════════════════════════════

with st.sidebar:
    st.markdown('<div class="sidebar-logo">🧠 MemoryLens</div>'
                '<div class="sidebar-version">AI Document Intelligence · v1.0</div>',
                unsafe_allow_html=True)
    st.markdown("---")

    page = st.radio(
        "Navigation",
        ["🏠 Dashboard", "📤 Capture", "🔍 Search", "⚙ Settings"],
        label_visibility="collapsed",
    )

    st.markdown("<br>", unsafe_allow_html=True)

    s = get_settings()
    provider = s.get("provider","gemini")
    key_field = f"{provider}_key"
    has_key   = bool(s.get(key_field,"").strip()) if provider != "custom" else bool(s.get("custom_url","").strip())

    st.markdown(f"""
    <div class="ml-card" style="padding:12px 16px">
        <div style="font-size:0.72rem;color:var(--muted);text-transform:uppercase;letter-spacing:1px;margin-bottom:6px">AI Provider</div>
        <div style="font-weight:600;font-size:0.9rem">{provider.title()}</div>
        <div style="margin-top:6px">
            {"<span class='badge badge-ok'>● Connected</span>" if has_key
             else "<span class='badge badge-warn'>⚠ No API Key</span>"}
        </div>
    </div>
    """, unsafe_allow_html=True)

    stats = get_stats()
    st.markdown(f"""
    <div class="ml-card" style="padding:12px 16px;margin-top:8px">
        <div style="font-size:0.72rem;color:var(--muted);text-transform:uppercase;letter-spacing:1px;margin-bottom:6px">Storage</div>
        <div style="font-weight:600;font-size:1.2rem;color:var(--primary)">{stats['total']}</div>
        <div style="font-size:0.78rem;color:var(--muted)">documents saved</div>
    </div>
    """, unsafe_allow_html=True)

# ── Route to page ─────────────────────────────────────────────────────────────
if   "Dashboard" in page: page_dashboard()
elif "Capture"   in page: page_capture()
elif "Search"    in page: page_search()
elif "Settings"  in page: page_settings()
