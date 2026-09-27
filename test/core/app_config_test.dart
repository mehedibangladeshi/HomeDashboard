import 'package:flutter_test/flutter_test.dart';
import 'package:home_management/src/core/config/app_config.dart';

void main() {
  test('web login returns to web while native login uses the app scheme', () {
    const config = AppConfig(
      supabaseUrl: 'http://localhost:54321',
      supabasePublishableKey: 'local-key',
      webAppUrl: 'http://localhost:3000',
    );
    expect(config.authRedirect(isWeb: true), 'http://localhost:3000');
    expect(config.authRedirect(isWeb: false),
        'io.homemanagement.app://login-callback');
    expect(config.googleSignInEnabled, isFalse);
    expect(config.calendarEnabled, isFalse);
    expect(config.pushEnabled, isFalse);
  });
}
