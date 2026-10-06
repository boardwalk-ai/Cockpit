import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/source.dart';
import '../../domain/entities/studio.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';
import 'study_create_mobile.dart';

/// A studio's settings on a phone: its name (edited in place), its files
/// (and new ones to add, then Update studio), export as study notes or
/// Anki cards, and delete.
class StudioSettingsMobile extends StatefulWidget {
  const StudioSettingsMobile({
    super.key,
    required this.studio,
    required this.onBack,
    required this.onRename,
    required this.onUpdate,
    required this.onExportNotes,
    required this.onExportCards,
    required this.onDelete,
    this.pickFiles,
  });

  final Studio studio;
  final VoidCallback onBack;

  /// Saves a new name; false when it didn't take.
  final Future<bool> Function(String title) onRename;

  /// Adds [files] to the studio and rebuilds it.
  final void Function(List<SmPickedFile> files) onUpdate;
  final Future<void> Function() onExportNotes;
  final Future<void> Function() onExportCards;
  final VoidCallback onDelete;

  /// Picks files (the add sheet; replaced in tests).
  final Future<List<SmPickedFile>> Function(BuildContext context)? pickFiles;

  @override
  State<StudioSettingsMobile> createState() => _StudioSettingsMobileState();
}

class _StudioSettingsMobileState extends State<StudioSettingsMobile> {
  late final _name = TextEditingController(text: widget.studio.title);
  final _focus = FocusNode();
  final _added = <SmPickedFile>[];

  /// The name as saved: "saving", "saved", or null.
  String? _nameState;
  String? _exporting;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _saveName();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final next = _name.text.trim();
    if (next.isEmpty) {
      _name.text = widget.studio.title;
      return;
    }
    if (next == widget.studio.title || _nameState == 'saving') return;
    setState(() => _nameState = 'saving');
    var ok = false;
    try {
      ok = await widget.onRename(next);
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      SmHaptics.done();
      setState(() => _nameState = 'saved');
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && _nameState == 'saved') setState(() => _nameState = null);
      });
    } else {
      SmHaptics.error();
      setState(() {
        _nameState = null;
        _name.text = widget.studio.title;
      });
      _say('Couldn’t rename the studio');
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add() async {
    final pick = widget.pickFiles ?? showSmAddSheet;
    final files = await pick(context);
    if (!mounted || files.isEmpty) return;
    SmHaptics.select();
    final room =
        StudyCreateMobile.maxFiles -
        widget.studio.sourceFiles.length -
        _added.length;
    setState(() => _added.addAll(files.take(room < 0 ? 0 : room)));
    if (files.length > room) {
      _say('A studio takes up to ${StudyCreateMobile.maxFiles} files.');
    }
  }

  Future<void> _export(String what, Future<void> Function() run) async {
    if (_exporting != null) return;
    setState(() => _exporting = what);
    try {
      await run();
    } on Object {
      SmHaptics.error();
      if (mounted) _say('Couldn’t export just now');
    }
    if (mounted) setState(() => _exporting = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final s = widget.studio;
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    var i = 0;
    Widget appear(Widget child) => SmAppear(index: i++, child: child);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10),
      child: Text(title, style: t.section.copyWith(fontSize: 11)),
    );
    final updating = _added.isNotEmpty;

    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'Studio', onBack: widget.onBack),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(22, top, 22, 40),
            children: [
              appear(section('NAME')),
              appear(
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 2, 8, 2),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          focusNode: _focus,
                          maxLength: 200,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _focus.unfocus(),
                          cursorColor: c.accent,
                          cursorWidth: 2,
                          cursorRadius: const Radius.circular(2),
                          style: t.title.copyWith(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, a) =>
                            ScaleTransition(scale: a, child: child),
                        child: switch (_nameState) {
                          'saving' => SizedBox(
                            key: const ValueKey('saving'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.accent,
                            ),
                          ),
                          'saved' => const Icon(
                            Icons.check_circle_rounded,
                            key: ValueKey('saved'),
                            color: Color(0xFF30A46C),
                            size: 22,
                          ),
                          _ => Icon(
                            Icons.edit_rounded,
                            key: const ValueKey('edit'),
                            color: c.hint,
                            size: 18,
                          ),
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              appear(
                Text.rich(
                  TextSpan(
                    children: [
                      for (final (k, (n, w)) in [
                        (s.topicCount, 'topics'),
                        (s.flashcardCount, 'cards'),
                        (s.quizCount, 'questions'),
                      ].indexed) ...[
                        if (k > 0) const TextSpan(text: '  ·  '),
                        TextSpan(
                          text: '$n',
                          style: TextStyle(
                            fontFamily: SmFonts.heading,
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                        TextSpan(text: ' $w'),
                      ],
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: t.small.copyWith(fontSize: 12.5, color: c.hint),
                ),
              ),
              appear(
                section('FILES · ${s.sourceFiles.length + _added.length}'),
              ),
              for (final f in s.sourceFiles)
                appear(
                  _FileRow(
                    icon: SmPaper(type: f.type),
                    name: f.name,
                    note: f.processed ? 'Read' : 'Still being read',
                  ),
                ),
              for (final (k, f) in _added.indexed)
                _NewFileRow(
                  key: ObjectKey(f),
                  file: f,
                  onRemove: () {
                    SmHaptics.tap();
                    setState(() => _added.removeAt(k));
                  },
                ),
              const SizedBox(height: 10),
              appear(
                Center(
                  child: SmPressable(
                    semanticLabel: 'Add files',
                    onTap: _add,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: c.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 18, color: c.text),
                          const SizedBox(width: 6),
                          Text(
                            'Add files',
                            style: t.body.copyWith(fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: updating
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          children: [
                            SmPressable(
                              semanticLabel: 'Update studio',
                              haptic: SmHaptics.thud,
                              onTap: () => widget.onUpdate(List.of(_added)),
                              child: Container(
                                height: 50,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.accent,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: c.accent.withValues(alpha: 0.3),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.22,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: Text(
                                          '${_added.length}',
                                          style: const TextStyle(
                                            fontFamily: SmFonts.heading,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Update studio',
                                        semanticsLabel: 'Update studio',
                                        style: TextStyle(
                                          fontFamily: SmFonts.heading,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Lessons that come back keep your progress',
                              style: t.small.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              appear(section('EXPORT')),
              appear(
                _ExportRow(
                  tag: 'PDF',
                  title: 'Study notes',
                  note: 'Every topic, key ideas, cards',
                  busy: _exporting == 'notes',
                  onTap: () => _export('notes', widget.onExportNotes),
                ),
              ),
              appear(
                _ExportRow(
                  tag: 'ANKI',
                  title: 'Flashcards',
                  note: '${s.flashcardCount} cards, tagged by topic',
                  busy: _exporting == 'cards',
                  onTap: s.flashcardCount == 0
                      ? null
                      : () => _export('cards', widget.onExportCards),
                ),
              ),
              const SizedBox(height: 34),
              appear(
                Center(
                  child: SmPressable(
                    semanticLabel: 'Delete studio',
                    haptic: SmHaptics.thud,
                    onTap: widget.onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'Delete studio',
                        style: TextStyle(
                          fontFamily: SmFonts.heading,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: c.accentSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.icon, required this.name, required this.note});

  final Widget icon;
  final String name;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: t.body.copyWith(fontSize: 14)),
                Text(note, style: t.small.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A file picked to add: dashed accent, slides in, and can go again.
class _NewFileRow extends StatelessWidget {
  const _NewFileRow({super.key, required this.file, required this.onRemove});

  final SmPickedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final kb = file.size / 1024;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: smReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(24 * (1 - v), 0),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            SmPaper(type: file.type, fresh: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          file.name,
                          style: t.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            fontFamily: SmFonts.heading,
                            fontSize: 8,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${kb < 1024 ? '${kb.round()} KB' : '${(kb / 1024).toStringAsFixed(1)} MB'}'
                    ' · waiting to be added',
                    style: t.small.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            SmPressable(
              semanticLabel: 'Remove ${file.name}',
              haptic: () {},
              scale: 0.85,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 18, color: c.hint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.tag,
    required this.title,
    required this.note,
    required this.busy,
    required this.onTap,
  });

  final String tag;
  final String title;
  final String note;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: 'Export $title',
      haptic: SmHaptics.tap,
      onTap: busy ? null : onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.body.copyWith(fontSize: 14)),
                    Text(note, style: t.small.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.line),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontFamily: SmFonts.heading,
                    fontSize: 9,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: busy
                    ? SizedBox(
                        key: const ValueKey('busy'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.accent,
                        ),
                      )
                    : Icon(
                        Icons.north_east_rounded,
                        key: const ValueKey('share'),
                        size: 17,
                        color: c.hint,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A file as a sheet of paper with a folded corner and its kind in small
/// caps (PDF, DOC…); dashed in the accent when it's [fresh].
class SmPaper extends StatelessWidget {
  const SmPaper({super.key, required this.type, this.fresh = false});

  final SourceFileType type;
  final bool fresh;

  static (String, Color) look(SourceFileType t) => switch (t) {
    SourceFileType.pdf => ('PDF', const Color(0xFFF0997B)),
    SourceFileType.docx => ('DOC', const Color(0xFF85B7EB)),
    SourceFileType.pptx => ('PPT', const Color(0xFFF5A623)),
    SourceFileType.txt => ('TXT', const Color(0xFFB4B2A9)),
    SourceFileType.image => ('IMG', const Color(0xFF5DCAA5)),
    SourceFileType.audio => ('AUD', const Color(0xFFED93B1)),
    SourceFileType.video => ('VID', const Color(0xFFAFA9EC)),
  };

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final (label, color) = look(type);
    return SizedBox(
      width: 30,
      height: 36,
      child: CustomPaint(
        painter: _PaperPainter(
          fill: fresh ? c.accent.withValues(alpha: 0.08) : c.raised,
          edge: fresh ? c.accent : c.line,
          fold: fresh ? c.accent.withValues(alpha: 0.35) : c.line,
          dashed: fresh,
        ),
        child: Align(
          alignment: const Alignment(0, 0.7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: SmFonts.heading,
              fontSize: 7.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w800,
              color: fresh ? c.accentSoft : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter({
    required this.fill,
    required this.edge,
    required this.fold,
    required this.dashed,
  });

  final Color fill;
  final Color edge;
  final Color fold;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final f = w * 0.32;
    const r = 4.0;
    final page = Path()
      ..moveTo(r, 0)
      ..lineTo(w - f, 0)
      ..lineTo(w, f)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    canvas.drawPath(page, Paint()..color = fill);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = edge;
    if (dashed) {
      for (final m in page.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 6) {
          canvas.drawPath(m.extractPath(d, d + 3.5), stroke);
        }
      }
    } else {
      canvas.drawPath(page, stroke);
    }
    final corner = Path()
      ..moveTo(w - f, 0)
      ..lineTo(w - f, f - 2)
      ..quadraticBezierTo(w - f, f, w - f + 2, f)
      ..lineTo(w, f)
      ..close();
    canvas.drawPath(corner, Paint()..color = fold);
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.fill != fill || old.edge != edge || old.fold != fold;
}
