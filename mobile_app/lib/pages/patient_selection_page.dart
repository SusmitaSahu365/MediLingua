import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'patient_profile_page.dart';
import 'edit_doctor_profile_page.dart';

class PatientSelectionPage extends StatefulWidget {
  final Doctor doctor;
  const PatientSelectionPage({super.key, required this.doctor});

  @override
  State<PatientSelectionPage> createState() => _PatientSelectionPageState();
}

class _PatientSelectionPageState extends State<PatientSelectionPage> {
  final _searchCtrl = TextEditingController();
  String        _query    = '';
  List<Patient> _patients = [];
  bool          _loading  = true;
  String?       _error;
  late Doctor   _doctor;  // mutable so profile edits reflect immediately

  @override
  void initState() {
    super.initState();
    _doctor = widget.doctor;
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await ApiService.getPatients();
      setState(() { _patients = list; _loading = false; });
    } catch (e) {
      setState(() {
        _error   = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<Patient> get _filtered => _patients
      .where((p) =>
          p.name.toLowerCase().contains(_query.toLowerCase()) ||
          p.phone.contains(_query))
      .toList();

  // ── Add patient ───────────────────────────────────────────
  void _showAddPatient() {
    final nameCtrl    = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final addressCtrl = TextEditingController();
    final dobCtrl     = TextEditingController();
    String  gender    = 'Male';
    bool    saving    = false;
    String? sheetErr;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(
          builder: (context, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.border,
                    borderRadius: BorderRadius.circular(100)),
              )),
              Row(children: [
                const Text('Add New Patient', style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 16),
              TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number')),
              const SizedBox(height: 12),
              // DOB
              TextField(
                controller: dobCtrl, readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  suffixIcon: Icon(Icons.calendar_today_outlined,
                      color: AppColors.textSecondary),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(1990),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    dobCtrl.text =
                        '${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
                  }
                },
              ),
              const SizedBox(height: 12),
              // Gender
              Row(children: ['Male','Female','Other'].map((g) {
                final sel = gender == g;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setS(() => gender = g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                            width: 1.5),
                      ),
                      child: Text(g, style: TextStyle(
                          color: sel ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                    ),
                  ),
                );
              }).toList()),
              const SizedBox(height: 12),
              TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address')),
              if (sheetErr != null) ...[
                const SizedBox(height: 8),
                Text(sheetErr!, style: const TextStyle(
                    color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (nameCtrl.text.trim().isEmpty ||
                        phoneCtrl.text.trim().isEmpty ||
                        dobCtrl.text.isEmpty) {
                      setS(() => sheetErr =
                          'Please fill name, phone and date of birth');
                      return;
                    }
                    setS(() { saving = true; sheetErr = null; });
                    try {
                      final p = await ApiService.createPatient(Patient(
                        patientId: 0,
                        name:      nameCtrl.text.trim(),
                        dob:       dobCtrl.text,
                        gender:    gender,
                        phone:     phoneCtrl.text.trim(),
                        address:   addressCtrl.text.trim(),
                      ));
                      setState(() => _patients.insert(0, p));
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setS(() {
                        sheetErr = e.toString().replaceAll('Exception: ', '');
                        saving   = false;
                      });
                    }
                  },
                  child: saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Register Patient'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Doctor initials
    final initials = _doctor.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('Select Patient'),
          Text(_doctor.name,
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () async {
                final updated = await Navigator.push<Doctor>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditDoctorProfilePage(doctor: _doctor),
                  ),
                );
                // Reflect profile changes immediately
                if (updated != null && mounted) {
                  setState(() => _doctor = updated);
                }
              },
              child: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                child: Text(initials,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
          ),
        ],
      ),

      body: Column(children: [
        // Search bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search by name or phone...',
              prefixIcon: Icon(Icons.search_rounded,
                  color: AppColors.textSecondary),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary))
              : _error != null
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _load,
                            child: const Text('Retry')),
                      ]))
                  : _filtered.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_rounded,
                                size: 56,
                                color: AppColors.textSecondary
                                    .withOpacity(0.3)),
                            const SizedBox(height: 12),
                            Text(
                              _query.isEmpty
                                  ? 'No patients yet.\nTap + Add Patient to register one.'
                                  : 'No patients found for "$_query"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.5)),
                          ]))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _PatientCard(
                              patient: _filtered[i],
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PatientProfilePage(
                                      doctor: _doctor,
                                      patient: _filtered[i],
                                    ),
                                  ),
                                );
                                // Refresh list in case patient was edited/deleted
                                _load();
                              },
                            ),
                          ),
                        ),
        ),
      ]),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPatient,
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('Add Patient',
            style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}

// ── Patient card ───────────────────────────────────────────────
class _PatientCard extends StatelessWidget {
  final Patient      patient;
  final VoidCallback onTap;
  const _PatientCard({required this.patient, required this.onTap});

  Color get _color {
    const colors = [
      Color(0xFF1A4FC4), Color(0xFFAD1457), Color(0xFF0F7A6B),
      Color(0xFF6A1B9A), Color(0xFF1565C0),
    ];
    return colors[patient.name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(patient.initials,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 18))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.name, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16,
                    color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('${patient.gender} · ${patient.age} · ${patient.phone}',
                    style: const TextStyle(fontSize: 13,
                        color: AppColors.textSecondary)),
                if (patient.address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    Expanded(child: Text(patient.address,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12,
                            color: AppColors.textSecondary))),
                  ]),
                ],
              ],
            )),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ]),
        ),
      );
}