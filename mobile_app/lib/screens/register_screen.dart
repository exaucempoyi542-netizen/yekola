import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  static const Color _primary = Color(0xFF152A45);
  static const Color _bg = Color(0xFFEEF1F6);
  static const Color _border = Color(0xFFD0D7E2);
  static const Color _muted = Color(0xFF5A6578);
  static const Color _ink = Color(0xFF0F172A);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.register(
        _nameController.text,
        _emailController.text,
        _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inscription réussie ! Vous pouvez vous connecter.'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      } else {
        final detail = authProvider.lastError ??
            'Échec de l\'inscription. Vérifiez votre connexion ou la validité de vos données.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(detail),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur inattendue: $e'),
          backgroundColor: Colors.red,
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
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0A1628).withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_stories_rounded,
                        size: 64,
                        color: _primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Yekola',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Créer un compte étudiant',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _label('Nom complet'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDecoration(hint: 'Votre nom complet'),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Champ requis' : null,
                      ),
                      const SizedBox(height: 16),
                      _label('Adresse email'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration:
                            _inputDecoration(hint: 'ex. etudiant@email.com'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Champ requis';
                          }
                          if (!value.contains('@')) {
                            return 'Veuillez entrer un email valide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _label('Mot de passe'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _isLoading ? null : _register(),
                        decoration: _inputDecoration(
                          hint: 'Minimum 6 caractères',
                          suffix: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: _muted,
                              size: 20,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.length < 6
                            ? 'Minimum 6 caractères'
                            : null,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                _primary.withValues(alpha: 0.6),
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
                                  'S\'inscrire',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                );
                              },
                        child: const Text(
                          'Déjà un compte ? Se connecter',
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Portail académique · Accès sécurisé',
                        style: TextStyle(fontSize: 12, color: _muted),
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

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _ink.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA3ADBE)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffix,
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFB91C1C)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.5),
      ),
    );
  }
}
