import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../aurora.dart';
import '../motion.dart';
import '../shell_models.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import '../voice/voice_orb.dart';
import '../widgets.dart';
import 'composer.dart';
import 'message_list.dart';
import 'mode_cards.dart';
import 'shell_drawer.dart';

/// Home: the main chat. Voice first; typing is one tap away. A new
/// conversation shows the three mode cards.
class ShellHomePage extends StatefulWidget {
  const ShellHomePage({super.key});

  @override
  State<ShellHomePage> createState() => _ShellHomePageState();
}

class _ShellHomePageState extends State<ShellHomePage> {
  var _typing = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _talk() async {
    Haptics.tap();
    final typing = await context.push<bool>('/voice');
    if (!mounted || typing != true) return;
    _type();
  }

  void _type() {
    Haptics.tap();
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final conversation = services.conversation;
    final c = ShellColors.of(context);

    return Scaffold(
      drawer: const ShellDrawer(),
      body: AuroraBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: conversation,
            builder: (context, _) {
              final empty =
                  conversation.isEmpty && conversation.failure == null;
              return Column(
                children: [
                  ShellTopBar(
                    title: 'Octopilot',
                    leading: Builder(
                      builder: (context) => ShellIconButton(
                        icon: Icons.menu_rounded,
                        tooltip: 'Chats',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    trailing: AnimatedSwitcher(
                      duration: motion(
                        context,
                        const Duration(milliseconds: 300),
                      ),
                      transitionBuilder: (child, a) =>
                          ScaleTransition(scale: a, child: child),
                      child: empty
                          ? const _AccountButton(key: ValueKey('account'))
                          : ShellIconButton(
                              key: const ValueKey('new'),
                              icon: Icons.edit_square,
                              tooltip: 'New chat',
                              onPressed: conversation.newChat,
                            ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: motion(
                        context,
                        const Duration(milliseconds: 450),
                      ),
                      switchInCurve: kShellEase,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.97, end: 1.0).animate(a),
                          child: child,
                        ),
                      ),
                      child: conversation.loading
                          ? Center(
                              key: const ValueKey('loading'),
                              child: BouncingDots(color: c.accent),
                            )
                          : empty
                          ? const _Welcome(key: ValueKey('welcome'))
                          : ShellMessageList(
                              key: ValueKey(conversation.threadId ?? 'new'),
                              conversation: conversation,
                            ),
                    ),
                  ),
                  ShellColumn(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 380),
                      curve: kShellEase,
                      child: AnimatedSwitcher(
                        duration: motion(
                          context,
                          const Duration(milliseconds: 380),
                        ),
                        switchInCurve: kShellEase,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: _typing || conversation.replying
                            ? ShellComposer(
                                key: const ValueKey('composer'),
                                focusNode: _focus,
                                replying: conversation.replying,
                                onSend: conversation.send,
                                onStop: conversation.stop,
                                onVoice: () {
                                  setState(() => _typing = false);
                                  _talk();
                                },
                              )
                            : _VoiceDock(
                                key: const ValueKey('dock'),
                                compact: !empty,
                                onTalk: _talk,
                                onType: _type,
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    return ValueListenableBuilder(
      valueListenable: services.account,
      builder: (context, account, _) => IconButton(
        tooltip: 'Settings',
        onPressed: () => context.push('/settings'),
        icon: ShellAvatar(account: account),
      ),
    );
  }
}

/// The voice button, front and centre, with typing beside it.
class _VoiceDock extends StatelessWidget {
  const _VoiceDock({
    super.key,
    required this.compact,
    required this.onTalk,
    required this.onType,
  });

  final bool compact;
  final VoidCallback onTalk;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final orb = compact ? 84.0 : 112.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shrinks rather than overflows on a very narrow screen.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SideButton(
                  icon: Icons.keyboard_alt_outlined,
                  tooltip: 'Type a message',
                  onTap: onType,
                ),
                const SizedBox(width: 28),
                Semantics(
                  button: true,
                  label: 'Talk to Octopilot',
                  child: Tooltip(
                    message: 'Talk',
                    child: Pressable(
                      scale: 0.9,
                      onTap: onTalk,
                      child: Hero(
                        tag: 'voice-orb',
                        child: ValueListenableBuilder(
                          valueListenable: ShellScope.of(context).voiceId,
                          builder: (context, _, _) => VoiceOrb(
                            size: orb,
                            colors: ShellScope.of(context).currentVoice?.colors,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                // Keeps the orb centred.
                const SizedBox(width: 48),
              ],
            ),
          ),
          if (!compact)
            Text(
              'Tap to talk',
              style: TextStyle(
                color: c.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Pressable(
          scale: 0.88,
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, color: c.text, size: 22),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final account = ShellScope.of(context).account;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 24),
          child: ShellColumn(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Reveal(
                  child: ValueListenableBuilder(
                    valueListenable: account,
                    builder: (context, account, _) => Text(
                      _greeting(account),
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Reveal(
                  delay: const Duration(milliseconds: 90),
                  child: ShimmerText(
                    'What will you do today?',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const ModeCards(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _greeting(ShellAccount? account) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final first = account?.name.trim().split(RegExp(r'\s+')).first;
    return first == null || first.isEmpty ? part : '$part, $first';
  }
}

/// Text with a slow band of light sweeping across it.
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: motion(context, const Duration(milliseconds: 3600)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final text = Text(
      widget.text,
      textAlign: TextAlign.center,
      style: widget.style,
    );
    if (reduceMotion(context)) return text;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final x = -1.5 + _c.value * 4;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 1, -0.3),
            end: Alignment(x + 1, 0.3),
            colors: [c.text, c.accent, const Color(0xFFFF8A5B), c.text],
            stops: const [0.3, 0.48, 0.55, 0.7],
          ).createShader(rect),
          child: child,
        );
      },
      child: text,
    );
  }
}
