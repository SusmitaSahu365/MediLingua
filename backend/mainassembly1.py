"""
MediLingua Backend — FastAPI + AssemblyAI + Groq
AssemblyAI  → transcription + diarization + timestamps
Groq LLaMA  → translate non-English utterances to English
LeMUR       → clinical summary on demand
"""

from dotenv import load_dotenv
load_dotenv()

import os
import uuid
import datetime
import tempfile
from typing import Optional

import assemblyai as aai
from groq import Groq

from fastapi import FastAPI, HTTPException, Depends, status, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import jwt
import bcrypt as _bcrypt_lib
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, Session, relationship
from contextlib import asynccontextmanager

# ──────────────────────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────────────────────
_raw_db_url          = os.getenv("DATABASE_URL", "sqlite:///./medilingua.db")
# Render provides postgres:// URLs — SQLAlchemy 1.4+ requires postgresql://
DATABASE_URL         = _raw_db_url.replace("postgres://", "postgresql://", 1)
SECRET_KEY           = os.getenv("SECRET_KEY", "CHANGE_ME_IN_PROD_USE_32chars!!")
ALGORITHM            = "HS256"
TOKEN_EXPIRE_MINUTES = 60 * 24
ASSEMBLYAI_API_KEY   = os.getenv("ASSEMBLYAI_API_KEY", "")
GROQ_API_KEY         = os.getenv("GROQ_API_KEY", "")

# ──────────────────────────────────────────────────────────────
# DATABASE
# ──────────────────────────────────────────────────────────────
_is_sqlite   = DATABASE_URL.startswith("sqlite")
_engine_args = {"check_same_thread": False} if _is_sqlite else {}
engine       = create_engine(DATABASE_URL, connect_args=_engine_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base         = declarative_base()


class DoctorDB(Base):
    __tablename__ = "doctors"
    id              = Column(Integer, primary_key=True, index=True)
    name            = Column(String, nullable=False)
    specialization  = Column(String, default="General Physician")
    email           = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    phone           = Column(String, nullable=True, default="")
    patients        = relationship("PatientDB", back_populates="doctor")
    sessions        = relationship("ConsultationSessionDB", back_populates="doctor")


class PatientDB(Base):
    __tablename__ = "patients"
    id        = Column(Integer, primary_key=True, index=True)
    doctor_id = Column(Integer, ForeignKey("doctors.id"), nullable=False)
    name      = Column(String, nullable=False)
    dob       = Column(String, nullable=False)
    gender    = Column(String, nullable=False)
    phone     = Column(String, nullable=False)
    address   = Column(String, default="")
    doctor    = relationship("DoctorDB", back_populates="patients")
    sessions  = relationship("ConsultationSessionDB", back_populates="patient")


class ConsultationSessionDB(Base):
    __tablename__ = "consultation_sessions"
    id         = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    doctor_id  = Column(Integer, ForeignKey("doctors.id"), nullable=False)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    status     = Column(String, default="active")
    doctor     = relationship("DoctorDB", back_populates="sessions")
    patient    = relationship("PatientDB", back_populates="sessions")
    segments   = relationship(
        "TranscriptSegmentDB", back_populates="session",
        order_by="TranscriptSegmentDB.id")
    summary       = relationship("ClinicalSummaryDB", back_populates="session", uselist=False)
    vitals        = relationship("VitalsDB", back_populates="session", uselist=False)
    prescriptions = relationship("PrescriptionDB", back_populates="session",
                                 order_by="PrescriptionDB.id")


class TranscriptSegmentDB(Base):
    __tablename__ = "transcript_segments"
    id                = Column(Integer, primary_key=True, autoincrement=True)
    session_id        = Column(String, ForeignKey("consultation_sessions.id"))
    speaker           = Column(String, default="Speaker 1")
    original_text     = Column(Text, default="")   # original language
    english_text      = Column(Text, default="")   # translated to English
    detected_language = Column(String, default="English")
    start_time        = Column(String, default="00:00")
    end_time          = Column(String, default="00:00")
    session           = relationship("ConsultationSessionDB", back_populates="segments")


class ClinicalSummaryDB(Base):
    __tablename__ = "clinical_summaries"
    id         = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String, ForeignKey("consultation_sessions.id"), unique=True)
    summary    = Column(Text, default="")
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    session    = relationship("ConsultationSessionDB", back_populates="summary")


class VitalsDB(Base):
    __tablename__ = "vitals"
    id            = Column(Integer, primary_key=True, autoincrement=True)
    session_id    = Column(String, ForeignKey("consultation_sessions.id"), unique=True)
    bp_systolic   = Column(String, nullable=True)   # e.g. "120"
    bp_diastolic  = Column(String, nullable=True)   # e.g. "80"
    heart_rate    = Column(String, nullable=True)   # e.g. "72 bpm"
    spo2          = Column(String, nullable=True)   # e.g. "98%"
    temperature   = Column(String, nullable=True)   # e.g. "98.6°F"
    weight        = Column(String, nullable=True)   # e.g. "70 kg"
    notes         = Column(Text, nullable=True)
    session       = relationship("ConsultationSessionDB", back_populates="vitals")


class PrescriptionDB(Base):
    __tablename__ = "prescriptions"
    id           = Column(Integer, primary_key=True, autoincrement=True)
    session_id   = Column(String, ForeignKey("consultation_sessions.id"))
    medicine     = Column(String, nullable=False)
    dosage       = Column(String, nullable=True)    # e.g. "500mg"
    frequency    = Column(String, nullable=True)    # e.g. "Twice daily"
    duration     = Column(String, nullable=True)    # e.g. "5 days"
    instructions = Column(String, nullable=True)    # e.g. "After food"
    session      = relationship("ConsultationSessionDB", back_populates="prescriptions")


Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ──────────────────────────────────────────────────────────────
# AUTH
# ──────────────────────────────────────────────────────────────
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def hash_password(pw: str) -> str:
    """Hash using bcrypt directly (passlib broken on Python 3.13+)."""
    secret = pw[:72].encode("utf-8")
    return _bcrypt_lib.hashpw(secret, _bcrypt_lib.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    secret = plain[:72].encode("utf-8")
    return _bcrypt_lib.checkpw(secret, hashed.encode("utf-8"))


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire    = datetime.datetime.utcnow() + datetime.timedelta(minutes=TOKEN_EXPIRE_MINUTES)
    to_encode["exp"] = expire
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def get_current_doctor(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> DoctorDB:
    exc = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid or expired token",
                        headers={"WWW-Authenticate": "Bearer"})
    try:
        payload   = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        doctor_id = int(payload["sub"])
    except Exception:
        raise exc
    doctor = db.query(DoctorDB).filter(DoctorDB.id == doctor_id).first()
    if not doctor:
        raise exc
    return doctor


# ──────────────────────────────────────────────────────────────
# GROQ — translate a single utterance to English
# Only called if text is not already English
# ──────────────────────────────────────────────────────────────
groq_client = None


def translate_to_english(text: str) -> tuple[str, str]:
    """
    Returns (english_text, detected_language)
    Uses Groq LLaMA to detect language and translate if not English.
    If already English, returns (text, 'English') immediately.
    """
    global groq_client
    if not groq_client:
        return text, "English"

    try:
        response = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a medical translator. Given a piece of text, "
                        "detect its language and translate it to English if it is not already English. "
                        "Respond in JSON format only, no explanation:\n"
                        '{"language": "<detected language name>", "english": "<english translation>"}\n'
                        "If the text is already in English, return the same text as english. "
                        "For mixed language (e.g. Hinglish), translate the non-English parts."
                    )
                },
                {
                    "role": "user",
                    "content": text
                }
            ],
            temperature=0,
            max_tokens=512,
        )
        import json
        raw = response.choices[0].message.content.strip()
        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        parsed   = json.loads(raw.strip())
        lang     = parsed.get("language", "English")
        english  = parsed.get("english", text).strip()
        return english, lang
    except Exception as e:
        print(f"[Groq] Translation failed: {e}")
        return text, "English"


# ──────────────────────────────────────────────────────────────
# APP
# ──────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    global groq_client
    if not ASSEMBLYAI_API_KEY:
        print("[MediLingua] WARNING: ASSEMBLYAI_API_KEY not set in .env!")
    else:
        aai.settings.api_key = ASSEMBLYAI_API_KEY
        print("[MediLingua] AssemblyAI ready.")
    if not GROQ_API_KEY:
        print("[MediLingua] WARNING: GROQ_API_KEY not set in .env!")
    else:
        groq_client = Groq(api_key=GROQ_API_KEY)
        print("[MediLingua] Groq ready.")
    yield


app = FastAPI(title="MediLingua API", version="6.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])


# ──────────────────────────────────────────────────────────────
# SCHEMAS
# ──────────────────────────────────────────────────────────────
class SignupRequest(BaseModel):
    name: str
    specialization: Optional[str] = "General Physician"
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    doctor_id: int
    name: str
    specialization: str
    email: str
    phone: Optional[str] = ""


class PatientCreate(BaseModel):
    name: str
    dob: str
    gender: str
    phone: str
    address: Optional[str] = ""


class SessionCreateRequest(BaseModel):
    patient_id: int


class VitalsRequest(BaseModel):
    bp_systolic:  Optional[str] = None
    bp_diastolic: Optional[str] = None
    heart_rate:   Optional[str] = None
    spo2:         Optional[str] = None
    temperature:  Optional[str] = None
    weight:       Optional[str] = None
    notes:        Optional[str] = None


class PrescriptionItem(BaseModel):
    medicine:     str
    dosage:       Optional[str] = None
    frequency:    Optional[str] = None
    duration:     Optional[str] = None
    instructions: Optional[str] = None


class PrescriptionRequest(BaseModel):
    prescriptions: list[PrescriptionItem]


# ──────────────────────────────────────────────────────────────
# AUTH ROUTES
# ──────────────────────────────────────────────────────────────
@app.post("/auth/signup", response_model=TokenResponse)
def signup(req: SignupRequest, db: Session = Depends(get_db)):
    if db.query(DoctorDB).filter(DoctorDB.email == req.email).first():
        raise HTTPException(400, "Email already registered")
    doc = DoctorDB(name=req.name,
                   specialization=req.specialization or "General Physician",
                   email=req.email,
                   hashed_password=hash_password(req.password))
    db.add(doc); db.commit(); db.refresh(doc)
    return TokenResponse(access_token=create_access_token({"sub": str(doc.id)}),
                         doctor_id=doc.id, name=doc.name,
                         specialization=doc.specialization, email=doc.email, phone=doc.phone or "")


@app.post("/auth/login", response_model=TokenResponse)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    doc = db.query(DoctorDB).filter(DoctorDB.email == form.username).first()
    if not doc or not verify_password(form.password, doc.hashed_password):
        raise HTTPException(401, "Invalid email or password")
    return TokenResponse(access_token=create_access_token({"sub": str(doc.id)}),
                         doctor_id=doc.id, name=doc.name,
                         specialization=doc.specialization, email=doc.email, phone=doc.phone or "")


# ──────────────────────────────────────────────────────────────
# PATIENT ROUTES
# ──────────────────────────────────────────────────────────────
@app.get("/patients")
def list_patients(doctor: DoctorDB = Depends(get_current_doctor),
                  db: Session = Depends(get_db)):
    return [{"patient_id": p.id, "name": p.name, "dob": p.dob,
             "gender": p.gender, "phone": p.phone, "address": p.address}
            for p in db.query(PatientDB).filter(PatientDB.doctor_id == doctor.id).all()]


@app.post("/patients")
def create_patient(req: PatientCreate,
                   doctor: DoctorDB = Depends(get_current_doctor),
                   db: Session = Depends(get_db)):
    p = PatientDB(doctor_id=doctor.id, name=req.name, dob=req.dob,
                  gender=req.gender, phone=req.phone, address=req.address or "")
    db.add(p); db.commit(); db.refresh(p)
    return {"patient_id": p.id, "name": p.name, "dob": p.dob,
            "gender": p.gender, "phone": p.phone, "address": p.address}


@app.delete("/patients/{patient_id}", status_code=204)
def delete_patient(patient_id: int,
                   doctor: DoctorDB = Depends(get_current_doctor),
                   db: Session = Depends(get_db)):
    p = db.query(PatientDB).filter(PatientDB.id == patient_id,
                                   PatientDB.doctor_id == doctor.id).first()
    if not p:
        raise HTTPException(404, "Patient not found")
    db.delete(p); db.commit()


@app.put("/patients/{patient_id}")
def update_patient(patient_id: int,
                   req: PatientCreate,
                   doctor: DoctorDB = Depends(get_current_doctor),
                   db: Session = Depends(get_db)):
    p = db.query(PatientDB).filter(PatientDB.id == patient_id,
                                   PatientDB.doctor_id == doctor.id).first()
    if not p:
        raise HTTPException(404, "Patient not found")
    p.name    = req.name
    p.dob     = req.dob
    p.gender  = req.gender
    p.phone   = req.phone
    p.address = req.address or ""
    db.commit()
    return {"patient_id": p.id, "name": p.name, "dob": p.dob,
            "gender": p.gender, "phone": p.phone, "address": p.address}


# ──────────────────────────────────────────────────────────────
# DOCTOR PROFILE
# ──────────────────────────────────────────────────────────────
class DoctorUpdateRequest(BaseModel):
    name:           Optional[str] = None
    specialization: Optional[str] = None
    phone:          Optional[str] = None
    current_password: Optional[str] = None
    new_password:   Optional[str] = None


@app.get("/auth/me")
def get_me(doctor: DoctorDB = Depends(get_current_doctor)):
    return {
        "doctor_id":      doctor.id,
        "name":           doctor.name,
        "specialization": doctor.specialization,
        "email":          doctor.email,
        "phone":          doctor.phone or "",
        "access_token":   None,
    }


@app.put("/auth/me")
def update_me(req: DoctorUpdateRequest,
              doctor: DoctorDB = Depends(get_current_doctor),
              db: Session = Depends(get_db)):
    if req.name:           doctor.name           = req.name
    if req.specialization: doctor.specialization = req.specialization
    if req.phone is not None: doctor.phone       = req.phone

    # Password change — requires current password
    if req.new_password:
        if not req.current_password:
            raise HTTPException(400, "Current password required")
        if not verify_password(req.current_password, doctor.hashed_password):
            raise HTTPException(400, "Current password is incorrect")
        if len(req.new_password) < 6:
            raise HTTPException(400, "New password must be at least 6 characters")
        doctor.hashed_password = hash_password(req.new_password)

    db.commit()
    return {
        "doctor_id":      doctor.id,
        "name":           doctor.name,
        "specialization": doctor.specialization,
        "email":          doctor.email,
        "phone":          doctor.phone or "",
        "access_token":   None,
    }


# ──────────────────────────────────────────────────────────────
# SESSION ROUTES
# ──────────────────────────────────────────────────────────────
@app.post("/sessions")
def create_session(req: SessionCreateRequest,
                   doctor: DoctorDB = Depends(get_current_doctor),
                   db: Session = Depends(get_db)):
    p = db.query(PatientDB).filter(PatientDB.id == req.patient_id,
                                   PatientDB.doctor_id == doctor.id).first()
    if not p:
        raise HTTPException(404, "Patient not found")
    s = ConsultationSessionDB(id=str(uuid.uuid4()),
                               doctor_id=doctor.id, patient_id=req.patient_id)
    db.add(s); db.commit()
    return {"session_id": s.id, "status": "active"}


@app.get("/sessions/{session_id}/transcript")
def get_transcript(session_id: str,
                   doctor: DoctorDB = Depends(get_current_doctor),
                   db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")
    return [{"speaker": seg.speaker,
             "original_text": seg.original_text,
             "english_text": seg.english_text,
             "detected_language": seg.detected_language,
             "start_time": seg.start_time,
             "end_time": seg.end_time}
            for seg in s.segments]


@app.post("/sessions/{session_id}/end")
def end_session(session_id: str,
                doctor: DoctorDB = Depends(get_current_doctor),
                db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")
    s.status = "ended"; db.commit()
    return {"status": "ended"}


@app.delete("/sessions/{session_id}", status_code=204)
def delete_session(session_id: str,
                   doctor: DoctorDB = Depends(get_current_doctor),
                   db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")
    db.delete(s); db.commit()


# ──────────────────────────────────────────────────────────────
# VITALS — optional, save before or during consultation
# ──────────────────────────────────────────────────────────────
@app.post("/sessions/{session_id}/vitals")
def save_vitals(session_id: str,
                req: VitalsRequest,
                doctor: DoctorDB = Depends(get_current_doctor),
                db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")

    existing = db.query(VitalsDB).filter_by(session_id=session_id).first()
    if existing:
        existing.bp_systolic  = req.bp_systolic
        existing.bp_diastolic = req.bp_diastolic
        existing.heart_rate   = req.heart_rate
        existing.spo2         = req.spo2
        existing.temperature  = req.temperature
        existing.weight       = req.weight
        existing.notes        = req.notes
    else:
        db.add(VitalsDB(
            session_id=session_id,
            bp_systolic=req.bp_systolic,
            bp_diastolic=req.bp_diastolic,
            heart_rate=req.heart_rate,
            spo2=req.spo2,
            temperature=req.temperature,
            weight=req.weight,
            notes=req.notes,
        ))
    db.commit()
    return {"status": "saved"}


@app.get("/sessions/{session_id}/vitals")
def get_vitals(session_id: str,
               doctor: DoctorDB = Depends(get_current_doctor),
               db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")
    v = s.vitals
    if not v:
        return {}
    return {
        "bp_systolic":  v.bp_systolic,
        "bp_diastolic": v.bp_diastolic,
        "heart_rate":   v.heart_rate,
        "spo2":         v.spo2,
        "temperature":  v.temperature,
        "weight":       v.weight,
        "notes":        v.notes,
    }


# ──────────────────────────────────────────────────────────────
# PRESCRIPTIONS — optional, add after consultation
# ──────────────────────────────────────────────────────────────
@app.post("/sessions/{session_id}/prescriptions")
def save_prescriptions(session_id: str,
                       req: PrescriptionRequest,
                       doctor: DoctorDB = Depends(get_current_doctor),
                       db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")

    # Clear old prescriptions and replace
    db.query(PrescriptionDB).filter_by(session_id=session_id).delete()
    for item in req.prescriptions:
        if item.medicine.strip():
            db.add(PrescriptionDB(
                session_id=session_id,
                medicine=item.medicine.strip(),
                dosage=item.dosage,
                frequency=item.frequency,
                duration=item.duration,
                instructions=item.instructions,
            ))
    db.commit()

    # Auto-regenerate summary with new prescriptions if summary already exists
    if s.summary and s.segments:
        transcript = "\n".join(
            f"{seg.speaker}: {seg.english_text}" for seg in s.segments)
        language = s.segments[0].detected_language if s.segments else "Unknown"
        duration = s.segments[-1].end_time if s.segments else "00:00"
        rx_lines = []
        for rx in s.prescriptions:
            line = f"- {rx.medicine}"
            details = [x for x in [rx.dosage, rx.frequency, rx.duration, rx.instructions] if x]
            if details: line += f" ({', '.join(details)})"
            rx_lines.append(line)
        rx_text = "\n".join(rx_lines)
        new_summary = _groq_summarize_single(
            transcript, language, duration, len(s.segments), rx_text)
        s.summary.summary = new_summary
        db.commit()
        print(f"[Prescriptions] Summary regenerated with {len(req.prescriptions)} prescriptions")
        return {"status": "saved", "count": len(req.prescriptions), "summary_updated": True}

    return {"status": "saved", "count": len(req.prescriptions)}


@app.get("/sessions/{session_id}/prescriptions")
def get_prescriptions(session_id: str,
                      doctor: DoctorDB = Depends(get_current_doctor),
                      db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")
    return [
        {"medicine": p.medicine, "dosage": p.dosage,
         "frequency": p.frequency, "duration": p.duration,
         "instructions": p.instructions}
        for p in s.prescriptions
    ]


# ──────────────────────────────────────────────────────────────
# TRANSCRIBE
# AssemblyAI  → transcription + Speaker A/B + timestamps
# Groq LLaMA → detect language + translate each utterance to English
# ──────────────────────────────────────────────────────────────
@app.post("/sessions/{session_id}/transcribe")
async def transcribe_audio(
    session_id: str,
    audio: UploadFile = File(...),
    doctor: DoctorDB = Depends(get_current_doctor),
    db: Session = Depends(get_db),
):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")

    audio_bytes = await audio.read()
    suffix      = ".wav" if (audio.filename or "").endswith(".wav") else ".m4a"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    print(f"[AssemblyAI] {len(audio_bytes)/1024:.1f}KB received")

    try:
        # ── Step 1: AssemblyAI transcription + diarization ────
        config = aai.TranscriptionConfig(
            speaker_labels=True,
            speakers_expected=2,
            punctuate=True,
            format_text=True,
            speech_model=aai.SpeechModel.best,
            language_detection=True,
        )
        transcript = aai.Transcriber().transcribe(tmp_path, config)

        if transcript.status == aai.TranscriptStatus.error:
            raise HTTPException(500, f"AssemblyAI error: {transcript.error}")

        utterances = transcript.utterances or []
        print(f"[AssemblyAI] {len(utterances)} utterances, detected lang: {transcript.language_code}")

        # Clear old segments
        db.query(TranscriptSegmentDB).filter_by(session_id=session_id).delete()

        out         = []
        speaker_map = {}
        counter     = 1

        for utt in utterances:
            # Map A/B → Speaker 1/2
            raw = utt.speaker
            if raw not in speaker_map:
                speaker_map[raw] = f"Speaker {counter}"
                counter += 1
            speaker      = speaker_map[raw]
            original_txt = utt.text.strip()
            if not original_txt:
                continue

            start_ts = _ms_to_ts(utt.start)
            end_ts   = _ms_to_ts(utt.end)

            # ── Step 2: Groq translation ──────────────────────
            english_txt, detected_lang = translate_to_english(original_txt)
            print(f"[Groq] {speaker} [{detected_lang}] {original_txt[:40]}...")
            if detected_lang != "English":
                print(f"       → {english_txt[:40]}...")

            db.add(TranscriptSegmentDB(
                session_id=session_id,
                speaker=speaker,
                original_text=original_txt,
                english_text=english_txt,
                detected_language=detected_lang,
                start_time=start_ts,
                end_time=end_ts,
            ))
            out.append({
                "speaker": speaker,
                "original_text": original_txt,
                "english_text": english_txt,
                "detected_language": detected_lang,
                "start_time": start_ts,
                "end_time": end_ts,
            })

        db.commit()
        print(f"[Done] {len(out)} segments saved. Speakers: {list(speaker_map.values())}")
        return {"segments": out, "speakers": list(speaker_map.values())}

    except HTTPException:
        raise
    except Exception as e:
        print(f"[Error] {e}")
        raise HTTPException(500, f"Transcription failed: {str(e)}")
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass


# ──────────────────────────────────────────────────────────────
# ──────────────────────────────────────────────────────────────
# SINGLE SESSION SUMMARY — Groq LLaMA
# ──────────────────────────────────────────────────────────────
@app.post("/sessions/{session_id}/summary")
def generate_summary(session_id: str,
                     doctor: DoctorDB = Depends(get_current_doctor),
                     db: Session = Depends(get_db)):
    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")
    if not s.segments:
        raise HTTPException(400, "No transcript yet — transcribe first")

    transcript = "\n".join(
        f"{seg.speaker}: {seg.english_text}" for seg in s.segments
    )
    language  = s.segments[0].detected_language if s.segments else "Unknown"
    duration  = s.segments[-1].end_time if s.segments else "00:00"
    exchanges = len(s.segments)

    # Include prescriptions already saved so Groq uses actual prescribed meds
    rx_text = ""
    if s.prescriptions:
        rx_lines = []
        for rx in s.prescriptions:
            line = f"- {rx.medicine}"
            details = [x for x in [rx.dosage, rx.frequency, rx.duration, rx.instructions] if x]
            if details:
                line += f" ({', '.join(details)})"
            rx_lines.append(line)
        rx_text = "\n".join(rx_lines)

    print(f"[Summary] Groq LLaMA — {exchanges} turns, lang={language}, prescriptions={len(s.prescriptions)}")

    summary_text = _groq_summarize_single(transcript, language, duration, exchanges, rx_text)

    existing = db.query(ClinicalSummaryDB).filter_by(session_id=session_id).first()
    if existing:
        existing.summary = summary_text
    else:
        db.add(ClinicalSummaryDB(session_id=session_id, summary=summary_text))
    db.commit()
    print(f"[Summary] Done.")
    return {"session_id": session_id, "summary": summary_text}



# ──────────────────────────────────────────────────────────────
# PATIENT HISTORY — all sessions for a patient
# ──────────────────────────────────────────────────────────────
@app.get("/patients/{patient_id}/sessions")
def get_patient_sessions(patient_id: int,
                         doctor: DoctorDB = Depends(get_current_doctor),
                         db: Session = Depends(get_db)):
    p = db.query(PatientDB).filter(PatientDB.id == patient_id,
                                   PatientDB.doctor_id == doctor.id).first()
    if not p:
        raise HTTPException(404, "Patient not found")

    sessions = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.patient_id == patient_id,
        ConsultationSessionDB.doctor_id == doctor.id,
    ).order_by(ConsultationSessionDB.created_at.desc()).all()

    result = []
    for s in sessions:
        segments = s.segments
        summary  = s.summary.summary if s.summary else None
        duration = segments[-1].end_time if segments else "00:00"
        langs    = list(set(seg.detected_language for seg in segments
                           if seg.detected_language != "English"))
        v = s.vitals
        result.append({
            "session_id":  s.id,
            "created_at":  s.created_at.isoformat(),
            "status":      s.status,
            "duration":    duration,
            "turn_count":  len(segments),
            "languages":   langs,
            "has_summary": summary is not None,
            "summary":     summary,
            "vitals": {
                "bp_systolic":  v.bp_systolic  if v else None,
                "bp_diastolic": v.bp_diastolic if v else None,
                "heart_rate":   v.heart_rate   if v else None,
                "spo2":         v.spo2         if v else None,
                "temperature":  v.temperature  if v else None,
                "weight":       v.weight       if v else None,
                "notes":        v.notes        if v else None,
            } if v else None,
            "prescriptions": [
                {"medicine": p.medicine, "dosage": p.dosage,
                 "frequency": p.frequency, "duration": p.duration,
                 "instructions": p.instructions}
                for p in s.prescriptions
            ],
            "segments": [{
                "speaker":           seg.speaker,
                "original_text":     seg.original_text,
                "english_text":      seg.english_text,
                "detected_language": seg.detected_language,
                "start_time":        seg.start_time,
                "end_time":          seg.end_time,
            } for seg in segments],
        })

    return {"patient_id": patient_id, "patient_name": p.name, "sessions": result}


# ──────────────────────────────────────────────────────────────
# CROSS-VISIT SUMMARY — Groq LLaMA analyzes ALL past sessions
# ──────────────────────────────────────────────────────────────
@app.post("/patients/{patient_id}/summary")
def get_patient_cross_summary(patient_id: int,
                               doctor: DoctorDB = Depends(get_current_doctor),
                               db: Session = Depends(get_db)):
    p = db.query(PatientDB).filter(PatientDB.id == patient_id,
                                   PatientDB.doctor_id == doctor.id).first()
    if not p:
        raise HTTPException(404, "Patient not found")

    sessions = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.patient_id == patient_id,
        ConsultationSessionDB.doctor_id == doctor.id,
    ).order_by(ConsultationSessionDB.created_at.asc()).all()

    if not sessions:
        raise HTTPException(400, "No consultation history found")

    # Build full history text with proper newlines
    history_lines = [f"Patient: {p.name}\n"]
    for i, s in enumerate(sessions):
        date = s.created_at.strftime("%d %b %Y")
        history_lines.append(f"\n=== VISIT {i+1} — {date} ===")
        if s.segments:
            for seg in s.segments:
                history_lines.append(f"{seg.speaker}: {seg.english_text}")
        else:
            history_lines.append("(No transcript available for this visit)")
        # Include prescriptions for this visit
        if s.prescriptions:
            history_lines.append("Prescriptions prescribed this visit:")
            for rx in s.prescriptions:
                line = f"  - {rx.medicine}"
                details = [x for x in [rx.dosage, rx.frequency, rx.duration, rx.instructions] if x]
                if details:
                    line += f" ({', '.join(details)})"
                history_lines.append(line)
    history_text = "\n".join(history_lines)

    print(f"[CrossSummary] Groq LLaMA — {len(sessions)} visits")
    summary_text = _groq_summarize_all_visits(p.name, history_text, len(sessions))
    print(f"[CrossSummary] Done.")

    return {
        "patient_id":   patient_id,
        "patient_name": p.name,
        "visit_count":  len(sessions),
        "summary":      summary_text,
    }


# ──────────────────────────────────────────────────────────────
# GROQ SUMMARY HELPERS
# ──────────────────────────────────────────────────────────────
def _groq_summarize_single(transcript: str, language: str,
                            duration: str, exchanges: int,
                            prescriptions: str = "") -> str:
    if not groq_client:
        return _fallback_summary(transcript, language, duration, exchanges)
    try:
        resp = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an expert medical scribe. Summarize the doctor-patient "
                        "consultation below clearly and concisely.\n"
                        "IMPORTANT: If prescriptions are provided, use those EXACT medications "
                        "in MEDICATIONS / TESTS — do NOT guess medications from the transcript.\n\n"
                        "Format your response EXACTLY like this:\n\n"
                        "CHIEF COMPLAINT:\n"
                        "KEY SYMPTOMS:\n"
                        "DOCTOR'S ADVICE:\n"
                        "MEDICATIONS / TESTS:\n"
                        "FOLLOW UP:\n\n"
                        f"(Language: {language} | Duration: {duration} | Turns: {exchanges})"
                    )
                },
                {
                    "role": "user",
                    "content": f"Transcript:\n{transcript}" + (f"\n\nPrescriptions added by doctor:\n{prescriptions}" if prescriptions else "")
                }
            ],
            temperature=0.3,
            max_tokens=1024,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        print(f"[Groq Summary] Failed: {e}")
        return _fallback_summary(transcript, language, duration, exchanges)


def _groq_summarize_all_visits(patient_name: str, history_text: str,
                                visit_count: int) -> str:
    if not groq_client:
        return f"Groq not configured. {visit_count} visits on record for {patient_name}."
    try:
        resp = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {
                    "role": "system",
                    "content": (
                        f"You are an expert medical assistant reviewing the complete "
                        f"consultation history of patient {patient_name} ({visit_count} visits). "
                        "Analyze all visits and provide a comprehensive medical summary.\n"
                        "IMPORTANT: For MEDICATIONS PRESCRIBED, use the exact prescriptions "
                        "listed in the history — do NOT guess medications from the dialogue.\n\n"
                        "Format your response EXACTLY like this:\n\n"
                        "PATIENT OVERVIEW:\n"
                        "ALL PAST COMPLAINTS:\n"
                        "(list each with visit number and date)\n\n"
                        "MEDICATIONS PRESCRIBED:\n"
                        "(all medications across all visits, from prescriptions provided)\n\n"
                        "DOCTOR'S ADVICE HISTORY:\n"
                        "FOLLOW-UP STATUS:\n"
                        "TRENDS / PATTERNS:\n"
                    )
                },
                {
                    "role": "user",
                    "content": history_text
                }
            ],
            temperature=0.3,
            max_tokens=2048,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        print(f"[Groq CrossSummary] Failed: {e}")
        return f"Summary generation failed: {str(e)}"


def _fallback_summary(transcript: str, language: str,
                       duration: str, exchanges: int) -> str:
    lines = transcript.split("\n")
    s1 = [l.split(":", 1)[1].strip() for l in lines
          if l.startswith("Speaker 1:") and ":" in l]
    s2 = [l.split(":", 1)[1].strip() for l in lines
          if l.startswith("Speaker 2:") and ":" in l]
    return (
        "CHIEF COMPLAINT:\n(Groq unavailable — manual review needed)\n\n"
        "SPEAKER 1 (Doctor):\n" + "\n".join(f"• {l}" for l in s1[:5])
        + "\n\nSPEAKER 2 (Patient):\n" + "\n".join(f"• {l}" for l in s2[:5])
        + f"\n\nLanguage: {language} | Duration: {duration} | Exchanges: {exchanges}"
    )


def _ms_to_ts(ms) -> str:
    try:
        t = int(float(ms)) // 1000
        return f"{t // 60:02d}:{t % 60:02d}"
    except Exception:
        return "00:00"


# ──────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────
# PDF HELPERS — shared across all PDF endpoints
# ──────────────────────────────────────────────────────────────
def _safe(text: str) -> str:
    if not text:
        return ""
    text = text.replace("\u2014", "-").replace("\u2013", "-")
    text = text.replace("\u2019", "'").replace("\u2018", "'")
    text = text.replace("\u201c", '"').replace("\u201d", '"')
    text = text.replace("\u2022", "*").replace("\u2026", "...")
    return text.encode("latin-1", errors="ignore").decode("latin-1")


def _pdf_header(pdf, title: str, subtitle: str = ""):
    from fpdf import FPDF
    # Blue top bar
    pdf.set_fill_color(26, 79, 196)
    pdf.rect(0, 0, 210, 22, "F")
    pdf.set_y(5)
    pdf.set_font("Helvetica", "B", 15)
    pdf.set_text_color(255, 255, 255)
    pdf.cell(0, 8, _safe(title), align="C", new_x="LMARGIN", new_y="NEXT")
    if subtitle:
        pdf.set_font("Helvetica", "", 9)
        pdf.set_text_color(200, 220, 255)
        pdf.cell(0, 5, _safe(subtitle), align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_y(26)
    pdf.set_text_color(0, 0, 0)
    pdf.ln(2)


def _pdf_patient_box(pdf, name: str, gender: str, phone: str, dob: str, date_str: str, doctor_name: str):
    # Light grey box
    pdf.set_fill_color(245, 247, 252)
    pdf.set_draw_color(220, 226, 245)
    y = pdf.get_y()
    pdf.rect(10, y, 190, 22, "FD")
    pdf.set_xy(14, y + 3)
    pdf.set_font("Helvetica", "B", 11)
    pdf.set_text_color(26, 79, 196)
    pdf.cell(90, 6, _safe(f"Patient: {name}"), new_x="RIGHT", new_y="TOP")
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(80, 80, 80)
    pdf.cell(90, 6, _safe(f"Dr. {doctor_name}  |  {date_str}"), align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_xy(14, y + 12)
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(80, 80, 80)
    pdf.cell(0, 5, _safe(f"{gender}  |  DOB: {dob}  |  Phone: {phone}"))
    pdf.set_y(y + 26)
    pdf.set_text_color(0, 0, 0)


def _pdf_section_header(pdf, title: str):
    pdf.ln(2)
    pdf.set_fill_color(235, 240, 255)
    pdf.set_draw_color(26, 79, 196)
    y = pdf.get_y()
    pdf.rect(10, y, 190, 8, "FD")
    pdf.set_xy(14, y + 1)
    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(26, 79, 196)
    pdf.cell(0, 6, _safe(title.upper()))
    pdf.set_y(y + 10)
    pdf.set_text_color(0, 0, 0)
    pdf.ln(1)


def _pdf_vitals_box(pdf, v):
    if not v or not any([v.bp_systolic, v.heart_rate, v.spo2, v.temperature, v.weight]):
        return
    _pdf_section_header(pdf, "Vitals")
    parts = []
    if v.bp_systolic and v.bp_diastolic:
        parts.append(("Blood Pressure", f"{v.bp_systolic}/{v.bp_diastolic} mmHg"))
    elif v.bp_systolic:
        parts.append(("Blood Pressure", f"{v.bp_systolic} mmHg"))
    if v.heart_rate:  parts.append(("Heart Rate",  f"{v.heart_rate} bpm"))
    if v.spo2:        parts.append(("SpO2",         f"{v.spo2}%"))
    if v.temperature: parts.append(("Temperature",  str(v.temperature)))
    if v.weight:      parts.append(("Weight",        f"{v.weight} kg"))

    # 2-column grid
    pdf.set_font("Helvetica", "", 10)
    for idx in range(0, len(parts), 2):
        pdf.set_x(14)
        label1, val1 = parts[idx]
        pdf.set_font("Helvetica", "B", 9)
        pdf.set_text_color(80, 80, 80)
        pdf.cell(35, 6, _safe(label1 + ":"))
        pdf.set_font("Helvetica", "", 10)
        pdf.set_text_color(0, 0, 0)
        pdf.cell(55, 6, _safe(val1))
        if idx + 1 < len(parts):
            label2, val2 = parts[idx + 1]
            pdf.set_font("Helvetica", "B", 9)
            pdf.set_text_color(80, 80, 80)
            pdf.cell(35, 6, _safe(label2 + ":"))
            pdf.set_font("Helvetica", "", 10)
            pdf.set_text_color(0, 0, 0)
            pdf.cell(55, 6, _safe(val2))
        pdf.ln(6)
    if v.notes:
        pdf.set_x(14)
        pdf.set_font("Helvetica", "I", 9)
        pdf.set_text_color(100, 100, 100)
        pdf.multi_cell(182, 5, _safe(f"Notes: {v.notes}"))
    pdf.ln(2)


def _pdf_prescriptions_table(pdf, rxs):
    if not rxs:
        return
    _pdf_section_header(pdf, "Prescription")
    # Table header
    pdf.set_fill_color(26, 79, 196)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 9)
    pdf.set_x(10)
    pdf.cell(5,  7, "#",           fill=True, border=1)
    pdf.cell(50, 7, "Medicine",    fill=True, border=1)
    pdf.cell(25, 7, "Dosage",      fill=True, border=1)
    pdf.cell(40, 7, "Frequency",   fill=True, border=1)
    pdf.cell(30, 7, "Duration",    fill=True, border=1)
    pdf.cell(40, 7, "Instructions",fill=True, border=1)
    pdf.ln()
    # Table rows
    for i, rx in enumerate(rxs):
        fill = i % 2 == 0
        pdf.set_fill_color(245, 247, 252) if fill else pdf.set_fill_color(255, 255, 255)
        pdf.set_text_color(0, 0, 0)
        pdf.set_font("Helvetica", "", 9)
        pdf.set_x(10)
        pdf.cell(5,  6, str(i+1),                        fill=fill, border=1)
        pdf.cell(50, 6, _safe(rx.medicine or ""),         fill=fill, border=1)
        pdf.cell(25, 6, _safe(rx.dosage or "-"),          fill=fill, border=1)
        pdf.cell(40, 6, _safe(rx.frequency or "-"),       fill=fill, border=1)
        pdf.cell(30, 6, _safe(rx.duration or "-"),        fill=fill, border=1)
        pdf.cell(40, 6, _safe(rx.instructions or "-"),    fill=fill, border=1)
        pdf.ln()
    pdf.ln(4)


def _pdf_summary_section(pdf, summary: str):
    _pdf_section_header(pdf, "Clinical Summary")
    lines = summary.split("\n")
    for line in lines:
        clean = _safe(line.strip())
        if not clean:
            pdf.ln(2)
            continue
        # Section headers like "CHIEF COMPLAINT:" etc.
        if clean.endswith(":") and len(clean) < 50:
            pdf.ln(1)
            pdf.set_font("Helvetica", "B", 10)
            pdf.set_text_color(26, 79, 196)
            pdf.set_x(10)
            pdf.cell(0, 6, clean, new_x="LMARGIN", new_y="NEXT")
            pdf.set_text_color(0, 0, 0)
        else:
            pdf.set_font("Helvetica", "", 10)
            pdf.set_text_color(30, 30, 30)
            pdf.set_x(14)
            pdf.multi_cell(182, 5, clean)
    pdf.ln(3)


def _pdf_transcript_section(pdf, segments):
    _pdf_section_header(pdf, "Consultation Transcript")
    for seg in segments:
        is_s1 = seg.speaker == "Speaker 1"
        # Speaker pill
        pdf.set_x(10)
        pdf.set_fill_color(26, 79, 196) if is_s1 else pdf.set_fill_color(180, 30, 100)
        pdf.set_text_color(255, 255, 255)
        pdf.set_font("Helvetica", "B", 8)
        spk_label = _safe(f"  {seg.speaker}  [{seg.start_time}-{seg.end_time}]  {seg.detected_language}  ")
        pdf.cell(len(spk_label) * 1.8, 5, spk_label, fill=True)
        pdf.ln(6)
        # Text
        pdf.set_x(14)
        pdf.set_font("Helvetica", "", 10)
        pdf.set_text_color(20, 20, 20)
        pdf.multi_cell(182, 5, _safe(seg.english_text))
        # Original if different
        if seg.original_text and seg.original_text != seg.english_text:
            pdf.set_x(14)
            pdf.set_font("Helvetica", "I", 8)
            pdf.set_text_color(130, 130, 130)
            pdf.multi_cell(182, 4, _safe(f"Original: {seg.original_text}"))
        pdf.ln(3)


def _pdf_footer(pdf, doctor_name: str, date_str: str):
    pdf.set_y(-15)
    pdf.set_draw_color(200, 200, 200)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.set_font("Helvetica", "I", 7)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 5,
        _safe(f"MediLingua  |  Dr. {doctor_name}  |  {date_str}  |  Confidential Medical Record"),
        align="C")


# ──────────────────────────────────────────────────────────────
# SESSION PDF — ?type=summary | transcript | full (default)
# ──────────────────────────────────────────────────────────────
@app.get("/sessions/{session_id}/pdf")
def download_session_pdf(session_id: str,
                          type: str = "full",
                          doctor: DoctorDB = Depends(get_current_doctor),
                          db: Session = Depends(get_db)):
    from fpdf import FPDF
    from fastapi.responses import StreamingResponse
    import io

    s = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.id == session_id,
        ConsultationSessionDB.doctor_id == doctor.id).first()
    if not s:
        raise HTTPException(404, "Session not found")

    patient  = s.patient
    summary  = s.summary.summary if s.summary else "No summary generated yet."
    date_str = s.created_at.strftime("%d %b %Y  %H:%M")
    v        = s.vitals
    rxs      = s.prescriptions

    type_label = {"summary": "Summary", "transcript": "Transcript", "full": "Full Report"}.get(type, "Full Report")
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=18)
    pdf.add_page()

    _pdf_header(pdf, f"MediLingua - Consultation {type_label}", date_str)
    _pdf_patient_box(pdf, patient.name, patient.gender, patient.phone,
                     patient.dob, date_str, doctor.name)
    pdf.ln(4)

    if type in ("summary", "full"):
        _pdf_vitals_box(pdf, v)
        _pdf_summary_section(pdf, summary)
        _pdf_prescriptions_table(pdf, rxs)

    if type in ("transcript", "full"):
        _pdf_transcript_section(pdf, s.segments)

    _pdf_footer(pdf, doctor.name, date_str)

    buf = io.BytesIO(pdf.output())
    fname = f"consultation_{patient.name.replace(' ','_')}_{type}_{s.created_at.strftime('%Y%m%d')}.pdf"
    return StreamingResponse(buf, media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={fname}"})


# ──────────────────────────────────────────────────────────────
# ALL VISITS PDF — ?type=summary | transcript | full (default)
# ──────────────────────────────────────────────────────────────
@app.get("/patients/{patient_id}/summary/pdf")
def download_all_visits_pdf(patient_id: int,
                              type: str = "full",
                              doctor: DoctorDB = Depends(get_current_doctor),
                              db: Session = Depends(get_db)):
    from fpdf import FPDF
    from fastapi.responses import StreamingResponse
    import io

    p = db.query(PatientDB).filter(PatientDB.id == patient_id,
                                   PatientDB.doctor_id == doctor.id).first()
    if not p:
        raise HTTPException(404, "Patient not found")

    sessions = db.query(ConsultationSessionDB).filter(
        ConsultationSessionDB.patient_id == patient_id,
        ConsultationSessionDB.doctor_id == doctor.id,
    ).order_by(ConsultationSessionDB.created_at.asc()).all()

    if not sessions:
        raise HTTPException(400, "No sessions found")

    date_str    = datetime.datetime.now().strftime("%d %b %Y  %H:%M")
    type_label  = {"summary": "Summary", "transcript": "Transcripts", "full": "Full History"}.get(type, "Full History")

    # Build cross-visit summary text
    history_lines = [f"Patient: {p.name}\n"]
    for i, s in enumerate(sessions):
        date = s.created_at.strftime("%d %b %Y")
        history_lines.append(f"\n=== VISIT {i+1} - {date} ===")
        for seg in s.segments:
            history_lines.append(f"{seg.speaker}: {seg.english_text}")
        if s.prescriptions:
            history_lines.append("Prescriptions:")
            for rx in s.prescriptions:
                line = f"  - {rx.medicine}"
                details = [x for x in [rx.dosage, rx.frequency, rx.duration, rx.instructions] if x]
                if details:
                    line += f" ({', '.join(details)})"
                history_lines.append(line)
    history_text  = "\n".join(history_lines)
    cross_summary = _groq_summarize_all_visits(p.name, history_text, len(sessions))

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=18)
    pdf.add_page()

    _pdf_header(pdf, f"MediLingua - Patient History {type_label}",
                f"{p.name}  |  {len(sessions)} Visits  |  {date_str}")
    _pdf_patient_box(pdf, p.name, p.gender, p.phone, p.dob, date_str, doctor.name)
    pdf.ln(4)

    # Combined cross-visit summary (always shown for summary + full)
    if type in ("summary", "full"):
        _pdf_summary_section(pdf, cross_summary)

    # For summary type — also show vitals + prescriptions per visit (no transcripts)
    # For transcript type — show transcripts only
    # For full — show everything per visit
    if type == "summary":
        # Just the combined summary — no per-visit breakdown needed
        pass

    elif type in ("transcript", "full"):
        # Per-visit details
        for i, s in enumerate(sessions):
            visit_date = s.created_at.strftime("%d %b %Y  %H:%M")

            # Visit divider
            pdf.ln(2)
            pdf.set_fill_color(26, 79, 196)
            pdf.set_text_color(255, 255, 255)
            pdf.set_font("Helvetica", "B", 10)
            pdf.set_x(10)
            pdf.cell(190, 7, _safe(f"  Visit {i+1}  -  {visit_date}"),
                     fill=True, new_x="LMARGIN", new_y="NEXT")
            pdf.set_text_color(0, 0, 0)
            pdf.ln(2)

            if type == "full":
                _pdf_vitals_box(pdf, s.vitals)
                if s.summary:
                    _pdf_summary_section(pdf, s.summary.summary)
                _pdf_prescriptions_table(pdf, s.prescriptions)

            if s.segments:
                _pdf_transcript_section(pdf, s.segments)
            else:
                pdf.set_font("Helvetica", "I", 9)
                pdf.set_text_color(130, 130, 130)
                pdf.set_x(14)
                pdf.cell(0, 6, "No transcript available for this visit.",
                         new_x="LMARGIN", new_y="NEXT")
            pdf.ln(4)

    _pdf_footer(pdf, doctor.name, date_str)

    buf   = io.BytesIO(pdf.output())
    fname = f"history_{p.name.replace(' ','_')}_{type}.pdf"
    return StreamingResponse(buf, media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={fname}"})