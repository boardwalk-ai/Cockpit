import 'package:flutter/material.dart';
import 'studio_scaffold.dart';

/// Consistent touch targets for all Study Studio routes, including pages that
/// do not use the shared navigation shell. Desktop inherits its original theme.
class StudyMobileSurface extends StatelessWidget {
  const StudyMobileSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isMobilePlatform(context)) return child;
    final theme = Theme.of(context);
    const size = WidgetStatePropertyAll(Size(48, 48));
    const touch = MaterialTapTargetSize.padded;
    return Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(minimumSize: size, tapTargetSize: touch),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(minimumSize: size, tapTargetSize: touch),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: size,
            tapTargetSize: touch,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: size,
            tapTargetSize: touch,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Reflows metadata and small action groups on phones without shrinking text.
/// Desktop retains the original row, including its flex and spacing behavior.
class MobileWrap extends StatelessWidget {
  const MobileWrap({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });

  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    if (!isMobilePlatform(context)) {
      return Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: mainAxisSize,
        children: children,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: mainAxisAlignment == MainAxisAlignment.center
          ? WrapAlignment.center
          : WrapAlignment.start,
      children: [
        for (final child in children)
          if (child is! Spacer && !(child is SizedBox && child.child == null))
            if (child is Flexible) child.child else child,
      ],
    );
  }
}
