import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String _error = '';

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final result = await _authService.register(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
      _displayNameController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (result['message'] == 'Register successful') {
      Navigator.pop(context); // Goback Login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful! Please log in.')),
      );
    } else {
      setState(() => _error = result['error'] ?? 'Register Fail');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Register', style: TextStyle(color: Color(0xFF39FF14))),
        iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _displayNameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Display Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Username'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Password'),
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: 24),

            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: Colors.red)),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF39FF14),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('REGISTER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF39FF14)),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF1f2e1f)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF39FF14)),
      ),
    );
  }
}