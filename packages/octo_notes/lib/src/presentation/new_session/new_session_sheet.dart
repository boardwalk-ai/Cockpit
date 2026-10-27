import 'dart:async';

import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/session_providers.dart';
import '../../domain/pairing.dart';
import '../../theme/octo_notes_theme.dart';
import 'pair_panel.dart';
import 'pairing_widgets.dart';

/// New session on a phone: a sheet that rises over Home. What a lecture
/// needs is up top (title, course, workspace, where to record), the rest
/// folds under "More options", and Start stays at the bottom. The desktop
/// keeps its modal (`showNewSessionDialog`).
/// [courseId] picks the notebook (course) up front, e.g. "New page in Biology 101".
Future<void> showNewSessionSheet(BuildContext context, {String? courseId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => OctoNotesTheme.wrap(
      context: context,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .84,
        minChildSize: .5,
        maxChildSize: 1,
        snap: true,
        snapSizes: const [.84],
        builder: (_, scroll) => NewSessionSheet(scroll: scroll, courseId: courseId),
      ),
    ),
  );
}

const _workspaces = [
  ('typewriter', 'Typewriter', Icons.keyboard_alt_outlined),
  ('pencil', 'Magic Pencil', Icons.draw_outlined),
  ('both', 'Lecture capture', Icons.mic_none_rounded),
];

class _Course {
  const _Course(this.id, this.name);
  final String? id;
  final String name;
}

/// Settings kept for "Use last settings".
const _lastKey = 'octonotes.lastSession';

class NewSessionSheet extends ConsumerStatefulWidget {
  const NewSessionSheet({super.key, required this.scroll, this.courseId});

  final ScrollController scroll;
  final String? courseId;

  @override
  ConsumerState<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends ConsumerState<NewSessionSheet> {
  final _title = TextEditingController();
  final _topic = TextEditingController();
  bool _titleEdited = false;
  List<_Course> _courses = const [];
  _Course? _course;
  int _workspace = 2;
  bool _otherPhone = false;
  bool _more = false;
  bool _saveToDeck = true;
  bool _liveTranscription = true;
  bool _smartOrganization = true;
  bool _liveSuggestions = false;
  bool _usedLast = false;
  bool _starting = false;
  Pairing? _pairing;

  /// Read once: the sheet still cancels an unused pairing while it closes.
  late final _api = ref.read(octoNotesApiProvider);

  void _cancelPairing() {
    final p = _pairing;
    _pairing = null;
    if (p != null && !p.isStarted) {
      unawaited(_api?.cancelPairing(p.id).catchError((_) {}));
    }
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => _titleEdited = _title.text != _autoTitle());
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final api = ref.read(octoNotesApiProvider);
    var list = const [
      _Course(null, 'Biology 101'),
      _Course(null, 'Macroeconomics'),
      _Course(null, 'Contract Law'),
    ];
    if (api != null) {
      try {
        list = [
          for (final c in await api.courses())
            if (c is Map) _Course(c['id'] as String?, '${c['name']}'),
        ];
      } on Object {
        // Offline: no courses to pick; the title still works.
        list = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _courses = list;
      _course = list.where((c) => c.id != null && c.id == widget.courseId).firstOrNull ?? (list.isEmpty ? null : list.first);
      if (!_titleEdited) _title.text = _autoTitle();
    });
  }

  String _autoTitle() {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final when = '${months[now.month - 1]} ${now.day}, $h:${now.minute.toString().padLeft(2, '0')} '
        '${now.hour < 12 ? 'AM' : 'PM'}';
    return _course == null ? 'Lecture · $when' : '${_course!.name} · $when';
  }

  void _pickCourse(_Course c) {
    setState(() {
      _course = c;
      if (!_titleEdited) _title.text = _autoTitle();
    });
  }

  Future<void> _addCourse() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New course'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Organic Chemistry'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    final n = name.text.trim();
    if (ok != true || n.isEmpty) return;
    String? id;
    final api = ref.read(octoNotesApiProvider);
    if (api != null) {
      try {
        id = (await api.createCourse(n))['id'] as String?;
      } on Object catch (e) {
        if (mounted) _say('Could not add the course: $e');
        return;
      }
    }
    final c = _Course(id, n);
    setState(() => _courses = [..._courses, c]);
    _pickCourse(c);
  }

  Future<void> _useLast() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList(_lastKey);
    if (saved == null || saved.length < 6) {
      _say('No earlier session on this phone yet.');
      return;
    }
    setState(() {
      final course = _courses.where((c) => c.name == saved[0]).firstOrNull;
      if (course != null && widget.courseId == null) _course = course;
      _workspace = int.tryParse(saved[1]) ?? _workspace;
      _otherPhone = saved[2] == '1';
      _liveTranscription = saved[3] == '1';
      _smartOrganization = saved[4] == '1';
      _liveSuggestions = saved[5] == '1';
      if (!_titleEdited) _title.text = _autoTitle();
      _usedLast = true;
    });
  }

  Future<void> _saveLast() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_lastKey, [
      _course?.name ?? '',
      '$_workspace',
      _otherPhone ? '1' : '0',
      _liveTranscription ? '1' : '0',
      _smartOrganization ? '1' : '0',
      _liveSuggestions ? '1' : '0',
    ]);
  }

  void _say(String m) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _start() async {
    if (_otherPhone && !(_pairing?.isPaired ?? false)) {
      _say('Pair the other phone first, or record on this phone.');
      return;
    }
    final title = _title.text.trim().isEmpty ? _autoTitle() : _title.text.trim();
    setState(() => _starting = true);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final api = ref.read(octoNotesApiProvider);
    // This phone records and works the session (solo), or another phone
    // records and this one receives the transcript.
    final role = _otherPhone ? 'receiver' : 'solo';
    var target = '/notes/session?role=$role';
    if (api != null) {
      try {
        final session = await api.createSession(
          title: title,
          courseId: _course?.id,
          workspaceMode: _workspaces[_workspace].$1,
          config: {
            'record': true,
            'liveTranscription': _liveTranscription,
            'smartOrganization': _smartOrganization,
            'liveSuggestions': _liveSuggestions,
          },
        );
        if (_otherPhone) {
          await api.startPairing(_pairing!.id, session.id);
          PairHaptics.start();
        }
        target = '/notes/session?id=${session.id}&role=$role';
      } on Object catch (e) {
        if (mounted) {
          setState(() => _starting = false);
          _say('Could not start the session: $e');
        }
        return;
      }
    }
    _pairing = null; // Handed over: not cancelled on close.
    await _saveLast();
    navigator.pop();
    router.go(target);
  }

  @override
  void dispose() {
    _cancelPairing();
    _title.dispose();
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = scheme.surfaceContainerHigh;
    final label = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: .6,
    );
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: CockpitSpacing.lg, bottom: CockpitSpacing.sm),
          child: Text(t.toUpperCase(), style: label),
        );

    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, 0, CockpitSpacing.lg, CockpitSpacing.lg),
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: CockpitSpacing.sm, bottom: CockpitSpacing.md),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: Text('New session', style: theme.textTheme.titleLarge)),
                    ActionChip(
                      avatar: Icon(_usedLast ? Icons.check_rounded : Icons.history_rounded, size: 16),
                      label: Text(_usedLast ? 'Last settings used' : 'Use last settings'),
                      onPressed: _useLast,
                    ),
                  ],
                ),
                heading('Title'),
                TextField(controller: _title, textInputAction: TextInputAction.done),
                heading('Course'),
                Wrap(
                  spacing: CockpitSpacing.sm,
                  runSpacing: CockpitSpacing.sm,
                  children: [
                    for (final c in _courses)
                      ChoiceChip(
                        label: Text(c.name),
                        selected: identical(c, _course),
                        onSelected: (_) => _pickCourse(c),
                        showCheckmark: false,
                        selectedColor: scheme.primary,
                        labelStyle: TextStyle(color: identical(c, _course) ? scheme.onPrimary : null),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Course'),
                      onPressed: _addCourse,
                    ),
                  ],
                ),
                heading('Workspace'),
                Row(
                  children: [
                    for (var i = 0; i < _workspaces.length; i++) ...[
                      if (i > 0) const SizedBox(width: CockpitSpacing.sm),
                      Expanded(
                        child: _WorkspaceTile(
                          icon: _workspaces[i].$3,
                          label: _workspaces[i].$2,
                          selected: i == _workspace,
                          onTap: () => setState(() => _workspace = i),
                        ),
                      ),
                    ],
                  ],
                ),
                heading('Record on'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('This phone'), icon: Icon(Icons.smartphone_rounded)),
                    ButtonSegment(value: true, label: Text('Another phone'), icon: Icon(Icons.phonelink_ring_rounded)),
                  ],
                  selected: {_otherPhone},
                  onSelectionChanged: (s) => setState(() {
                    _otherPhone = s.first;
                    if (!_otherPhone) _cancelPairing();
                  }),
                ),
                const SizedBox(height: CockpitSpacing.sm),
                if (!_otherPhone)
                  _InfoRow(
                    fill: fill,
                    icon: Icons.mic_none_rounded,
                    text: 'This phone records the lecture',
                    trailing: Text('Ready', style: theme.textTheme.labelMedium?.copyWith(color: CockpitColors.brand.success)),
                  )
                else
                  PairPanel(onChanged: (p) => _pairing = p, onPaired: () => setState(() {})),
                const SizedBox(height: CockpitSpacing.sm),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => setState(() => _more = !_more),
                  icon: Icon(_more ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  label: Text(_more ? 'Fewer options' : 'More options · topic, deck, slides, AI'),
                ),
                if (_more) ...[
                  heading('Topic'),
                  TextField(controller: _topic, decoration: const InputDecoration(hintText: 'Cellular Respiration')),
                  const SizedBox(height: CockpitSpacing.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(Icons.layers_outlined, color: scheme.primary),
                    title: const Text('Save in The Deck'),
                    subtitle: Text(_course == null ? 'The Deck' : 'The Deck / ${_course!.name}'),
                    value: _saveToDeck,
                    onChanged: (v) => setState(() => _saveToDeck = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.upload_file_rounded, color: scheme.primary),
                    title: const Text('Add materials and slides'),
                    subtitle: const Text('After the session starts, from its Materials panel'),
                  ),
                  heading('AI assistance'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Live transcription'),
                    value: _liveTranscription,
                    onChanged: (v) => setState(() => _liveTranscription = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Smart organization'),
                    value: _smartOrganization,
                    onChanged: (v) => setState(() => _smartOrganization = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Live AI suggestions'),
                    value: _liveSuggestions,
                    onChanged: (v) => setState(() => _liveSuggestions = v),
                  ),
                ],
              ],
            ),
          ),
          // Start stays put while the options scroll.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(CockpitSpacing.lg, CockpitSpacing.sm, CockpitSpacing.lg, CockpitSpacing.md),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fiber_manual_record_rounded),
                  label: Text(
                    _otherPhone && (_pairing?.isPaired ?? false)
                        ? 'Start · record on ${_pairing!.recorderName ?? 'the other phone'}'
                        : 'Start session',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: .1) : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CockpitSpacing.md, horizontal: CockpitSpacing.xs),
          child: Column(
            children: [
              Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: CockpitSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: selected ? scheme.primary : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.fill, required this.icon, required this.text, this.trailing});

  final Color fill;
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.md, vertical: CockpitSpacing.md),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: CockpitSpacing.sm),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            ?trailing,
          ],
        ),
      );
}
