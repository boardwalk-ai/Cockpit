import 'package:flutter/material.dart';

/// Octopilot's dark palette: near-black, red → coral accent.
abstract final class AdminColors {
  static const bg = Color(0xFF0B0B0C);
  static const surface = Color(0xFF151517);
  static const surface2 = Color(0xFF1C1C1F);
  static const line = Color(0xFF2A2A2F);
  static const text = Color(0xFFF5F5F6);
  static const muted = Color(0xFFA3A3AB);
  static const faint = Color(0xFF6E6E78);
  static const accent = Color(0xFFFF343C);
  static const accent2 = Color(0xFFFF8A5B);
  static const good = Color(0xFF34D399);
  static const gradient = LinearGradient(
    colors: [accent, Color(0xFFD5121B), accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData adminTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AdminColors.accent,
      secondary: AdminColors.accent2,
      surface: AdminColors.surface,
      onSurface: AdminColors.text,
      outlineVariant: AdminColors.line,
    ),
    scaffoldBackgroundColor: AdminColors.bg,
    useMaterial3: true,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AdminColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AdminColors.text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AdminColors.surface,
      indicatorColor: AdminColors.accent.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? AdminColors.accent
              : AdminColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? AdminColors.text
              : AdminColors.muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AdminColors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AdminColors.accent, width: 1.4),
      ),
      hintStyle: const TextStyle(color: AdminColors.faint),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Colors.white : AdminColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AdminColors.accent
            : AdminColors.surface2,
      ),
      trackOutlineColor: WidgetStateProperty.all(AdminColors.line),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AdminColors.surface2,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AdminColors.surface,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AdminColors.surface),
  );
}

/// The Octopilot ring.
class OctoMark extends StatelessWidget {
  const OctoMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const SweepGradient(
        colors: [AdminColors.accent, AdminColors.accent2, AdminColors.accent],
      ),
      boxShadow: [
        BoxShadow(
          color: AdminColors.accent.withValues(alpha: 0.4),
          blurRadius: size * 0.6,
        ),
      ],
    ),
    child: Padding(
      padding: EdgeInsets.all(size * 0.26),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AdminColors.bg,
        ),
      ),
    ),
  );
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.5 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: AdminColors.gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AdminColors.accent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
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

/// A rounded card on the dark background.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.onTap,
    this.highlight = false,
    this.padding,
  });
  final Widget child;
  final VoidCallback? onTap;
  final bool highlight;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: highlight ? AdminColors.surface2 : AdminColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: highlight
            ? AdminColors.accent.withValues(alpha: 0.5)
            : AdminColors.line,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
