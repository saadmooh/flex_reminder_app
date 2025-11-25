import 'package:flutter/material.dart';

class NavigationService {
  static void navigateTo(BuildContext context, String route, {Object? arguments}) {
    Navigator.pushReplacementNamed(context, route, arguments: arguments);
  }
}