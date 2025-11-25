import 'package:flutter/material.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/auth_provider.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  int _step = 1;

  Future<void> _sendResetCode() async {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.invalidEmail;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authProvider = AuthProvider.instance;
      await authProvider
          .resendVerificationCode(_emailController.text.trim().toLowerCase());
      setState(() {
        _step = 2;
        _successMessage = AppLocalizations.of(context)!.resetCodeSent;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resendResetCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authProvider = AuthProvider.instance;
      await authProvider
          .resendVerificationCode(_emailController.text.trim().toLowerCase());
      setState(() {
        _successMessage = AppLocalizations.of(context)!.newResetCodeSent;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.isEmpty) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.pleaseEnterResetCode;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authProvider = AuthProvider.instance;
      await authProvider.verifyEmail(
        _emailController.text.trim().toLowerCase(),
        _codeController.text.trim(),
      );
      setState(() {
        _step = 3;
        _successMessage =
            AppLocalizations.of(context)!.codeVerifiedSuccessfully;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePassword() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.passwordsDoNotMatch;
      });
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.passwordMinLength;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authProvider = AuthProvider.instance;
      // ⚠️ تأكد من وجود هذه الدالة في AuthProvider
      await authProvider.updatePassword(
        _emailController.text.trim().toLowerCase(),
        _passwordController.text,
        _confirmPasswordController.text,
      );

      // عرض رسالة نجاح ثم الرجوع
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.passwordUpdatedSuccessfully,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white, // ✅ مثل باقي الصفحات
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black, // ✅ أيقونة الرجوع سوداء
        title: Text(
          localizations.resetPassword,
          style: const TextStyle(color: Colors.black),
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // رسائل الخطأ أو النجاح
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        margin: const EdgeInsets.only(bottom: 16.0),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          border: Border.all(color: Colors.red),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (_successMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        margin: const EdgeInsets.only(bottom: 16.0),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),

                    // الخطوة 1: إدخال البريد
                    if (_step == 1) ...[
                      Text(
                        localizations.resetPassword,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: localizations.email,
                          labelStyle: const TextStyle(color: Colors.black),
                          filled: true,
                          fillColor: Colors.white,
                          border: const UnderlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black, // ✅ زر أسود مثل AuthScreen
                          padding: const EdgeInsets.symmetric(vertical: 15.0),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero, // ✅ مستطيل بدون زوايا
                          ),
                        ),
                        onPressed: _sendResetCode,
                        child: Text(
                          localizations.resetPassword,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],

                    // الخطوة 2: إدخال الكود
                    if (_step == 2) ...[
                      Text(
                        localizations.enterCodeSentToEmail,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _codeController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: localizations.resetCode,
                          labelStyle: const TextStyle(color: Colors.black),
                          filled: true,
                          fillColor: Colors.white,
                          border: const UnderlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _resendResetCode,
                        child: Text(
                          localizations.resendCode,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15.0),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: _verifyCode,
                        child: Text(
                          localizations.verifyCode,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],

                    // الخطوة 3: إدخال كلمة المرور الجديدة
                    if (_step == 3) ...[
                      Text(
                        localizations.enterNewPassword,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _passwordController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: localizations.password,
                          labelStyle: const TextStyle(color: Colors.black),
                          filled: true,
                          fillColor: Colors.white,
                          border: const UnderlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _confirmPasswordController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: localizations.confirmPassword,
                          labelStyle: const TextStyle(color: Colors.black),
                          filled: true,
                          fillColor: Colors.white,
                          border: const UnderlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15.0),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: _updatePassword,
                        child: Text(
                          localizations.updatePassword,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}