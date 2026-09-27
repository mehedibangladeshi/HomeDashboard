final class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;

  factory AppConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be supplied with '
        '--dart-define or --dart-define-from-file.',
      );
    }
    return const AppConfig(supabaseUrl: url, supabasePublishableKey: key);
  }
}
