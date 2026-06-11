import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ApiService {
   static const String baseUrl   = 'http://100.113.210.35:8000';
  static const String wsBaseUrl = 'ws://100.113.210.35:8000';

  static String? _token;
  static Doctor? _currentDoctor;

  static String? get token         => _token;
  static Doctor? get currentDoctor => _currentDoctor;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ── Persist session ───────────────────────────────────────
  static Future<void> _saveSession(Doctor doctor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', doctor.token ?? '');
    await prefs.setString('doctor_data', jsonEncode({
      'doctor_id':      doctor.doctorId,
      'name':           doctor.name,
      'specialization': doctor.specialization,
      'email':          doctor.email,
      'phone':          doctor.phone,
      'access_token':   doctor.token,
      'token_type':     'bearer',
    }));
    _token         = doctor.token;
    _currentDoctor = doctor;
  }

  static Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('doctor_data');
    _token         = null;
    _currentDoctor = null;
  }

  // ── Try restore session on app start ─────────────────────
  static Future<Doctor?> tryRestoreSession() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final token  = prefs.getString('token');
      final docStr = prefs.getString('doctor_data');
      if (token == null || token.isEmpty || docStr == null) return null;

      // Verify token still valid
      final res = await http.get(
        Uri.parse('$baseUrl/patients'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        _token         = token;
        _currentDoctor = Doctor.fromJson(jsonDecode(docStr));
        return _currentDoctor;
      }
      await _clearSession();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Auth ──────────────────────────────────────────────────
  static Future<Doctor> signup({
    required String name,
    required String specialization,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name, 'specialization': specialization,
        'email': email, 'password': password,
      }),
    );
    if (res.statusCode == 200) {
      final doctor = Doctor.fromJson(jsonDecode(res.body));
      await _saveSession(doctor);
      return doctor;
    }
    throw Exception(jsonDecode(res.body)['detail'] ?? 'Signup failed');
  }

  static Future<Doctor> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (res.statusCode == 200) {
      final doctor = Doctor.fromJson(jsonDecode(res.body));
      await _saveSession(doctor);
      return doctor;
    }
    throw Exception(jsonDecode(res.body)['detail'] ?? 'Login failed');
  }

  static Future<void> logout() async => await _clearSession();

  // ── Doctor profile ────────────────────────────────────────
  static Future<Doctor> updateDoctor({
    String? name,
    String? specialization,
    String? phone,
    String? currentPassword,
    String? newPassword,
  }) async {
    final body = <String, dynamic>{};
    if (name != null)           body['name']             = name;
    if (specialization != null) body['specialization']   = specialization;
    if (phone != null)          body['phone']            = phone;
    if (newPassword != null) {
      body['new_password']     = newPassword;
      body['current_password'] = currentPassword;
    }
    final res = await http.put(
      Uri.parse('$baseUrl/auth/me'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      final updated = Doctor.fromJson({
        ...jsonDecode(res.body),
        'access_token': _token,
      });
      await _saveSession(updated);
      return updated;
    }
    throw Exception(jsonDecode(res.body)['detail'] ?? 'Update failed');
  }

  // ── Patients ──────────────────────────────────────────────
  static Future<List<Patient>> getPatients() async {
    final res = await http.get(
        Uri.parse('$baseUrl/patients'), headers: _headers);
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List)
          .map((e) => Patient.fromJson(e))
          .toList();
    }
    throw Exception('Failed to load patients');
  }

  static Future<Patient> createPatient(Patient patient) async {
    final res = await http.post(
      Uri.parse('$baseUrl/patients'),
      headers: _headers,
      body: jsonEncode(patient.toJson()),
    );
    if (res.statusCode == 200) return Patient.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to create patient');
  }

  static Future<Patient> updatePatient(Patient patient) async {
    final res = await http.put(
      Uri.parse('$baseUrl/patients/${patient.patientId}'),
      headers: _headers,
      body: jsonEncode(patient.toJson()),
    );
    if (res.statusCode == 200) return Patient.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to update patient');
  }

  static Future<void> deletePatient(int patientId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/patients/$patientId'),
      headers: _headers,
    );
    if (res.statusCode != 204) throw Exception('Failed to delete patient');
  }

  // ── Sessions ──────────────────────────────────────────────
  static Future<String> createSession(int patientId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/sessions'),
      headers: _headers,
      body: jsonEncode({'patient_id': patientId}),
    );
    if (res.statusCode == 200) return jsonDecode(res.body)['session_id'];
    throw Exception('Failed to create session');
  }

  static Future<void> deleteSession(String sessionId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/sessions/$sessionId'),
      headers: _headers,
    );
    if (res.statusCode != 204) throw Exception('Failed to delete session');
  }

  static Future<List<TranscriptSegment>> getTranscript(String sessionId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/sessions/$sessionId/transcript'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List)
          .map((e) => TranscriptSegment.fromJson(e))
          .toList();
    }
    throw Exception('Failed to load transcript');
  }

  static Future<String> generateSummary(String sessionId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/sessions/$sessionId/summary'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body)['summary'];
    throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to generate summary');
  }

  static Future<void> endSession(String sessionId) async {
    await http.post(
      Uri.parse('$baseUrl/sessions/$sessionId/end'),
      headers: _headers,
    );
  }

  static String wsUrl(String sessionId) =>
      '$wsBaseUrl/ws/audio/$sessionId?token=${_token ?? ''}';
}