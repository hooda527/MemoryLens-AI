/* ============================================================
   MemoryLens AI — main.js
   Neural sphere canvas · Cycling search · Upload & extraction
   Reminder persistence · SVG connecting lines
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
    this.R      = 170;
    this.rotation = 0;
    this.nodes  = [];
    this.generateNodes(90);

    window.addEventListener("mousemove", (e) => {
      const w = window.innerWidth, h = window.innerHeight;
      const dx = (e.clientX - w/2) / (w/2);
      const dy = (e.clientY - h/2) / (h/2);
      this.targetCx = (this.W / 2) - dx * 30;
      this.targetCy = (this.H / 2) - dy * 30;
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
        size:        Math.random() * 1.8 + 0.8,
        brightness:  Math.random() * 0.5 + 0.5,
        pulseOffset: Math.random() * Math.PI * 2,
        color:       Math.random() > 0.7 ? "cyan" : Math.random() > 0.5 ? "purple" : "indigo",
      });
    }
  }

  project(x, y, z) {
    const cos = Math.cos(this.rotation);
    const sin = Math.sin(this.rotation);
    const rx  = x * cos - z * sin;
    const rz  = x * sin + z * cos;
    const fov = 2.6;
    const s   = fov / (fov + rz);
    return { x: this.cx + rx * this.R * s, y: this.cy + y * this.R * s, z: rz, scale: s };
  }

  nodeColor(node) {
    const c = node.color;
    if (c === "cyan")   return [6, 182, 212];
    if (c === "purple") return [168, 85, 247];
    return [99, 102, 241];
  }

  draw() {
    const ctx = this.ctx;
    const t   = Date.now() / 1000;

    // smoothly interpolate center
    this.cx += (this.targetCx - this.cx) * 0.1;
    this.cy += (this.targetCy - this.cy) * 0.1;

    ctx.clearRect(0, 0, this.W, this.H);

    /* — Sphere ambient glow — */
    const g1 = ctx.createRadialGradient(this.cx, this.cy, 0, this.cx, this.cy, this.R * 1.35);
    g1.addColorStop(0,   "rgba(99,102,241,0.18)");
    g1.addColorStop(0.4, "rgba(168,85,247,0.10)");
    g1.addColorStop(0.7, "rgba(6,182,212,0.04)");
    g1.addColorStop(1,   "rgba(0,0,0,0)");
    ctx.fillStyle = g1;
    ctx.fillRect(0, 0, this.W, this.H);

    /* — Core sphere glow — */
    const g2 = ctx.createRadialGradient(this.cx - 40, this.cy - 40, 0, this.cx, this.cy, this.R);
    g2.addColorStop(0,   "rgba(167,139,250,0.12)");
    g2.addColorStop(0.5, "rgba(99,102,241,0.06)");
    g2.addColorStop(1,   "rgba(0,0,0,0)");
    ctx.beginPath();
    ctx.arc(this.cx, this.cy, this.R, 0, Math.PI * 2);
    ctx.fillStyle = g2;
    ctx.fill();

    /* — Project & sort nodes — */
    const projected = this.nodes.map((n, i) => {
      const p     = this.project(n.ox, n.oy, n.oz);
      const pulse = Math.sin(t * 2.2 + n.pulseOffset) * 0.3 + 0.7;
      return { ...p, size: n.size, brightness: n.brightness, pulse, rgb: this.nodeColor(n) };
    });
    projected.sort((a, b) => a.z - b.z);

    /* — Connections — */
    for (let i = 0; i < projected.length; i++) {
      for (let j = i + 1; j < projected.length; j++) {
        const a = projected[i], b = projected[j];
        if (a.z < -0.25 || b.z < -0.25) continue;
        const dx = a.x - b.x, dy = a.y - b.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > 72) continue;
        const alpha = (1 - dist / 72) * 0.22 * Math.min(a.scale, b.scale);
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.strokeStyle = `rgba(129,140,248,${alpha})`;
        ctx.lineWidth   = 0.6;
        ctx.stroke();
      }
    }

    /* — Nodes — */
    for (const p of projected) {
      if (p.z < -0.3) continue;
      const alpha = ((p.z + 1) / 2) * p.brightness * p.pulse;
      const size  = p.size * p.scale * 1.6;
      const [r, g, b] = p.rgb;
      ctx.shadowBlur  = 10;
      ctx.shadowColor = `rgba(${r},${g},${b},${alpha * 0.8})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, size, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${r},${g},${b},${alpha})`;
      ctx.fill();
    }
    ctx.shadowBlur = 0;

    /* — Rotating equator ring — */
    ctx.beginPath();
    ctx.ellipse(
      this.cx, this.cy,
      this.R * 0.98, this.R * 0.18,
      this.rotation, 0, Math.PI * 2
    );
    ctx.strokeStyle = "rgba(99,102,241,0.15)";
    ctx.lineWidth   = 1;
    ctx.stroke();

    this.rotation += 0.0022;
  }

  animate() {
    this.draw();
    requestAnimationFrame(() => this.animate());
  }
}

/* ════════════════════════════════════════════════════════════
   2. SVG CONNECTING LINES (cards → sphere center)
════════════════════════════════════════════════════════════ */
function drawConnectingLines() {
  const svg       = document.getElementById("svgLines");
  const section   = document.getElementById("sphereSection");
  const canvas    = document.getElementById("sphereCanvas");
  if (!svg || !section || !canvas) return;

  /* Clear previous lines */
  while (svg.children.length > 2) svg.removeChild(svg.lastChild); // keep <defs>

  const secRect = section.getBoundingClientRect();
  const canRect = canvas.getBoundingClientRect();

  /* Sphere center relative to the section */
  const cx = canRect.left - secRect.left + canRect.width  / 2;
  const cy = canRect.top  - secRect.top  + canRect.height / 2;

  const cards = section.querySelectorAll(".doc-card");
  const GRADS = ["lineGrad1", "lineGrad2", "lineGrad1", "lineGrad2", "lineGrad1"];

  cards.forEach((card, idx) => {
    const cr   = card.getBoundingClientRect();
    const cardX = cr.left - secRect.left + cr.width  / 2;
    const cardY = cr.top  - secRect.top  + cr.height / 2;

    /* Quadratic bezier with a slight curve */
    const mpx = (cardX + cx) / 2 + (Math.random() - 0.5) * 60;
    const mpy = (cardY + cy) / 2 + (Math.random() - 0.5) * 60;

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", `M${cardX},${cardY} Q${mpx},${mpy} ${cx},${cy}`);
    path.setAttribute("stroke", `url(#${GRADS[idx % GRADS.length]})`);
    path.setAttribute("stroke-width", "1.4");
    path.setAttribute("fill", "none");
    path.setAttribute("stroke-dasharray", "7 5");
    path.setAttribute("opacity", "0.65");

    /* Animate the dash flow */
    const anim = document.createElementNS("http://www.w3.org/2000/svg", "animate");
    anim.setAttribute("attributeName", "stroke-dashoffset");
    anim.setAttribute("from", "0");
    anim.setAttribute("to", "-24");
    anim.setAttribute("dur", `${1.4 + idx * 0.3}s`);
    anim.setAttribute("repeatCount", "indefinite");
    path.appendChild(anim);

    svg.appendChild(path);
  });
}

/* ════════════════════════════════════════════════════════════
   3. CYCLING SEARCH BAR (typewriter effect)
════════════════════════════════════════════════════════════ */
function initSearchCycler() {
  const input = document.getElementById("searchBar");
  if (!input) return;

  const queries = [
    "Find my electricity bill...",
    "When does my prescription expire?",
    "Upcoming concert ticket details...",
    "Chemistry exam date and venue...",
    "Grocery receipt from last week...",
    "Insurance policy expiry date...",
    "Flight booking confirmation...",
    "Rent due date this month...",
  ];

  let qIdx  = 0;
  let cIdx  = 0;
  let deleting = false;
  let pausing  = false;
  let isFocused = false;

  input.addEventListener("focus", () => {
    isFocused = true;
    input.placeholder = "Ask something...";
  });
  input.addEventListener("blur", () => {
    isFocused = false;
    if (!input.value) cIdx = 0;
  });

  input.addEventListener("keypress", (e) => {
    if (e.key === "Enter") {
      performSearch(input.value);
    }
  });

  // click outside to close results
  document.addEventListener("click", (e) => {
    const resDiv = document.getElementById("searchResults");
    if (resDiv && !e.target.closest(".search-wrap")) {
      resDiv.style.display = "none";
    }
  });

  function tick() {
    if (isFocused || input.value) {
      setTimeout(tick, 500);
      return;
    }

    const target = queries[qIdx];
    if (pausing) { pausing = false; setTimeout(tick, 1600); return; }

    if (!deleting) {
      cIdx++;
      input.placeholder = target.slice(0, cIdx) + "|";
      if (cIdx === target.length) { deleting = true; pausing = true; }
      setTimeout(tick, 65);
    } else {
      cIdx--;
      input.placeholder = target.slice(0, cIdx) + (cIdx > 0 ? "|" : "");
      if (cIdx === 0) {
        deleting = false;
        qIdx = (qIdx + 1) % queries.length;
      }
      setTimeout(tick, 35);
    }
  }

  setTimeout(tick, 800);
}

function performSearch(query) {
  if (!query.trim()) return;
  const resDiv = document.getElementById("searchResults");
  const content = document.getElementById("searchContent");
  resDiv.style.display = "block";
  content.innerHTML = '<div class="spinner" style="display:inline-block; width:16px; height:16px; margin-right:8px; border-width:2px; vertical-align: middle;"></div> <span style="vertical-align: middle;">Searching...</span>';

  fetch("/api/search", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query: query })
  })
  .then(r => r.json())
  .then(data => {
    if (data.success) {
      content.innerHTML = "<strong style='color:#a5b4fc'>🧠 AI Response:</strong><br><br>" + escHtml(data.answer).replace(/\n/g, "<br>");
    } else {
      content.innerHTML = "<span style='color:#ef4444'>❌ " + escHtml(data.error) + "</span>";
    }
  })
  .catch(err => {
    content.innerHTML = "<span style='color:#ef4444'>Network error: " + err.message + "</span>";
  });
}

/* ════════════════════════════════════════════════════════════
   4. FILE UPLOAD & AI EXTRACTION
════════════════════════════════════════════════════════════ */
const TYPE_EMOJIS = {
  bill: "💸", prescription: "💊", ticket: "🎫",
  receipt: "🧾", exam: "📋", notice: "📢", other: "📄",
};

function showLoading() {
  document.getElementById("resultPanel").innerHTML = `
    <div class="result-loading">
      <div class="spinner"></div>
      <div class="loading-text">🤖 Gemini is reading your document…</div>
    </div>`;
}

function renderError(msg) {
  document.getElementById("resultPanel").innerHTML = `
    <div class="error-panel">
      <strong>⚠ Extraction Failed</strong>
      <div>${escHtml(msg)}</div>
      <div style="font-size:0.78rem;color:#94a3b8;margin-top:4px">
        Check your API key in .env, or try a clearer image.
      </div>
    </div>`;
}

function renderResult(data) {
  window.lastExtraction = data;

  const type    = (data.document_type || "other").toLowerCase();
  const emoji   = TYPE_EMOJIS[type] || "📄";
  const fields  = data.fields || {};
  const dates   = data.dates  || {};
  const summary = data.summary || "";
  const raw     = data.raw_text || "";

  /* Build fields HTML */
  let fieldsHtml = "";
  for (const [k, v] of Object.entries(fields)) {
    const label = k.replace(/_/g, " ");
    if (v === null || v === undefined || v === "") {
      fieldsHtml += `
        <div class="field-item">
          <div class="field-key">${escHtml(label)}</div>
          <div class="field-null">⚠ Could not extract</div>
        </div>`;
    } else {
      const display = Array.isArray(v) ? v.join(", ") : String(v);
      fieldsHtml += `
        <div class="field-item">
          <div class="field-key">${escHtml(label)}</div>
          <div class="field-val">${escHtml(display)}</div>
        </div>`;
    }
  }

  /* Reminder section — only if a primary date was extracted */
  let reminderHtml = "";
  if (dates.primary_date) {
    const lbl = dates.primary_date_label || "Key Date";
    reminderHtml = `
      <div class="reminder-set-area" id="reminderArea">
        <h4>📅 Set Reminder — ${escHtml(lbl)}: <strong>${escHtml(dates.primary_date)}</strong></h4>
        <div class="reminder-inputs">
          <input type="date" class="reminder-date-input" id="reminderDateInput"
                 value="${escHtml(dates.primary_date)}">
          <input type="text" class="reminder-note-input" id="reminderNoteInput"
                 placeholder="Optional note…">
          <button class="set-reminder-btn" id="setReminderBtn">Save Reminder</button>
        </div>
        <div id="reminderFeedback"></div>
      </div>`;
  }

  document.getElementById("resultPanel").innerHTML = `
    <div class="result-content">
      <div class="result-type-badge type-${type}">${emoji} ${type}</div>
      ${summary ? `<div class="result-summary">${escHtml(summary)}</div>` : ""}
      <div class="fields-grid">${fieldsHtml || '<div style="color:var(--muted);font-size:0.85rem">No fields extracted.</div>'}</div>
      ${reminderHtml}
      <button class="raw-text-toggle" onclick="toggleRaw()">🔍 Show raw text</button>
      <div class="raw-text-box" id="rawTextBox">${escHtml(raw)}</div>
    </div>`;

  /* Attach reminder handler */
  const btn = document.getElementById("setReminderBtn");
  if (btn) btn.addEventListener("click", handleSetReminder);
}

function toggleRaw() {
  const box = document.getElementById("rawTextBox");
  if (!box) return;
  const shown = box.style.display === "block";
  box.style.display = shown ? "none" : "block";
  document.querySelector(".raw-text-toggle").textContent =
    shown ? "🔍 Show raw text" : "🙈 Hide raw text";
}

function handleFile(file) {
  if (!file) return;
  if (!file.type.startsWith("image/")) {
    renderError("Please upload an image file (PNG, JPG, WEBP, GIF, BMP).");
    return;
  }

  /* Preview */
  const preview  = document.getElementById("uploadedPreview");
  const img      = document.getElementById("previewImg");
  const nameEl   = document.getElementById("uploadedFileName");
  const reader   = new FileReader();
  reader.onload  = e => { img.src = e.target.result; };
  reader.readAsDataURL(file);
  preview.style.display = "block";
  nameEl.textContent = `${file.name} · ${(file.size / 1024).toFixed(0)} KB`;

  showLoading();

  const fd = new FormData();
  fd.append("file", file);

  fetch("/api/extract", { method: "POST", body: fd })
    .then(r => r.json())
    .then(json => {
      if (json.success) renderResult(json.data);
      else              renderError(json.error || "Unknown error from server.");
    })
    .catch(err => renderError("Network error: " + err.message));
}

function initUpload() {
  const dropzone  = document.getElementById("dropzone");
  const fileInput = document.getElementById("fileInput");
  const uploadBtn = document.getElementById("uploadBtn");
  if (!dropzone || !fileInput) return;

  /* Drag & drop */
  dropzone.addEventListener("dragover",  e => { e.preventDefault(); dropzone.classList.add("dragover"); });
  dropzone.addEventListener("dragleave", ()  => dropzone.classList.remove("dragover"));
  dropzone.addEventListener("drop",      e  => {
    e.preventDefault();
    dropzone.classList.remove("dragover");
    handleFile(e.dataTransfer.files[0]);
  });

  /* Click to open */
  dropzone.addEventListener("click", e => {
    if (e.target !== uploadBtn) fileInput.click();
  });
  uploadBtn.addEventListener("click", e => { e.stopPropagation(); fileInput.click(); });
  fileInput.addEventListener("change", () => handleFile(fileInput.files[0]));
}

/* ════════════════════════════════════════════════════════════
   5. SET REMINDER
════════════════════════════════════════════════════════════ */
function handleSetReminder() {
  const dateVal = (document.getElementById("reminderDateInput")?.value || "").trim();
  const noteVal = (document.getElementById("reminderNoteInput")?.value || "").trim();
  const fb      = document.getElementById("reminderFeedback");
  if (!fb) return;

  if (!dateVal) {
    fb.className = "reminder-feedback err";
    fb.textContent = "Please pick a date first.";
    return;
  }

  /* Build title from extracted data */
  const data = window.lastExtraction || {};
  const f    = data.fields || {};
  const type = (data.document_type || "document").toLowerCase();
  const titleCandidates = [
    f.vendor, f.medicine_name, f.event_name, f.subject,
    f.store_name, f.title, f.issued_by,
  ];
  const title = titleCandidates.find(v => v && String(v).trim()) || `${type} document`;

  fb.className   = "reminder-feedback";
  fb.textContent = "Saving…";

  fetch("/api/reminder", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title, date: dateVal, document_type: type, note: noteVal }),
  })
    .then(r => r.json())
    .then(json => {
      if (json.success) {
        fb.className   = "reminder-feedback ok";
        fb.textContent = "✅ Reminder saved! Scroll down to see it.";
        loadReminders();

        /* Scroll to reminders */
        setTimeout(() =>
          document.getElementById("reminders")
            ?.scrollIntoView({ behavior: "smooth", block: "start" }), 800);
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
   6. LOAD & DISPLAY REMINDERS
════════════════════════════════════════════════════════════ */
function daysUntil(dateStr) {
  const now    = new Date(); now.setHours(0,0,0,0);
  const target = new Date(dateStr);
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
  if (days <= 3) return `<span class="days-badge days-soon">in ${days}d</span>`;
  return `<span class="days-badge days-future">in ${days}d</span>`;
}

function loadReminders() {
  const list = document.getElementById("remindersList");
  if (!list) return;

  fetch("/api/reminders")
    .then(r => r.json())
    .then(json => {
      const items = json.reminders || [];
      if (!items.length) {
        list.innerHTML = `
          <div class="reminder-empty">
            <div>🔔</div>
            <div style="font-weight:600">No reminders yet</div>
            <div style="font-size:0.85rem;margin-top:6px">
              Extract a document with a date field to set your first reminder
            </div>
          </div>`;
        return;
      }

      list.innerHTML = items.map(r => {
        const days  = daysUntil(r.reminder_date);
        const fDate = formatDate(r.reminder_date);
        return `
          <div class="reminder-card" data-id="${escHtml(r.id)}">
            <button class="reminder-delete" onclick="deleteReminder('${escHtml(r.id)}')"
                    title="Delete reminder">✕</button>
            <div class="reminder-type">${escHtml(r.document_type || "document")}</div>
            <div class="reminder-title">${escHtml(r.document_title)}</div>
            <div class="reminder-date-display">${escHtml(fDate)}</div>
            <div>${daysBadge(days)}</div>
            ${r.note ? `<div class="reminder-note">${escHtml(r.note)}</div>` : ""}
          </div>`;
      }).join("");
    })
    .catch(err => console.error("Failed to load reminders:", err));
}

function deleteReminder(id) {
  fetch(`/api/reminder/${id}`, { method: "DELETE" })
    .then(r => r.json())
    .then(json => { if (json.success) loadReminders(); })
    .catch(err => console.error("Delete error:", err));
}

/* ════════════════════════════════════════════════════════════
   7. UTILITY
════════════════════════════════════════════════════════════ */
function escHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/* Debounce */
function debounce(fn, ms) {
  let timer;
  return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); };
}

/* ════════════════════════════════════════════════════════════
   8. SETTINGS MODAL (BYOK)
════════════════════════════════════════════════════════════ */
function openSettingsModal() {
  document.getElementById("settingsModal").style.display = "flex";
}
function closeSettingsModal() {
  document.getElementById("settingsModal").style.display = "none";
}
function handleProviderChange() {
  const provider = document.getElementById("providerSelect").value;
  const baseUrlGroup = document.getElementById("baseUrlGroup");
  if (provider === "custom") {
    baseUrlGroup.style.display = "block";
  } else {
    baseUrlGroup.style.display = "none";
  }
}
function togglePassword() {
  const input = document.getElementById("apiKeyInput");
  if (input.type === "password") {
    input.type = "text";
  } else {
    input.type = "password";
  }
}

function saveProvider() {
  const provider = document.getElementById("providerSelect").value;
  const apiKey = document.getElementById("apiKeyInput").value.trim();
  const baseUrl = document.getElementById("baseUrlInput").value.trim();
  const modelNameInput = document.getElementById("modelNameInput");
  const modelName = modelNameInput ? modelNameInput.value.trim() : "";
  const fb = document.getElementById("settingsFeedback");
  const btn = document.getElementById("saveProviderBtn");

  if (!apiKey) {
    fb.className = "reminder-feedback err";
    fb.textContent = "API Key is required.";
    return;
  }
  if (provider === "custom" && !baseUrl) {
    fb.className = "reminder-feedback err";
    fb.textContent = "Base URL is required for Custom provider.";
    return;
  }

  fb.className = "reminder-feedback";
  fb.textContent = "Testing connection...";
  btn.disabled = true;

  fetch("/api/connect", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ provider, api_key: apiKey, base_url: baseUrl, model_name: modelName }),
  })
    .then(r => r.json())
    .then(json => {
      btn.disabled = false;
      if (json.success) {
        fb.className = "reminder-feedback ok";
        fb.textContent = "✅ Connected to " + provider;
        setTimeout(() => location.reload(), 1000); // Reload to update UI
      } else {
        fb.className = "reminder-feedback err";
        fb.textContent = "❌ " + (json.error || "Failed to connect.");
      }
    })
    .catch(err => {
      btn.disabled = false;
      fb.className = "reminder-feedback err";
      fb.textContent = "Network error: " + err.message;
    });
}

function disconnectProvider() {
  fetch("/api/disconnect", { method: "POST" })
    .then(() => location.reload())
    .catch(err => console.error(err));
}

/* ════════════════════════════════════════════════════════════
   9. INIT
════════════════════════════════════════════════════════════ */
document.addEventListener("DOMContentLoaded", () => {
  /* Neural sphere */
  const canvas = document.getElementById("sphereCanvas");
  if (canvas) new NeuralSphere(canvas);

  /* SVG lines — small delay so layout is settled */
  setTimeout(drawConnectingLines, 180);
  window.addEventListener("resize", debounce(drawConnectingLines, 250));

  /* Cycling search */
  initSearchCycler();

  /* Upload */
  initUpload();

  /* Reminders */
  loadReminders();

  /* Smooth scroll on nav CTA */
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener("click", e => {
      e.preventDefault();
      const target = document.querySelector(a.getAttribute("href"));
      if (target) target.scrollIntoView({ behavior: "smooth" });
    });
  });
});
