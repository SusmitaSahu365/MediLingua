import 'dart:io';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class EditDoctorProfilePage extends StatefulWidget {
  final Doctor doctor;
  const EditDoctorProfilePage({super.key, required this.doctor});

  @override
  State<EditDoctorProfilePage> createState() => _EditDoctorProfilePageState();
}

class _EditDoctorProfilePageState extends State<EditDoctorProfilePage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _specCtrl;
  late final TextEditingController _phoneCtrl;
  final TextEditingController _currPassCtrl = TextEditingController();
  final TextEditingController _newPassCtrl  = TextEditingController();
  final TextEditingController _confPassCtrl = TextEditingController();

  File?   _imageFile;
  bool    _saving          = false;
  bool    _showPassSection = false;
  bool    _obscureCurr     = true;
  bool    _obscureNew      = true;
  bool    _obscureConf     = true;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.doctor.name);
    _specCtrl  = TextEditingController(text: widget.doctor.specialization);
    _phoneCtrl = TextEditingController(text: widget.doctor.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _specCtrl.dispose(); _phoneCtrl.dispose();
    _currPassCtrl.dispose(); _newPassCtrl.dispose(); _confPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(100))),
          const Text('Choose Photo', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded,
                color: AppColors.primary),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded,
                color: AppColors.primary),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (_imageFile != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text('Remove Photo',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                setState(() => _imageFile = null);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
        source: source, imageQuality: 80, maxWidth: 400);
    if (picked != null && mounted) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; _success = null; });

    // Validate password if changing
    if (_showPassSection && _newPassCtrl.text.isNotEmpty) {
      if (_currPassCtrl.text.isEmpty) {
        setState(() { _error = 'Enter your current password'; _saving = false; });
        return;
      }
      if (_newPassCtrl.text != _confPassCtrl.text) {
        setState(() { _error = 'New passwords do not match'; _saving = false; });
        return;
      }
      if (_newPassCtrl.text.length < 6) {
        setState(() { _error = 'New password must be at least 6 characters'; _saving = false; });
        return;
      }
    }

    try {
      await ApiService.updateDoctor(
        name:            _nameCtrl.text.trim(),
        specialization:  _specCtrl.text.trim(),
        phone:           _phoneCtrl.text.trim(),
        currentPassword: _showPassSection && _newPassCtrl.text.isNotEmpty
            ? _currPassCtrl.text : null,
        newPassword:     _showPassSection && _newPassCtrl.text.isNotEmpty
            ? _newPassCtrl.text : null,
      );
      setState(() => _success = 'Profile updated successfully');
      // Pop with updated doctor so caller can refresh
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context, ApiService.currentDoctor);
      });
      // Clear password fields
      _currPassCtrl.clear(); _newPassCtrl.clear(); _confPassCtrl.clear();
      setState(() => _showPassSection = false);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
              ),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [

          // ── Avatar with image picker ───────────────────
          Center(
            child: Column(children: [
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!) as ImageProvider
                          : null,
                      child: _imageFile == null
                          ? Text(
                              widget.doctor.name.isNotEmpty
                                  ? widget.doctor.name[0].toUpperCase()
                                  : 'D',
                              style: const TextStyle(fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary))
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Tap to change photo',
                  style: TextStyle(fontSize: 12,
                      color: AppColors.textSecondary.withOpacity(0.7))),
              const SizedBox(height: 2),
              Text(widget.doctor.email,
                  style: const TextStyle(fontSize: 13,
                      color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 28),

          // ── Feedback ───────────────────────────────────
          if (_error != null)
            _FeedbackBanner(message: _error!, isError: true,
                onClose: () => setState(() => _error = null)),
          if (_success != null)
            _FeedbackBanner(message: _success!, isError: false,
                onClose: () => setState(() => _success = null)),

          // ── Basic info ─────────────────────────────────
          _SectionHeader(label: 'Basic Information'),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _specCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Specialization',
              prefixIcon: Icon(Icons.medical_services_outlined),
              hintText: 'e.g. General Physician, Cardiologist',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 28),

          // ── Change password toggle ─────────────────────
          InkWell(
            onTap: () => setState(
                () => _showPassSection = !_showPassSection),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _showPassSection
                    ? AppColors.primary
                    : AppColors.border),
              ),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded,
                    color: _showPassSection
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Change Password',
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                Icon(
                  _showPassSection
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                ),
              ]),
            ),
          ),

          // ── Password fields ────────────────────────────
          if (_showPassSection) ...[
            const SizedBox(height: 14),
            _SectionHeader(label: 'Change Password'),
            const SizedBox(height: 12),
            TextField(
              controller: _currPassCtrl,
              obscureText: _obscureCurr,
              decoration: InputDecoration(
                labelText: 'Current Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurr
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () =>
                      setState(() => _obscureCurr = !_obscureCurr),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _newPassCtrl,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New Password',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () =>
                      setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confPassCtrl,
              obscureText: _obscureConf,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConf
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () =>
                      setState(() => _obscureConf = !_obscureConf),
                ),
              ),
            ),
          ],

          const SizedBox(height: 40),

          // ── Save button ────────────────────────────────
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Logout button ──────────────────────────────
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Log Out'),
                    content: const Text(
                        'Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.error),
                          child: const Text('Log Out')),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await ApiService.logout();
                  // Navigate to login, clear all routes
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text('Log Out',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3));
}

class _FeedbackBanner extends StatelessWidget {
  final String       message;
  final bool         isError;
  final VoidCallback onClose;
  const _FeedbackBanner({
    required this.message,
    required this.isError,
    required this.onClose,
  });
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (isError ? AppColors.error : AppColors.success)
              .withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: (isError ? AppColors.error : AppColors.success)
                  .withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 16,
              color: isError ? AppColors.error : AppColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text(message,
              style: TextStyle(fontSize: 13,
                  color: isError ? AppColors.error : AppColors.success))),
          GestureDetector(onTap: onClose,
              child: Icon(Icons.close, size: 16,
                  color: isError ? AppColors.error : AppColors.success)),
        ]),
      );
}