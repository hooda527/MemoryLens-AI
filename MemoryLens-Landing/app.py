"""
MemoryLens AI — Flask Landing Page Backend
==========================================
Real AI document extraction with BYOK API support.
Real reminder persistence via SQLite.
All other features are visual UI only.
"""

from flask import Flask, render_template, request, jsonify
import sqlite3
import os
import json
import requests
import uuid
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv

from ai_provider import get_provider

load_dotenv()

app = Flask(__name__, static_folder=os.path.join(os.path.dirname(os.path.abspath(__file__)), "static"))
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024  # 16 MB limit
app.secret_key = os.getenv("FLASK_SECRET_KEY", "dev-secret-change-me")

# ── Paths ────────────────────────────────────────────────────────────────────
# On Vercel, the filesystem is read-only except /tmp
IS_VERCEL = os.getenv("VERCEL") == "1"

if IS_VERCEL:
    UPLOAD_FOLDER = Path("/tmp/uploads")
    DATA_DIR = Path("/tmp")
else:
    UPLOAD_FOLDER = Path("static/uploads")
    DATA_DIR = Path("data")
    DATA_DIR.mkdir(exist_ok=True)

UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "memorylens.db"

ALLOWED_MIME = {"image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif", "image/bmp"}

# ── Extraction Prompt ────────────────────────────────────────────────────────
EXTRACTION_PROMPT = """Analyze this document image carefully and extract all information.
Return ONLY a valid JSON object. No markdown, no code fences, no explanation.

{
  "document_type": "<one of: bill | prescription | ticket | receipt | exam | notice | other>",
  "summary": "<one sentence describing what this document is>",
  "fields": {
    "<field_name>": "<value or null>"
  },
  "dates": {
    "primary_date": "<the single most important actionable date in YYYY-MM-DD format, or null>",
    "primary_date_label": "<label for the date, e.g. Due Date / Expiry Date / Event Date / Exam Date, or null>"
  },
  "raw_text": "<all text found verbatim in the document>"
}

FIELD RULES (extract what is relevant for the detected document type):
- bill: vendor, amount (number), currency, due_date (YYYY-MM-DD), account_number, bill_period
- prescription: medicine_name, dosage, doctor_name, patient_name, expiry_date (YYYY-MM-DD), refills
- ticket: event_name, event_date (YYYY-MM-DD), venue, seat_number, price (number), currency, organizer
- receipt: store_name, total_amount (number), currency, purchase_date (YYYY-MM-DD), payment_method, items (array)
- exam: subject, exam_date (YYYY-MM-DD), venue, student_name, exam_code, duration
- notice: title, issued_by, issued_date (YYYY-MM-DD), deadline_date (YYYY-MM-DD), reference_number
- other: title, description, date (YYYY-MM-DD), issuer

CRITICAL RULES:
1. If you CANNOT determine a field from the image, set it to JSON null — NEVER guess.
2. Dates MUST be YYYY-MM-DD. Partial dates (e.g. "March 2024") must be null.
3. Numeric values (amount, price, total_amount) must be JSON numbers, not strings.
4. Return ONLY the raw JSON object. Nothing else."""


# ── Database ─────────────────────────────────────────────────────────────────
def init_db():
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("""
        CREATE TABLE IF NOT EXISTS reminders (
            id           TEXT PRIMARY KEY,
            document_title TEXT NOT NULL,
            reminder_date  TEXT NOT NULL,
            document_type  TEXT,
            note           TEXT,
            created_at     TEXT NOT NULL
        )
    """)
    conn.commit()
    conn.close()


init_db()


def get_all_reminders() -> list[dict]:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT * FROM reminders ORDER BY reminder_date ASC"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ── Routes ────────────────────────────────────────────────────────────────────
def _get_creds():
    """Read AI credentials from request headers (stored in localStorage by the frontend)."""
    provider  = request.headers.get("X-AI-Provider", "").strip()
    api_key   = request.headers.get("X-AI-Key", "").strip()
    base_url  = request.headers.get("X-AI-Base-Url", "").strip() or None
    model_name = request.headers.get("X-AI-Model", "").strip() or None
    return provider, api_key, base_url, model_name


@app.route("/")
def index():
    reminders = get_all_reminders()
    return render_template(
        "index.html",
        reminders=reminders,
        connected_provider=None
    )

@app.route("/hero")
def hero():
    return render_template("hero.html")

@app.route("/api/connect", methods=["POST"])
def connect_provider():
    """Validate credentials sent in the request body — no session needed."""
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"success": False, "error": "No JSON body."}), 400

    provider_name = body.get("provider", "").strip()
    api_key       = body.get("api_key", "").strip()
    base_url      = body.get("base_url", "").strip() or None
    model_name    = body.get("model_name", "").strip() or None

    if not provider_name or not api_key:
        return jsonify({"success": False, "error": "Provider and API Key are required."}), 400

    try:
        provider = get_provider(provider_name, api_key, base_url, model_name)
        provider.test_connection()
        # Return success — frontend stores creds in localStorage
        return jsonify({"success": True, "provider": provider_name})
    except ValueError as e:
        return jsonify({"success": False, "error": str(e)}), 400
    except requests.exceptions.HTTPError as e:
        msg = str(e.args[0]) if e.args else "API key rejected by provider"
        return jsonify({"success": False, "error": f"❌ {msg}"}), 400
    except requests.exceptions.ConnectionError:
        return jsonify({"success": False, "error": "Network error — could not reach the AI provider."}), 500
    except requests.exceptions.Timeout:
        return jsonify({"success": False, "error": "Connection timed out. Provider may be busy, try again."}), 500
    except Exception as e:
        return jsonify({"success": False, "error": f"Failed to connect: {str(e)}"}), 500


@app.route("/api/disconnect", methods=["POST"])
def disconnect_provider():
    # Frontend will clear localStorage; nothing to do server-side
    return jsonify({"success": True})


@app.route("/api/extract", methods=["POST"])
def extract():
    """Upload a document image → call AI Provider → return structured JSON."""
    provider_name, api_key, base_url, model_name = _get_creds()

    if not provider_name or not api_key:
        return jsonify({
            "success": False,
            "error": "No AI Provider connected. Please connect a provider in settings first."
        }), 401

    if "file" not in request.files:
        return jsonify({"success": False, "error": "No file uploaded."}), 400

    file = request.files["file"]
    if not file.filename:
        return jsonify({"success": False, "error": "Empty filename."}), 400

    mime_type = file.content_type or "image/jpeg"
    if mime_type not in ALLOWED_MIME:
        return jsonify({
            "success": False,
            "error": f"Unsupported file type: {mime_type}. "
                     "Please upload PNG, JPG, WEBP, or GIF."
        }), 400

    image_bytes = file.read()
    if len(image_bytes) == 0:
        return jsonify({"success": False, "error": "File is empty."}), 400

    try:
        provider = get_provider(provider_name, api_key, base_url, model_name)
        result = provider.analyze(image_bytes, mime_type, EXTRACTION_PROMPT)
        return jsonify({"success": True, "data": result})

    except ValueError as e:
        return jsonify({"success": False, "error": str(e)}), 400

    except requests.exceptions.HTTPError as e:
        code = e.response.status_code if e.response else "?"
        msg = f"AI Provider API error (HTTP {code})."
        
        if code == 400:
            msg = "Provider rejected the request — check image quality or API limits."
        elif code == 401 or code == 403:
            msg = "Unauthorized API key. Please disconnect and reconnect your provider."
        elif code == 429:
            msg = "Provider rate limit hit. Wait a moment and try again."
        else:
            try:
                err_body = e.response.json()
                msg = err_body.get("error", {}).get("message", msg)
            except Exception:
                pass
        return jsonify({"success": False, "error": msg}), 500

    except requests.exceptions.Timeout:
        return jsonify({
            "success": False,
            "error": "Request timed out. The image may be too large, or provider is busy. Try again."
        }), 504

    except json.JSONDecodeError as e:
        return jsonify({
            "success": False,
            "error": f"AI returned malformed JSON. Try a clearer image. Detail: {e}"
        }), 500

    except Exception as e:
        return jsonify({"success": False, "error": f"Unexpected error: {e}"}), 500


@app.route("/api/reminder", methods=["POST"])
def set_reminder():
    """Persist a reminder in SQLite."""
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"success": False, "error": "No JSON body."}), 400

    title         = (body.get("title") or "").strip()
    reminder_date = (body.get("date") or "").strip()
    doc_type      = (body.get("document_type") or "other").strip()
    note          = (body.get("note") or "").strip()

    if not title:
        return jsonify({"success": False, "error": "title is required."}), 400
    if not reminder_date:
        return jsonify({"success": False, "error": "date is required."}), 400

    try:
        datetime.strptime(reminder_date, "%Y-%m-%d")
    except ValueError:
        return jsonify({"success": False, "error": "date must be YYYY-MM-DD."}), 400

    rid = str(uuid.uuid4())
    now = datetime.now().isoformat()

    conn = sqlite3.connect(str(DB_PATH))
    conn.execute(
        "INSERT INTO reminders (id, document_title, reminder_date, document_type, note, created_at) "
        "VALUES (?,?,?,?,?,?)",
        (rid, title, reminder_date, doc_type, note, now),
    )
    conn.commit()
    conn.close()

    return jsonify({
        "success": True,
        "reminder": {
            "id": rid,
            "document_title": title,
            "reminder_date": reminder_date,
            "document_type": doc_type,
            "note": note,
            "created_at": now,
        },
    })


@app.route("/api/reminders", methods=["GET"])
def list_reminders():
    return jsonify({"reminders": get_all_reminders()})


@app.route("/api/reminder/<reminder_id>", methods=["DELETE"])
def delete_reminder(reminder_id):
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("DELETE FROM reminders WHERE id = ?", (reminder_id,))
    conn.commit()
    conn.close()
    return jsonify({"success": True})


@app.route("/api/search", methods=["POST"])
def search_documents():
    provider_name, api_key, base_url, model_name = _get_creds()

    if not provider_name or not api_key:
        return jsonify({"success": False, "error": "No AI Provider connected. Please connect one in settings."}), 401

    body = request.get_json(silent=True)
    query = (body.get("query") or "").strip() if body else ""
    if not query:
        return jsonify({"success": False, "error": "Query is empty."}), 400

    reminders = get_all_reminders()
    if not reminders:
        return jsonify({"success": True, "answer": "You have no saved documents or reminders yet."})

    context_lines = []
    for r in reminders:
        context_lines.append(f"- [{r['document_type']}] {r['document_title']} (Date: {r['reminder_date']}) - Note: {r['note'] or 'None'}")
    context = "\n".join(context_lines)

    prompt = (
        f"You are a helpful assistant for MemoryLens AI. The user has the following saved documents/reminders:\n"
        f"{context}\n\n"
        f"Based on this information ONLY, answer the user's question. Keep it concise, helpful, and friendly. "
        f"If the answer isn't in the saved documents, say you don't have that information.\n"
        f"User Question: {query}"
    )

    try:
        provider = get_provider(provider_name, api_key, base_url, model_name)
        answer = provider.chat(prompt)
        return jsonify({"success": True, "answer": answer})
    except Exception as e:
        return jsonify({"success": False, "error": f"AI search failed: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(debug=True, port=5000)
