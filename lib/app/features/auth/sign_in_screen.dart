import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  if (state.failure != null) ...[
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
                            state.failure!.message,
                            key: const Key('auth-error'),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFEF9A9A)),
                          ),
                        ),
                      ],
                    ),
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
