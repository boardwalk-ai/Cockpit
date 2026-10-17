import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'theme.dart';

/// Writes an announcement (picture, title, text), shows how it will look on
/// a phone, and sends it now — to this admin's own phone first, then to
/// some testers or all of them.
class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

enum _To { me, emails, all }

class _NotifyPageState extends State<NotifyPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _emails = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _uploading = false;
  bool _sending = false;
  _To _to = _To.me;
  late Future<List<SentNotice>> _history = widget.api.sentNotices();

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _body.addListener(() => setState(() {}));
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 82,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime =
        file.mimeType ??
        (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    setState(() {
      _imageBytes = bytes;
      _imageUrl = null;
      _uploading = true;
    });
    try {
      final url = await widget.api.uploadImage(bytes, mime);
      if (mounted) setState(() => _imageUrl = url);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _imageBytes = null);
        toast(context, '$e');
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  List<String> get _emailList => _emails.text
      .split(RegExp(r'[\s,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _send(_To to) async {
    if (_title.text.trim().isEmpty) {
      toast(context, 'Write a title');
      return;
    }
    if (_uploading) {
      toast(context, 'The picture is still uploading');
      return;
    }
    if (to == _To.emails && _emailList.isEmpty) {
      toast(context, 'Add at least one email');
      return;
    }
    if (to != _To.me) {
      final who = to == _To.all
          ? 'every tester'
          : '${_emailList.length} people';
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Send now?'),
          content: Text(
            '"${_title.text.trim()}" goes to $who right away. It can\'t be taken back.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _sending = true);
    try {
      final r = await widget.api.notify(
        title: _title.text.trim(),
        body: _body.text.trim(),
        image: _imageUrl,
        audience: switch (to) {
          _To.me => {'kind': 'me'},
          _To.all => {'kind': 'all'},
          _To.emails => {'kind': 'emails', 'emails': _emailList},
        },
      );
      final devices = r['devices'] as int? ?? 0;
      final sent = r['sent'] as int? ?? 0;
      final errors = (r['errors'] as List?)?.cast<String>() ?? const [];
      if (mounted) {
        toast(
          context,
          devices == 0
              ? 'No phone to send to — open the test app and sign in first'
              : 'Sent to $sent of $devices phone${devices == 1 ? '' : 's'}${errors.isEmpty ? '' : ' · ${errors.first}'}',
        );
        setState(() => _history = widget.api.sentNotices());
      }
    } on Object catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Text(
          'Notify',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ),
      const SizedBox(height: 14),
      _Preview(
        title: _title.text,
        body: _body.text,
        image: _imageBytes,
        uploading: _uploading,
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          _ImageButton(bytes: _imageBytes, uploading: _uploading, onTap: _pick),
          if (_imageBytes != null)
            TextButton(
              onPressed: () => setState(() {
                _imageBytes = null;
                _imageUrl = null;
              }),
              child: const Text('Remove picture'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        maxLength: 80,
        decoration: const InputDecoration(hintText: 'Title'),
      ),
      TextField(
        controller: _body,
        maxLength: 400,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Description'),
      ),
      const SizedBox(height: 8),
      SegmentedButton<_To>(
        segments: const [
          ButtonSegment(
            value: _To.me,
            label: Text('Me'),
            icon: Icon(Icons.phone_android_rounded),
          ),
          ButtonSegment(
            value: _To.emails,
            label: Text('Some'),
            icon: Icon(Icons.group_outlined),
          ),
          ButtonSegment(
            value: _To.all,
            label: Text('All testers'),
            icon: Icon(Icons.campaign_outlined),
          ),
        ],
        selected: {_to},
        onSelectionChanged: (s) => setState(() => _to = s.first),
      ),
      if (_to == _To.emails) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _emails,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Emails, one per line'),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          if (_to != _To.me) ...[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _sending ? null : () => _send(_To.me),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Send to me'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: GradientButton(
              label: _sending
                  ? 'Sending…'
                  : (_to == _To.me ? 'Send to me' : 'Send'),
              icon: Icons.send_rounded,
              onPressed: _sending ? null : () => _send(_to),
            ),
          ),
        ],
      ),
      const SizedBox(height: 28),
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          'Sent',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      FutureBuilder(
        future: _history,
        builder: (context, s) {
          if (s.hasError)
            return Text(
              '${s.error}',
              style: const TextStyle(color: AdminColors.muted),
            );
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) {
            return const Text(
              'Nothing sent yet.',
              style: TextStyle(color: AdminColors.muted),
            );
          }
          return Column(
            children: [
              for (final n in s.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        if (n.image != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              n.image!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 44, height: 44),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${switch (n.audience) {
                                  'me' => 'Me',
                                  'all' => 'All testers',
                                  _ => 'Some',
                                }} · '
                                '${n.sent}/${n.devices} phones${n.at == null ? '' : ' · ${_ago(n.at!)}'}',
                                style: const TextStyle(
                                  color: AdminColors.faint,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _ImageButton extends StatelessWidget {
  const _ImageButton({
    required this.bytes,
    required this.uploading,
    required this.onTap,
  });
  final Uint8List? bytes;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: uploading ? null : onTap,
    child: Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AdminColors.surface2,
        border: Border.all(color: AdminColors.line),
        image: bytes == null
            ? null
            : DecorationImage(image: MemoryImage(bytes!), fit: BoxFit.cover),
      ),
      child: uploading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : bytes == null
          ? const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  color: AdminColors.muted,
                ),
                SizedBox(height: 2),
                Text(
                  'Picture',
                  style: TextStyle(fontSize: 11, color: AdminColors.muted),
                ),
              ],
            )
          : null,
    ),
  );
}

/// How the notification shows on an Android phone.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.title,
    required this.body,
    required this.image,
    required this.uploading,
  });
  final String title;
  final String body;
  final Uint8List? image;
  final bool uploading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        colors: [Color(0xFF2A0F12), Color(0xFF121214)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: AdminColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PREVIEW',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: AdminColors.faint,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF26262B),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  _Ring(),
                  SizedBox(width: 6),
                  Text(
                    'Octopilot',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.accent2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ' · now',
                    style: TextStyle(fontSize: 12, color: AdminColors.faint),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.trim().isEmpty ? 'Title' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: title.trim().isEmpty
                                ? AdminColors.faint
                                : AdminColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body.trim().isEmpty ? 'Description' : body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (image != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Opacity(
                        opacity: uploading ? 0.5 : 1,
                        child: Image.memory(
                          image!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (image != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 2,
                    child: Image.memory(image!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Expanded',
                  style: TextStyle(fontSize: 10, color: AdminColors.faint),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Ring extends StatelessWidget {
  const _Ring();

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: AdminColors.accent, width: 3.2),
    ),
  );
}
