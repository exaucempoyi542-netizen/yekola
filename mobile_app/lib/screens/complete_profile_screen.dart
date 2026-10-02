import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'dashboard_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  static const Color _primary = Color(0xFF152A45);
  static const Color _bg = Color(0xFFEEF1F6);
  static const Color _border = Color(0xFFD0D7E2);
  static const Color _muted = Color(0xFF5A6578);
  static const Color _ink = Color(0xFF0F172A);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.completeProfile(_emailController.text);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.lastError ??
                'Impossible d\'enregistrer votre Gmail. Réessayez.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.mail_outline, size: 56, color: _primary),
                      const SizedBox(height: 16),
                      const Text(
                        'Compléter votre profil',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Votre compte a été créé par le décanat. '
                        'Ajoutez votre adresse Gmail pour finaliser votre profil '
                        'et accéder à toutes les fonctionnalités.',
                        style: TextStyle(fontSize: 14, color: _muted, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Adresse Gmail',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _isLoading ? null : _submit(),
                        decoration: InputDecoration(
                          hintText: 'exemple@gmail.com',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _primary, width: 1.5),
                          ),
                        ),
                        validator: (value) {
                          final email = (value ?? '').trim().toLowerCase();
                          if (email.isEmpty) return 'Champ requis';
                          if (!email.endsWith('@gmail.com')) {
                            return 'Utilisez une adresse @gmail.com';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Enregistrer et continuer',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
