# MediLingua – Multilingual Clinical Dialogue System
## Flutter UI Project

### Pages Included

| Page | File | Description |
|------|------|-------------|
| Login | `pages/login_page.dart` | Doctor authentication with animated entry |
| Patient Selection | `pages/patient_selection_page.dart` | Search, view & add patients |
| Consultation | `pages/consultation_page.dart` | Live recording + real-time transcript |
| Summary | `pages/summary_page.dart` | AI summary + prescriptions + full transcript |

### Project Structure
```
lib/
├── main.dart                        ← App entry point
├── theme/
│   └── app_theme.dart               ← Colors, fonts, theme
├── models/
│   └── models.dart                  ← Doctor, Patient, Consultation, etc.
└── pages/
    ├── login_page.dart
    ├── patient_selection_page.dart
    ├── consultation_page.dart
    └── summary_page.dart
```

### How to Run
```bash
flutter pub get
flutter run
```

### Key Features per Page

**Login Page**
- Animated fade + slide on load
- Form validation
- Feature chips (Languages, Speaker AI, Summary)

**Patient Selection Page**
- Search by name / phone
- Gender-colored patient avatars
- Add Patient bottom sheet with gender chips

**Consultation Page**
- Mic button to start/stop recording
- Live timer display
- Chat-style transcript bubbles (Doctor / Patient)
- Language badge on each bubble (Hindi → English)
- One-tap "Summary" button when transcript is available
- Mock data simulates live speech every 3 seconds

**Summary Page**
- Patient info card
- AI-generated clinical summary card (purple gradient badge)
- Stats row: Duration, Exchanges, Language
- Prescription list with add-prescription form
- Full transcript table with original + translated text
- Save / End Consultation button

### Tech Stack (Backend integration points)
- **Whisper** → Replace mock segments in `consultation_page.dart` with API call
- **pyannote.audio** → Speaker label in `TranscriptSegment.speaker`
- **MySQL** → Wire `Save` button in summary to your REST API
- **Translation** → `englishText` field on each segment from backend
