import 'package:flutter/material.dart';

import '../aurora.dart';
import '../home/mode_cards.dart';
import '../motion.dart';
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
      body: AuroraBackground(
        colors: [mode.color, mode.color.withValues(alpha: 0.7), c.accent],
        child: SafeArea(
          child: Column(
            children: [
              ShellTopBar(
                title: '',
                leading: ShellIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    ShellColumn(
                      maxWidth: 880,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ModeIcon(mode, size: 64),
                          const SizedBox(height: 16),
                          Reveal(
                            delay: const Duration(milliseconds: 120),
                            child: Text(
                              mode.title,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                          Reveal(
                            delay: const Duration(milliseconds: 180),
                            child: Text(
                              mode.tagline,
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (modules.isEmpty)
                            Reveal(
                              delay: const Duration(milliseconds: 260),
                              child: Text(
                                'Nothing here yet. New tools are on the way.',
                                style: TextStyle(color: c.hint, fontSize: 12),
                              ),
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
            for (final (i, module) in modules.indexed)
              SizedBox(
                width: width,
                child: Reveal(
                  delay: Duration(milliseconds: 260 + i * 90),
                  offset: const Offset(0, 0.25),
                  scale: 0.9,
                  child: ModuleCard(module),
                ),
              ),
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

    return Semantics(
      button: true,
      label: module.title,
      child: Pressable(
        onTap: out
            ? () {
                Haptics.tap();
                services.openModule(context, module);
              }
            : () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text('${module.title} is coming soon.')),
                ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 168),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: out
                  ? [
                      Color.alphaBlend(color.withValues(alpha: 0.2), c.surface),
                      c.surface.withValues(alpha: 0.9),
                    ]
                  : [
                      c.surface.withValues(alpha: 0.7),
                      c.surface.withValues(alpha: 0.5),
                    ],
            ),
            border: Border.all(
              color: out ? color.withValues(alpha: 0.55) : c.border,
            ),
            boxShadow: out
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: out
                          ? color.withValues(alpha: 0.2)
                          : c.raised.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      module.icon,
                      color: out ? color : c.hint,
                      size: 24,
                    ),
                  ),
                  const Spacer(),
                  if (out)
                    Icon(Icons.arrow_outward_rounded, color: color, size: 20)
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.raised,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Soon',
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                module.title,
                style: TextStyle(
                  color: out ? c.text : c.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                module.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.hint, fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
