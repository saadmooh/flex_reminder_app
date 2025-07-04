import 'package:flutter/material.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final bool fromLogin;

  const EmailVerificationScreen({
    Key? key,
    required this.email,
    this.fromLogin = false,
  }) : super(key: key);

  @override
  _EmailVerificationScreenState createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _codeController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _verifyEmail() async {
    if (_codeController.text.isEmpty) {
      _showErrorDialog(
          AppLocalizations.of(context)!.pleaseEnterVerificationCode);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.verifyEmail(widget.email, _codeController.text);
      _showSuccessDialog(AppLocalizations.of(context)!.emailVerifiedSuccess);
      // توجيه المستخدم إلى صفحة التحذيرات بعد التفعيل
      Navigator.pushReplacementNamed(context, '/reminders');
    } catch (error) {
      _showErrorDialog(error.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resendVerificationCode() async {
    setState(() => _isLoading = true);

    try {
      await _apiService.resendVerificationCode(widget.email);
      _showSuccessDialog(AppLocalizations.of(context)!.verificationCodeResent);
    } catch (error) {
      _showErrorDialog(error.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[800],
        title: Text(AppLocalizations.of(context)!.anErrorOccurred,
            style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: <Widget>[
          TextButton(
            child: Text(AppLocalizations.of(context)!.okay,
                style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[800],
        title: Text(AppLocalizations.of(context)!.success,
            style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: <Widget>[
          TextButton(
            child: Text(AppLocalizations.of(context)!.okay,
                style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Apply white background
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                AppLocalizations.of(context)!.verifyYourEmail,
                style: TextStyle(
                  fontSize: 32.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.black, // Black text
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                "${AppLocalizations.of(context)!.verificationCodeSent} ${widget.email}.",
                style: const TextStyle(
                    fontSize: 16.0, color: Colors.black), // Black text
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32.0),
              TextFormField(
                controller: _codeController,
                style:
                    const TextStyle(color: Colors.black), // Black text in input
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.verificationCode,
                  labelStyle:
                      const TextStyle(color: Colors.black), // Black label
                  filled: true,
                  fillColor: Colors.white, // White fill
                  border: const UnderlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty
                    ? AppLocalizations.of(context)!.pleaseEnterCode
                    : null,
              ),
              const SizedBox(height: 16.0),
              TextButton(
                onPressed: _isLoading ? null : _resendVerificationCode,
                child: Text(
                  AppLocalizations.of(context)!.resendCode,
                  style: TextStyle(color: Colors.black), // Black text
                ),
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black, // Black button
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48.0, vertical: 16.0),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero, // Rectangular button
                  ),
                ),
                onPressed: _isLoading ? null : _verifyEmail,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        AppLocalizations.of(context)!.verify,
                        style: TextStyle(fontSize: 18.0, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
