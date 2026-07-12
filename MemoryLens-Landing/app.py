"""
MemoryLens AI — Flask Landing Page Backend
==========================================
Real AI document extraction with BYOK API support.
Real reminder persistence via SQLite.
All other features are visual UI only.
"""

from flask import Flask, render_template, request, jsonify, session
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

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024  # 16 MB limit
app.secret_key = os.getenv("FLASK_SECRET_KEY", "dev-secret-change-me")

# ── Paths ────────────────────────────────────────────────────────────────────
UPLOAD_FOLDER = Path("static/uploads")
UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)

DATA_DIR = Path("data")
DATA_DIR.mkdir(exist_ok=True)
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
@app.route("/")
def index():
    reminders = get_all_reminders()
    connected_provider = session.get("ai_provider")
    
    return render_template(
        "index.html",
        reminders=reminders,
        connected_provider=connected_provider
    )

@app.route("/api/connect", methods=["POST"])
def connect_provider():
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"success": False, "error": "No JSON body."}), 400
        
    provider_name = body.get("provider")
    api_key = body.get("api_key")
    base_url = body.get("base_url")
    
    if not provider_name or not api_key:
        return jsonify({"success": False, "error": "Provider and API Key are required."}), 400
        
    try:
        provider = get_provider(provider_name, api_key, base_url)
        provider.test_connection()
        
        # Save to session (signed cookie)
        session["ai_provider"] = provider_name
        session["ai_api_key"] = api_key
        if base_url:
            session["ai_base_url"] = base_url
            
        return jsonify({"success": True, "provider": provider_name})
    except ValueError as e:
        return jsonify({"success": False, "error": str(e)}), 400
    except requests.exceptions.HTTPError as e:
        return jsonify({"success": False, "error": f"API Key rejected by provider (HTTP {e.response.status_code})"}), 400
    except Exception as e:
        return jsonify({"success": False, "error": f"Failed to connect: {str(e)}"}), 500

@app.route("/api/disconnect", methods=["POST"])
def disconnect_provider():
    session.pop("ai_provider", None)
    session.pop("ai_api_key", None)
    session.pop("ai_base_url", None)
    return jsonify({"success": True})


@app.route("/api/extract", methods=["POST"])
def extract():
    """Upload a document image → call AI Provider → return structured JSON."""
    provider_name = session.get("ai_provider")
    api_key = session.get("ai_api_key")
    base_url = session.get("ai_base_url")
    
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
        provider = get_provider(provider_name, api_key, base_url)
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


if __name__ == "__main__":
    app.run(debug=True, port=5000)
