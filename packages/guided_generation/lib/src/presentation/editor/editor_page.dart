import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../data/guided_generation_repository.dart';
import '../../formatters/citation_formatter.dart';

class GuidedEditorPage extends StatefulWidget {
  const GuidedEditorPage({super.key, this.repository, this.threadId});

  final GuidedGenerationRepository? repository;
  final String? threadId;

  @override
  State<GuidedEditorPage> createState() => _GuidedEditorPageState();
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB8B8B8)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) => false;
}

class _GuidedEditorPageState extends State<GuidedEditorPage> {
  late QuillController _controller;
  late final GuidedGenerationRepository _repository;
  final CitationFormatter _formatter = const CitationFormatter();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  TextSelection _editorSelection = const TextSelection.collapsed(offset: 0);

  CitationStyle _citationStyle = CitationStyle.apa;
  String? _threadId;
  Map<String, dynamic> _runState = {};
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _saved = true;
  double _zoom = 1.0;
  bool _showReferences = true;

  List<CitationSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? ApiGuidedGenerationRepository.defaultClient();
    _threadId = widget.threadId;
    _controller = QuillController.basic();
    _attachControllerListeners();
    _load();
  }

  void _attachControllerListeners() {
    _controller.addListener(_handleDocumentChange);
    _controller.onSelectionChanged = (selection) {
      _editorSelection = selection;
      if (mounted) setState(() {});
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final thread = await _repository.loadEditor(threadId: _threadId);
      if (!mounted) return;

      if (thread == null) {
        setState(() {
          _loading = false;
          _saved = true;
        });
        return;
      }

      Document document;
      try {
        document = thread.delta == null
            ? (Document()..insert(0, thread.plainText))
            : Document.fromJson(thread.delta!);
      } catch (_) {
        document = Document()..insert(0, thread.plainText);
      }

      _controller.removeListener(_handleDocumentChange);
      _controller.dispose();
      _controller = QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _attachControllerListeners();

      setState(() {
        _threadId = thread.id;
        _citationStyle = thread.citationStyle;
        _sources = thread.sources;
        _runState = thread.runState;
        _loading = false;
        _saved = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load the document. $error';
      });
    }
  }

  void _handleDocumentChange() {
    if (_saved && mounted) {
      setState(() => _saved = false);
    }
  }

  int get _wordCount {
    final text = _controller.document.toPlainText().trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final plainText = _controller.document.toPlainText().trimRight();
      final title = plainText
          .split('\n')
          .firstWhere(
            (line) => line.trim().isNotEmpty,
            orElse: () => 'Untitled essay',
          )
          .trim();
      final thread = await _repository.saveEditor(
        threadId: _threadId,
        title: title.length > 120 ? title.substring(0, 120) : title,
        plainText: plainText,
        wordCount: _wordCount,
        citationStyle: _citationStyle,
        delta: _controller.document.toDelta().toJson(),
        sources: _sources,
        runState: _runState,
      );
      if (!mounted) return;
      setState(() {
        _threadId = thread.id;
        _runState = thread.runState;
        _saving = false;
        _saved = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the document. $error')),
      );
    }
  }

  void _changeCitationStyle(CitationStyle? style) {
    if (style == null || style == _citationStyle) return;

    final oldStyle = _citationStyle;

    for (var i = 0; i < _sources.length; i++) {
      final source = _sources[i];

      final oldInline = _formatter.inlineCitation(
        source,
        oldStyle,
        index: i + 1,
      );

      final newInline = _formatter.inlineCitation(source, style, index: i + 1);

      _replaceAll(oldInline, newInline);

      final oldEntry = _formatter.bibliographyEntry(
        source,
        oldStyle,
        index: i + 1,
      );

      final newEntry = _formatter.bibliographyEntry(
        source,
        style,
        index: i + 1,
      );

      _replaceAll(oldEntry, newEntry);
    }

    setState(() {
      _citationStyle = style;
      _saved = false;
    });

    _focusNode.requestFocus();
  }

  void _replaceAll(String oldText, String newText) {
    while (true) {
      final text = _controller.document.toPlainText();
      final index = text.indexOf(oldText);

      if (index == -1) return;

      _controller.replaceText(
        index,
        oldText.length,
        newText,
        TextSelection.collapsed(offset: index + newText.length),
      );
    }
  }

  void _changeZoom(double change) {
    setState(() {
      _zoom = (_zoom + change).clamp(0.75, 1.25);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleDocumentChange);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _loading
                  ? const Center(
                      key: Key('guided-editor-loading'),
                      child: CircularProgressIndicator(),
                    )
                  : _loadError != null
                  ? _buildLoadError(context)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1000;

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildEditor(context)),
                              if (_showReferences)
                                SizedBox(
                                  width: 300,
                                  child: _buildReferences(context),
                                ),
                            ],
                          );
                        }

                        return _buildEditor(context);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    return Center(
      key: const Key('guided-editor-error'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('guided-editor-retry'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    const red = Color(0xFFEF233C);
    const muted = Color(0xFFA99F91);

    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          color: const Color(0xFF080808),
          child: Row(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(6),
                child: const SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: Text(
                      '‹',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.1,
                  ),
                  children: [
                    TextSpan(
                      text: 'Octo',
                      style: TextStyle(color: red),
                    ),
                    TextSpan(
                      text: 'Pilot',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextSpan(
                      text: 'AI',
                      style: TextStyle(
                        color: red,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Container(width: 1, height: 28, color: Colors.white12),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Guided Generation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$_wordCount words',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (!_saved) ...[
                const Text(
                  'Unsaved',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(width: 14),
              ],
              SizedBox(
                height: 34,
                child: FilledButton(
                  key: const Key('guided-editor-save'),
                  onPressed: _saving || _loading || _loadError != null
                      ? null
                      : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _saving ? 'Saving...' : 'Save',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 55,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D0D),
            border: Border(bottom: BorderSide(color: Color(0xFF24211D))),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStep('WRITING STYLE', past: true),
                    _stepDivider(true),
                    _buildStep('INSTRUCTIONS', past: true),
                    _stepDivider(true),
                    _buildStep('OUTLINES', past: true),
                    _stepDivider(true),
                    _buildStep('CONFIGURATION', past: true),
                    _stepDivider(true),
                    _buildStep('FORMAT', past: true),
                    _stepDivider(true),
                    _buildStep('GENERATION', past: true),
                    _stepDivider(true),
                    _buildStep('PREVIEW', past: true),
                    _stepDivider(true),
                    _buildStep('HUMANIZER', past: true),
                    _stepDivider(true),
                    _buildStep('EDITOR', active: true),
                    _stepDivider(false),
                    _buildStep('EXPORT'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'WRITING MODE: GUIDED GENERATION',
                style: TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 3,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          color: const Color(0xFF151515),
          child: FractionallySizedBox(
            widthFactor: 0.9,
            child: Container(
              decoration: BoxDecoration(
                color: red,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(color: red.withValues(alpha: 0.45), blurRadius: 7),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep(String label, {bool active = false, bool past = false}) {
    final color = active
        ? const Color(0xFFEF4444)
        : past
        ? const Color(0xFF8A2D2D)
        : Colors.white24;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: active ? 10.5 : 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _stepDivider(bool past) {
    return Text(
      '>>>',
      style: TextStyle(
        color: past
            ? const Color(0xFF652727)
            : Colors.white.withValues(alpha: 0.08),
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  void _toggleInlineFormat(Attribute attribute) {
    _controller.updateSelection(_editorSelection, ChangeSource.local);

    final current = _controller.getSelectionStyle().attributes[attribute.key];

    _controller.formatSelection(
      current == null ? attribute : Attribute.clone(attribute, null),
    );

    _editorSelection = _controller.selection;
    _focusNode.requestFocus();
    setState(() {});
  }

  void _applyFormat(Attribute attribute) {
    _controller.updateSelection(_editorSelection, ChangeSource.local);
    _controller.formatSelection(attribute);
    _editorSelection = _controller.selection;
    _focusNode.requestFocus();
    setState(() {});
  }

  bool _formatActive(String key) {
    return _controller.getSelectionStyle().attributes.containsKey(key);
  }

  Widget _toolbarButton({
    required Widget child,
    required String tooltip,
    required VoidCallback onPressed,
    bool active = false,
    double width = 32,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: width,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _toolbarLabel(
    String text, {
    FontWeight? weight,
    FontStyle? style,
    TextDecoration? decoration,
    double size = 14,
  }) {
    return Text(
      text,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        fontStyle: style,
        decoration: decoration,
      ),
    );
  }

  Widget _toolbarDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildFormattingToolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = _controller.getSelectionStyle().attributes;

    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarButton(
              tooltip: 'Undo',
              onPressed: () {
                _controller.undo();
                _focusNode.requestFocus();
                setState(() {});
              },
              child: _toolbarLabel('↶', size: 18),
            ),
            _toolbarButton(
              tooltip: 'Redo',
              onPressed: () {
                _controller.redo();
                _focusNode.requestFocus();
                setState(() {});
              },
              child: _toolbarLabel('↷', size: 18),
            ),

            _toolbarDivider(context),

            MenuAnchor(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(colors.surface),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                elevation: const WidgetStatePropertyAll(4),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 4),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                minimumSize: const WidgetStatePropertyAll(Size(150, 0)),
                maximumSize: const WidgetStatePropertyAll(Size(190, 220)),
              ),
              menuChildren: [
                for (final font in const [
                  'Arial',
                  'Times New Roman',
                  'Georgia',
                  'Roboto',
                ])
                  MenuItemButton(
                    onPressed: () {
                      final attribute = Attribute.fromKeyValue('font', font);
                      if (attribute != null) {
                        _applyFormat(attribute);
                      }
                    },
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(150, 32)),
                      maximumSize: const WidgetStatePropertyAll(Size(190, 32)),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      alignment: Alignment.centerLeft,
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 13),
                      ),
                    ),
                    child: Text(
                      font,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              builder: (context, controller, child) {
                return InkWell(
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    width: 132,
                    height: 30,
                    padding: const EdgeInsets.only(left: 9, right: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            style['font']?.value?.toString() ?? 'Arial',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CustomPaint(
                          size: const Size(8, 5),
                          painter: _ChevronPainter(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 2),

            MenuAnchor(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(colors.surface),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                elevation: const WidgetStatePropertyAll(4),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 4),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                minimumSize: const WidgetStatePropertyAll(Size(58, 0)),
                maximumSize: const WidgetStatePropertyAll(Size(70, 260)),
              ),
              menuChildren: [
                for (final size in const [
                  '10',
                  '11',
                  '12',
                  '14',
                  '16',
                  '18',
                  '20',
                  '24',
                ])
                  MenuItemButton(
                    onPressed: () {
                      final attribute = Attribute.fromKeyValue('size', size);
                      if (attribute != null) {
                        _applyFormat(attribute);
                      }
                    },
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(58, 30)),
                      maximumSize: WidgetStatePropertyAll(Size(70, 30)),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      alignment: Alignment.centerLeft,
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 13),
                      ),
                    ),
                    child: Text(size),
                  ),
              ],
              builder: (context, controller, child) {
                return InkWell(
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    width: 52,
                    height: 30,
                    padding: const EdgeInsets.only(left: 8, right: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            style['size']?.value?.toString() ?? '12',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(8, 5),
                          painter: _ChevronPainter(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            _toolbarDivider(context),

            _toolbarButton(
              tooltip: 'Bold',
              active: _formatActive(Attribute.bold.key),
              onPressed: () => _toggleInlineFormat(Attribute.bold),
              child: _toolbarLabel('B', weight: FontWeight.w700),
            ),
            _toolbarButton(
              tooltip: 'Italic',
              active: _formatActive(Attribute.italic.key),
              onPressed: () => _toggleInlineFormat(Attribute.italic),
              child: _toolbarLabel('I', style: FontStyle.italic),
            ),
            _toolbarButton(
              tooltip: 'Underline',
              active: _formatActive(Attribute.underline.key),
              onPressed: () => _toggleInlineFormat(Attribute.underline),
              child: _toolbarLabel('U', decoration: TextDecoration.underline),
            ),

            _toolbarDivider(context),

            _toolbarButton(
              tooltip: 'Align left',
              active: style[Attribute.align.key]?.value == 'left',
              onPressed: () => _applyFormat(Attribute.leftAlignment),
              child: _toolbarLabel('≡', size: 18),
            ),
            _toolbarButton(
              tooltip: 'Align center',
              active: style[Attribute.align.key]?.value == 'center',
              onPressed: () => _applyFormat(Attribute.centerAlignment),
              child: _toolbarLabel('≡', size: 18),
            ),
            _toolbarButton(
              tooltip: 'Align right',
              active: style[Attribute.align.key]?.value == 'right',
              onPressed: () => _applyFormat(Attribute.rightAlignment),
              child: Transform.flip(
                flipX: true,
                child: _toolbarLabel('≡', size: 18),
              ),
            ),
            _toolbarButton(
              tooltip: 'Justify',
              active: style[Attribute.align.key]?.value == 'justify',
              onPressed: () => _applyFormat(Attribute.justifyAlignment),
              child: _toolbarLabel('☰', size: 16),
            ),

            _toolbarDivider(context),

            _toolbarButton(
              tooltip: 'Numbered list',
              active: style[Attribute.list.key]?.value == 'ordered',
              onPressed: () => _applyFormat(Attribute.ol),
              width: 38,
              child: _toolbarLabel('1. ≡', size: 12),
            ),
            _toolbarButton(
              tooltip: 'Bulleted list',
              active: style[Attribute.list.key]?.value == 'bullet',
              onPressed: () => _applyFormat(Attribute.ul),
              width: 38,
              child: _toolbarLabel('• ≡', size: 13),
            ),

            _toolbarDivider(context),

            _toolbarButton(
              tooltip: 'Decrease indent',
              onPressed: () {
                _controller.updateSelection(
                  _editorSelection,
                  ChangeSource.local,
                );
                _controller.indentSelection(false);
                _editorSelection = _controller.selection;
                _focusNode.requestFocus();
                setState(() {});
              },
              width: 38,
              child: _toolbarLabel('← ≡', size: 12),
            ),
            _toolbarButton(
              tooltip: 'Increase indent',
              onPressed: () {
                _controller.updateSelection(
                  _editorSelection,
                  ChangeSource.local,
                );
                _controller.indentSelection(true);
                _editorSelection = _controller.selection;
                _focusNode.requestFocus();
                setState(() {});
              },
              width: 38,
              child: _toolbarLabel('≡ →', size: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentControls(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(
            'Page 1',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _showReferences = !_showReferences;
              });
            },
            child: Text(
              _showReferences ? 'Hide references' : 'Show references',
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _changeZoom(-0.1),
            child: const Text('−'),
          ),
          SizedBox(
            width: 42,
            child: Center(
              child: Text(
                '${(_zoom * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          TextButton(onPressed: () => _changeZoom(0.1), child: const Text('+')),
        ],
      ),
    );
  }

  Widget _buildRuler(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: 24,
      child: Row(
        children: [
          for (var i = 0; i <= 8; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.only(left: 4, top: 3),
                child: Text(
                  '$i',
                  style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildFormattingToolbar(context),
        _buildDocumentControls(context),
        Expanded(
          child: Container(
            width: double.infinity,
            color: colors.surfaceContainerLowest,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
              child: Center(
                child: SizedBox(
                  width: 816 * _zoom,
                  child: Transform.scale(
                    scale: _zoom,
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 816,
                      constraints: const BoxConstraints(minHeight: 1056),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                            color: colors.shadow.withValues(alpha: 0.10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 72),
                            child: _buildRuler(context),
                          ),
                          Divider(height: 1, color: colors.outlineVariant),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(72, 18, 72, 0),
                            child: Row(
                              children: [
                                Text(
                                  'Guided Generation',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                const Spacer(),
                                Text(
                                  '1',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 960,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                72,
                                34,
                                72,
                                72,
                              ),
                              child: QuillEditor.basic(
                                controller: _controller,
                                focusNode: _focusNode,
                                scrollController: _scrollController,
                                config: const QuillEditorConfig(
                                  scrollable: true,
                                  expands: true,
                                  autoFocus: false,
                                  padding: EdgeInsets.zero,
                                  placeholder: 'Start writing...',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildMobileReferences(context),
      ],
    );
  }

  Widget _buildMobileReferences(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;

        if (screenWidth >= 1000) {
          return const SizedBox.shrink();
        }

        return ExpansionTile(
          leading: const SizedBox(
            width: 24,
            child: Center(
              child: Text('R', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          title: const Text('References'),
          subtitle: Text(_citationStyle.label),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CockpitSpacing.lg,
                0,
                CockpitSpacing.lg,
                CockpitSpacing.lg,
              ),
              child: _referencesContent(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReferences(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CockpitSpacing.xl),
        child: _referencesContent(context),
      ),
    );
  }

  Widget _referencesContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = _formatter.bibliography(_sources, _citationStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'References',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: CockpitSpacing.xs),
        Text(
          'Citation style',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: CockpitSpacing.sm),
        DropdownButtonFormField<CitationStyle>(
          initialValue: _citationStyle,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: CitationStyle.values
              .map(
                (style) =>
                    DropdownMenuItem(value: style, child: Text(style.label)),
              )
              .toList(),
          onChanged: _changeCitationStyle,
        ),
        const SizedBox(height: CockpitSpacing.xl),
        for (var i = 0; i < entries.length; i++) ...[
          SelectableText(
            entries[i],
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.55),
          ),
          if (i != entries.length - 1)
            const SizedBox(height: CockpitSpacing.lg),
        ],
      ],
    );
  }
}
