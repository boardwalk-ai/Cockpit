import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'chat/chat_controller.dart';
import 'chat/main_chat.dart';
import 'shell_models.dart';
import 'voice/voice_engine.dart';

/// Everything the shell needs from the host app. The shell owns the screens;
/// the host owns sign-in, the account, settings that touch a server, and the
/// modules.
class ShellServices {
  ShellServices({
    required this.chat,
    VoiceEngine? voice,
    required this.modules,
    required this.account,
    required this.themeMode,
    required this.setThemeMode,
    this.onAiSettings,
    this.onNotifications,
    this.onCredits,
    this.onAbout,
    this.onSignIn,
    this.onSignOut,
    this.onDeleteAccount,
    void Function(BuildContext context, ShellModuleEntry module)? openModule,
  }) : voice = voice ?? DemoVoiceEngine(),
       openModule = openModule ?? _push;

  final MainChat chat;

  /// Microphone and speaker for voice chat.
  final VoiceEngine voice;

  /// Every module, out or not, in Library order.
  final List<ShellModuleEntry> modules;

  /// Null while signed out or loading.
  final ValueNotifier<ShellAccount?> account;

  final ValueNotifier<ThemeMode> themeMode;
  final void Function(ThemeMode mode) setThemeMode;

  /// Settings rows; a null one is not shown.
  final void Function(BuildContext context)? onAiSettings;
  final void Function(BuildContext context)? onNotifications;
  final void Function(BuildContext context)? onCredits;
  final void Function(BuildContext context)? onAbout;

  /// Shown while signed out.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// Deletes the account for good (after the shell has asked).
  final Future<void> Function(BuildContext context)? onDeleteAccount;

  final void Function(BuildContext context, ShellModuleEntry module) openModule;

  /// The conversation on the Home screen, kept while the user visits modules.
  late final ChatController conversation = ChatController(chat);

  List<ShellModuleEntry> modulesIn(ShellMode mode) => [
    for (final m in modules)
      if (m.mode == mode) m,
  ];

  static void _push(BuildContext context, ShellModuleEntry module) =>
      context.push(module.path!);
}

/// Hands [ShellServices] to the shell's screens.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.services, required super.child});

  final ShellServices services;

  static ShellServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) =>
      services != oldWidget.services;
}
