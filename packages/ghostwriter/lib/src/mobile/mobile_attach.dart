import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../session/attachments.dart';
import 'mobile_motion.dart';
import 'mobile_theme.dart';

/// A file the user picked, ready to upload.
typedef PickedFile = ({String name, List<int> bytes});

/// The kinds of file GhostWriter reads.
const _extensions = ['pdf', 'docx', 'txt', 'md', 'jpg', 'jpeg', 'png', 'webp'];

/// The "+" sheet: a file (from the phone or a cloud drive, through the
/// system picker), a photo, or the camera. Returns what was picked.
Future<List<PickedFile>> showGwAttachSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<_Source>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => const _AttachSheet(),
  );
  if (choice == null) return const [];
  try {
    return switch (choice) {
      _Source.camera => _photo(ImageSource.camera),
      _Source.photos => _photo(ImageSource.gallery),
      _ => _files(),
    };
  } on Object {
    return const [];
  }
}

Future<List<PickedFile>> _files() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _extensions,
    allowMultiple: true,
    withData: true,
  );
  return [
    for (final file in result?.files ?? const <PlatformFile>[])
      if (file.bytes != null) (name: file.name, bytes: file.bytes!),
  ];
}

Future<List<PickedFile>> _photo(ImageSource source) async {
  final image = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 85,
  );
  if (image == null) return const [];
  return [(name: image.name, bytes: await image.readAsBytes())];
}

enum _Source { files, drive, oneDrive, dropbox, photos, camera }

class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    Widget row(_Source source, IconData icon, String title, String hint) =>
        _SheetRow(
          icon: icon,
          title: title,
          hint: hint,
          onTap: () => Navigator.of(context).pop(source),
        );
    const cloud = 'Pick it there in the next screen';
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        decoration: BoxDecoration(
          color: GwColors.panel,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: GwColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: GwColors.border,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                'Attach an essay, a source or an assignment',
                style: kGwBody.copyWith(color: GwColors.muted, fontSize: 12),
              ),
            ),
            // Scrolls when the screen is short (a phone on its side).
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row(
                      _Source.files,
                      Icons.upload_file_rounded,
                      'Upload a file',
                      'PDF, Word, text',
                    ),
                    row(
                      _Source.drive,
                      Icons.add_to_drive_rounded,
                      'Google Drive',
                      cloud,
                    ),
                    row(
                      _Source.oneDrive,
                      Icons.cloud_outlined,
                      'OneDrive',
                      cloud,
                    ),
                    row(
                      _Source.dropbox,
                      Icons.cloud_queue_rounded,
                      'Dropbox',
                      cloud,
                    ),
                    row(
                      _Source.photos,
                      Icons.photo_library_outlined,
                      'Photos',
                      'A page you photographed',
                    ),
                    row(
                      _Source.camera,
                      Icons.photo_camera_outlined,
                      'Camera',
                      'Take a photo of a page',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      onTap: onTap,
      haptic: GwHaptic.selection,
      pressedScale: 0.97,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF2A1416),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF7A2D31)),
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: kGwBody.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    hint,
                    style: kGwBody.copyWith(
                      color: GwColors.muted,
                      fontSize: 11,
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

/// The files attached to the next message, above the composer's text.
class GwAttachmentChips extends StatelessWidget {
  const GwAttachmentChips({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<GwAttachment> attachments;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final file = attachments[i];
          return _Chip(file: file, onRemove: () => onRemove(file.id));
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.file, required this.onRemove});

  final GwAttachment file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final card = file.card;
    final failed = file.error != null;
    final subtitle = failed
        ? file.error!
        : card == null
        ? 'Reading…'
        : attachmentLabel(card);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: failed ? const Color(0xFF7A2D31) : GwColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: file.uploading
                ? const Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GwColors.accent,
                    ),
                  )
                : Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : _icon(card?['kind']?.toString()),
                    size: 19,
                    color: failed ? const Color(0xFFFF777D) : Colors.white,
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kGwBody.copyWith(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kGwBody.copyWith(
                    color: failed ? const Color(0xFFFF9A9E) : GwColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          GwPressable(
            tooltip: 'Remove',
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 16, color: GwColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _icon(String? kind) => switch (kind) {
  'essay' => Icons.description_outlined,
  'assignment' => Icons.assignment_outlined,
  'notes' => Icons.sticky_note_2_outlined,
  'article' => Icons.article_outlined,
  _ => Icons.insert_drive_file_outlined,
};

/// A sent file, in the user's message.
class GwFileCard extends StatelessWidget {
  const GwFileCard({super.key, required this.card});

  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final flagged = card['addressedToAi'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GwColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon(card['kind']?.toString()),
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card['title']?.toString() ?? 'File',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: kGwBody.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      attachmentLabel(card),
                      style: kGwBody.copyWith(
                        color: GwColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (flagged) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 13,
                  color: Color(0xFFFFB020),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'It contains instructions meant for an AI. I ignore those.',
                    style: kGwBody.copyWith(
                      color: const Color(0xFFFFC966),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
