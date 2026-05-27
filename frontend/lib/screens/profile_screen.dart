import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

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

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ───────────── AVATAR COLORS ─────────────
  static const List<Color> _avatarPalette = [
    Color(0xFF1A56DB), // blue (default)
    Color(0xFF7C3AED), // violet
    Color(0xFF059669), // emerald
    Color(0xFFDB2777), // pink
    Color(0xFFD97706), // amber
    Color(0xFFDC2626), // red
    Color(0xFF0891B2), // cyan
    Color(0xFF65A30D), // lime
    Color(0xFF9333EA), // purple
    Color(0xFFF97316), // orange
  ];

  Color _avatarColor = const Color(0xFF1A56DB);

  // ───────────── THEME ─────────────
  static const _bg = Color(0xFFF5F7FF);
  static const _surface = Colors.white;
  static const _text = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF64748B);
  static const _divider = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ───────────── SNACKBAR ─────────────
  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(msg, style: const TextStyle(fontSize: 14)),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }

  // ───────────── INPUT DECORATION ─────────────
  InputDecoration _inputDecor(String label, String hint) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _avatarColor, width: 1.5),
    ),
  );

  // ───────────── AVATAR COLOR PICKER ─────────────
  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Avatar color',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _avatarPalette.map((color) {
                final isSelected = color == _avatarColor;
                return GestureDetector(
                  onTap: () {
                    setState(() => _avatarColor = color);
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: color.withOpacity(0.4), width: 4)
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 22,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── LOGOUT ─────────────
  void _handleLogout() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConfirmSheet(
        icon: Icons.logout_rounded,
        iconColor: const Color(0xFFEF4444),
        title: 'Logout',
        subtitle: 'Are you sure you want to logout?',
        confirmLabel: 'Logout',
        confirmColor: const Color(0xFFEF4444),
        onConfirm: () async {
          Navigator.pop(ctx);
          await StorageService.clearUser();
          widget.onLogout();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  // ───────────── EDIT DISPLAY NAME ─────────────
  Future<void> _showEditDisplayName() async {
    final controller = TextEditingController(text: widget.user.displayName);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InputSheet(
        title: 'Change Display Name',
        icon: Icons.badge_outlined,
        children: [
          TextField(
            controller: controller,
            decoration: _inputDecor('Display Name', 'Enter new display name'),
            autofocus: true,
          ),
        ],
        onSave: () async {
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
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  // ───────────── CHANGE PASSWORD ─────────────
  Future<void> _showChangePassword() async {
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InputSheet(
        title: 'Change Password',
        icon: Icons.lock_outline_rounded,
        children: [
          TextField(
            controller: newPassCtrl,
            obscureText: true,
            decoration: _inputDecor('New Password', 'Enter new password'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmCtrl,
            obscureText: true,
            decoration: _inputDecor('Confirm Password', 'Confirm new password'),
          ),
        ],
        onSave: () async {
          if (newPassCtrl.text != confirmCtrl.text) {
            _showSnack('Passwords do not match', isError: true);
            return;
          }
          final result = await _authService.updateProfile(
            widget.user.token,
            newPassword: newPassCtrl.text,
          );
          Navigator.pop(ctx);
          if (result['error'] != null) {
            _showSnack(result['error'], isError: true);
          } else {
            _showSnack('Password updated!');
          }
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  // ───────────── DELETE ACCOUNT ─────────────
  Future<void> _showDeleteAccount() async {
    final passCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InputSheet(
        title: 'Delete Account',
        icon: Icons.delete_forever_outlined,
        iconColor: const Color(0xFFEF4444),
        titleColor: const Color(0xFFEF4444),
        saveLabel: 'Delete',
        saveColor: const Color(0xFFEF4444),
        children: [
          const Text(
            'This action cannot be undone. Enter your password to confirm.',
            style: TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: _inputDecor('Password', 'Enter your password'),
            autofocus: true,
          ),
        ],
        onSave: () async {
          final result = await _authService.deleteAccount(
            widget.user.token,
            passCtrl.text,
          );
          Navigator.pop(ctx);
          if (result['error'] != null) {
            _showSnack(result['error'], isError: true);
          } else {
            await StorageService.clearUser();
            widget.onLogout();
          }
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  // ───────────── BUILD ─────────────
  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.displayName.isNotEmpty
        ? widget.user.displayName
        : widget.user.username;
    final initial = displayName[0].toUpperCase();

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── HEADER ──
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                      color: _text,
                    ),
                    const Expanded(
                      child: Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── AVATAR CARD ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _avatarColor.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Avatar with edit button
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: _avatarColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _avatarColor.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: GestureDetector(
                              onTap: _showColorPicker,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: _surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _divider),
                                ),
                                child: Icon(
                                  Icons.palette_outlined,
                                  size: 13,
                                  color: _avatarColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _text,
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

              const SizedBox(height: 20),

              // ── SETTINGS GROUP ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('Account'),
                    const SizedBox(height: 8),
                    _GroupCard(
                      children: [
                        _Tile(
                          icon: Icons.badge_outlined,
                          label: 'Change Display Name',
                          onTap: _showEditDisplayName,
                          accentColor: _avatarColor,
                        ),
                        _TileDivider(),
                        _Tile(
                          icon: Icons.lock_outline_rounded,
                          label: 'Change Password',
                          onTap: _showChangePassword,
                          accentColor: _avatarColor,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    _SectionLabel('Session'),
                    const SizedBox(height: 8),
                    _GroupCard(
                      children: [
                        _Tile(
                          icon: Icons.logout_rounded,
                          label: 'Logout',
                          onTap: _handleLogout,
                          accentColor: const Color(0xFFEF4444),
                          labelColor: const Color(0xFFEF4444),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    _SectionLabel('Danger Zone'),
                    const SizedBox(height: 8),
                    _GroupCard(
                      borderColor: const Color(0xFFFFE4E4),
                      children: [
                        _Tile(
                          icon: Icons.delete_forever_outlined,
                          label: 'Delete Account',
                          onTap: _showDeleteAccount,
                          accentColor: const Color(0xFFEF4444),
                          labelColor: const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── HELPERS ───────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  final Color? borderColor;
  const _GroupCard({required this.children, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: borderColor ?? const Color(0xFFE2E8F0),
        width: 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _TileDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
    height: 1,
    thickness: 0.5,
    indent: 52,
    color: Color(0xFFF1F5F9),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accentColor;
  final Color? labelColor;

  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accentColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: accentColor, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: labelColor ?? const Color(0xFF0F172A),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: const Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────── BOTTOM SHEETS ───────────────────────

class _InputSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Color? titleColor;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String saveLabel;
  final Color? saveColor;

  const _InputSheet({
    required this.title,
    required this.icon,
    required this.children,
    required this.onSave,
    required this.onCancel,
    this.iconColor,
    this.titleColor,
    this.saveLabel = 'Save',
    this.saveColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = saveColor ?? const Color(0xFF1A56DB);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor ?? accent, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: titleColor ?? const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      saveLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String confirmLabel;
  final Color confirmColor;
  final Future<void> Function() onConfirm;
  final VoidCallback onCancel;

  const _ConfirmSheet({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
