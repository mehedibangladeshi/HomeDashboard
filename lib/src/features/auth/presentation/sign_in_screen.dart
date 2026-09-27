import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _magicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(supabaseProvider).auth.signInWithOtp(
            email: email,
            emailRedirectTo:
                ref.read(appConfigProvider).authRedirect(isWeb: kIsWeb),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check your email for the sign-in link.'),
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    if (!ref.read(appConfigProvider).googleSignInEnabled) return;
    await ref.read(supabaseProvider).auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: ref.read(appConfigProvider).authRedirect(isWeb: kIsWeb),
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.home_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Home, together.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Spending, chores, and family plans in one calm place.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (ref.watch(appConfigProvider).googleSignInEnabled) ...[
                      FilledButton.icon(
                        onPressed: _busy ? null : _google,
                        icon: const Icon(Icons.login),
                        label: const Text('Continue with Google'),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or'),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                      ),
                    ],
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      onSubmitted: (_) => _magicLink(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _magicLink,
                      child: const Text('Email me a sign-in link'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
