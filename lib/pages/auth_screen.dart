import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/services/authentication_service.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flutter/foundation.dart';

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

    final languageManager = Provider.of<LanguageManager>(context, listen: false);
    final authService = AuthenticationService(context);

    try {
      if (_isRegistering) {
        await authService.register(
          name: _nameController.text,
          email: _emailController.text.trim().toLowerCase(),
          password: _passwordController.text,
          language: languageManager.locale.languageCode,
        );
        if (kDebugMode) {
          print('✅ Registration successful for ${_emailController.text}');
        }
      } else {
        await authService.login(
          email: _emailController.text.trim().toLowerCase(),
          password: _passwordController.text,
          language: languageManager.locale.languageCode,
        );
        if (kDebugMode) {
          print('✅ Login successful for ${_emailController.text}');
        }
      }
    } catch (e) {
      final localizations = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.errorOccurred, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      if (kDebugMode) {
        print('❌ Auth error: $e');
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    final languageManager = Provider.of<LanguageManager>(context, listen: false);
    final authService = AuthenticationService(context);

    try {
      await authService.signInWithGoogle(language: languageManager.locale.languageCode);
      if (kDebugMode) {
        print('✅ Google Sign-In successful');
      }
    } catch (e) {
      if (!e.toString().contains('canceled') && !e.toString().contains('cancelled')) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.googleSignInFailed, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        if (kDebugMode) {
          print('❌ Google Sign-In error: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageManager = Provider.of<LanguageManager>(context);
    // استخدام Singleton instance
    final authProvider = AuthProvider.instance;
    final isArabic = languageManager.locale.languageCode == 'ar';
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: SingleChildScrollView(
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
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                    if (_isRegistering && (value == null || value.isEmpty)) {
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
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                      color: Colors.black,
                                    ),
                                    onPressed: () {
                                      setState(() => _obscurePassword = !_obscurePassword);
                                    },
                                  ),
                                ),
                                textDirection: textDirection,
                                obscureText: _obscurePassword,
                                validator: (value) =>
                                    value == null || value.length < 6 ? localizations.requiredField : null,
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
                                        _isRegistering ? localizations.signUp : localizations.login,
                                        style: const TextStyle(fontSize: 16.0, color: Colors.white),
                                      ),
                              ),
                              const SizedBox(height: 20.0),
                              if (!_isRegistering)
                                TextButton(
                                  onPressed: () {
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
                                      _isRegistering ? localizations.login : localizations.signUp,
                                      style: const TextStyle(color: Color(0xFF6200EE)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20.0),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10.0),
                            child: Text(
                              'OR',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 20.0),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(vertical: 15.0),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: authProvider.isGoogleSignInLoading ? null : _signInWithGoogle,
                        icon: Image.asset(
                          'assets/google_logo.png',
                          height: 24.0,
                        ),
                        label: Text(
                          localizations.signInWithGoogle,
                          style: const TextStyle(fontSize: 16.0, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (authProvider.isLoading || authProvider.isGoogleSignInLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
          ],
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