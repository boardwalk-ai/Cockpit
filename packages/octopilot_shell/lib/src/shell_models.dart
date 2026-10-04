import 'package:flutter/material.dart';

/// The three modes every module belongs to.
enum ShellMode {
  create(
    title: 'Create',
    tagline: 'Write and make things',
    icon: Icons.edit_outlined,
    color: Color(0xFFFF5A4E),
  ),
  learn(
    title: 'Learn',
    tagline: 'Study and practise',
    icon: Icons.school_outlined,
    color: Color(0xFF2BB58C),
  ),
  organize(
    title: 'Organize',
    tagline: 'Notes and plans',
    icon: Icons.folder_open_outlined,
    color: Color(0xFF8B83F0),
  );

  const ShellMode({
    required this.title,
    required this.tagline,
    required this.icon,
    required this.color,
  });

  final String title;
  final String tagline;
  final IconData icon;
  final Color color;

  /// The mode's Library page.
  String get path => '/mode/$name';

  static ShellMode? byName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}

/// A module as a Library shows it. The host app lists them; the shell never
/// imports a module.
@immutable
class ShellModuleEntry {
  const ShellModuleEntry({
    required this.id,
    required this.mode,
    required this.title,
    required this.description,
    required this.icon,
    this.path,
  });

  final String id;
  final ShellMode mode;
  final String title;
  final String description;
  final IconData icon;

  /// Where the module lives. Null = not out yet ("Soon").
  final String? path;

  bool get available => path != null;
}

/// The signed-in account, as the shell shows it.
@immutable
class ShellAccount {
  const ShellAccount({
    required this.name,
    this.email,
    this.photoUrl,
    this.plan,
    this.credits,
  });

  final String name;
  final String? email;
  final String? photoUrl;
  final String? plan;

  /// OctoCredits; null while unknown.
  final int? credits;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }
}

/// A voice the main chat can speak in. Each has its own orb colours.
@immutable
class ShellVoice {
  const ShellVoice({
    required this.id,
    required this.name,
    required this.colors,
    this.female = false,
  });

  final String id;
  final String name;

  /// The orb's two colours.
  final List<Color> colors;
  final bool female;
}
