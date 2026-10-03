import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shell_models.dart';
import '../shell_theme.dart';

/// Create, Learn and Organize. Stacked on phones, side by side when wide.
class ModeCards extends StatelessWidget {
  const ModeCards({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cards = [for (final mode in ShellMode.values) ModeCard(mode)];
        if (box.maxWidth >= 600) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: card),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              card,
            ],
          ],
        );
      },
    );
  }
}

class ModeCard extends StatelessWidget {
  const ModeCard(this.mode, {super.key});

  final ShellMode mode;

  @override
  Widget build(BuildContext context) {
    final c = ShellColors.of(context);
    final radius = BorderRadius.circular(18);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.push(mode.path),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(mode.icon, color: mode.color, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.tagline,
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.hint),
            ],
          ),
        ),
      ),
    );
  }
}
