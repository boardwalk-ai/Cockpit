import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:guided_generation/guided_generation.dart';
import 'package:http/http.dart' as http;

const _apiBaseUrl = String.fromEnvironment(
  'GUIDED_GENERATION_API_URL',
  defaultValue: 'http://localhost:8200',
);

enum _ChamberPhase { loading, empty, ready, generating, error }

class WritingChamberPage extends StatefulWidget {
  const WritingChamberPage({
    super.key,
    this.threadId,
    this.repository,
    this.apiBaseUrl = _apiBaseUrl,
  });

  final String? threadId;
  final GuidedGenerationRepository? repository;
  final String apiBaseUrl;

  @override
  State<WritingChamberPage> createState() => _WritingChamberPageState();
}

class _WritingChamberPageState extends State<WritingChamberPage> {
  final _topicController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _sourceController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _formatter = const CitationFormatter();
  late final QuillController _editorController;
  late final GuidedGenerationRepository _repository;
  late final String _baseUrl;

  _ChamberPhase _phase = _ChamberPhase.loading;
  String? _error;
  String? _threadId;
  CitationStyle _citationStyle = CitationStyle.apa;
  List<CitationSource> _sources = [];
  bool _searching = false;
  bool _saving = false;
  String _streamText = '';

  @override
  void initState() {
    super.initState();
    _editorController = QuillController.basic();
    _editorController.addListener(_markReady);
    _repository =
        widget.repository ?? ApiGuidedGenerationRepository.defaultClient();
    _baseUrl = widget.apiBaseUrl;
    _threadId = widget.threadId;
    _load();
  }

  void _markReady() {
    if (_phase == _ChamberPhase.empty && mounted) {
      setState(() => _phase = _ChamberPhase.ready);
    }
  }

  Future<void> _load() async {
    try {
      final thread = await _repository.loadEditor(threadId: _threadId);
      if (!mounted) return;
      if (thread == null) {
        setState(() => _phase = _ChamberPhase.empty);
        return;
      }

      final document = thread.delta == null
          ? (Document()..insert(0, thread.plainText))
          : _documentFromDelta(thread.delta!, thread.plainText);
      _editorController.document = document;
      _threadId = thread.id;
      _citationStyle = thread.citationStyle;
      _sources = thread.sources;
      _phase = _ChamberPhase.ready;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ChamberPhase.error;
        _error = 'Could not load the Writing Chamber. $error';
      });
    }
  }

  Document _documentFromDelta(List<dynamic> delta, String fallback) {
    try {
      return Document.fromJson(delta);
    } catch (_) {
      return Document()..insert(0, fallback);
    }
  }

  Future<void> _searchSources() async {
    final query = _sourceController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/alvin/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'essayTopic': query, 'targetCount': 5}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Source search returned ${response.statusCode}.');
      }
      final payload = jsonDecode(response.body);
      final rows = payload is List
          ? payload
          : payload is Map
          ? (payload['sources'] ?? payload['results'] ?? const [])
          : const [];
      final found = rows
          .whereType<Map>()
          .map((row) => CitationSource.fromJson(row.cast<String, dynamic>()))
          .where((source) => source.title.trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _sources = _mergeSources(_sources, found);
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _searching = false);
      _showMessage('Source search failed: $error');
    }
  }

  List<CitationSource> _mergeSources(
    List<CitationSource> current,
    List<CitationSource> incoming,
  ) {
    final result = [...current];
    final keys = result.map((source) => _sourceKey(source)).toSet();
    for (final source in incoming) {
      if (keys.add(_sourceKey(source))) result.add(source);
    }
    return result;
  }

  String _sourceKey(CitationSource source) {
    return source.id.trim().isNotEmpty
        ? source.id.trim().toLowerCase()
        : '${source.title.trim().toLowerCase()}|${source.url ?? ''}';
  }

  Future<void> _generate() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showMessage('Add an essay topic first.');
      return;
    }
    if (_sources.isEmpty) {
      _showMessage('Search for at least one source first.');
      return;
    }

    setState(() {
      _phase = _ChamberPhase.generating;
      _error = null;
      _streamText = '';
    });
    _replaceEditorText('');

    final payload = {
      'essayTopic': topic,
      'instructions': _instructionsController.text.trim(),
      'wordCount': 800,
      'citationStyle': _citationStyle.label,
      'tone': 'academic',
      'selectedOutlines': [
        {
          'title': 'Argument and evidence',
          'description':
              'Develop a clear thesis and support it with the supplied sources.',
        },
      ],
      'compactedSources': _sources
          .map(
            (source) => {
              'id': source.id,
              'Title': source.title,
              'Author': source.author ?? '',
              'Publisher': source.publisher ?? '',
              'publishedYear': source.year ?? '',
              'website_URL': source.url ?? '',
              'compactedContent': source.content ?? source.title,
            },
          )
          .toList(),
    };

    try {
      final request =
          http.Request(
              'POST',
              Uri.parse('$_baseUrl/api/guided-generation/generate'),
            )
            ..headers['Content-Type'] = 'application/json'
            ..headers['Accept'] = 'text/event-stream'
            ..body = jsonEncode(payload);
      final response = await request.send();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Generation returned ${response.statusCode}.');
      }

      var event = '';
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.startsWith('event: ')) {
          event = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          _handleStreamEvent(event, line.substring(6));
        }
      }

      if (!mounted) return;
      final output = _parseGeneratedOutput(_streamText);
      _replaceEditorText(output.essay);
      setState(() => _phase = _ChamberPhase.ready);
      await _save();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ChamberPhase.error;
        _error = 'Generation failed: $error';
      });
    }
  }

  void _handleStreamEvent(String event, String rawData) {
    if (rawData == '{}') return;
    try {
      final data = jsonDecode(rawData);
      if (event == 'delta' && data is Map) {
        _streamText += data['text']?.toString() ?? '';
        if (mounted) setState(() {});
      } else if (event == 'error' && data is Map) {
        throw StateError(data['message']?.toString() ?? 'Agent error');
      }
    } catch (error) {
      if (event == 'error') rethrow;
    }
  }

  ({String essay, String bibliography}) _parseGeneratedOutput(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return (
          essay: decoded['essay_content']?.toString() ?? raw,
          bibliography: decoded['bibliography']?.toString() ?? '',
        );
      }
    } catch (_) {}
    return (essay: raw, bibliography: '');
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final text = _editorController.document.toPlainText().trimRight();
      final title = _topicController.text.trim().isEmpty
          ? 'Writing Chamber draft'
          : _topicController.text.trim();
      final thread = await _repository.saveEditor(
        threadId: _threadId,
        title: title,
        plainText: text,
        wordCount: _wordCount,
        citationStyle: _citationStyle,
        delta: _editorController.document.toDelta().toJson(),
        sources: _sources,
        runState: {
          'chamber': {
            'topic': _topicController.text,
            'instructions': _instructionsController.text,
          },
        },
      );
      if (!mounted) return;
      setState(() {
        _threadId = thread.id;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Save failed: $error');
    }
  }

  void _insertCitation(CitationSource source, int index) {
    final citation = _formatter.inlineCitation(
      source,
      _citationStyle,
      index: index,
    );
    final selection = _editorController.selection;
    final offset = selection.start.clamp(
      0,
      _editorController.document.length - 1,
    );
    _editorController.replaceText(
      offset,
      selection.isCollapsed ? 0 : selection.end - selection.start,
      '$citation ',
      TextSelection.collapsed(offset: offset + citation.length + 1),
    );
    _focusNode.requestFocus();
  }

  void _replaceEditorText(String text) {
    final length = _editorController.document.length - 1;
    _editorController.replaceText(
      0,
      length < 0 ? 0 : length,
      text,
      const TextSelection.collapsed(offset: 0),
    );
  }

  int get _wordCount {
    final text = _editorController.document.toPlainText().trim();
    return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _topicController.dispose();
    _instructionsController.dispose();
    _sourceController.dispose();
    _editorController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing Chamber'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text('$_wordCount words')),
          ),
          IconButton(
            tooltip: 'Save draft',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _phase == _ChamberPhase.generating ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _phase == _ChamberPhase.generating ? 'Generating…' : 'Generate',
              ),
            ),
          ),
        ],
      ),
      body: _phase == _ChamberPhase.loading
          ? const Center(child: CircularProgressIndicator())
          : _phase == _ChamberPhase.error
          ? _buildError()
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1100;
                if (!wide) return _buildCompact();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 290, child: _buildSourcesPanel()),
                    Expanded(child: _buildEditor()),
                    SizedBox(width: 300, child: _buildControlsPanel()),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildCompact() {
    return Column(
      children: [
        _buildControlsPanel(compact: true),
        Expanded(child: _buildEditor()),
        _buildSourcesPanel(compact: true),
      ],
    );
  }

  Widget _panel(Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _buildSourcesPanel({bool compact = false}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sources', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _sourceController,
          onSubmitted: (_) => _searchSources(),
          decoration: InputDecoration(
            hintText: 'Search a topic or paste a URL',
            suffixIcon: IconButton(
              onPressed: _searching ? null : _searchSources,
              icon: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_sources.isEmpty)
          const Text('Search for sources before generating.')
        else
          for (var i = 0; i < _sources.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                _sources[i].title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _formatter.inlineCitation(
                  _sources[i],
                  _citationStyle,
                  index: i + 1,
                ),
              ),
              trailing: IconButton(
                tooltip: 'Insert citation',
                onPressed: () => _insertCitation(_sources[i], i + 1),
                icon: const Icon(Icons.add_link),
              ),
            ),
      ],
    );
    return compact
        ? _panel(content)
        : _panel(SingleChildScrollView(child: content));
  }

  Widget _buildControlsPanel({bool compact = false}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assignment', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _topicController,
          decoration: const InputDecoration(labelText: 'Essay topic'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instructionsController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Instructions'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<CitationStyle>(
          initialValue: _citationStyle,
          decoration: const InputDecoration(labelText: 'Citation style'),
          items: CitationStyle.values
              .map(
                (style) =>
                    DropdownMenuItem(value: style, child: Text(style.label)),
              )
              .toList(),
          onChanged: (style) =>
              setState(() => _citationStyle = style ?? _citationStyle),
        ),
        const SizedBox(height: 12),
        Text(
          _phase == _ChamberPhase.generating
              ? 'Lucas is streaming the draft…'
              : 'Generation uses the live Go → Python agent route.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_streamText.isNotEmpty) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _phase == _ChamberPhase.generating ? null : 1,
          ),
          const SizedBox(height: 8),
          Text('Live output', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: SingleChildScrollView(
              child: SelectableText(
                _streamText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
    return compact
        ? _panel(content)
        : _panel(SingleChildScrollView(child: content));
  }

  Widget _buildEditor() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Text(
                _formatter.bibliographyTitle(_citationStyle),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              if (_threadId != null)
                Text(
                  'Saved draft',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: QuillEditor.basic(
              controller: _editorController,
              focusNode: _focusNode,
              scrollController: _scrollController,
              config: const QuillEditorConfig(
                expands: true,
                padding: EdgeInsets.zero,
                placeholder: 'Your generated draft will appear here…',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          Text(_error ?? 'Writing Chamber is unavailable.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
