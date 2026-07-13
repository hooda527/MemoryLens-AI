/* ============================================================
   MemoryLens AI — main.js
   Neural sphere · OCR · AI extraction · Reminders · Search
   ============================================================ */

"use strict";

/* ════════════════════════════════════════════════════════════
   1. NEURAL SPHERE CANVAS
   ════════════════════════════════════════════════════════════ */
class NeuralSphere {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx    = canvas.getContext("2d");
    this.W      = canvas.width;
    this.H      = canvas.height;
    this.cx     = this.W / 2;
    this.cy     = this.H / 2;
    this.targetCx = this.cx;
    this.targetCy = this.cy;
    this.R      = 155;
    this.rotation = 0;
    this.nodes  = [];
    this.generateNodes(100);

    window.addEventListener("mousemove", (e) => {
      const w = window.innerWidth, h = window.innerHeight;
      const dx = (e.clientX - w / 2) / (w / 2);
      const dy = (e.clientY - h / 2) / (h / 2);
      this.targetCx = this.W / 2 - dx * 24;
      this.targetCy = this.H / 2 - dy * 24;
    });

    this.animate();
  }

  generateNodes(count) {
    const golden = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < count; i++) {
      const y     = 1 - (i / (count - 1)) * 2;
      const r     = Math.sqrt(1 - y * y);
      const theta = golden * i;
      this.nodes.push({
        ox:          Math.cos(theta) * r,
        oy:          y,
        oz:          Math.sin(theta) * r,
        size:        Math.random() * 1.6 + 0.6,
        brightness:  Math.random() * 0.5 + 0.5,
        pulseOffset: Math.random() * Math.PI * 2,
        color:       Math.random() > 0.55
                       ? "cyan"
                       : Math.random() > 0.4
                         ? "purple"
                         : "blue",
      });
    }
  }

  project(x, y, z) {
    const cos = Math.cos(this.rotation);
    const sin = Math.sin(this.rotation);
    const rx  = x * cos - z * sin;
    const rz  = x * sin + z * cos;
    const fov = 2.8;
    const s   = fov / (fov + rz);
    return { x: this.cx + rx * this.R * s, y: this.cy + y * this.R * s, z: rz, scale: s };
  }

  nodeRGB(node) {
    if (node.color === "cyan")   return [6, 182, 212];
    if (node.color === "purple") return [168, 85, 247];
    return [59, 130, 246];
  }

  draw() {
    const ctx = this.ctx;
    const t   = Date.now() / 1000;

    this.cx += (this.targetCx - this.cx) * 0.08;
    this.cy += (this.targetCy - this.cy) * 0.08;

    ctx.clearRect(0, 0, this.W, this.H);

    /* ambient glow */
    const g1 = ctx.createRadialGradient(this.cx, this.cy, 0, this.cx, this.cy, this.R * 1.4);
    g1.addColorStop(0,   "rgba(59,130,246,0.16)");
    g1.addColorStop(0.4, "rgba(168,85,247,0.08)");
    g1.addColorStop(0.7, "rgba(6,182,212,0.04)");
    g1.addColorStop(1,   "rgba(0,0,0,0)");
    ctx.fillStyle = g1;
    ctx.fillRect(0, 0, this.W, this.H);

    /* core sphere glow */
    const g2 = ctx.createRadialGradient(this.cx - 35, this.cy - 35, 0, this.cx, this.cy, this.R);
    g2.addColorStop(0,   "rgba(99,102,241,0.14)");
    g2.addColorStop(0.5, "rgba(59,130,246,0.06)");
    g2.addColorStop(1,   "rgba(0,0,0,0)");
    ctx.beginPath();
    ctx.arc(this.cx, this.cy, this.R, 0, Math.PI * 2);
    ctx.fillStyle = g2;
    ctx.fill();

    /* project & sort nodes */
    const projected = this.nodes.map(n => {
      const p     = this.project(n.ox, n.oy, n.oz);
      const pulse = Math.sin(t * 2.4 + n.pulseOffset) * 0.3 + 0.7;
      return { ...p, size: n.size, brightness: n.brightness, pulse, rgb: this.nodeRGB(n) };
    });
    projected.sort((a, b) => a.z - b.z);

    /* connections */
    for (let i = 0; i < projected.length; i++) {
      for (let j = i + 1; j < projected.length; j++) {
        const a = projected[i], b = projected[j];
        if (a.z < -0.25 || b.z < -0.25) continue;
        const dx = a.x - b.x, dy = a.y - b.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > 68) continue;
        const alpha = (1 - dist / 68) * 0.20 * Math.min(a.scale, b.scale);
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.strokeStyle = `rgba(99,130,246,${alpha})`;
        ctx.lineWidth   = 0.55;
        ctx.stroke();
      }
    }

    /* nodes */
    for (const p of projected) {
      if (p.z < -0.3) continue;
      const alpha = ((p.z + 1) / 2) * p.brightness * p.pulse;
      const size  = p.size * p.scale * 1.5;
      const [r, g, b] = p.rgb;
      ctx.shadowBlur  = 8;
      ctx.shadowColor = `rgba(${r},${g},${b},${alpha * 0.9})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, size, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${r},${g},${b},${alpha})`;
      ctx.fill();
    }
    ctx.shadowBlur = 0;

    /* equator ring */
    ctx.beginPath();
    ctx.ellipse(this.cx, this.cy, this.R * 0.97, this.R * 0.16, this.rotation, 0, Math.PI * 2);
    ctx.strokeStyle = "rgba(59,130,246,0.18)";
    ctx.lineWidth   = 1;
    ctx.stroke();

    this.rotation += 0.002;
  }

  animate() {
    this.draw();
    requestAnimationFrame(() => this.animate());
  }
}

/* ════════════════════════════════════════════════════════════
   2. SVG CONNECTING LINES (phone → sphere → workflows)
   ════════════════════════════════════════════════════════════ */
function drawConnectingLines() {
  const svg     = document.getElementById("svgLines");
  const section = document.getElementById("sphereSection");
  const canvas  = document.getElementById("sphereCanvas");
  if (!svg || !section || !canvas) return;

  /* clear old lines except <defs> */
  while (svg.children.length > 2) svg.removeChild(svg.lastChild);

  const secRect = section.getBoundingClientRect();
  const canRect = canvas.getBoundingClientRect();
  const cx = canRect.left - secRect.left + canRect.width  / 2;
  const cy = canRect.top  - secRect.top  + canRect.height / 2;

  /* draw lines from phone deck cards if visible */
  const phoneSection = document.querySelector(".left-phone-section");
  const wfSection    = document.querySelector(".right-workflows-section");
  if (!phoneSection || !wfSection) return;

  const drawSvgLine = (x1, y1, gradId, delay) => {
    const mpx = (x1 + cx) / 2 + (Math.random() - 0.5) * 50;
    const mpy = (y1 + cy) / 2 + (Math.random() - 0.5) * 50;

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", `M${x1},${y1} Q${mpx},${mpy} ${cx},${cy}`);
    path.setAttribute("stroke", `url(#${gradId})`);
    path.setAttribute("stroke-width", "1.2");
    path.setAttribute("fill", "none");
    path.setAttribute("stroke-dasharray", "6 5");
    path.setAttribute("opacity", "0.7");

    const anim = document.createElementNS("http://www.w3.org/2000/svg", "animate");
    anim.setAttribute("attributeName", "stroke-dashoffset");
    anim.setAttribute("from", "0");
    anim.setAttribute("to",  "-22");
    anim.setAttribute("dur", `${1.3 + delay * 0.25}s`);
    anim.setAttribute("repeatCount", "indefinite");
    path.appendChild(anim);
    svg.appendChild(path);
  };

  /* phone deck → center */
  const phoneRect = phoneSection.getBoundingClientRect();
  const px = phoneRect.right - secRect.left;
  const py = phoneRect.top + phoneRect.height / 2 - secRect.top;
  [0, 1, 2].forEach(i => drawSvgLine(px, py + (i - 1) * 40, "lineGrad1", i));

  /* center → right workflows */
  const wfRect = wfSection.getBoundingClientRect();
  const wx = wfRect.left - secRect.left;
  const wy = wfRect.top + wfRect.height / 2 - secRect.top;
  [0, 1, 2].forEach(i => {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    const tx   = wx;
    const ty   = wy + (i - 1) * 50;
    const mpx2 = (cx + tx) / 2 + (Math.random() - 0.5) * 40;
    const mpy2 = (cy + ty) / 2 + (Math.random() - 0.5) * 40;
    path.setAttribute("d", `M${cx},${cy} Q${mpx2},${mpy2} ${tx},${ty}`);
    path.setAttribute("stroke", "url(#lineGrad2)");
    path.setAttribute("stroke-width", "1.2");
    path.setAttribute("fill", "none");
    path.setAttribute("stroke-dasharray", "6 5");
    path.setAttribute("opacity", "0.6");
    const anim = document.createElementNS("http://www.w3.org/2000/svg", "animate");
    anim.setAttribute("attributeName", "stroke-dashoffset");
    anim.setAttribute("from", "0");
    anim.setAttribute("to",  "22");
    anim.setAttribute("dur", `${1.5 + i * 0.3}s`);
    anim.setAttribute("repeatCount", "indefinite");
    path.appendChild(anim);
    svg.appendChild(path);
  });
}

/* ════════════════════════════════════════════════════════════
   3. CYCLING SEARCH BAR (typewriter)
   ════════════════════════════════════════════════════════════ */
function initSearchCycler() {
  const input = document.getElementById("searchBar");
  if (!input) return;

  const queries = [
    'medicine" or "exam"',
    "Find my electricity bill...",
    "When does my prescription expire?",
    "Concert ticket seat number...",
    "Chemistry exam date and venue...",
    "Insurance policy renewal date...",
    "Flight boarding time...",
    "Rent due date this month...",
  ];

  let qIdx  = 0, cIdx = 0, deleting = false, pausing = false, isFocused = false;

  input.addEventListener("focus", () => { isFocused = true; input.placeholder = "Search your documents..."; });
  input.addEventListener("blur",  () => { isFocused = false; if (!input.value) cIdx = 0; });
  input.addEventListener("keypress", e => { if (e.key === "Enter") performSearch(input.value); });

  document.addEventListener("click", e => {
    const res = document.getElementById("searchResults");
    if (res && !e.target.closest(".search-wrap")) res.style.display = "none";
  });

  function tick() {
    if (isFocused || input.value) { setTimeout(tick, 500); return; }
    const target = queries[qIdx];
    if (pausing) { pausing = false; setTimeout(tick, 1800); return; }
    if (!deleting) {
      cIdx++;
      input.placeholder = target.slice(0, cIdx) + "|";
      if (cIdx === target.length) { deleting = true; pausing = true; }
      setTimeout(tick, 70);
    } else {
      cIdx--;
      input.placeholder = target.slice(0, cIdx) + (cIdx > 0 ? "|" : "");
      if (cIdx === 0) { deleting = false; qIdx = (qIdx + 1) % queries.length; }
      setTimeout(tick, 38);
    }
  }
  setTimeout(tick, 900);
}

function fillSearch(term) {
  const input = document.getElementById("searchBar");
  if (input) { input.value = term; input.focus(); performSearch(term); }
}

function performSearch(query) {
  if (!query.trim()) return;
  const resDiv  = document.getElementById("searchResults");
  const content = document.getElementById("searchContent");
  resDiv.style.display = "block";
  content.innerHTML = `<div style="display:flex;align-items:center;gap:8px;color:#94a3b8;font-size:0.82rem;">
    <div class="ocr-spinner" style="width:14px;height:14px;border-width:2px;"></div>
    Searching documents…</div>`;

  fetch("/api/search", { credentials: "same-origin", 
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify({ query }),
  })
    .then(r => r.json())
    .then(data => {
      if (data.success) {
        content.innerHTML = `<strong style="color:#93c5fd;font-size:0.8rem;">🧠 AI Answer:</strong>
          <br><br><span style="font-size:0.84rem;line-height:1.6;">${escHtml(data.answer).replace(/\n/g, "<br>")}</span>`;
      } else {
        content.innerHTML = `<span style="color:#fca5a5;font-size:0.82rem;">❌ ${escHtml(data.error)}</span>`;
      }
    })
    .catch(err => {
      content.innerHTML = `<span style="color:#fca5a5;font-size:0.82rem;">Network error: ${err.message}</span>`;
    });
}

/* ════════════════════════════════════════════════════════════
   4. LOCAL TESSERACT OCR (browser-side)
   ════════════════════════════════════════════════════════════ */
async function runLocalOCR(file) {
  const panel   = document.getElementById("localOcrStatusPanel");
  const msgEl   = document.getElementById("ocrStatusMsg");
  const progress= document.getElementById("ocrProgressBar");
  if (!panel) return null;

  panel.style.display = "flex";
  msgEl.textContent   = "Loading OCR engine…";
  progress.style.width = "5%";

  try {
    const { createWorker } = Tesseract;
    const worker = await createWorker("eng", 1, {
      logger: m => {
        if (m.status === "loading tesseract core") { msgEl.textContent = "Loading Tesseract core…"; progress.style.width = "20%"; }
        if (m.status === "loading language traineddata") { msgEl.textContent = "Loading language data…"; progress.style.width = "45%"; }
        if (m.status === "initializing api") { msgEl.textContent = "Initializing OCR…"; progress.style.width = "65%"; }
        if (m.status === "recognizing text") {
          const pct = Math.round((m.progress || 0) * 35) + 65;
          progress.style.width = `${pct}%`;
          msgEl.textContent = `Extracting text… ${Math.round(m.progress * 100)}%`;
        }
      }
    });

    const { data } = await worker.recognize(file);
    await worker.terminate();

    progress.style.width = "100%";
    msgEl.textContent    = `✓ OCR complete — ${data.words.length} words found`;
    setTimeout(() => { panel.style.display = "none"; }, 2200);

    return data.text;
  } catch (err) {
    msgEl.textContent   = `OCR failed: ${err.message}`;
    progress.style.width = "100%";
    return null;
  }
}

/* ════════════════════════════════════════════════════════════
   5. RENDER HELPERS
   ════════════════════════════════════════════════════════════ */
const TYPE_EMOJIS = {
  bill: "💸", prescription: "💊", ticket: "🎫",
  receipt: "🧾", exam: "📋", notice: "📢", other: "📄",
};

function showLoading(msg = "🤖 AI is reading your document…") {
  document.getElementById("resultPanel").innerHTML = `
    <div class="result-loading">
      <div class="spinner"></div>
      <div class="loading-text">${msg}</div>
    </div>`;
}

function renderError(msg) {
  document.getElementById("resultPanel").innerHTML = `
    <div class="error-panel">
      <strong>⚠ Extraction Failed</strong>
      <div>${escHtml(msg)}</div>
      <div style="font-size:0.74rem;color:#94a3b8;margin-top:4px">
        Check your API key in Settings, or try a clearer image.
      </div>
    </div>`;
}

function renderResult(data, ocrText) {
  window.lastExtraction = data;

  const type    = (data.document_type || "other").toLowerCase();
  const emoji   = TYPE_EMOJIS[type] || "📄";
  const fields  = data.fields  || {};
  const dates   = data.dates   || {};
  const summary = data.summary || "";
  const raw     = data.raw_text || ocrText || "";

  try {
    spawnNodeFromUpload(data.document_title || 'Document', type);
    const amt = fields.amount || fields.total || fields.total_amount || fields.total_spent;
    if (amt) logExpenseFromUpload(data.document_title || 'Document', type, amt);
  } catch(e) { console.log(e); }


  /* build fields HTML */
  let fieldsHtml = "";
  for (const [k, v] of Object.entries(fields)) {
    const label   = k.replace(/_/g, " ");
    const display = v === null || v === undefined || v === ""
      ? `<div class="field-null">⚠ Could not extract</div>`
      : `<div class="field-val">${escHtml(Array.isArray(v) ? v.join(", ") : String(v))}</div>`;
    fieldsHtml += `<div class="field-item"><div class="field-key">${escHtml(label)}</div>${display}</div>`;
  }

  /* reminder section */
  let reminderHtml = "";
  if (dates.primary_date) {
    reminderHtml = `
      <div class="reminder-set-area" id="reminderArea">
        <h4>📅 Schedule Reminder — ${escHtml(dates.primary_date_label || "Key Date")}: <strong>${escHtml(dates.primary_date)}</strong></h4>
        <div class="reminder-inputs">
          <input type="date" class="reminder-date-input" id="reminderDateInput" value="${escHtml(dates.primary_date)}">
          <input type="text" class="reminder-note-input" id="reminderNoteInput" placeholder="Optional note…">
          <button class="set-reminder-btn" id="setReminderBtn">Save Reminder</button>
        </div>
        <div id="reminderFeedback"></div>
      </div>`;
  }

  /* OCR raw text panel */
  const ocrBoxHtml = ocrText ? `
    <div class="ocr-extracted-box">
      <div class="ocr-extracted-label">📖 Local Tesseract OCR Output</div>
      <div class="ocr-extracted-text">${escHtml(ocrText.slice(0, 600))}${ocrText.length > 600 ? "…" : ""}</div>
    </div>` : "";

  document.getElementById("resultPanel").innerHTML = `
    <div class="result-content">
      <div class="result-type-badge type-${type}">${emoji} ${type}</div>
      ${summary ? `<div class="result-summary">${escHtml(summary)}</div>` : ""}
      ${ocrBoxHtml}
      <div class="fields-grid">${fieldsHtml || `<div style="color:var(--muted2);font-size:0.82rem">No structured fields extracted.</div>`}</div>
      ${reminderHtml}
      <button class="raw-text-toggle" onclick="toggleRaw()">🔍 Show full extracted text</button>
      <div class="raw-text-box" id="rawTextBox">${escHtml(raw)}</div>
    </div>`;

  const btn = document.getElementById("setReminderBtn");
  if (btn) btn.addEventListener("click", handleSetReminder);

  /* highlight matching workflow card */
  document.querySelectorAll(".workflow-card").forEach(card => {
    card.style.borderColor = "";
    card.style.boxShadow   = "";
  });
  const matchCard = document.querySelector(`[data-category="${type}"]`);
  if (matchCard) {
    matchCard.style.borderColor = "rgba(6,182,212,0.6)";
    matchCard.style.boxShadow   = "0 0 20px rgba(6,182,212,0.2)";
    matchCard.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }
}

function toggleRaw() {
  const box = document.getElementById("rawTextBox");
  if (!box) return;
  const shown = box.style.display === "block";
  box.style.display = shown ? "none" : "block";
  document.querySelector(".raw-text-toggle").textContent =
    shown ? "🔍 Show full extracted text" : "🙈 Hide extracted text";
}

/* ════════════════════════════════════════════════════════════
   6. FILE UPLOAD + OCR + AI EXTRACTION FLOW
   ════════════════════════════════════════════════════════════ */
async function handleFile(file) {
  if (!file) return;
  if (!file.type.startsWith("image/")) {
    renderError("Please upload an image file (PNG, JPG, WEBP, GIF, BMP).");
    return;
  }

  /* image preview */
  const preview  = document.getElementById("uploadedPreview");
  const img      = document.getElementById("previewImg");
  const nameEl   = document.getElementById("uploadedFileName");
  const reader   = new FileReader();
  reader.onload  = e => { img.src = e.target.result; };
  reader.readAsDataURL(file);
  preview.style.display = "block";
  nameEl.textContent = `${file.name}  ·  ${(file.size / 1024).toFixed(0)} KB`;

  /* 1 — run Tesseract.js OCR first (local, no API needed) */
  showLoading("📖 Running local Tesseract OCR…");
  const ocrText = await runLocalOCR(file);

  /* 2 — send to AI provider for structured extraction */
  showLoading("🤖 Sending to AI provider for extraction…");

  const fd = new FormData();
  fd.append("file", file);

  fetch("/api/extract", { credentials: "same-origin",  method: "POST", body: fd })
    .then(r  => r.json())
    .then(json => {
      if (json.success) renderResult(json.data, ocrText);
      else              renderError(json.error || "Unknown error from server.");
    })
    .catch(err => renderError("Network error: " + err.message));
}

function initUpload() {
  const dropzone  = document.getElementById("dropzone");
  const fileInput = document.getElementById("fileInput");
  const uploadBtn = document.getElementById("uploadBtn");
  if (!dropzone || !fileInput) return;

  dropzone.addEventListener("dragover",  e => { e.preventDefault(); dropzone.classList.add("dragover"); });
  dropzone.addEventListener("dragleave", ()  => dropzone.classList.remove("dragover"));
  dropzone.addEventListener("drop",      e  => {
    e.preventDefault();
    dropzone.classList.remove("dragover");
    handleFile(e.dataTransfer.files[0]);
  });

  dropzone.addEventListener("click", e => { if (e.target !== uploadBtn) fileInput.click(); });
  uploadBtn.addEventListener("click", e => { e.stopPropagation(); fileInput.click(); });
  fileInput.addEventListener("change", () => handleFile(fileInput.files[0]));
}

/* ════════════════════════════════════════════════════════════
   7. MOCK UPLOAD (smartphone click demo)
   ════════════════════════════════════════════════════════════ */
function triggerMockUpload() {
  /* Scroll to upload section */
  document.getElementById("upload").scrollIntoView({ behavior: "smooth" });
  setTimeout(() => document.getElementById("fileInput")?.click(), 600);
}

/* ════════════════════════════════════════════════════════════
   8. WORKFLOW ACTION POPUP
   ════════════════════════════════════════════════════════════ */
const WF_DESCRIPTIONS = {
  "Delivery Reminder":    "Creates a push/email reminder when your order is out for delivery based on the extracted delivery date.",
  "Price History":        "Tracks all Amazon/receipt prices over time and shows a sparkline of spending trends.",
  "Expense Tracker":      "Auto-categorizes this receipt into monthly expense buckets (Food, Electronics, Utilities).",
  "Wishlist":             "Adds this item to your personal MemoryLens wishlist for price-drop alerts.",
  "Medicine Reminder":    "Schedules daily medication intake reminders based on dosage and prescription start date.",
  "Health Summary":       "Summarizes your prescription history, active medicines, and doctor notes.",
  "Expiry Alert":         "Notifies you 7 days before your prescription or medicine expires.",
  "Doctor Questions":     "Generates a smart list of follow-up questions for your next doctor appointment.",
  "Simple Explanation":   "Rewrites complex legal or official notice text in plain, simple English.",
  "Highlighted Values":   "Extracts and highlights the most critical values: amounts, dates, penalties, and clauses.",
  "Timeline Comparison":  "Shows a visual side-by-side timeline of key dates in this document vs. your calendar.",
  "Departure Countdown":  "Shows a live countdown to your departure/event date with day/hour/minute ticker.",
  "Platform/Gate Reminder":"Sends a reminder with your platform, gate, or check-in details 2 hours before travel.",
  "Travel Timeline":      "Generates a visual hour-by-hour itinerary from your ticket details.",
  "Weather Info":         "Fetches a 7-day weather forecast for your destination on the travel date.",
  "Exam Countdown":       "Shows a live countdown widget to your exam date pinned to your dashboard.",
  "Assignment Due":       "Adds your assignment or coursework deadline to your MemoryLens calendar.",
  "Calendar Event":       "Creates a Google/iCal event for this exam with venue and time details.",
  "Alert Reminder":       "Sets a multi-stage reminder: 7 days before, 1 day before, and morning-of alert.",
};

function triggerWfAction(category, actionName) {
  let panel = document.getElementById("wfPopupPanel");
  if (!panel) {
    panel = document.createElement("div");
    panel.id = "wfPopupPanel";
    panel.className = "wf-popup-panel";
    document.body.appendChild(panel);
  }

  const desc = WF_DESCRIPTIONS[actionName] || "This workflow will process your extracted document data and generate the relevant output.";

  panel.innerHTML = `
    <div class="wf-popup-header">
      <div class="wf-popup-title">🔧 ${escHtml(actionName)}</div>
      <button class="wf-popup-close" onclick="document.getElementById('wfPopupPanel').classList.remove('visible')">✕</button>
    </div>
    <div class="wf-popup-body">
      ${escHtml(desc)}
      <br><br>
      <em style="color:#64748b;font-size:0.76rem;">Upload a matching document in the AI Workspace below to activate this flow automatically.</em>
    </div>
    <div class="wf-popup-badge">Category: ${escHtml(category)}</div>`;

  panel.classList.add("visible");
}

/* ════════════════════════════════════════════════════════════
   9. SET REMINDER
   ════════════════════════════════════════════════════════════ */
function handleSetReminder() {
  const dateVal = (document.getElementById("reminderDateInput")?.value || "").trim();
  const noteVal = (document.getElementById("reminderNoteInput")?.value || "").trim();
  const fb      = document.getElementById("reminderFeedback");
  if (!fb) return;

  if (!dateVal) {
    fb.className   = "reminder-feedback err";
    fb.textContent = "Please pick a date first.";
    return;
  }

  const data = window.lastExtraction || {};
  const f    = data.fields || {};
  const type = (data.document_type || "document").toLowerCase();
  const title = [
    f.vendor, f.medicine_name, f.event_name, f.subject,
    f.store_name, f.title, f.issued_by,
  ].find(v => v && String(v).trim()) || `${type} document`;

  fb.className   = "reminder-feedback";
  fb.textContent = "Saving…";

  fetch("/api/reminder", { credentials: "same-origin", 
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify({ title, date: dateVal, document_type: type, note: noteVal }),
  })
    .then(r => r.json())
    .then(json => {
      if (json.success) {
        fb.className   = "reminder-feedback ok";
        fb.textContent = "✅ Reminder saved! Scroll down to see it.";
        loadReminders();
        setTimeout(() =>
          document.getElementById("reminders")
            ?.scrollIntoView({ behavior: "smooth", block: "start" }), 1000);
      } else {
        fb.className   = "reminder-feedback err";
        fb.textContent = "❌ " + (json.error || "Failed to save reminder.");
      }
    })
    .catch(err => {
      fb.className   = "reminder-feedback err";
      fb.textContent = "Network error: " + err.message;
    });
}

/* ════════════════════════════════════════════════════════════
   10. LOAD & DISPLAY REMINDERS
   ════════════════════════════════════════════════════════════ */
function daysUntil(dateStr) {
  const now    = new Date(); now.setHours(0,0,0,0);
  const target = new Date(dateStr + "T00:00:00");
  return Math.round((target - now) / 86400000);
}

function formatDate(dateStr) {
  try {
    return new Date(dateStr + "T00:00:00").toLocaleDateString("en-GB", {
      day: "numeric", month: "short", year: "numeric",
    });
  } catch { return dateStr; }
}

function daysBadge(days) {
  if (days < 0)  return `<span class="days-badge days-past">${Math.abs(days)}d ago</span>`;
  if (days <= 3) return `<span class="days-badge days-soon">in ${days}d ⚠</span>`;
  return            `<span class="days-badge days-future">in ${days}d</span>`;
}

function loadReminders() {
  const list = document.getElementById("remindersList");
  if (!list) return;

  fetch("/api/reminders", { credentials: "same-origin" })
    .then(r => r.json())
    .then(json => {
      const items = json.reminders || [];
      if (!items.length) {
        list.innerHTML = `
          <div class="reminder-empty">
            <div>🔔</div>
            <div class="empty-rem-header">No Reminders Scheduled</div>
            <div class="empty-rem-desc">Extract a document with a date to create your first reminder.</div>
          </div>`;
        return;
      }
      list.innerHTML = items.map(r => {
        const days  = daysUntil(r.reminder_date);
        const fDate = formatDate(r.reminder_date);
        return `
          <div class="reminder-card" data-id="${escHtml(r.id)}">
            <button class="reminder-delete" onclick="deleteReminder('${escHtml(r.id)}')" title="Delete">✕</button>
            <div class="reminder-type">${escHtml(r.document_type || "document")}</div>
            <div class="reminder-title">${escHtml(r.document_title)}</div>
            <div class="reminder-date-display">${escHtml(fDate)}</div>
            <div>${daysBadge(days)}</div>
            ${r.note ? `<div class="reminder-note">${escHtml(r.note)}</div>` : ""}
          </div>`;
      }).join("");
    })
    .catch(err => console.error("Reminders load error:", err));
}

function deleteReminder(id) {
  fetch(`/api/reminder/${id}`, { credentials: "same-origin",  credentials: "same-origin",  method: "DELETE" })
    .then(r => r.json())
    .then(json => { if (json.success) loadReminders(); })
    .catch(err => console.error("Delete error:", err));
}

/* ════════════════════════════════════════════════════════════
   11. DOCK NAV / UPCOMING MODAL / SCROLL HELPERS
   ════════════════════════════════════════════════════════════ */
function scrollDockTo(id) {
  const el = document.getElementById(id);
  if (el) el.scrollIntoView({ behavior: "smooth" });

  document.querySelectorAll(".dock-item").forEach(d => d.classList.remove("active"));
  const items = document.querySelectorAll(".dock-item");
  const map   = { home: 1, upload: 0, reminders: 3 };
  const idx   = map[id];
  if (idx !== undefined && items[idx]) items[idx].classList.add("active");
}

function showUpcomingModal(featureName) {
  document.getElementById("upcomingModal").style.display = "flex";
  document.getElementById("upcomingModalTitle").textContent   = "🚀 Coming Soon";
  document.getElementById("upcomingFeatureName").textContent  = featureName;
  document.getElementById("upcomingModalDesc").textContent    =
    `The "${featureName}" module is currently in active development and will be available in the next release. ` +
    `AI Understanding, OCR Extraction, and Smart Reminders are fully live — try uploading a receipt or prescription above!`;
}

function closeUpcomingModal() {
  document.getElementById("upcomingModal").style.display = "none";
}

/* ════════════════════════════════════════════════════════════
   12. SETTINGS MODAL (BYOK)
   ════════════════════════════════════════════════════════════ */
function openSettingsModal() {
  document.getElementById("settingsModal").style.display = "flex";
}

function closeSettingsModal() {
  document.getElementById("settingsModal").style.display = "none";
}

function handleProviderChange() {
  const val = document.getElementById("providerSelect").value;
  document.getElementById("baseUrlGroup").style.display = val === "custom" ? "block" : "none";
}

function togglePassword() {
  const input = document.getElementById("apiKeyInput");
  input.type  = input.type === "password" ? "text" : "password";
}

function saveProvider() {
  const provider   = document.getElementById("providerSelect").value;
  const apiKey     = document.getElementById("apiKeyInput").value.trim();
  const baseUrl    = document.getElementById("baseUrlInput").value.trim();
  const modelName  = (document.getElementById("modelNameInput")?.value || "").trim();
  const fb         = document.getElementById("settingsFeedback");
  const btn        = document.getElementById("saveProviderBtn");

  if (!apiKey) { fb.className = "reminder-feedback err"; fb.textContent = "API Key is required."; return; }
  if (provider === "custom" && !baseUrl) {
    fb.className = "reminder-feedback err"; fb.textContent = "Base URL required for Custom."; return;
  }

  fb.className   = "reminder-feedback";
  fb.textContent = "Testing connection…";
  btn.disabled   = true;

  fetch("/api/connect", { credentials: "same-origin", 
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify({ provider, api_key: apiKey, base_url: baseUrl, model_name: modelName }),
  })
    .then(r => r.json())
    .then(json => {
      btn.disabled = false;
      if (json.success) {
        fb.className   = "reminder-feedback ok";
        fb.textContent = `✅ Connected to ${provider}`;
        setTimeout(() => location.reload(), 1000);
      } else {
        fb.className   = "reminder-feedback err";
        fb.textContent = "❌ " + (json.error || "Failed to connect.");
      }
    })
    .catch(err => {
      btn.disabled   = false;
      fb.className   = "reminder-feedback err";
      fb.textContent = "Network error: " + err.message;
    });
}

function disconnectProvider() {
  fetch("/api/disconnect", { credentials: "same-origin",  method: "POST" })
    .then(() => location.reload())
    .catch(console.error);
}

/* ════════════════════════════════════════════════════════════
   13. UTILITY
   ════════════════════════════════════════════════════════════ */
function escHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

/* Escape key closes all modals */
document.addEventListener("keydown", e => {
  if (e.key === "Escape") {
    closeSettingsModal();
    closeUpcomingModal();
    const panel = document.getElementById("wfPopupPanel");
    if (panel) panel.classList.remove("visible");
  }
});

/* ════════════════════════════════════════════════════════════
   14. INIT
   ════════════════════════════════════════════════════════════ */
document.addEventListener("DOMContentLoaded", () => {
  /* Neural sphere canvas */
  const canvas = document.getElementById("sphereCanvas");
  if (canvas) new NeuralSphere(canvas);

  /* SVG connecting lines */
  setTimeout(drawConnectingLines, 350);
  window.addEventListener("resize", debounce(drawConnectingLines, 280));

  /* Typewriter search */
  initSearchCycler();

  /* Upload flow */
  initUpload();

  /* Load persisted reminders */
  loadReminders();

  /* Smooth anchor scroll for nav links */
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener("click", e => {
      e.preventDefault();
      const target = document.querySelector(a.getAttribute("href"));
      if (target) target.scrollIntoView({ behavior: "smooth" });
    });
  });

  /* Dock: highlight active on scroll */
  const sections = [
    { id: "home",      dockIdx: 0 },
    { id: "upload",    dockIdx: 0 },
    { id: "reminders", dockIdx: 3 },
  ];
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const match = sections.find(s => s.id === entry.target.id);
        if (match) {
          const items = document.querySelectorAll(".dock-item");
          items.forEach(d => d.classList.remove("active"));
          if (items[match.dockIdx]) items[match.dockIdx].classList.add("active");
        }
      }
    });
  }, { threshold: 0.4 });

  sections.forEach(s => {
    const el = document.getElementById(s.id);
    if (el) observer.observe(el);
  });

  /* ── Animated stat counters ── */
  const animateCounters = () => {
    document.querySelectorAll(".stat-val[data-count]").forEach(el => {
      const target = parseInt(el.getAttribute("data-count"), 10);
      const isPercent = target === 100;
      const duration = 1400;
      const stepMs   = 16;
      const totalSteps = Math.round(duration / stepMs);
      let current = 0;
      const inc = target / totalSteps;
      const timer = setInterval(() => {
        current = Math.min(current + inc, target);
        el.textContent = isPercent
          ? Math.round(current) + "%"
          : Math.round(current);
        if (current >= target) {
          el.textContent = isPercent ? "100%" : String(target);
          clearInterval(timer);
        }
      }, stepMs);
    });
  };

  const statsStrip = document.querySelector(".stats-strip");
  if (statsStrip) {
    let counted = false;
    const statsObs = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting && !counted) {
        counted = true;
        animateCounters();
      }
    }, { threshold: 0.35 });
    statsObs.observe(statsStrip);
  }

  /* ── Step cards fade-in on scroll ── */
  const stepCards = document.querySelectorAll(".step-card, .bento-card, .usecase-card");
  stepCards.forEach(card => { card.style.opacity = "0"; card.style.transform = "translateY(28px)"; card.style.transition = "opacity 0.55s ease, transform 0.55s ease"; });
  const cardObs = new IntersectionObserver(entries => {
    entries.forEach((entry, i) => {
      if (entry.isIntersecting) {
        setTimeout(() => {
          entry.target.style.opacity = "1";
          entry.target.style.transform = "translateY(0)";
        }, 60);
        cardObs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12 });
  stepCards.forEach(card => cardObs.observe(card));

  /* ── Bento search demo typewriter ── */
  const bentoEl = document.getElementById("bentoSearchDemo");
  if (bentoEl) {
    const bentoQ = [
      "When does my medicine expire?",
      "How much was the electricity bill?",
      "What seat is my train ticket?",
      "When is my exam scheduled?",
      "Show bills due this month...",
    ];
    let bqIdx = 0, bcIdx = 0, bDel = false, bPause = false;
    function bentoTick() {
      const target = bentoQ[bqIdx];
      if (bPause) { bPause = false; setTimeout(bentoTick, 2200); return; }
      if (!bDel) {
        bcIdx++;
        bentoEl.textContent = target.slice(0, bcIdx);
        if (bcIdx === target.length) { bDel = true; bPause = true; }
        setTimeout(bentoTick, 78);
      } else {
        bcIdx--;
        bentoEl.textContent = target.slice(0, bcIdx);
        if (bcIdx === 0) { bDel = false; bqIdx = (bqIdx + 1) % bentoQ.length; }
        setTimeout(bentoTick, 42);
      }
    }
    setTimeout(bentoTick, 2000);
  }

  /* ── CTA banner glow parallax on mousemove ── */
  const ctaBanner = document.querySelector(".cta-banner");
  if (ctaBanner) {
    ctaBanner.addEventListener("mousemove", e => {
      const rect = ctaBanner.getBoundingClientRect();
      const x = ((e.clientX - rect.left) / rect.width - 0.5) * 30;
      const y = ((e.clientY - rect.top)  / rect.height - 0.5) * 30;
      const glow = ctaBanner.querySelector(".cta-glow");
      if (glow) glow.style.transform = `translateX(calc(-50% + ${x}px)) translateY(${y}px)`;
    });
    ctaBanner.addEventListener("mouseleave", () => {
      const glow = ctaBanner.querySelector(".cta-glow");
      if (glow) glow.style.transform = "translateX(-50%) translateY(0)";
    });
  }
});

/* --- HERO JS --- */
/* ═══════════════════════════
   NEURAL SPHERE CANVAS
═══════════════════════════ */
(function() {
  const canvas = document.getElementById('brainCanvas');
  const ctx    = canvas.getContext('2d');
  const W = 300, H = 300, R = 120;
  let rot = 0, targetCX = W/2, targetCY = H/2, cx = W/2, cy = H/2;

  const nodes = [];
  const golden = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < 110; i++) {
    const y = 1 - (i / 109) * 2;
    const r = Math.sqrt(Math.max(0, 1 - y*y));
    const theta = golden * i;
    nodes.push({
      ox: Math.cos(theta) * r,
      oy: y,
      oz: Math.sin(theta) * r,
      size: Math.random() * 1.5 + 0.5,
      pulse: Math.random() * Math.PI * 2,
      col: Math.random() > 0.5 ? [0,200,255] : Math.random() > 0.5 ? [100,60,240] : [60,130,255]
    });
  }

  document.addEventListener('mousemove', e => {
    targetCX = W/2 - (e.clientX/window.innerWidth - 0.5) * 28;
    targetCY = H/2 - (e.clientY/window.innerHeight - 0.5) * 28;
  });

  function project(x, y, z) {
    const cos = Math.cos(rot), sin = Math.sin(rot);
    const rx = x*cos - z*sin, rz = x*sin + z*cos;
    const fov = 2.6, s = fov/(fov+rz);
    return { x: cx + rx*R*s, y: cy + y*R*s, z: rz, s };
  }

  function draw() {
    const t = Date.now()/1000;
    cx += (targetCX - cx) * 0.08;
    cy += (targetCY - cy) * 0.08;
    ctx.clearRect(0,0,W,H);

    const proj = nodes.map(n => {
      const p = project(n.ox, n.oy, n.oz);
      const pulse = Math.sin(t*2.2 + n.pulse)*0.3+0.7;
      return {...p, size:n.size, pulse, col:n.col};
    }).sort((a,b) => a.z-b.z);

    // Connections
    for(let i=0;i<proj.length;i++) for(let j=i+1;j<proj.length;j++) {
      if(proj[i].z < -0.2 || proj[j].z < -0.2) continue;
      const dx=proj[i].x-proj[j].x, dy=proj[i].y-proj[j].y;
      const d=Math.sqrt(dx*dx+dy*dy);
      if(d>65) continue;
      const alpha=(1-d/65)*0.18*Math.min(proj[i].s,proj[j].s);
      ctx.beginPath();
      ctx.moveTo(proj[i].x,proj[i].y);
      ctx.lineTo(proj[j].x,proj[j].y);
      ctx.strokeStyle=`rgba(60,160,255,${alpha})`;
      ctx.lineWidth=0.5;
      ctx.stroke();
    }

    // Nodes
    for(const p of proj) {
      if(p.z < -0.2) continue;
      const alpha=((p.z+1)/2)*p.pulse*0.9;
      const sz=p.size*p.s*1.6;
      const [r,g,b]=p.col;
      ctx.shadowBlur=7;
      ctx.shadowColor=`rgba(${r},${g},${b},${alpha})`;
      ctx.beginPath();
      ctx.arc(p.x,p.y,sz,0,Math.PI*2);
      ctx.fillStyle=`rgba(${r},${g},${b},${alpha})`;
      ctx.fill();
    }
    ctx.shadowBlur=0;
    rot += 0.0025;
    requestAnimationFrame(draw);
  }
  draw();
})();

/* ═══════════════════════════
   TYPEWRITER SEARCH
═══════════════════════════ */
(function() {
  const inp = document.getElementById('searchInput');
  const queries = [
    '"medicine" or "exam"|',
    'Find my electricity bill due date...',
    'When does my prescription expire?',
    'What is my train seat number?',
    'Show all bills due this month...',
    'Exam date and venue details...',
  ];
  let qi=0, ci=0, del=false, pause=false, focused=false;
  inp.addEventListener('focus', ()=>{ focused=true; inp.placeholder='Search your documents...'; });
  inp.addEventListener('blur',  ()=>{ focused=false; });
  inp.addEventListener('keypress', e=>{ if(e.key==='Enter') doSearch(); });

  function tick() {
    if(focused||inp.value){ setTimeout(tick,400); return; }
    const t=queries[qi];
    if(pause){ pause=false; setTimeout(tick,2000); return; }
    if(!del){ ci++; inp.placeholder=t.slice(0,ci)+(ci<t.length?'|':''); if(ci>=t.length){del=true;pause=true;} setTimeout(tick,75); }
    else { ci--; inp.placeholder=ci>0?t.slice(0,ci)+'|':''; if(ci<=0){del=false;qi=(qi+1)%queries.length;} setTimeout(tick,38); }
  }
  setTimeout(tick, 1200);
})();

/* ═══════════════════════════
   SEARCH
═══════════════════════════ */
function doSearch() {
  const q = document.getElementById('searchInput').value.trim();
  if(!q) return;
  const pop = document.getElementById('searchPop');
  const con = document.getElementById('searchPopContent');
  pop.style.display = 'block';
  con.innerHTML = '<div style="color:#94A3B8;font-size:0.82rem;display:flex;gap:8px;align-items:center;"><div style="width:14px;height:14px;border:2px solid rgba(0,200,255,0.3);border-top-color:#00C8FF;border-radius:50%;animation:spin 0.7s linear infinite;"></div>Searching…</div>';
  fetch('/api/search', { credentials: "same-origin", method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query:q})})
    .then(r=>r.json())
    .then(d=>{
      if(d.success) con.innerHTML=`<strong style="color:#93C5FD;font-size:0.78rem;">🧠 AI:</strong><br><br><span style="font-size:0.82rem;line-height:1.6;">${d.answer.replace(/\n/g,'<br>')}</span>`;
      else con.innerHTML=`<span style="color:#FCA5A5;font-size:0.8rem;">❌ ${d.error}</span>`;
    })
    .catch(e=>{con.innerHTML=`<span style="color:#FCA5A5;font-size:0.8rem;">Connect an AI key first → <a href="/" style="color:#60A5FA;">Go to App ⚙️</a></span>`;});
}
document.addEventListener('click', e=>{ if(!e.target.closest('.search-outer')) document.getElementById('searchPop').style.display='none'; });

/* ═══════════════════════════
   WORKFLOW ACTION POPUP
═══════════════════════════ */
function showActionPop(title, desc) {
  document.getElementById('actionPopTitle').textContent = '🔧 ' + title;
  document.getElementById('actionPopDesc').textContent  = desc;
  document.getElementById('actionPop').style.display    = 'block';
}

/* ═══════════════════════════
   DOCK NAVIGATION
═══════════════════════════ */
function dockNav(id) {
  document.querySelectorAll('.dock-item').forEach(d=>d.classList.remove('active'));
  
  // Highlight clicked
  if (event && event.currentTarget) {
    event.currentTarget.classList.add('active');
  } else {
    const selector = `#dock-${id}`;
    const el = document.querySelector(selector);
    if (el) el.classList.add('active');
  }

  // Smooth scroll support
  const target = document.getElementById(id);
  if (target) {
    target.scrollIntoView({ behavior: 'smooth' });
  } else {
    // Fallback search scroll
    if (id === 'search') {
      document.getElementById('home').scrollIntoView({ behavior: 'smooth' });
    } else {
      window.location.href = '/#' + id;
    }
  }
}


/* ══════════════════════════════════════
   INTERACTIVE MEMORY GRAPH JS
   ══════════════════════════════════════ */
let graphNodes = [];
let graphLinks = [];
let draggedNode = null;
let graphAnimationId = null;

function initMemoryGraph() {
  const canvas = document.getElementById('memoryGraphCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  
  // Set explicit dimensions
  canvas.width = canvas.parentElement.clientWidth || 900;
  canvas.height = 450;
  
  const width = canvas.width;
  const height = canvas.height;
  
  // Base category nodes
  graphNodes = [
    { id: 'center', label: 'MemoryLens AI', x: width/2, y: height/2, size: 24, color: '#38bdf8', fx: width/2, fy: height/2, type: 'core' },
    { id: 'bill', label: 'Bills & Utilities', x: width/2 - 150, y: height/2 - 100, size: 16, color: '#06b6d4', type: 'category', emoji: '💸' },
    { id: 'prescription', label: 'Medical Rx', x: width/2 + 150, y: height/2 - 100, size: 16, color: '#a855f7', type: 'category', emoji: '💊' },
    { id: 'ticket', label: 'Travel & Tickets', x: width/2 - 150, y: height/2 + 100, size: 16, color: '#22c55e', type: 'category', emoji: '🎫' },
    { id: 'study', label: 'Study & Exams', x: width/2 + 150, y: height/2 + 100, size: 16, color: '#ef4444', type: 'category', emoji: '📋' },
  ];
  
  graphLinks = [
    { source: 'center', target: 'bill' },
    { source: 'center', target: 'prescription' },
    { source: 'center', target: 'ticket' },
    { source: 'center', target: 'study' },
  ];
  
  // Add some initial mock documents
  const mockDocs = [
    { id: 'doc1', label: 'BESCOM Electricity Bill', parent: 'bill', color: '#06b6d4', emoji: '⚡' },
    { id: 'doc2', label: 'Health Prescription', parent: 'prescription', color: '#a855f7', emoji: '💊' },
    { id: 'doc3', label: 'Delhi Metro recharge', parent: 'ticket', color: '#22c55e', emoji: '🚇' },
    { id: 'doc4', label: 'Maths Exam Schedule', parent: 'study', color: '#ef4444', emoji: '📝' },
  ];
  
  mockDocs.forEach(d => {
    const parentNode = graphNodes.find(n => n.id === d.parent);
    const angle = Math.random() * Math.PI * 2;
    const dist = 60 + Math.random() * 40;
    graphNodes.push({
      id: d.id,
      label: d.label,
      x: parentNode.x + Math.cos(angle) * dist,
      y: parentNode.y + Math.sin(angle) * dist,
      size: 10,
      color: d.color,
      type: 'document',
      emoji: d.emoji
    });
    graphLinks.push({ source: d.parent, target: d.id });
  });
  
  updateGraphStatus();
  
  // Event listeners for dragging
  canvas.addEventListener('mousedown', onMouseDown);
  canvas.addEventListener('mousemove', onMouseMove);
  canvas.addEventListener('mouseup', onMouseUp);
  canvas.addEventListener('touchstart', onTouchStart, { passive: true });
  canvas.addEventListener('touchmove', onTouchMove, { passive: true });
  canvas.addEventListener('touchend', onTouchEnd);
  
  // Start simulation loop
  if (graphAnimationId) cancelAnimationFrame(graphAnimationId);
  simulateGraph();
}

function updateGraphStatus() {
  const el = document.getElementById('graphStatus');
  if (el) {
    el.textContent = `Nodes Active: ${graphNodes.length} | Links: ${graphLinks.length}`;
  }
}

function addMockGraphNode() {
  const titles = ['Amazon Invoice', 'Flight Ticket', 'Rent Receipt', 'Physics Notes', 'Broadband Bill'];
  const cats = ['bill', 'ticket', 'bill', 'study', 'bill'];
  const emojis = ['📦', '✈️', '🏠', '📐', '🌐'];
  const idx = Math.floor(Math.random() * titles.length);
  
  const parentId = cats[idx];
  const parentNode = graphNodes.find(n => n.id === parentId);
  if (!parentNode) return;
  
  const angle = Math.random() * Math.PI * 2;
  const dist = 60 + Math.random() * 40;
  const nodeId = 'doc_' + Date.now();
  
  graphNodes.push({
    id: nodeId,
    label: titles[idx],
    x: parentNode.x + Math.cos(angle) * dist,
    y: parentNode.y + Math.sin(angle) * dist,
    size: 10,
    color: parentNode.color,
    type: 'document',
    emoji: emojis[idx]
  });
  
  graphLinks.push({ source: parentId, target: nodeId });
  updateGraphStatus();
}

// Hook to trigger when AI processes a real file
function spawnNodeFromUpload(fileName, docType) {
  const catsMap = {
    'bill': 'bill', 'receipt': 'bill',
    'prescription': 'prescription', 'medical': 'prescription',
    'ticket': 'ticket', 'travel': 'ticket',
    'exam': 'study', 'study': 'study'
  };
  
  const parentId = catsMap[docType] || 'bill';
  const parentNode = graphNodes.find(n => n.id === parentId) || graphNodes.find(n => n.id === 'center');
  
  const angle = Math.random() * Math.PI * 2;
  const dist = 80;
  const emojis = { bill: '💸', prescription: '💊', ticket: '🎫', study: '📋', other: '📄' };
  
  graphNodes.push({
    id: 'upload_' + Date.now(),
    label: fileName.slice(0, 18),
    x: parentNode.x + Math.cos(angle) * dist,
    y: parentNode.y + Math.sin(angle) * dist,
    size: 11,
    color: parentNode.color || '#38bdf8',
    type: 'document',
    emoji: emojis[parentId] || '📄'
  });
  
  graphLinks.push({ source: parentId, target: graphNodes[graphNodes.length-1].id });
  updateGraphStatus();
}

function simulateGraph() {
  const canvas = document.getElementById('memoryGraphCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  
  const width = canvas.width;
  const height = canvas.height;
  
  // Forces parameters
  const kRepulsion = 400; 
  const kAttraction = 0.05;
  const damping = 0.85;
  
  // Repulsion between all node pairs
  for (let i = 0; i < graphNodes.length; i++) {
    let n1 = graphNodes[i];
    if (n1.fx !== undefined) continue;
    
    let ax = 0, ay = 0;
    
    for (let j = 0; j < graphNodes.length; j++) {
      if (i === j) continue;
      let n2 = graphNodes[j];
      
      let dx = n1.x - n2.x;
      let dy = n1.y - n2.y;
      let distSq = dx*dx + dy*dy + 0.1;
      let dist = Math.sqrt(distSq);
      
      if (dist < 200) {
        let force = kRepulsion / distSq;
        ax += (dx / dist) * force;
        ay += (dy / dist) * force;
      }
    }
    
    n1.vx = (n1.vx || 0) + ax;
    n1.vy = (n1.vy || 0) + ay;
  }
  
  // Attraction between linked nodes
  graphLinks.forEach(link => {
    let n1 = graphNodes.find(n => n.id === link.source);
    let n2 = graphNodes.find(n => n.id === link.target);
    if (!n1 || !n2) return;
    
    let dx = n2.x - n1.x;
    let dy = n2.y - n1.y;
    let dist = Math.sqrt(dx*dx + dy*dy);
    let force = dist * kAttraction;
    
    let fx = (dx / dist) * force;
    let fy = (dy / dist) * force;
    
    if (n1.fx === undefined) { n1.vx = (n1.vx || 0) + fx; n1.vy = (n1.vy || 0) + fy; }
    if (n2.fx === undefined) { n2.vx = (n2.vx || 0) - fx; n2.vy = (n2.vy || 0) - fy; }
  });
  
  // Gravity towards center
  graphNodes.forEach(node => {
    if (node.fx !== undefined) return;
    let dx = width/2 - node.x;
    let dy = height/2 - node.y;
    node.vx = (node.vx || 0) + dx * 0.005;
    node.vy = (node.vy || 0) + dy * 0.005;
    
    // Apply velocity & damping
    node.x += node.vx;
    node.y += node.vy;
    node.vx *= damping;
    node.vy *= damping;
    
    // Bounds check
    node.x = Math.max(20, Math.min(width - 20, node.x));
    node.y = Math.max(20, Math.min(height - 20, node.y));
  });
  
  // Draw graph
  ctx.clearRect(0, 0, width, height);
  
  // Render Links
  ctx.strokeStyle = 'rgba(59, 130, 246, 0.15)';
  ctx.lineWidth = 1.5;
  graphLinks.forEach(link => {
    let n1 = graphNodes.find(n => n.id === link.source);
    let n2 = graphNodes.find(n => n.id === link.target);
    if (!n1 || !n2) return;
    
    ctx.beginPath();
    ctx.moveTo(n1.x, n1.y);
    ctx.lineTo(n2.x, n2.y);
    ctx.stroke();
  });
  
  // Render Nodes
  graphNodes.forEach(node => {
    ctx.beginPath();
    ctx.arc(node.x, node.y, node.size, 0, Math.PI*2);
    ctx.fillStyle = node.color;
    ctx.fill();
    
    // Outer glow for category / core
    if (node.type !== 'document') {
      ctx.strokeStyle = 'rgba(255,255,255,0.2)';
      ctx.lineWidth = 2;
      ctx.stroke();
    }
    
    // Draw emoji text inside
    if (node.emoji) {
      ctx.font = `${node.size * 1.1}px Arial`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(node.emoji, node.x, node.y);
    } else if (node.type === 'core') {
      ctx.font = '10px sans-serif';
      ctx.fillStyle = '#fff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('AI', node.x, node.y);
    }
    
    // Label text
    ctx.font = '10px sans-serif';
    ctx.fillStyle = '#94a3b8';
    ctx.textAlign = 'center';
    ctx.fillText(node.label, node.x, node.y + node.size + 14);
  });
  
  graphAnimationId = requestAnimationFrame(simulateGraph);
}

// Drag helper events
function getMousePos(canvas, evt) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: (evt.clientX - rect.left) * (canvas.width / rect.width),
    y: (evt.clientY - rect.top) * (canvas.height / rect.height)
  };
}

function onMouseDown(e) {
  const pos = getMousePos(e.currentTarget, e);
  draggedNode = graphNodes.find(node => {
    let dx = node.x - pos.x;
    let dy = node.y - pos.y;
    return (dx*dx + dy*dy) < (node.size * node.size * 1.5);
  });
  
  if (draggedNode && draggedNode.type !== 'core') {
    draggedNode.fx = pos.x;
    draggedNode.fy = pos.y;
  }
}

function onMouseMove(e) {
  if (!draggedNode || draggedNode.type === 'core') return;
  const pos = getMousePos(e.currentTarget, e);
  draggedNode.fx = pos.x;
  draggedNode.fy = pos.y;
  draggedNode.x = pos.x;
  draggedNode.y = pos.y;
}

function onMouseUp() {
  if (draggedNode) {
    draggedNode.fx = undefined;
    draggedNode.fy = undefined;
    draggedNode = null;
  }
}

function onTouchStart(e) {
  if (e.touches.length === 1) onMouseDown(e.touches[0]);
}

function onTouchMove(e) {
  if (e.touches.length === 1) onMouseMove(e.touches[0]);
}

function onTouchEnd() {
  onMouseUp();
}

/* Initialize when content loads */
window.addEventListener('DOMContentLoaded', () => {
  setTimeout(initMemoryGraph, 800);
});

/* ══════════════════════════════════════
   EXPENSE TRACKER LOGIC
   ══════════════════════════════════════ */
let loggedExpenses = [
  { id: 1, name: 'BESCOM Electricity Bill', cat: 'bill', date: '2026-07-12', amount: 1847.00 },
  { id: 2, name: 'Amazon Pharmacy - Medicines', cat: 'prescription', date: '2026-07-10', amount: 1120.00 },
  { id: 3, name: 'Delhi Metro Recharge', cat: 'ticket', date: '2026-07-08', amount: 353.00 }
];

function recalculateBudget() {
  const total = loggedExpenses.reduce((sum, item) => sum + item.amount, 0);
  const highest = loggedExpenses.length > 0 ? Math.max(...loggedExpenses.map(i => i.amount)) : 0;
  
  document.getElementById('totalExpenseVal').textContent = `₹ ${total.toFixed(2)}`;
  document.getElementById('highestExpenseVal').textContent = `₹ ${highest.toFixed(2)}`;
  
  // Redraw bar chart values
  const totalsByCat = { bill: 0, prescription: 0, ticket: 0, study: 0, other: 0 };
  loggedExpenses.forEach(i => {
    totalsByCat[i.cat] = (totalsByCat[i.cat] || 0) + i.amount;
  });
  
  const categories = [
    { key: 'bill', label: 'Bills', color: '#38bdf8' },
    { key: 'prescription', label: 'Medical', color: '#c084fc' },
    { key: 'ticket', label: 'Travel', color: '#34d399' },
  ];
  
  let chartHtml = '';
  categories.forEach(c => {
    const amt = totalsByCat[c.key] || 0;
    const maxVal = Math.max(1000, total);
    const pct = Math.max(5, (amt / maxVal) * 100);
    
    chartHtml += `
      <div class="chart-bar-group">
        <span class="bar-lbl">${c.label}</span>
        <div class="bar-outer"><div class="bar-fill" style="width: ${pct}%; background:${c.color};"></div></div>
        <span class="bar-val">₹ ${amt.toFixed(0)}</span>
      </div>`;
  });
  
  document.getElementById('expenseChart').innerHTML = chartHtml;
}

function addManualExpense(event) {
  event.preventDefault();
  const desc = document.getElementById('expDesc').value.trim();
  const amt = parseFloat(document.getElementById('expAmt').value);
  const cat = document.getElementById('expCat').value;
  
  if (!desc || isNaN(amt)) return;
  
  const newItem = {
    id: Date.now(),
    name: desc,
    cat: cat,
    date: new Date().toISOString().split('T')[0],
    amount: amt
  };
  
  loggedExpenses.push(newItem);
  renderExpenseTable();
  recalculateBudget();
  
  // Reset form
  document.getElementById('expDesc').value = '';
  document.getElementById('expAmt').value = '';
}

function deleteExpenseRow(btn, amt) {
  const row = btn.closest('tr');
  row.style.opacity = '0';
  setTimeout(() => {
    row.remove();
    loggedExpenses = loggedExpenses.filter(i => i.amount !== amt); // simplistic deletion match
    recalculateBudget();
  }, 300);
}

function renderExpenseTable() {
  const tbody = document.getElementById('expenseTableBody');
  if (!tbody) return;
  
  tbody.innerHTML = '';
  loggedExpenses.slice().reverse().forEach(item => {
    const catLabels = { bill: 'Bills', prescription: 'Medical', ticket: 'Travel', study: 'Study', other: 'Other' };
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${escapeHtmlStr(item.name)}</td>
      <td><span class="exp-tag tag-${item.cat}">${catLabels[item.cat] || 'Other'}</span></td>
      <td>${item.date}</td>
      <td>₹ ${item.amount.toFixed(2)}</td>
      <td><button class="exp-del-btn" onclick="deleteExpenseRow(this, ${item.amount})">✕</button></td>
    `;
    tbody.appendChild(row);
  });
}

function escapeHtmlStr(str) {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Automatically log expense when receipt upload gets parsed with an amount
function logExpenseFromUpload(fileName, docType, amount) {
  if (!amount || isNaN(amount)) return;
  
  const newItem = {
    id: Date.now(),
    name: fileName,
    cat: docType,
    date: new Date().toISOString().split('T')[0],
    amount: parseFloat(amount)
  };
  
  loggedExpenses.push(newItem);
  renderExpenseTable();
  recalculateBudget();
}
