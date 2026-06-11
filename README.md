# 🏥 MediLingua
### Multilingual Clinical Dialogue System for Automated Medical Documentation

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
  <img src="https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white"/>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white"/>
  <img src="https://img.shields.io/badge/AssemblyAI-FF4B4B?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Groq-F55036?style=for-the-badge"/>
</p>

<p align="center">
  <a href="https://github.com/yourusername/medilingua/releases/latest">
    <img src="https://img.shields.io/badge/⬇️ Download APK-brightgreen?style=for-the-badge"/>
  </a>
</p>

> ⚠️ **Note:** On first launch, the backend may take ~30 seconds to respond (Render free tier cold start). Please wait before retrying.

---

## 🧠 Overview

MediLingua is an AI-powered healthcare documentation platform that assists doctors during multilingual consultations. The system converts recorded doctor–patient conversations into structured medical records by combining speech transcription, speaker identification, translation, and clinical summarization.

The platform addresses a common challenge in healthcare environments where consultations occur in regional languages while medical records must be maintained in English. By automating documentation, MediLingua reduces administrative workload and improves consultation efficiency.

---

## 🚨 Problem Statement

Healthcare professionals spend a significant amount of time manually documenting consultations. In multilingual environments, the challenge is even greater due to language barriers and the need for standardized English medical records.

**MediLingua automates the entire pipeline:**

| Step | What happens |
|------|-------------|
| 🎙️ Record | Capture doctor–patient consultation audio |
| 📝 Transcribe | Convert speech to text with speaker identification |
| 🌐 Translate | Translate multilingual dialogue into English |
| 🩺 Summarize | Generate structured clinical summaries |
| 💾 Store | Save records for future reference and export |

---

## ✨ Features

### 🎙️ Consultation Recording
- Record doctor–patient conversations
- Session-based consultation workflow

### 📝 Speech Transcription
- Accurate speech-to-text conversion using AssemblyAI
- Speaker-aware transcription with diarization support

### 🌐 Translation
- Multilingual consultation transcripts translated into English
- Powered by Llama 3 through Groq

### 🩺 Clinical Summarization
- Automatic generation of consultation summaries
- Extraction of symptoms, diagnosis, and recommendations

### 👥 Patient Management
- Add and manage patient records
- Search and select patients

### 📂 Consultation History
- Store transcripts and summaries
- Retrieve previous consultation records

### 💊 Prescription Management
- Maintain prescription details alongside consultation records

---

## 🏗️ System Architecture

<img width="521" height="602" alt="System Architecture" src="https://github.com/user-attachments/assets/3c2e91eb-7cec-48a2-a9ef-6c1ad21cb9fa" />

---

## 🛠️ Technology Stack

| Layer | Technology |
|-------|-----------|
| 📱 Frontend | Flutter, Dart |
| ⚙️ Backend | FastAPI, Python |
| 🗣️ Speech-to-Text | AssemblyAI |
| 🔊 Speaker Diarization | AssemblyAI |
| 🌐 Translation | Llama 3 via Groq |
| 🩺 Summarization | Llama 3 via Groq |
| 🗄️ Database | MySQL, Firebase Realtime Database |
| 🔧 Version Control | Git, GitHub |

---

## 💡 Architecture Decisions

### 🎤 Why AssemblyAI?
During development, multiple speech recognition approaches were evaluated including self-hosted Whisper models. While Whisper provides excellent multilingual transcription, running large speech models locally introduces significant computational overhead.

AssemblyAI was selected because it provides:
- ✅ High-quality transcription
- ✅ Built-in speaker diarization
- ✅ Cloud-managed infrastructure
- ✅ Faster integration
- ✅ Reduced deployment complexity

### ⚡ Why Llama 3 via Groq?
- ✅ Low-latency inference
- ✅ Simple API integration
- ✅ High-quality translation
- ✅ Effective clinical summarization

### 📱 Why Flutter?
Flutter enables rapid cross-platform development while maintaining a consistent user experience across platforms from a single codebase.

---

## 🔄 Application Workflow

```
1. 🔐 Doctor logs into the application
2. 👤 Patient is selected or created
3. 🎙️ Consultation audio is recorded
4. 🤖 Audio is processed by AssemblyAI
5. 🗣️ Speaker-tagged transcripts are generated
6. 🌐 Transcript is translated into English using Llama 3
7. 🩺 Clinical summary is generated
8. 💾 Consultation details are stored
9. 📄 Records can be reviewed and exported
```

---

## 📁 Project Structure

```
lib/
├── main.dart
├── theme/
│   └── app_theme.dart
├── models/
│   └── models.dart
└── pages/
    ├── login_page.dart
    ├── patient_selection_page.dart
    ├── consultation_page.dart
    └── summary_page.dart
```

---

## 🚀 Installation

### Prerequisites
- Flutter SDK
- Dart SDK
- Python 3.10+
- MySQL
- Firebase Project

### Clone Repository
```bash
git clone https://github.com/yourusername/medilingua.git
cd medilingua
```

### Install Dependencies
```bash
flutter pub get
```

### Run Application
```bash
flutter run
```

---

## 📸 Screenshots

<img width="957" height="495" alt="pic1" src="https://github.com/user-attachments/assets/a7c22d5a-1ca1-4b37-b51b-cc3e140e7050" />

&nbsp;&nbsp;&nbsp;

<img width="812" height="501" alt="pic2" src="https://github.com/user-attachments/assets/d1d056bd-a0ee-429c-9a00-a3c15167dc77" />

---

## 📊 Current Status

### ✅ Implemented
- [x] Consultation workflow
- [x] Patient management
- [x] Audio transcription
- [x] Speaker diarization
- [x] Translation pipeline
- [x] Clinical summarization
- [x] Database integration
- [x] Flutter frontend

### 🔮 Planned
- [ ] Real-time transcription
- [ ] Medical vocabulary fine-tuning
- [ ] EHR integration
- [ ] Offline support
- [ ] Multi-hospital deployment
- [ ] Analytics dashboard

---

## 👩‍💻 Team

| Name | Role |
|------|------|
| Susmita Sahu | Developer |
| Shruti Patel | Developer |
| Nidhi Sinha | Developer |

**Project Guide:** Prof. Deepti Chandran

---

## 📄 License

This project was developed for academic and research purposes.
