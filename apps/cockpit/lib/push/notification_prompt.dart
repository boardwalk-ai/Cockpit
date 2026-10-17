import 'package:flutter/material.dart';

import 'device_registrar.dart';

/// A card at the bottom of every screen while this phone can't get
/// notifications: "Allow" opens the system dialog (or the app's settings
/// when Android won't ask again). Gone once the phone is registered; "Not
/// now" hides it until the app is opened again.
class NotificationPrompt extends StatefulWidget {
  const NotificationPrompt({
    super.key,
    required this.registrar,
    required this.child,
  });

  final DeviceRegistrar registrar;
  final Widget child;

  @override
  State<NotificationPrompt> createState() => _NotificationPromptState();
}

class _NotificationPromptState extends State<NotificationPrompt> {
  bool _dismissed = false;
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    await widget.registrar.askPermission();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      ValueListenableBuilder(
        valueListenable: widget.registrar.state,
        builder: (context, state, _) {
          final show =
              !_dismissed &&
              (state == PushState.needsPermission ||
                  state == PushState.blocked);
          return AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            left: 12,
            right: 12,
            bottom: show ? 0 : -260,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Card(
                  blocked: state == PushState.blocked,
                  busy: _busy,
                  onAllow: _allow,
                  onLater: () => setState(() => _dismissed = true),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.blocked,
    required this.busy,
    required this.onAllow,
    required this.onLater,
  });

  final bool blocked;
  final bool busy;
  final VoidCallback onAllow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF151517);
    return Material(
      color: dark ? const Color(0xFF1C1C1F) : Colors.white,
      elevation: 16,
      shadowColor: const Color(0x55FF343C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x55FF343C)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF343C), Color(0xFFFF8A5B)],
                    ),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Turn on notifications',
                    style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              blocked
                  ? 'Notifications are off for Octopilot in your phone\'s '
                        'settings. Open Settings → Notifications and turn them '
                        'on, so team news and study reminders reach you.'
                  : 'So news from the Octopilot team, finished studios and '
                        'your study reminders reach this phone.',
              style: TextStyle(
                color: fg.withValues(alpha: 0.7),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onLater, child: const Text('Not now')),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF343C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : onAllow,
                  child: Text(blocked ? 'Open settings' : 'Allow'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
