import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Width at/above which we switch from the phone layout (bottom nav, single
/// column) to the desktop/web layout (left nav rail, multi-column).
const double kStudioDesktop = 900;

/// True when the current view should use the desktop/web layout.
bool isDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kStudioDesktop;

/// The five persistent destinations, shared by the phone bottom nav and the
/// desktop rail.
const studioNavItems = <(IconData, IconData, String)>[
  (Icons.home_outlined, Icons.home_rounded, 'Home'),
  (Icons.school_outlined, Icons.school_rounded, 'Study Studio'),
  (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Cockpit'),
  (Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Calendar'),
  (Icons.person_outline, Icons.person_rounded, 'Profile'),
];

void handleStudioNav(BuildContext context, int i) {
  switch (i) {
    case 0:
    case 2:
      context.go('/'); // Home / Cockpit launcher
    case 1:
      context.go('/study');
    case 3:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calendar — coming soon')),
      );
    case 4:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile — coming soon')),
      );
  }
}

/// Responsive chrome for the shell screens (Home, Dashboard). On desktop it
/// renders a left navigation rail beside the content; on phones it falls back
/// to the bottom navigation bar. The content itself is provided by each screen.
class StudioShell extends StatelessWidget {
  const StudioShell({
    super.key,
    required this.child,
    this.selectedIndex = 1,
  });

  final Widget child;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (isDesktop(context)) {
      return Scaffold(
        body: Row(
          children: [
            _NavRail(selectedIndex: selectedIndex),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNav(selectedIndex: selectedIndex),
    );
  }
}

/// Left navigation rail for desktop/web.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final violet = _shiftHue(scheme.primary, -28);

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.lg,
                CockpitSpacing.lg,
                CockpitSpacing.lg,
                CockpitSpacing.xl,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(CockpitRadii.sm),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [violet, scheme.primary],
                      ),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: CockpitSpacing.sm),
                  Expanded(
                    child: Text(
                      'Study Studio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < studioNavItems.length; i++)
              _RailItem(
                icon: studioNavItems[i].$1,
                selectedIcon: studioNavItems[i].$2,
                label: studioNavItems[i].$3,
                selected: i == selectedIndex,
                onTap: () => handleStudioNav(context, i),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(CockpitSpacing.lg),
              child: Text(
                'Boardwalks LLC',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CockpitSpacing.md,
        vertical: 3,
      ),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(CockpitRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: CockpitSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: CockpitSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone bottom navigation.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationBar(
      selectedIndex: selectedIndex,
      backgroundColor: theme.colorScheme.surface,
      onDestinationSelected: (i) => handleStudioNav(context, i),
      destinations: [
        for (final item in studioNavItems)
          NavigationDestination(
            icon: Icon(item.$1),
            selectedIcon: Icon(item.$2),
            label: item.$3,
          ),
      ],
    );
  }
}

/// Centers page content and caps its width on very wide screens so lines stay
/// readable. Use inside desktop layouts.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child, this.maxWidth = 1160});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

Color _shiftHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  final h = (hsl.hue + degrees) % 360;
  return hsl.withHue(h < 0 ? h + 360 : h).toColor();
}
