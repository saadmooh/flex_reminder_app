import 'package:flutter/material.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final ApiService _apiService = ApiService();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage; // لإظهار رسائل النجاح
  int _step = 1; // 1: إدخال البريد، 2: إدخال الرمز، 3: تحديث كلمة المرور

  Future<void> _sendResetCode() async {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
      setState(() {
        _errorMessage = 'Please enter a valid email';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await _apiService.request(
        'POST',
        'password/send-code',
        data: {'email': _emailController.text.trim().toLowerCase()},
      );

      if (response['statusCode'] == 200) {
        setState(() {
          _step = 2; // الانتقال إلى إدخال الرمز
          _successMessage = AppLocalizations.of(context)!.resetCodeSent;
        });
      } else {
        setState(() {
          _errorMessage = response['data']['message'] ??
              AppLocalizations.of(context)!.failedToSendCode;
        });
      }
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
      final response = await _apiService.request(
        'POST',
        'password/send-code', // نفس النهاية المستخدمة لإرسال الرمز الأولي
        data: {'email': _emailController.text.trim().toLowerCase()},
      );

      if (response['statusCode'] == 200) {
        setState(() {
          _successMessage = AppLocalizations.of(context)!.newResetCodeSent;
        });
      } else {
        setState(() {
          _errorMessage = response['data']['message'] ??
              AppLocalizations.of(context)!.failedToSendCode;
        });
      }
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
      final response = await _apiService.request(
        'POST',
        'password/verify-code',
        data: {
          'email': _emailController.text.trim().toLowerCase(),
          'code': _codeController.text.trim(),
        },
      );

      if (response['statusCode'] == 200) {
        setState(() {
          _step = 3; // الانتقال إلى تحديث كلمة المرور
          _successMessage =
              AppLocalizations.of(context)!.codeVerifiedSuccessfully;
        });
      } else {
        setState(() {
          _errorMessage = response['data']['message'] ??
              AppLocalizations.of(context)!.invalidCode;
        });
      }
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
      final response = await _apiService.request(
        'POST',
        'password/update',
        data: {
          'email': _emailController.text.trim().toLowerCase(),
          'password': _passwordController.text,
          'password_confirmation': _confirmPasswordController.text,
        },
      );

      if (response['statusCode'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.passwordUpdatedSuccessfully)),
        );
        Navigator.pop(context); // العودة إلى شاشة تسجيل الدخول
      } else {
        setState(() {
          _errorMessage = response['data']['message'] ??
              AppLocalizations.of(context)!.failedToUpdatePassword;
        });
      }
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
      backgroundColor: Colors.grey[200], // Light grey background
      appBar: AppBar(
        backgroundColor: Colors.white, // White app bar
        title: Text(
          localizations.resetPassword,
          style: const TextStyle(color: Colors.black), // Title color black
        ),
        iconTheme:
            const IconThemeData(color: Colors.black), // Back arrow color black
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    if (_step == 1) ...[
                      // Step 1: Enter Email
                      Text(
                        localizations.resetPassword,
                        style:
                            const TextStyle(fontSize: 18, color: Colors.black),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: _sendResetCode,
                        child: Text(localizations.resetPassword),
                      ),
                    ],
                    if (_step == 2) ...[
                      // Step 2: Enter Code
                      Text(
                        localizations.enterCodeSentToEmail,
                        style:
                            const TextStyle(fontSize: 18, color: Colors.black),
                      ),
                      const SizedBox(height: 16),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              onPressed: _verifyCode,
                              child: Text(localizations.verifyCode),
                            ),
                          ),
                          TextButton(
                            onPressed: _resendResetCode,
                            child: Text(
                              localizations.resendCode,
                              style: const TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_step == 3) ...[
                      // Step 3: Enter New Password
                      Text(
                        localizations.enterNewPassword,
                        style:
                            const TextStyle(fontSize: 18, color: Colors.black),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: _updatePassword,
                        child: Text(localizations.updatePassword),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
