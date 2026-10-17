import 'package:flutter/material.dart';

/// Shown instead of the app to a signed-in account that isn't on the test
/// list. It opens by itself once an admin adds them (the watcher asks every
/// few seconds).
class NotInvitedApp extends StatelessWidget {
  const NotInvitedApp({
    super.key,
    required this.email,
    required this.theme,
    this.onSignOut,
  });

  final String? email;
  final ValueNotifier<ThemeMode> theme;
  final Future<void> Function()? onSignOut;

  static const _accent = Color(0xFFFF343C);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: theme,
    builder: (context, mode, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Octopilot',
      themeMode: mode,
      theme: ThemeData(colorSchemeSeed: _accent, brightness: Brightness.light),
      darkTheme: ThemeData(
        colorSchemeSeed: _accent,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E0F),
      ),
      home: _NotInvitedPage(email: email, onSignOut: onSignOut),
    ),
  );
}

class _NotInvitedPage extends StatelessWidget {
  const _NotInvitedPage({required this.email, this.onSignOut});

  final String? email;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF343C), Color(0xFFFF8A5B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                "You're not on the test list yet",
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Octopilot is in testing. Ask the team to add this account — '
                'the app opens by itself as soon as they do.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodyLarge?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
              ),
              if (email != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.colorScheme.outlineVariant),
                  ),
                  child: Text(email!, style: t.textTheme.bodyMedium),
                ),
              ],
              const Spacer(flex: 4),
              if (onSignOut != null)
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Use another account'),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
