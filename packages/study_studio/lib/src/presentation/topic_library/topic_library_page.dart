import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/entities/topic.dart';
import '../widgets/topic_card.dart';

enum _Filter { all, weak, mastered, highImportance, hard }

enum _Sort { importance, difficulty, mastery, title }

class TopicLibraryPage extends ConsumerStatefulWidget {
  const TopicLibraryPage({super.key, required this.studioId});
  final String studioId;

  @override
  ConsumerState<TopicLibraryPage> createState() => _TopicLibraryPageState();
}

class _TopicLibraryPageState extends ConsumerState<TopicLibraryPage> {
  String _query = '';
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.importance;

  List<Topic> _apply(List<Topic> topics) {
    var list = topics.where((t) {
      if (_query.isNotEmpty &&
          !t.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.weak:
          return t.isWeak;
        case _Filter.mastered:
          return t.mastery >= 0.8;
        case _Filter.highImportance:
          return t.importance >= 4;
        case _Filter.hard:
          return t.difficulty >= 4;
      }
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case _Sort.importance:
          return b.importance.compareTo(a.importance);
        case _Sort.difficulty:
          return b.difficulty.compareTo(a.difficulty);
        case _Sort.mastery:
          return a.mastery.compareTo(b.mastery);
        case _Sort.title:
          return a.title.compareTo(b.title);
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioProvider(widget.studioId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Topic Library'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/study/${widget.studioId}'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (studio) {
          final topics = _apply(studio.topics);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(CockpitSpacing.lg),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search topics',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: CockpitSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _EnumDropdown<_Filter>(
                            label: 'Filter',
                            value: _filter,
                            values: _Filter.values,
                            naming: _filterName,
                            onChanged: (v) => setState(() => _filter = v),
                          ),
                        ),
                        const SizedBox(width: CockpitSpacing.md),
                        Expanded(
                          child: _EnumDropdown<_Sort>(
                            label: 'Sort by',
                            value: _sort,
                            values: _Sort.values,
                            naming: _sortName,
                            onChanged: (v) => setState(() => _sort = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: topics.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        title: 'No topics match',
                        message: 'Try a different filter or search term.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            CockpitSpacing.lg, 0, CockpitSpacing.lg, CockpitSpacing.lg),
                        itemCount: topics.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CockpitSpacing.md),
                        itemBuilder: (_, i) => TopicCard(topic: topics[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _filterName(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.weak => 'Weak',
        _Filter.mastered => 'Mastered',
        _Filter.highImportance => 'High importance',
        _Filter.hard => 'Hard',
      };

  static String _sortName(_Sort s) => switch (s) {
        _Sort.importance => 'Importance',
        _Sort.difficulty => 'Difficulty',
        _Sort.mastery => 'Lowest mastery',
        _Sort.title => 'Title',
      };
}

class _EnumDropdown<T> extends StatelessWidget {
  const _EnumDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.naming,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) naming;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text(naming(v))),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }
}
