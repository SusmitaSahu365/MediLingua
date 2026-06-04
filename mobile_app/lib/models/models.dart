class Doctor {
  final int    doctorId;
  final String name;
  final String specialization;
  final String email;
  final String phone;
  final String? token;

  Doctor({
    required this.doctorId,
    required this.name,
    required this.specialization,
    required this.email,
    required this.phone,
    this.token,
  });

  factory Doctor.fromJson(Map<String, dynamic> j) => Doctor(
        doctorId:       j['doctor_id'] ?? 0,
        name:           j['name'] ?? '',
        specialization: j['specialization'] ?? 'General Physician',
        email:          j['email'] ?? '',
        phone:          j['phone'] ?? '',
        token:          j['access_token'],
      );

  Doctor copyWith({String? name, String? specialization, String? phone}) =>
      Doctor(
        doctorId:       doctorId,
        name:           name ?? this.name,
        specialization: specialization ?? this.specialization,
        email:          email,
        phone:          phone ?? this.phone,
        token:          token,
      );
}

class Patient {
  final int    patientId;
  final String name;
  final String dob;
  final String gender;
  final String phone;
  final String address;

  Patient({
    required this.patientId,
    required this.name,
    required this.dob,
    required this.gender,
    required this.phone,
    required this.address,
  });

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
        patientId: j['patient_id'],
        name:      j['name'],
        dob:       j['dob'],
        gender:    j['gender'],
        phone:     j['phone'],
        address:   j['address'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name, 'dob': dob, 'gender': gender,
        'phone': phone, 'address': address,
      };

  String get age {
    final birth = DateTime.tryParse(dob);
    if (birth == null) return 'N/A';
    final now = DateTime.now();
    int a = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) a--;
    return '$a yrs';
  }

  String get initials => name
      .split(' ')
      .take(2)
      .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
      .join();
}

class TranscriptSegment {
  final String speaker;
  final String originalText;
  final String englishText;
  final String startTime;
  final String endTime;
  final String detectedLanguage;

  TranscriptSegment({
    required this.speaker,
    required this.originalText,
    required this.englishText,
    required this.startTime,
    required this.endTime,
    required this.detectedLanguage,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> j) =>
      TranscriptSegment(
        speaker:          j['speaker'] ?? 'Speaker 1',
        originalText:     j['original_text'] ?? '',
        englishText:      j['english_text'] ?? '',
        startTime:        j['start_time'] ?? '00:00',
        endTime:          j['end_time'] ?? '00:00',
        detectedLanguage: j['detected_language'] ?? 'English',
      );
}

class Consultation {
  final int                     consultationId;
  final Patient                 patient;
  final DateTime                visitDate;
  final List<TranscriptSegment> segments;
  final String?                 summary;
  final String                  sessionId;

  Consultation({
    required this.consultationId,
    required this.patient,
    required this.visitDate,
    required this.segments,
    required this.sessionId,
    this.summary,
  });
}

class Prescription {
  final String medicineName;
  final String dosage;
  final String duration;
  final String instructions;

  Prescription({
    required this.medicineName,
    required this.dosage,
    required this.duration,
    required this.instructions,
  });
}