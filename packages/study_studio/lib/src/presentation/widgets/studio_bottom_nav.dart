import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The persistent Cockpit bottom navigation. Shared across Study Studio screens
/// (Home, Dashboard, …) so the chrome stays consistent. Study Studio is the
/// selected tab by default. Calendar/Profile are placeholders until built.
class StudioBottomNav extends StatelessWidget {
  const StudioBottomNav({super.key, this.selectedIndex = 1});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void soon(String label) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label — coming soon')),
        );

    return NavigationBar(
      selectedIndex: selectedIndex,
      backgroundColor: theme.colorScheme.surface,
      onDestinationSelected: (i) {
        switch (i) {
          case 0:
          case 2:
            context.go('/'); // Home / Cockpit launcher
          case 3:
            soon('Calendar');
          case 4:
            soon('Profile');
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.school_outlined),
          selectedIcon: Icon(Icons.school_rounded),
          label: 'Study Studio',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: 'Cockpit',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          label: 'Calendar',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    );
  }
}
