final class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.environment = 'local',
    this.googleSignInEnabled = false,
    this.calendarEnabled = false,
    this.pushEnabled = false,
    this.webAppUrl = 'http://localhost:3000',
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String environment;
  final bool googleSignInEnabled;
  final bool calendarEnabled;
  final bool pushEnabled;
  final String webAppUrl;

  String authRedirect({required bool isWeb}) =>
      isWeb ? webAppUrl : 'io.homemanagement.app://login-callback';

  factory AppConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be supplied with '
        '--dart-define or --dart-define-from-file.',
      );
    }
    return const AppConfig(
      supabaseUrl: url,
      supabasePublishableKey: key,
      environment: String.fromEnvironment('APP_ENV', defaultValue: 'local'),
      googleSignInEnabled: bool.fromEnvironment('GOOGLE_SIGN_IN_ENABLED'),
      calendarEnabled: bool.fromEnvironment('GOOGLE_CALENDAR_ENABLED'),
      pushEnabled: bool.fromEnvironment('PUSH_ENABLED'),
      webAppUrl: String.fromEnvironment('WEB_APP_URL',
          defaultValue: 'http://localhost:3000'),
    );
  }
}
