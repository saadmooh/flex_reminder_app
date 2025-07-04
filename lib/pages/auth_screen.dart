import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isRegistering = true;
  bool _obscurePassword = true;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final languageManager =
        Provider.of<LanguageManager>(context, listen: false);
    final localizations = AppLocalizations.of(context)!;

    try {
      if (_isRegistering) {
        await authProvider.register(
          name: _nameController.text,
          email: _emailController.text.trim().toLowerCase(),
          password: _passwordController.text,
          language: languageManager.locale.languageCode,
        );
        _showSuccessSnackBar(localizations.registrationSuccessful);
      } else {
        await authProvider.login(
          email: _emailController.text.trim().toLowerCase(),
          password: _passwordController.text,
          language: languageManager.locale.languageCode,
        );
        _showSuccessSnackBar(localizations.loginSuccessful);
        Navigator.pushReplacementNamed(context, '/reminders');
      }
    } catch (e) {
      _showErrorSnackBar(
          authProvider.errorMessage ?? 'An unexpected error occurred');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageManager = Provider.of<LanguageManager>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final isArabic = languageManager.locale.languageCode == 'ar';
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Image.asset(
                      'assets/logo.png',
                      height: 80.0,
                    ),
                    const SizedBox(height: 40.0),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PopupMenuButton<String>(
                        color: Colors.white,
                        icon: const Icon(Icons.language, color: Colors.black),
                        onSelected: (value) {
                          if (value == 'en') {
                            languageManager.setLocale(const Locale('en'));
                          } else if (value == 'ar') {
                            languageManager.setLocale(const Locale('ar'));
                          } else if (value == 'zh') {
                            languageManager.setLocale(const Locale('zh'));
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem(
                            value: 'en',
                            child: Text(
                              'English',
                              style: const TextStyle(color: Colors.black),
                              textDirection: textDirection,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'ar',
                            child: Text(
                              'العربية',
                              style: const TextStyle(color: Colors.black),
                              textDirection: textDirection,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'zh',
                            child: Text(
                              '中文',
                              style: const TextStyle(color: Colors.black),
                              textDirection: textDirection,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20.0),
                    if (_isRegistering)
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: localizations.name,
                          labelStyle: const TextStyle(color: Colors.black),
                          border: const UnderlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        textDirection: textDirection,
                        validator: (value) {
                          if (_isRegistering &&
                              (value == null || value.isEmpty)) {
                            return localizations.requiredField;
                          }
                          return null;
                        },
                      ),
                    if (_isRegistering) const SizedBox(height: 20.0),
                    TextFormField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        labelText: localizations.email,
                        labelStyle: const TextStyle(color: Colors.black),
                        border: const UnderlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textDirection: textDirection,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null || value.isEmpty || !value.contains('@')
                              ? localizations.invalidEmail
                              : null,
                    ),
                    const SizedBox(height: 20.0),
                    TextFormField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        labelText: localizations.password,
                        labelStyle: const TextStyle(color: Colors.black),
                        border: const UnderlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          icon:
                              const Icon(Icons.visibility, color: Colors.black),
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ),
                      textDirection: textDirection,
                      obscureText: _obscurePassword,
                      validator: (value) => value == null || value.length < 6
                          ? localizations.requiredField
                          : null,
                    ),
                    const SizedBox(height: 30.0),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15.0),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      onPressed: authProvider.isLoading ? null : _submitForm,
                      child: authProvider.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _isRegistering
                                  ? localizations.signUp
                                  : localizations.login,
                              style: const TextStyle(
                                  fontSize: 16.0, color: Colors.white),
                            ),
                    ),
                    const SizedBox(height: 20.0),
                    if (!_isRegistering)
                      TextButton(
                        onPressed: authProvider.isLoading
                            ? null
                            : () {
                                Navigator.pushNamed(context, '/reset-password');
                              },
                        child: Text(
                          localizations.forgotPassword,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    const SizedBox(height: 16.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isRegistering
                              ? localizations.alreadyHaveAccount
                              : localizations.dontHaveAccount,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _isRegistering = !_isRegistering);
                          },
                          child: Text(
                            _isRegistering
                                ? localizations.login
                                : localizations.signUp,
                            style: const TextStyle(color: Color(0xFF6200EE)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
