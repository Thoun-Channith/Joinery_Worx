// lib/app/routes/app_routes.dart
part of 'app_pages.dart';

abstract class Routes {
  Routes._();
  static const HOME = _Paths.HOME;
  static const LOGIN = _Paths.LOGIN;
  static const SPLASH = _Paths.SPLASH;
  static const ADMIN = _Paths.ADMIN; // <-- ADD THIS
  static const STAFF_HISTORY = _Paths.STAFF_HISTORY; // <-- ADD THIS
}

abstract class _Paths {
  _Paths._();
  static const HOME = '/home';
  static const LOGIN = '/login';
  static const SPLASH = '/splash';
  static const ADMIN = '/admin'; // <-- ADD THIS
  static const STAFF_HISTORY = '/staff-history'; // <-- ADD THIS
}