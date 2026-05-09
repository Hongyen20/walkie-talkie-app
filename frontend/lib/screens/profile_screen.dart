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

  Future<void> _showEditDisplayName() async {
    final controller = TextEditingController(text: widget.user.displayName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Display Name',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: _text),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: _white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePassword() async {
    final newPassController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Change Password',
            style: TextStyle(
              color: _text,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPassController,
                obscureText: obscureNew,
                style: const TextStyle(color: _text),
                decoration:
                    _inputDecoration(
                      'New Password',
                      'Enter new password',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew ? Icons.visibility_off : Icons.visibility,
                          color: _textSub,
                          size: 18,
                        ),
                        onPressed: () =>
                            setStateDialog(() => obscureNew = !obscureNew),
                      ),
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: obscureConfirm,
                style: const TextStyle(color: _text),
                decoration:
                    _inputDecoration(
                      'Confirm Password',
                      'Confirm new password',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: _textSub,
                          size: 18,
                        ),
                        onPressed: () => setStateDialog(
                          () => obscureConfirm = !obscureConfirm,
                        ),
                      ),
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
                if (newPassController.text.isEmpty) return;
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
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: _white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccount() async {
    final passwordController = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Account',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This action is permanent and cannot be undone. Enter your password to confirm.',
                style: TextStyle(color: _textSub, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscure,
                style: const TextStyle(color: _text),
                decoration: _inputDecoration('Password', 'Enter your password')
                    .copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: _textSub,
                          size: 18,
                        ),
                        onPressed: () =>
                            setStateDialog(() => obscure = !obscure),
                      ),
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
                if (passwordController.text.isEmpty) return;
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
                foregroundColor: _white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: _text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            // ── Avatar + name ────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          widget.user.displayName.isNotEmpty
                              ? widget.user.displayName[0].toUpperCase()
                              : widget.user.username[0].toUpperCase(),
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.displayName.isNotEmpty
                                ? widget.user.displayName
                                : widget.user.username,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                         
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Actions ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Text(
                'Account Settings',
                style: TextStyle(
                  color: _textSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _settingTile(
                      icon: Icons.badge_outlined,
                      label: 'Edit Display Name',
                      onTap: _showEditDisplayName,
                    ),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _settingTile(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change Password',
                      onTap: _showChangePassword,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Text(
                'Danger Zone',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: _settingTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete Account',
                  color: const Color(0xFFEF4444),
                  onTap: _showDeleteAccount,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
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
}
