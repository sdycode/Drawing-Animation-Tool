import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_service.dart';
import 'sign_in_controller.dart';

/// The `/signin` screen (docs/v3/05 §1).
///
/// One form, two modes. Email + password, nothing else: no social buttons and
/// **no "forgot password" link** — a forgotten password is unrecoverable in v1
/// and the UI must not imply otherwise (AC-10.0.5).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(signInControllerProvider.notifier).submit(
          email: _email.text,
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInControllerProvider);
    final isSignUp = state.mode == AuthMode.signUp;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Drawing Animation Tool',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSignUp ? 'Create an account' : 'Sign in',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    autofocus: true,
                    enabled: !state.busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => ref
                        .read(signInControllerProvider.notifier)
                        .clearError(),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email address'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    enabled: !state.busy,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      // Firebase's own minimum. Stated up front so "weak
                      // password" is never the first time the user hears it.
                      helperText: 'At least 6 characters',
                    ),
                    onFieldSubmitted: (_) => _submit(),
                    onChanged: (_) => ref
                        .read(signInControllerProvider.notifier)
                        .clearError(),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'At least 6 characters'
                        : null,
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    // Inline, never a modal (AC-10.0.4).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: Color(0xFFEF9A9A)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            state.error!.failure.message,
                            key: const Key('auth-error'),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFEF9A9A)),
                          ),
                        ),
                      ],
                    ),
                    _TechnicalDetail(error: state.error!),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: state.busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: state.busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isSignUp ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : ref
                            .read(signInControllerProvider.notifier)
                            .toggleMode,
                    child: Text(
                      isSignUp
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The raw provider error, shown **in debug builds only**.
///
/// Two audiences, two messages: the user gets
/// [AuthFailure.message] (never a provider string, AC-10.0.4), the developer
/// gets the code that produced it. Without this, `AuthFailure.unknown` — which
/// by definition means the mapping in `FirebaseAuthService` fell short — is a
/// dead end that reads only "Something went wrong".
///
/// `kDebugMode` is a compile-time constant, so this whole widget and the raw
/// strings it renders tree-shake out of a release build.
class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.error});

  final AuthException error;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || error.technical.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'debug detail',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: Colors.white38,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: error.toString()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Error copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.copy, size: 12, color: Colors.white38),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              error.technical,
              key: const Key('auth-error-technical'),
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFFB0BEC5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
