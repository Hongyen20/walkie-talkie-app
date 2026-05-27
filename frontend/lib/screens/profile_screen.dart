import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final User user;
  final VoidCallback onLogout;
  final Function(User) onProfileUpdated;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onProfileUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();

  static const _bg = Color(0xFFF0F4FF);
  static const _blue = Color(0xFF1A56DB);
  static const _white = Colors.white;
  static const _text = Color(0xFF111827);
  static const _textSub = Color(0xFF6B7280);

  // ───────────────────────── SNACKBAR ─────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFEF4444) : _blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ───────────────────────── INPUT STYLE ─────────────────────────
  InputDecoration _inputDecoration(
    String label,
    String hint, {
    bool isPassword = false,
  }) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _textSub, fontSize: 13),
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
  );

  // ───────────────────────── LOGOUT (NEW) ─────────────────────────
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Logout',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: _textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── EDIT DISPLAY NAME ─────────────────────────
  Future<void> _showEditDisplayName() async {
    final controller = TextEditingController(text: widget.user.displayName);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Change Display Name',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          decoration: _inputDecoration(
            'Display Name',
            'Enter new display name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;

              final result = await _authService.updateProfile(
                widget.user.token,
                displayName: controller.text.trim(),
              );

              Navigator.pop(ctx);

              if (result['error'] != null) {
                _showSnack(result['error'], isError: true);
              } else {
                _showSnack('Display name updated!');

                widget.onProfileUpdated(
                  User(
                    id: widget.user.id,
                    username: widget.user.username,
                    displayName: controller.text.trim(),
                    inviteCode: widget.user.inviteCode,
                    token: widget.user.token,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── CHANGE PASSWORD ─────────────────────────
  Future<void> _showChangePassword() async {
    final newPassController = TextEditingController();
    final confirmController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Change Password',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassController,
              obscureText: true,
              decoration: _inputDecoration(
                'New Password',
                'Enter new password',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: _inputDecoration(
                'Confirm Password',
                'Confirm password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPassController.text != confirmController.text) {
                _showSnack('Passwords do not match', isError: true);
                return;
              }

              final result = await _authService.updateProfile(
                widget.user.token,
                newPassword: newPassController.text,
              );

              Navigator.pop(ctx);

              if (result['error'] != null) {
                _showSnack(result['error'], isError: true);
              } else {
                _showSnack('Password updated!');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── DELETE ACCOUNT ─────────────────────────
  Future<void> _showDeleteAccount() async {
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Color(0xFFEF4444)),
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: _inputDecoration('Password', 'Enter password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final result = await _authService.deleteAccount(
                widget.user.token,
                passwordController.text,
              );

              Navigator.pop(ctx);

              if (result['error'] != null) {
                _showSnack(result['error'], isError: true);
              } else {
                widget.onLogout();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── TILE ─────────────────────────
  Widget _settingTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = _text,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: color.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Profile",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // USER CARD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _blue,
                      child: Text(
                        widget.user.displayName.isNotEmpty
                            ? widget.user.displayName[0]
                            : widget.user.username[0],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.user.displayName.isNotEmpty
                          ? widget.user.displayName
                          : widget.user.username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // SETTINGS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _settingTile(
                    icon: Icons.edit,
                    label: "Change Display Name",
                    onTap: _showEditDisplayName,
                  ),
                  _settingTile(
                    icon: Icons.lock,
                    label: "Change Password",
                    onTap: _showChangePassword,
                  ),

                  // LOGOUT
                  _settingTile(
                    icon: Icons.logout,
                    label: "Logout",
                    color: Colors.red,
                    onTap: _handleLogout,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _settingTile(
                icon: Icons.delete,
                label: "Delete Account",
                color: Colors.red,
                onTap: _showDeleteAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
