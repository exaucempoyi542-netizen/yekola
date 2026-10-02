import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _showPasswordFields = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _nameController = TextEditingController(text: authProvider.userName);
    _emailController = TextEditingController(text: authProvider.userEmail);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _saveChanges() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.clearLastError();

      final passwordAttempted =
          _showPasswordFields && _newPasswordController.text.isNotEmpty;
      final profileAttempted =
          _nameController.text.trim() != authProvider.userName.trim() ||
          _emailController.text.trim().toLowerCase() !=
              authProvider.userEmail.trim().toLowerCase();

      var profileSuccess = true;
      var passwordSuccess = true;

      if (profileAttempted) {
        profileSuccess = await authProvider.updateProfile(
          _nameController.text,
          _emailController.text,
        );
      }

      if (passwordAttempted) {
        passwordSuccess = await authProvider.updatePassword(
          _oldPasswordController.text,
          _newPasswordController.text,
        );
      }

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (profileSuccess && passwordSuccess) {
        final message = passwordAttempted && profileAttempted
            ? 'Profil et mot de passe mis à jour avec succès.'
            : passwordAttempted
                ? 'Mot de passe mis à jour avec succès.'
                : 'Profil mis à jour avec succès.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authProvider.lastError ?? 'Une erreur est survenue.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Éditer le profil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF152A45),
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informations personnelles',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF152A45),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => 
                    value == null || value.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Adresse Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Champ requis';
                  if (!value.contains('@')) return 'Email invalide';
                  return null;
                },
              ),
              const SizedBox(height: 32),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sécurité',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF152A45),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _showPasswordFields = !_showPasswordFields);
                    },
                    icon: Icon(_showPasswordFields ? Icons.expand_less : Icons.expand_more),
                    label: Text(_showPasswordFields ? 'Masquer' : 'Changer le mot de passe par défaut'),
                  ),
                ],
              ),
              const Divider(),
              if (_showPasswordFields) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Ancien mot de passe',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_showPasswordFields && (value == null || value.isEmpty)) {
                      return 'Veuillez saisir votre ancien mot de passe';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    prefixIcon: Icon(Icons.lock_reset),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_showPasswordFields && (value == null || value.length < 6)) {
                      return 'Minimum 6 caractères';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le nouveau mot de passe',
                    prefixIcon: Icon(Icons.check_circle_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_showPasswordFields && value != _newPasswordController.text) {
                      return 'Les mots de passe ne correspondent pas';
                    }
                    return null;
                  },
                ),
              ],
              
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF152A45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('ENREGISTRER LES MODIFICATIONS', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
