import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/supabase_provider.dart';

enum _Mode { signIn, signUp }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final client = ref.read(supabaseClientProvider);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      if (_mode == _Mode.signIn) {
        await client.auth.signInWithPassword(email: email, password: password);
      } else {
        final res = await client.auth.signUp(email: email, password: password);
        if (mounted && res.session == null) {
          setState(() {
            _info = 'Check your email to confirm your account, then sign in.';
            _mode = _Mode.signIn;
          });
        }
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignIn = _mode == _Mode.signIn;

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
                  Image.asset('assets/icon/slate.png', height: 64, width: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Slate',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    enabled: !_busy,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) return 'Required';
                      if (!value.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Required';
                      if (_mode == _Mode.signUp && (v ?? '').length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _info!,
                      style: TextStyle(color: theme.colorScheme.primary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isSignIn ? 'Sign in' : 'Create account'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _mode = isSignIn ? _Mode.signUp : _Mode.signIn;
                              _error = null;
                              _info = null;
                            }),
                    child: Text(isSignIn
                        ? "Don't have an account? Sign up"
                        : 'Already have an account? Sign in'),
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
