import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'patient_selection_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _specCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePw = true, _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _specCtrl,
      _pwCtrl,
      _confirmCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doctor = await ApiService.signup(
        name: _nameCtrl.text.trim(),
        specialization: _specCtrl.text.trim().isEmpty
            ? 'General Physician'
            : _specCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (_) => PatientSelectionPage(doctor: doctor)),
          (_) => false);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: const BackButton(color: AppColors.textPrimary)),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primary.withOpacity(0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6))
                          ],
                        ),
                        child: const Icon(Icons.medical_services_rounded,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MediLingua',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary)),
                            Text('Doctor Registration',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary)),
                          ]),
                    ]),
                    const SizedBox(height: 28),
                    const Text('Create Account',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4)),
                    const SizedBox(height: 4),
                    const Text('Register to start using MediLingua',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary)),
                    const SizedBox(height: 28),
                    _label('Full Name'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter full name' : null,
                      decoration: const InputDecoration(
                        hintText: 'Dr. Priya Sharma',
                        prefixIcon: Icon(Icons.person_outline_rounded,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Email Address'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          (v == null || !v.contains('@'))
                              ? 'Enter valid email'
                              : null,
                      decoration: const InputDecoration(
                        hintText: 'doctor@hospital.com',
                        prefixIcon: Icon(Icons.email_outlined,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Phone Number'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      validator: (v) =>
                          (v == null || v.trim().length < 10)
                              ? 'Enter valid phone'
                              : null,
                      decoration: const InputDecoration(
                        hintText: '9876543210',
                        prefixIcon: Icon(Icons.phone_outlined,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Specialization (optional)'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _specCtrl,
                      decoration: const InputDecoration(
                        hintText: 'e.g. General Physician',
                        prefixIcon: Icon(Icons.local_hospital_outlined,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Password'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _pwCtrl,
                      obscureText: _obscurePw,
                      validator: (v) =>
                          (v == null || v.length < 6)
                              ? 'Minimum 6 characters'
                              : null,
                      decoration: InputDecoration(
                        hintText: 'Min 6 characters',
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: AppColors.textSecondary),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscurePw
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textSecondary),
                          onPressed: () =>
                              setState(() => _obscurePw = !_obscurePw),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Confirm Password'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscureConfirm,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Confirm your password';
                        if (v != _pwCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: 'Re-enter password',
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: AppColors.textSecondary),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textSecondary),
                          onPressed: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.error, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.error, fontSize: 13))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _signup,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : const Text('Create Account'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Already have an account? ',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text('Login',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary));
}