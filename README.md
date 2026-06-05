# MediLingua

Multilingual Clinical Dialogue System for Automated Medical Documentation

## Overview

MediLingua is an AI-powered healthcare documentation platform that assists doctors during multilingual consultations. The system converts recorded doctor–patient conversations into structured medical records by combining speech transcription, speaker identification, translation, and clinical summarization.

The platform is designed to address a common challenge in healthcare environments where consultations occur in regional languages while medical records must be maintained in English. By automating documentation, MediLingua reduces administrative workload and improves consultation efficiency.

---

## Problem Statement

Healthcare professionals spend a significant amount of time manually documenting consultations. In multilingual environments, the challenge becomes even greater due to language barriers and the need for standardized English medical records.

MediLingua provides an automated pipeline that:

* Transcribes consultation audio
* Identifies speakers
* Translates multilingual conversations into English
* Generates structured clinical summaries
* Stores consultation records for future reference

---

## Features

### Consultation Recording

* Record doctor–patient conversations
* Session-based consultation workflow

### Speech Transcription

* Accurate speech-to-text conversion using AssemblyAI
* Speaker-aware transcription with diarization support

### Translation

* Translation of multilingual consultation transcripts into English
* Powered by Llama 3 through Groq

### Clinical Summarization

* Automatic generation of consultation summaries
* Extraction of symptoms, diagnosis, and recommendations

### Patient Management

* Add and manage patient records
* Search and select patients

### Consultation History

* Store transcripts and summaries
* Retrieve previous consultation records

### Prescription Management

* Maintain prescription details alongside consultation records

---

## System Architecture/ Flowchart


<img width="1405" height="1119" alt="ChatGPT Image Jun 5, 2026, 10_47_24 PM" src="https://github.com/user-attachments/assets/f27b28e0-4ece-479e-b5b9-11a19ec8b3af" />




---

## Technology Stack

### Frontend

* Flutter
* Dart

### Backend

* FastAPI
* Python

### AI Services

* AssemblyAI

  * Speech-to-Text
  * Speaker Diarization

* Llama 3 via Groq

  * Translation
  * Clinical Summarization

### Database

* MySQL
* Firebase Realtime Database

### Version Control

* Git
* GitHub

---

## Architecture Decisions

### Why AssemblyAI?

During development, multiple speech recognition approaches were evaluated, including self-hosted Whisper models.

While Whisper provides excellent multilingual transcription capabilities, running large speech models locally introduces significant computational overhead and hardware requirements.

AssemblyAI was selected because it provides:

* High-quality transcription
* Built-in speaker diarization
* Cloud-managed infrastructure
* Faster integration
* Reduced deployment complexity

This allowed development efforts to focus on healthcare workflow integration rather than model hosting and optimization.

### Why Llama 3 via Groq?

Llama 3 provides strong multilingual reasoning and text generation capabilities.

Groq was selected because it offers:

* Low-latency inference
* Simple API integration
* High-quality translation
* Effective clinical summarization

### Why Flutter?

Flutter enables rapid cross-platform development while maintaining a consistent user experience and a single codebase.

---

## Application Workflow

1. Doctor logs into the application.
2. Patient is selected or created.
3. Consultation audio is recorded.
4. Audio is processed by AssemblyAI.
5. Speaker-tagged transcripts are generated.
6. Transcript is translated into English using Llama 3.
7. Clinical summary is generated.
8. Consultation details are stored.
9. Records can be reviewed and exported.

---

## Project Structure

```text
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

## Installation

### Prerequisites

* Flutter SDK
* Dart SDK
* Python 3.10+
* MySQL
* Firebase Project

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

## Screenshots




<img width="657" height="340" alt="pic11" src="https://github.com/user-attachments/assets/b282f401-d703-4502-9e03-38ccc7b1aadb" />





<img width="600" height="370" alt="pic21" src="https://github.com/user-attachments/assets/694cd6c1-52e2-4a1e-8aa8-36dd1ed36627" />




---

## Current Status

Implemented:

* Consultation workflow
* Patient management
* Audio transcription
* Speaker diarization
* Translation pipeline
* Clinical summarization
* Database integration
* Flutter frontend

Planned:

* Real-time transcription
* Medical vocabulary fine-tuning
* EHR integration
* Offline support
* Multi-hospital deployment
* Analytics dashboard

---

## Team

### Project Members

* Susmita Sahu
* Shruti Patel
* Nidhi Sinha

### Project Guide

Prof. Deepti Chandran

---

## License

This project was developed for academic and research purposes.
