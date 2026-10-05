import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/source.dart';
import 'mobile_header.dart';
import 'mobile_motion.dart';
import 'mobile_style.dart';

/// A material picked on the phone, not uploaded yet.
class SmPickedFile {
  const SmPickedFile({
    required this.name,
    required this.type,
    required this.bytes,
  });

  final String name;
  final SourceFileType type;
  final Uint8List bytes;

  int get size => bytes.length;
}

/// What Study Studio reads.
const smStudyExtensions = [
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt', 'md', //
  'png', 'jpg', 'jpeg', 'webp', 'mp3', 'wav', 'm4a', 'mp4', 'mov',
];

SourceFileType smTypeFor(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'pdf' => SourceFileType.pdf,
    'doc' || 'docx' => SourceFileType.docx,
    'ppt' || 'pptx' => SourceFileType.pptx,
    'png' || 'jpg' || 'jpeg' || 'webp' || 'heic' => SourceFileType.image,
    'mp3' || 'wav' || 'm4a' => SourceFileType.audio,
    'mp4' || 'mov' => SourceFileType.video,
    _ => SourceFileType.txt,
  };
}

String smFormatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// "Networks_ch4-final.pdf" → "Networks ch4 final".
String smNameFromFile(String file) {
  final dot = file.lastIndexOf('.');
  final stem = dot > 0 ? file.substring(0, dot) : file;
  return stem.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
}

/// The phone's New Study Studio: a few words up top and, at the foot, a
/// composer like GhostWriter's: the materials, the name, Build. The
/// materials show as cards (1–2), a strip to swipe (3–5) or one summary
/// that opens a sheet (6 and up), so the composer never grows.
class StudyCreateMobile extends StatelessWidget {
  const StudyCreateMobile({
    super.key,
    required this.files,
    required this.name,
    required this.onAdd,
    required this.onRemove,
    required this.onBuild,
    this.building = false,
    this.credits,
  });

  final List<SmPickedFile> files;
  final TextEditingController name;

  /// Opens the "+" sheet.
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onBuild;
  final bool building;
  final int? credits;

  /// The most materials one studio takes.
  static const maxFiles = 20;

  /// From this many on, the materials fold into one summary.
  static const foldAt = 6;

  /// From this many on, the cards become a strip to swipe.
  static const stripAt = 3;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final top = MediaQuery.paddingOf(context).top + SmHeader.clearance;
    return Scaffold(
      backgroundColor: c.background,
      body: SmHeaderPage(
        header: SmHeader(title: 'New studio', credits: credits),
        child: Column(
          children: [
            // The words sit in the middle of the room the composer leaves
            // (a short screen, or the keyboard up, scrolls them).
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(28, top, 28, 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (box.maxHeight - top - 16).clamp(
                        0,
                        double.infinity,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SmAppear(
                          index: 0,
                          child: Text(
                            'Let’s make it stick',
                            style: t.body.copyWith(
                              color: c.accentSoft,
                              fontFamily: SmFonts.heading,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SmAppear(
                          index: 1,
                          child: Text(
                            'Drop in your notes.\nWe’ll build the rest.',
                            textAlign: TextAlign.center,
                            style: t.greeting,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SmAppear(
                          index: 2,
                          child: Text(
                            'Notes, slides, photos of pages or a recording',
                            textAlign: TextAlign.center,
                            style: t.small.copyWith(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 22),
                        const SmAppear(index: 3, child: _WhatYouGet()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SmAppear(
                  index: 4,
                  child: _Composer(
                    files: files,
                    name: name,
                    onAdd: onAdd,
                    onRemove: onRemove,
                    onBuild: onBuild,
                    building: building,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a studio holds, as chips; "+6 more" lists the rest.
class _WhatYouGet extends StatelessWidget {
  const _WhatYouGet();

  static const _all = [
    (Icons.account_tree_outlined, 'Topics', Color(0xFF378ADD)),
    (Icons.style_outlined, 'Flashcards', Color(0xFFF0997B)),
    (Icons.quiz_outlined, 'Quizzes', Color(0xFFFF5258)),
    (Icons.forum_outlined, 'AI tutor', Color(0xFF8B83E6)),
    (Icons.bookmark_border_rounded, 'Definitions', Color(0xFF30A46C)),
    (Icons.view_in_ar_outlined, 'Scenarios', Color(0xFF30A46C)),
    (Icons.hub_outlined, 'Knowledge graph', Color(0xFF8B83E6)),
    (Icons.psychology_outlined, 'Memory hooks', Color(0xFFF5A623)),
    (Icons.gps_fixed_rounded, 'Weak topics', Color(0xFFFF5258)),
    (Icons.insights_rounded, 'Visual explanations', Color(0xFF378ADD)),
  ];

  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (icon, label, color) in _all.take(_shown))
          _Chip(icon: icon, label: label, color: color),
        SmPressable(
          semanticLabel: 'Everything a studio has',
          onTap: () => _showAll(context),
          child: _Chip(label: '+${_all.length - _shown} more'),
        ),
      ],
    );
  }

  void _showAll(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      isScrollControlled: true,
      builder: (context) => _Sheet(
        title: 'Every studio comes with',
        children: [
          for (final (icon, label, color) in _all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 14),
                  Text(label, style: t.body.copyWith(color: c.text)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: t.small.copyWith(
              color: icon == null ? c.muted : c.text,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.files,
    required this.name,
    required this.onAdd,
    required this.onRemove,
    required this.onBuild,
    required this.building,
  });

  final List<SmPickedFile> files;
  final TextEditingController name;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onBuild;
  final bool building;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready = files.isNotEmpty && !building;
    final total = files.fold<int>(0, (sum, f) => sum + f.size);

    final Widget materials;
    if (files.isEmpty) {
      materials = _AddTile(onTap: onAdd);
    } else if (files.length >= StudyCreateMobile.foldAt) {
      materials = _Summary(
        files: files,
        total: total,
        onTap: () => showSmFilesSheet(
          context,
          files: files,
          onAdd: onAdd,
          onRemove: onRemove,
        ),
      );
    } else if (files.length >= StudyCreateMobile.stripAt) {
      materials = SizedBox(
        height: 54,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: files.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => SizedBox(
            width: 148,
            child: _FileCard(file: files[i], onRemove: () => onRemove(i)),
          ),
        ),
      );
    } else {
      materials = Row(
        children: [
          for (final (i, f) in files.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _FileCard(file: f, onRemove: () => onRemove(i)),
            ),
          ],
        ],
      );
    }

    final suggested = files.isEmpty ? null : smNameFromFile(files.first.name);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2B2B) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: materials,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: TextField(
              controller: name,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              style: t.body.copyWith(fontSize: 14),
              cursorColor: c.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: suggested ?? 'Name your studio',
                hintStyle: t.body.copyWith(fontSize: 14, color: c.hint),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.line),
          const SizedBox(height: 8),
          Row(
            children: [
              SmPressable(
                semanticLabel: 'Add material',
                haptic: SmHaptics.tap,
                onTap: building ? null : onAdd,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: c.text),
                      const SizedBox(width: 4),
                      Text('Add', style: t.body),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  files.isEmpty
                      ? 'Up to ${StudyCreateMobile.maxFiles} files'
                      : '${files.length} '
                            '${files.length == 1 ? 'file' : 'files'}'
                            ' · ${smFormatSize(total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.small,
                ),
              ),
              SmPressable(
                semanticLabel: 'Build studio',
                haptic: SmHaptics.thud,
                scale: 0.9,
                onTap: ready ? onBuild : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: ready || building ? c.accent : c.raised,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (building)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: ready ? Colors.white : c.hint,
                        ),
                      const SizedBox(width: 7),
                      Text(
                        building ? 'Uploading' : 'Build',
                        style: t.body.copyWith(
                          fontFamily: SmFonts.heading,
                          fontWeight: FontWeight.w700,
                          color: ready || building ? Colors.white : c.hint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// No materials yet: one wide dashed tile.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return SmPressable(
      semanticLabel: 'Add material',
      haptic: SmHaptics.tap,
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorder(color: c.accent.withValues(alpha: 0.5)),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_file_rounded, size: 20, color: c.accentSoft),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Add notes, slides or photos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(color: c.accentSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// The icon and tint for a kind of material.
(IconData, Color) _look(SourceFileType type) => switch (type) {
  SourceFileType.pdf => (
    Icons.picture_as_pdf_outlined,
    const Color(0xFFFF5258),
  ),
  SourceFileType.docx => (Icons.description_outlined, const Color(0xFF378ADD)),
  SourceFileType.pptx => (Icons.slideshow_outlined, const Color(0xFFF0997B)),
  SourceFileType.txt => (Icons.notes_rounded, const Color(0xFFA0A2A5)),
  SourceFileType.image => (Icons.image_outlined, const Color(0xFF30A46C)),
  SourceFileType.audio => (Icons.graphic_eq_rounded, const Color(0xFFF5A623)),
  SourceFileType.video => (Icons.videocam_outlined, const Color(0xFF8B83E6)),
};

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type, this.size = 30});

  final SourceFileType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.onRemove});

  final SmPickedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _TypeIcon(type: file.type),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(fontSize: 12),
                ),
                Text(smFormatSize(file.size), style: t.small),
              ],
            ),
          ),
          SmPressable(
            semanticLabel: 'Remove ${file.name}',
            haptic: SmHaptics.tap,
            scale: 0.85,
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close_rounded, size: 16, color: c.hint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six or more materials: their icons stacked, the count, the size.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.files,
    required this.total,
    required this.onTap,
  });

  final List<SmPickedFile> files;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final shown = files.take(3).toList();
    return SmPressable(
      semanticLabel: 'Review ${files.length} files',
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30 + 18.0 * (shown.length - 1),
              height: 30,
              child: Stack(
                children: [
                  for (final (i, f) in shown.indexed)
                    Positioned(
                      left: 18.0 * i,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.raised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.raised, width: 2),
                        ),
                        child: _TypeIcon(type: f.type, size: 26),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${files.length} files',
                    style: t.body.copyWith(
                      fontFamily: SmFonts.heading,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text('${smFormatSize(total)} · Review all', style: t.small),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_up_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// Every material, to check over and remove; "Add more" opens the "+"
/// sheet.
Future<void> showSmFilesSheet(
  BuildContext context, {
  required List<SmPickedFile> files,
  required VoidCallback onAdd,
  required void Function(int index) onRemove,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final c = SmColors.of(context);
        final t = SmText.of(context);
        final total = files.fold<int>(0, (sum, f) => sum + f.size);
        return _Sheet(
          title: '${files.length} files · ${smFormatSize(total)}',
          footer: Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: 'Add more',
                  icon: Icons.add_rounded,
                  onTap: () {
                    Navigator.of(context).pop();
                    onAdd();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  label: 'Done',
                  filled: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          children: [
            for (final (i, f) in files.indexed)
              Container(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: c.line)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _TypeIcon(type: f.type),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body,
                      ),
                    ),
                    Text(smFormatSize(f.size), style: t.small),
                    SmPressable(
                      semanticLabel: 'Remove ${f.name}',
                      haptic: SmHaptics.tap,
                      scale: 0.85,
                      onTap: () {
                        onRemove(i);
                        if (files.isEmpty) {
                          Navigator.of(context).pop();
                        } else {
                          setSheet(() {});
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: c.hint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Where a material comes from.
enum SmSource { files, photos, camera }

/// The "+" sheet: a file (from the phone, or Google Drive, OneDrive or
/// Dropbox through the system picker), a photo, or the camera.
Future<List<SmPickedFile>> showSmAddSheet(BuildContext context) async {
  final c = SmColors.of(context);
  final t = SmText.of(context);
  final choice = await showModalBottomSheet<SmSource>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (context) {
      Widget row(SmSource source, IconData icon, String title, String hint) =>
          SmPressable(
            onTap: () => Navigator.of(context).pop(source),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: c.accentSoft),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.title.copyWith(fontSize: 14)),
                        Text(hint, style: t.small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
      return _Sheet(
        title: 'Add material',
        children: [
          row(
            SmSource.files,
            Icons.upload_file_rounded,
            'Files',
            'PDF, Word, slides, audio, also Drive or OneDrive',
          ),
          row(
            SmSource.photos,
            Icons.photo_library_outlined,
            'Photos',
            'Pages or a whiteboard you photographed',
          ),
          row(
            SmSource.camera,
            Icons.photo_camera_outlined,
            'Camera',
            'Take a photo of a page',
          ),
        ],
      );
    },
  );
  if (choice == null) return const [];
  try {
    switch (choice) {
      case SmSource.files:
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: smStudyExtensions,
          allowMultiple: true,
          withData: true,
        );
        return [
          for (final f in result?.files ?? const <PlatformFile>[])
            if (f.bytes != null)
              SmPickedFile(
                name: f.name,
                type: smTypeFor(f.name),
                bytes: f.bytes!,
              ),
        ];
      case SmSource.photos:
        final images = await ImagePicker().pickMultiImage(
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 85,
        );
        return [
          for (final image in images)
            SmPickedFile(
              name: image.name,
              type: SourceFileType.image,
              bytes: await image.readAsBytes(),
            ),
        ];
      case SmSource.camera:
        final image = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 85,
        );
        if (image == null) return const [];
        return [
          SmPickedFile(
            name: image.name,
            type: SourceFileType.image,
            bytes: await image.readAsBytes(),
          ),
        ];
    }
  } on Object {
    return const [];
  }
}

/// A bottom sheet in the page's look.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2B2B) : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            Text(title, style: t.title),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = SmColors.of(context);
    final t = SmText.of(context);
    final color = filled ? Colors.white : c.text;
    return SmPressable(
      haptic: SmHaptics.tap,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? c.accent : c.raised,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: t.body.copyWith(
                color: color,
                fontFamily: SmFonts.heading,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
