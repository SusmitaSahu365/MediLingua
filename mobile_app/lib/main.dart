import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/login_page.dart';
import 'pages/patient_selection_page.dart';
import 'services/api_service.dart';

void main() => runApp(const MediLinguaApp());

class MediLinguaApp extends StatelessWidget {
  const MediLinguaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MediLingua',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const _SplashRouter(),
      );
}

class _SplashRouter extends StatefulWidget {
  const _SplashRouter();
  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final doctor = await ApiService.tryRestoreSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => doctor != null
            ? PatientSelectionPage(doctor: doctor)
            : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.medical_services_rounded,
                    size: 44, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              const Text('MediLingua',
                  style: TextStyle(fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
              const SizedBox(height: 8),
              const Text('Clinical Dialogue System',
                  style: TextStyle(fontSize: 14,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: AppColors.primary),
            ],
          ),
        ),
      );
}