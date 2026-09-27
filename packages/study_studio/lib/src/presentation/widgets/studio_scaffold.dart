import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'account_bar.dart';

/// Width at/above which we switch from the phone layout (bottom nav, single
/// column) to the desktop/web layout (left nav rail, multi-column).
const double kStudioDesktop = 900;

/// True when the current view should use the desktop/web layout.
bool isMobilePlatform(BuildContext context) =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    MediaQuery.sizeOf(context).width < kStudioDesktop;

/// Wide desktop browsers keep their existing layout. Native phones retain the
/// independent mobile layout when rotated; narrow browsers use it as well.
bool isDesktop(BuildContext context) => !isMobilePlatform(context);

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Calendar — coming soon')));
    case 4:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile — coming soon')));
  }
}

/// Responsive chrome for the shell screens (Home, Dashboard). On desktop it
/// renders a left navigation rail beside the content; on phones it falls back
/// to the bottom navigation bar. The content itself is provided by each screen.
class StudioShell extends StatelessWidget {
  const StudioShell({super.key, required this.child, this.selectedIndex = 1});

  final Widget child;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (isDesktop(context)) {
      return Scaffold(
        body: Column(
          children: [
            _TopDock(selectedIndex: selectedIndex),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _MobileTopBar(),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(selectedIndex: selectedIndex),
    );
  }
}

/// Slim top bar for phones: brand on the left, Octocredits + profile on the
/// right. On desktop the same controls live at the bottom of the nav rail.
class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CockpitSpacing.md,
        CockpitSpacing.sm,
        CockpitSpacing.md,
        CockpitSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: CockpitSpacing.sm),
          Flexible(
            child: Text(
              'Study Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: CockpitSpacing.sm),
          const AccountBar(compact: true),
        ],
      ),
    );
  }
}

/// Top navigation dock for desktop/web — brand + horizontal nav on the left,
/// the account/credits/notification cluster docked on the right. Shell-level,
/// so it appears on every Study Studio page. Replaces the old left rail.
class _TopDock extends StatelessWidget {
  const _TopDock({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xl),
        child: Row(
          children: [
            const _DockBrand(),
            const SizedBox(width: CockpitSpacing.lg),
            for (var i = 0; i < studioNavItems.length; i++)
              _DockNavItem(
                label: studioNavItems[i].$3,
                selected: i == selectedIndex,
                onTap: () => handleStudioNav(context, i),
              ),
            const Spacer(),
            _DockIconButton(
              icon: Icons.notifications_none_rounded,
              showDot: true,
              onTap: () {},
            ),
            const SizedBox(width: CockpitSpacing.md),
            const AccountBar(compact: true),
          ],
        ),
      ),
    );
  }
}

/// The brand lockup in the top dock: red logo tile + wordmark.
class _DockBrand extends StatelessWidget {
  const _DockBrand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadii.md),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                Color.lerp(scheme.primary, Colors.black, 0.45)!,
              ],
            ),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
        ),
        const SizedBox(width: CockpitSpacing.sm),
        Text(
          'Study Studio',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

/// A single horizontal nav link in the dock. Labels only — active reads as a
/// red-tinted pill; inactive is muted with a hover fill.
class _DockNavItem extends StatelessWidget {
  const _DockNavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(CockpitRadii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.pill),
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CockpitSpacing.md,
              vertical: CockpitSpacing.sm,
            ),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular icon button for the dock (notifications), with an optional
/// unread dot and the theme's 1px black ring.
class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.icon,
    required this.onTap,
    this.showDot = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CockpitRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20, color: scheme.onSurface),
            if (showDot)
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                ),
              ),
          ],
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
