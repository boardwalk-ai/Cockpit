import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/studio.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';
import 'study_home_mobile.dart';

/// `/study/library`: every studio, to search and sort. Opened from "View
/// all" on the home.
class StudioLibraryPage extends ConsumerWidget {
  const StudioLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SmColors.of(context);
    final studios = ref.watch(studioListProvider);
    return Scaffold(
      backgroundColor: c.background,
      body: studios.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: c.accent, strokeWidth: 2.5),
        ),
        error: (e, _) => Center(
          child: Text(
            "Couldn't load your studios.",
            style: SmText.of(context).small,
          ),
        ),
        data: (list) => StudioLibrary(
          studios: list,
          onRefresh: () {
            ref.invalidate(studioListProvider);
            return ref.read(studioListProvider.future);
          },
        ),
      ),
    );
  }
}

enum StudioSort { recent, name, mastery }

/// The library itself, from a list (tests drive this directly).
class StudioLibrary extends StatefulWidget {
  const StudioLibrary({super.key, required this.studios, this.onRefresh});

  final List<Studio> studios;
  final Future<void> Function()? onRefresh;

  @override
  State<StudioLibrary> createState() => _StudioLibraryState();
}

class _StudioLibraryState extends State<StudioLibrary> {
  final _search = TextEditingController();
  var _sort = StudioSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Studio> get _shown {
    final q = _search.text.trim().toLowerCase();
    final matching = [
      for (final s in widget.studios)
        if (q.isEmpty ||
            s.title.toLowerCase().contains(q) ||
            s.subject.toLowerCase().contains(q))
          s,
    ];
    return switch (_sort) {
      StudioSort.recent => byRecent(matching),
      StudioSort.name =>
        matching..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        ),
      StudioSort.mastery =>
        matching..sort((a, b) => b.overallMastery.compareTo(a.overallMastery)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final shown = _shown;

    Widget list(double top) => ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(20, top, 20, 32),
      children: [
        SmAppear(index: 0, child: Text('Your studios', style: t.greeting)),
        const SizedBox(height: 4),
        SmAppear(
          index: 1,
          child: Text(
            '${widget.studios.length} studio${widget.studios.length == 1 ? '' : 's'}',
            style: t.small.copyWith(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        SmAppear(
          index: 2,
          child: _SearchField(
            controller: _search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        SmAppear(
          index: 3,
          child: Row(
            children: [
              for (final (sort, label) in const [
                (StudioSort.recent, 'Recent'),
                (StudioSort.name, 'Name'),
                (StudioSort.mastery, 'Mastery'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SortChip(
                    label: label,
                    selected: _sort == sort,
                    onTap: () => setState(() => _sort = sort),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text(
              widget.studios.isEmpty
                  ? 'No studios yet.'
                  : 'No studio matches “${_search.text.trim()}”.',
              textAlign: TextAlign.center,
              style: t.small,
            ),
          ),
        for (final (i, studio) in shown.indexed)
          SmAppear(
            // Keyed so a new order animates in afresh.
            key: ValueKey('${_sort.name}-${studio.id}'),
            index: 4 + i,
            child: StudioRow(studio: studio, divider: i < shown.length - 1),
          ),
      ],
    );

    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    return SmHeaderPage(
      header: SmHeader(
        trailing: SmPressable(
          semanticLabel: 'New study studio',
          haptic: SmHaptics.thud,
          scale: 0.9,
          onTap: () => context.go('/study/upload'),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.add_rounded, color: c.accentSoft, size: 24),
          ),
        ),
      ),
      child: widget.onRefresh == null
          ? list(top)
          : RefreshIndicator(
              color: c.accent,
              backgroundColor: c.raised,
              edgeOffset: top,
              onRefresh: () async {
                SmHaptics.tap();
                await widget.onRefresh!();
              },
              child: list(top),
            ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: c.hint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: c.accent,
              style: t.body,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search studios',
                hintStyle: t.body.copyWith(color: c.hint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    return SmPressable(
      semanticLabel: 'Sort by $label',
      onTap: onTap,
      child: AnimatedContainer(
        duration: smReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.text : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.text : c.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: SmFonts.heading,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? c.background : c.muted,
          ),
        ),
      ),
    );
  }
}
