import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import 'my_courses_screen.dart';
import 'assignment_screen.dart';
import 'privacy_screen.dart';
import 'security_screen.dart';
import 'support_screen.dart';
import 'student_grades_screen.dart';
import 'user_profile_screen.dart';
import 'edit_profile_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );
    if (image == null || !mounted) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    if (bytes.lengthInBytes > 600 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image trop lourde. Choisissez une photo plus légère.')),
      );
      return;
    }
    await Provider.of<AuthProvider>(context, listen: false).setProfileAvatarBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil enregistrée.')),
      );
    }
  }

  void _showEmojiDialog() {
    String tempEmoji = '';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choisir un émoji'),
          content: TextField(
            maxLength: 2,
            decoration: const InputDecoration(hintText: '😊'),
            onChanged: (value) => tempEmoji = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                if (tempEmoji.isNotEmpty) {
                  await Provider.of<AuthProvider>(context, listen: false)
                      .setProfileEmoji(tempEmoji);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Importer une photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions),
                title: const Text('Mettre un émoji'),
                onTap: () {
                  Navigator.pop(context);
                  _showEmojiDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Retirer la photo / émoji'),
                onTap: () async {
                  Navigator.pop(context);
                  await Provider.of<AuthProvider>(context, listen: false).clearProfileAvatar();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAuthenticated = authProvider.isAuthenticated;
    final userName = authProvider.userName;
    final userEmail = authProvider.userEmail;

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF152A45), Color(0xFF1E3A5F)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
                boxShadow: [
                  BoxShadow(color: Color(0xFF152A45), blurRadius: 20, offset: Offset(0, 10), spreadRadius: -10),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: GestureDetector(
                          onTap: () {
                            if (isAuthenticated) {
                              _showImageOptions();
                            } else {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                            }
                          },
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.white,
                            backgroundImage: authProvider.hasCustomAvatar
                                ? MemoryImage(authProvider.avatarBytes!)
                                : null,
                            child: authProvider.hasCustomAvatar
                                ? null
                                : (authProvider.hasEmojiAvatar
                                    ? Text(
                                        authProvider.profileEmoji!,
                                        style: const TextStyle(fontSize: 45),
                                      )
                                    : Icon(
                                        isAuthenticated
                                            ? Icons.person_rounded
                                            : Icons.person_add_rounded,
                                        size: 45,
                                        color: const Color(0xFF152A45),
                                      )),
                          ),
                        ),
                      ),
                      if (isAuthenticated)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                            child: const Icon(Icons.check, color: Colors.white, size: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isAuthenticated ? (userName.isNotEmpty ? userName : 'Utilisateur') : 'Bienvenue sur Yekola',
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 24, 
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAuthenticated ? userEmail : 'Connectez-vous pour accéder à vos cours',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7), 
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isAuthenticated) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  email: userEmail,
                                  initialName: userName,
                                  initialRole: authProvider.userRole,
                                ),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Profil public'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Modifier'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('GÉNÉRAL'),
                  const SizedBox(height: 12),
                  _buildMenuGrid(context),
                  const SizedBox(height: 32),
                  _buildSectionHeader('COMPTE'),
                  const SizedBox(height: 8),
                  _buildActionTile(context, Icons.settings_outlined, 'Paramètres', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  }),
                  _buildActionTile(context, Icons.lock_outline_rounded, 'Confidentialité', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()));
                  }),
                  _buildActionTile(context, Icons.security_rounded, 'Sécurité', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
                  }),
                  const SizedBox(height: 24),
                  _buildSectionHeader('SUPPORT'),
                  const SizedBox(height: 8),
                  _buildActionTile(context, Icons.help_outline_rounded, 'Aide & Support', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
                  }),
                  const SizedBox(height: 16),
                  _buildActionTile(context, Icons.logout_rounded, 'Déconnexion', () {
                    authProvider.logout();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Déconnexion réussie')),
                    );
                  }, isDestructive: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[500],
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildMenuGrid(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1.4,
                child: _buildMenuCard(context, Icons.book_rounded, 'Mes Cours', const Color(0xFF152A45), () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCoursesScreen()));
                }),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1.4,
                child: _buildMenuCard(context, Icons.assignment_turned_in_rounded, 'Mes Notes', Colors.amber[700]!, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentGradesScreen()));
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 88,
          width: double.infinity,
          child: _buildWideMenuCard(
            context,
            Icons.assignment_rounded,
            'TPs',
            'Travaux pratiques et devoirs',
            Colors.deepOrange,
            () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AssignmentScreen()));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWideMenuCard(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.0 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: theme.textTheme.bodyMedium?.color ?? const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.0 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6), // Reduced from 10 to prevent overflow
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24), // Reduced from 28
              ),
              const SizedBox(height: 6), // Reduced from 12
              Text(
                title, 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: theme.textTheme.bodyMedium?.color ?? const Color(0xFF1A1A1A))
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDestructive ? Colors.red.withValues(alpha: 0.02) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDestructive 
              ? Colors.red.withValues(alpha: 0.1) 
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[100]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: isDestructive ? Colors.red : theme.iconTheme.color, size: 20),
        ),
        title: Text(
          title, 
          style: TextStyle(
            color: isDestructive ? Colors.red : theme.textTheme.bodyMedium?.color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          )
        ),
        trailing: Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[400]),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}


