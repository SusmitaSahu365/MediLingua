"""
MediLingua Backend — FastAPI + AssemblyAI Prerecorded
Transcription + Diarization (Speaker A/B) in one simple API call
"""

from dotenv import load_dotenv
load_dotenv()

import os
import uuid
import datetime
import tempfile
from typing import Optional

import assemblyai as aai

from fastapi import FastAPI, HTTPException, Depends, status, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import jwt
from passlib.context import CryptContext
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, Session, relationship
from contextlib import asynccontextmanager

# ──────────────────────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────────────────────
DATABASE_URL         = "sqlite:///./medilingua.db"
SECRET_KEY           = os.getenv("SECRET_KEY", "CHANGE_ME_IN_PROD_USE_32chars!!")
ALGORITHM            = "HS256"
TOKEN_EXPIRE_MINUTES = 60 * 24
ASSEMBLYAI_API_KEY   = os.getenv("ASSEMBLYAI_API_KEY", "")

# ──────────────────────────────────────────────────────────────
# DATABASE
# ──────────────────────────────────────────────────────────────
engine       = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base         = declarative_base()


class DoctorDB(Base):
    __tablename__ = "doctors"
    id              = Column(Integer, primary_key=True, index=True)
    name            = Column(String, nullable=False)
    specialization  = Column(String, default="General Physician")
    email           = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
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
    summary = relationship("ClinicalSummaryDB", back_populates="session", uselist=False)


class TranscriptSegmentDB(Base):
    __tablename__ = "transcript_segments"
    id                = Column(Integer, primary_key=True, autoincrement=True)
    session_id        = Column(String, ForeignKey("consultation_sessions.id"))
    speaker           = Column(String, default="Speaker 1")
    text              = Column(Text, default="")
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
pwd_context   = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def hash_password(pw: str) -> str:
    return pwd_context.hash(pw[:72].encode("utf-8"))


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain[:72].encode("utf-8"), hashed)


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
# APP
# ──────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    if not ASSEMBLYAI_API_KEY:
        print("[MediLingua] WARNING: ASSEMBLYAI_API_KEY not set in .env!")
    else:
        aai.settings.api_key = ASSEMBLYAI_API_KEY
        print("[MediLingua] AssemblyAI ready.")
    yield


app = FastAPI(title="MediLingua API", version="5.0.0", lifespan=lifespan)
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


class PatientCreate(BaseModel):
    name: str
    dob: str
    gender: str
    phone: str
    address: Optional[str] = ""


class SessionCreateRequest(BaseModel):
    patient_id: int


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
                         specialization=doc.specialization, email=doc.email)


@app.post("/auth/login", response_model=TokenResponse)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    doc = db.query(DoctorDB).filter(DoctorDB.email == form.username).first()
    if not doc or not verify_password(form.password, doc.hashed_password):
        raise HTTPException(401, "Invalid email or password")
    return TokenResponse(access_token=create_access_token({"sub": str(doc.id)}),
                         doctor_id=doc.id, name=doc.name,
                         specialization=doc.specialization, email=doc.email)


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
    return [{"speaker": seg.speaker, "text": seg.text,
             "detected_language": seg.detected_language,
             "start_time": seg.start_time, "end_time": seg.end_time}
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


# ──────────────────────────────────────────────────────────────
# TRANSCRIBE — AssemblyAI prerecorded with diarization
# One API call → transcription + Speaker A/B labels + timestamps
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

    # Save audio to temp file
    audio_bytes = await audio.read()
    suffix      = ".wav" if (audio.filename or "").endswith(".wav") else ".m4a"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    print(f"[AssemblyAI] {len(audio_bytes)/1024:.1f}KB audio received")

    try:
        # ── AssemblyAI transcribe with diarization ────────────
        config     = aai.TranscriptionConfig(
            speaker_labels=True,
            speakers_expected=2,
            punctuate=True,
            format_text=True,
            speech_models=["universal-2"],
            language_detection=True,
        )
        transcriber = aai.Transcriber()
        transcript  = transcriber.transcribe(tmp_path, config)

        if transcript.status == aai.TranscriptStatus.error:
            raise HTTPException(500, f"AssemblyAI error: {transcript.error}")

        print(f"[AssemblyAI] Done — {len(transcript.utterances or [])} utterances")

        # Clear old segments
        db.query(TranscriptSegmentDB).filter_by(session_id=session_id).delete()

        out         = []
        speaker_map = {}   # "A" → "Speaker 1", "B" → "Speaker 2"
        counter     = 1

        for utt in (transcript.utterances or []):
            raw = utt.speaker  # "A" or "B"
            if raw not in speaker_map:
                speaker_map[raw] = f"Speaker {counter}"
                counter += 1
            speaker  = speaker_map[raw]
            text     = utt.text.strip()
            if not text:
                continue

            start_ts = _ms_to_ts(utt.start)
            end_ts   = _ms_to_ts(utt.end)

            db.add(TranscriptSegmentDB(
                session_id=session_id,
                speaker=speaker,
                text=text,
                detected_language="English",
                start_time=start_ts,
                end_time=end_ts,
            ))
            out.append({
                "speaker": speaker,
                "text": text,
                "detected_language": "English",
                "start_time": start_ts,
                "end_time": end_ts,
            })

        db.commit()
        print(f"[AssemblyAI] Saved {len(out)} segments. Speakers: {list(speaker_map.values())}")
        return {"segments": out, "speakers": list(speaker_map.values())}

    except HTTPException:
        raise
    except Exception as e:
        print(f"[AssemblyAI] Error: {e}")
        raise HTTPException(500, f"Transcription failed: {str(e)}")
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass


# ──────────────────────────────────────────────────────────────
# SUMMARY — uses AssemblyAI LeMUR (Claude-powered) on demand
# Only called when doctor taps the Summary button
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

    # Build transcript text with speaker labels
    input_text = ""
    for seg in s.segments:
        input_text += f"Speaker {seg.speaker}:\n{seg.text}\n"

    language  = s.segments[0].detected_language if s.segments else "Unknown"
    duration  = s.segments[-1].end_time if s.segments else "00:00"
    exchanges = len(s.segments)

    print(f"[Summary] Calling LeMUR for {exchanges} turns...")

    try:
        result = aai.Lemur().task(
            "You are a medical scribe. Summarize this doctor-patient consultation.\n"
            "Format as:\nCHIEF COMPLAINT:\nKEY SYMPTOMS:\nDOCTOR'S ADVICE:\nMEDICATIONS / TESTS:\nFOLLOW UP:",
            input_text=input_text,
            final_model=aai.LemurModel.claude3_5_sonnet,
        )
        summary_text = result.response.strip()
        print(f"[Summary] Done.")
    except Exception as e:
        print(f"[Summary] LeMUR failed: {e} — using fallback")
        s1 = [seg.text for seg in s.segments if "1" in seg.speaker]
        s2 = [seg.text for seg in s.segments if "2" in seg.speaker]
        summary_text = (
            f"SPEAKER 1:\n" + "\n".join(f"• {l}" for l in s1)
            + f"\n\nSPEAKER 2:\n" + "\n".join(f"• {l}" for l in s2)
            + f"\n\nLanguage: {language} | Duration: {duration} | Exchanges: {exchanges}"
        )

    existing = db.query(ClinicalSummaryDB).filter_by(session_id=session_id).first()

# ──────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────
def _ms_to_ts(ms) -> str:
    try:
        t = int(float(ms)) // 1000
        return f"{t // 60:02d}:{t % 60:02d}"
    except Exception:
        return "00:00"