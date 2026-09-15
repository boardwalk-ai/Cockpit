import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The editor's formatting toolbar, wired to the [QuillController] and styled
/// borderless. Everything you need to write a paper: font + size, bold/italic/
/// underline/strikethrough, text + highlight colour, alignment, lists, indent,
/// undo/redo and clear. Rebuilds on selection change to reflect active state.
class EditorToolbar extends StatefulWidget {
  const EditorToolbar({super.key, required this.controller});

  final QuillController controller;

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  // (display label, bundled metric-compatible family) — CanvasKit only renders
  // bundled fonts, so we apply the real family and show the familiar name.
  // Package-bundled fonts must carry the `packages/<pkg>/` prefix.
  static const _fonts = <(String, String)>[
    ('Times New Roman', 'packages/doc_oct/Tinos'),
    ('Arial', 'packages/doc_oct/Arimo'),
    ('Georgia', 'packages/doc_oct/Gelasio'),
    ('Courier New', 'packages/doc_oct/Cousine'),
  ];
  static const _sizes = [
    '8', '9', '10', '11', '12', '14', '16', '18', '20', '24', '28', '36', '48',
  ];
  static const _swatches = [
    '#1A1A1A', '#5F6368', '#9AA0AA', '#E11D2E', '#EA580C', '#D97706',
    '#16A34A', '#2563EB', '#7C3AED', '#DB2777', '#0369A1', '#FFFFFF',
  ];

  QuillController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_refresh);
  }

  @override
  void didUpdateWidget(EditorToolbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      _c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Style get _style => _c.getSelectionStyle();

  bool _has(String key) => _style.attributes.containsKey(key);
  bool _valueIs(String key, String value) =>
      _style.attributes[key]?.value == value;

  void _toggle(Attribute a) =>
      _c.formatSelection(_has(a.key) ? Attribute.clone(a, null) : a);

  void _exclusive(Attribute a) => _c.formatSelection(
      _valueIs(a.key, a.value as String) ? Attribute.clone(a, null) : a);

  void _apply(Attribute base, String? value) =>
      _c.formatSelection(Attribute.clone(base, value));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final curFamily =
        _style.attributes['font']?.value as String? ?? 'packages/doc_oct/Tinos';
    final curFontLabel = _fonts
        .firstWhere((f) => f.$2 == curFamily, orElse: () => _fonts.first)
        .$1;
    final curSize = _style.attributes['size']?.value?.toString() ?? '16';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: CockpitSpacing.md, vertical: CockpitSpacing.xxs),
      child: Row(
        children: [
          _icon(Icons.undo_rounded, onTap: _c.hasUndo ? _c.undo : null),
          _icon(Icons.redo_rounded, onTap: _c.hasRedo ? _c.redo : null),
          _sep(scheme),
          _dropdown(
            label: curFontLabel,
            width: 132,
            items: _fonts.map((f) => f.$1).toList(),
            itemFont: (lbl) => _fonts.firstWhere((f) => f.$1 == lbl).$2,
            onSelected: (lbl) =>
                _apply(Attribute.font, _fonts.firstWhere((f) => f.$1 == lbl).$2),
          ),
          _sep(scheme),
          _dropdown(
            label: curSize,
            width: 46,
            items: _sizes,
            onSelected: (s) => _apply(Attribute.size, s),
          ),
          _sep(scheme),
          _icon(Icons.format_bold_rounded,
              active: _has('bold'), onTap: () => _toggle(Attribute.bold)),
          _icon(Icons.format_italic_rounded,
              active: _has('italic'), onTap: () => _toggle(Attribute.italic)),
          _icon(Icons.format_underlined_rounded,
              active: _has('underline'),
              onTap: () => _toggle(Attribute.underline)),
          _icon(Icons.format_strikethrough_rounded,
              active: _has('strike'),
              onTap: () => _toggle(Attribute.strikeThrough)),
          _sep(scheme),
          _colorButton(Icons.format_color_text_rounded, background: false),
          _colorButton(Icons.format_color_fill_rounded, background: true),
          _sep(scheme),
          _icon(Icons.format_align_left_rounded,
              active: _valueIs('align', 'left') || !_has('align'),
              onTap: () => _exclusive(Attribute.leftAlignment)),
          _icon(Icons.format_align_center_rounded,
              active: _valueIs('align', 'center'),
              onTap: () => _exclusive(Attribute.centerAlignment)),
          _icon(Icons.format_align_right_rounded,
              active: _valueIs('align', 'right'),
              onTap: () => _exclusive(Attribute.rightAlignment)),
          _icon(Icons.format_align_justify_rounded,
              active: _valueIs('align', 'justify'),
              onTap: () => _exclusive(Attribute.justifyAlignment)),
          _sep(scheme),
          _icon(Icons.format_list_bulleted_rounded,
              active: _valueIs('list', 'bullet'),
              onTap: () => _exclusive(Attribute.ul)),
          _icon(Icons.format_list_numbered_rounded,
              active: _valueIs('list', 'ordered'),
              onTap: () => _exclusive(Attribute.ol)),
          _icon(Icons.format_indent_decrease_rounded,
              onTap: () => _c.indentSelection(false)),
          _icon(Icons.format_indent_increase_rounded,
              onTap: () => _c.indentSelection(true)),
          _sep(scheme),
          _icon(Icons.format_clear_rounded, onTap: _clearFormat),
        ],
      ),
    );
  }

  void _clearFormat() {
    for (final a in [
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
    ]) {
      _c.formatSelection(Attribute.clone(a, null));
    }
    _c.formatSelection(Attribute.clone(Attribute.color, null));
    _c.formatSelection(Attribute.clone(Attribute.background, null));
  }

  // ── pieces ────────────────────────────────────────────────────────────────
  Widget _icon(IconData i, {bool active = false, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(CockpitRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CockpitRadii.sm),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(i,
                size: 17,
                color: onTap == null
                    ? scheme.onSurface.withValues(alpha: 0.25)
                    : active
                        ? scheme.primary
                        : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _sep(ColorScheme scheme) => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: CockpitSpacing.xs),
        color: scheme.onSurface.withValues(alpha: 0.08),
      );

  Widget _dropdown({
    required String label,
    required double width,
    required List<String> items,
    required ValueChanged<String> onSelected,
    String? Function(String item)? itemFont,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      color: scheme.surfaceContainerHigh,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final it in items)
          PopupMenuItem(
            value: it,
            height: 36,
            child: Text(it,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontFamily: itemFont?.call(it),
                    fontSize: 13)),
          ),
      ],
      child: Container(
        width: width,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: CockpitSpacing.sm),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ),
            Icon(Icons.arrow_drop_down_rounded,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _colorButton(IconData icon, {required bool background}) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      color: scheme.surfaceContainerHigh,
      onSelected: (hex) =>
          _apply(background ? Attribute.background : Attribute.color, hex),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 168,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in _swatches)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, hex),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: scheme.onSurface.withValues(alpha: 0.15)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: SizedBox(
        width: 30,
        height: 30,
        child: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
