# MemoryLens AI

A cross-platform (mobile + desktop) Flutter application that allows users to upload any document, screenshot, bill, receipt, or prescription. Using AI (vision + OCR), it extracts structured data, schedules local reminders, and generates analytics reports.

## Features
- **Universal Capture**: Drag-and-drop or select files on desktop; camera or gallery upload on mobile.
- **AI Document Understanding**: Auto-classifies and extracts structured metadata (e.g., due date + amount for bills, expiry for prescriptions) with zero mock fallback data.
- **Smart Reminders**: Schedule notifications based on AI-extracted dates after user review.
- **Auto-Generated Reports**: Analytics dashboard with live calculations from Firestore.
- **BYOK (Bring Your Own Key)**: Support for custom Gemini, Groq, Claude, OpenAI, or custom OpenAI-compatible keys saved securely on-device.

## Tech Stack
- **Frontend**: Flutter (Riverpod state management)
- **Backend**: Firebase Auth & Firestore
- **Local Storage**: `flutter_secure_storage` for API keys
- **Local Notifications**: `flutter_local_notifications`

## Setup Instructions

1. **Clone & Dependencies**:
   ```bash
   flutter pub get
   ```
2. **Firebase Setup**:
   - Link standard Firebase files (`google-services.json` for Android, `GoogleService-Info.plist` for iOS/macOS).
   - *Do NOT commit these files to version control.*
3. **Run**:
   ```bash
   flutter run
   ```

## GitHub Setup & Safe Push
To publish this repository safely without exposing secrets:
```bash
git init
git add .
git commit -m "initial commit"
git remote add origin <your-repo-url>
git push -u origin main
```
Note: Sensitives files like API keys or config files are automatically excluded by `.gitignore`.
