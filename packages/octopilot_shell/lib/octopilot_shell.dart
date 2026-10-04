/// The Octopilot app shell: the main chat Home, a Library per mode, and the
/// app's settings. Modules plug in through [ShellServices]; the shell never
/// imports one.
library;

export 'src/chat/chat_controller.dart';
export 'src/chat/main_chat.dart';
export 'src/shell_app.dart';
export 'src/shell_models.dart';
export 'src/shell_scope.dart';
export 'src/shell_theme.dart';
export 'src/voice/greetings.dart';
export 'src/voice/voice_engine.dart';
export 'src/voice/voice_orb.dart' show VoiceOrb, VoicePhase;
export 'src/widgets.dart' show formatCredits;
