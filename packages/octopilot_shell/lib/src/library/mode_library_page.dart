import 'package:flutter/material.dart';

import '../shell_models.dart';
import '../shell_scope.dart';
import '../shell_theme.dart';
import '../widgets.dart';

/// One mode's Library: its modules, the ones not out yet marked "Soon".
class ModeLibraryPage extends StatelessWidget {
  const ModeLibraryPage({super.key, required this.mode});

  final ShellMode mode;

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final modules = services.modulesIn(mode);
    final c = ShellColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ShellTopBar(
              title: mode.title,
              leading: ShellIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  ShellColumn(
                    maxWidth: 880,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: mode.color.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(mode.icon, color: mode.color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${mode.title} library',
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    mode.tagline,
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        if (modules.isEmpty)
                          Text(
                            'Nothing here yet. New tools are on the way.',
                            style: TextStyle(color: c.hint, fontSize: 14),
                          )
                        else
                          _Grid(modules: modules),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.modules});

  final List<ShellModuleEntry> modules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 640 ? 3 : 2;
        const gap = 12.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final module in modules)
              SizedBox(width: width, child: ModuleCard(module)),
          ],
        );
      },
    );
  }
}

class ModuleCard extends StatelessWidget {
  const ModuleCard(this.module, {super.key});

  final ShellModuleEntry module;

  @override
  Widget build(BuildContext context) {
    final services = ShellScope.of(context);
    final c = ShellColors.of(context);
    final color = module.mode.color;
    final out = module.available;
    final radius = BorderRadius.circular(18);

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: out ? color.withValues(alpha: 0.55) : c.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: out
            ? () => services.openModule(context, module)
            : () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text('${module.title} is coming soon.')),
                ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: out
                          ? color.withValues(alpha: 0.16)
                          : c.raised.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      module.icon,
                      color: out ? color : c.hint,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  if (!out)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.raised,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Soon',
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                module.title,
                style: TextStyle(
                  color: out ? c.text : c.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                module.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.hint, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
