import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavigationHistoryService extends ChangeNotifier {
  final List<String> _backStack = [];
  final List<String> _forwardStack = [];
  String _currentRoute = '/dashboard';

  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;
  String get currentRoute => _currentRoute;

  List<String> get breadcrumbs {
    final cleanRoute = _currentRoute.startsWith('/') ? _currentRoute.substring(1) : _currentRoute;
    if (cleanRoute.isEmpty) return ['Home'];
    return cleanRoute.split('/').map((s) => s[0].toUpperCase() + s.substring(1)).toList();
  }

  void navigateTo(String route, BuildContext context) {
    if (_currentRoute == route) return;
    _backStack.add(_currentRoute);
    _forwardStack.clear();
    _currentRoute = route;
    notifyListeners();
    Navigator.pushNamed(context, route);
  }

  void goBack(BuildContext context) {
    if (!canGoBack) return;
    _forwardStack.add(_currentRoute);
    _currentRoute = _backStack.removeLast();
    notifyListeners();
    Navigator.pushNamed(context, _currentRoute);
  }

  void goForward(BuildContext context) {
    if (!canGoForward) return;
    _backStack.add(_currentRoute);
    _currentRoute = _forwardStack.removeLast();
    notifyListeners();
    Navigator.pushNamed(context, _currentRoute);
  }

  void setInitialRoute(String route) {
    _currentRoute = route;
    notifyListeners();
  }
}

final navigationHistoryProvider = ChangeNotifierProvider<NavigationHistoryService>((ref) {
  return NavigationHistoryService();
});
