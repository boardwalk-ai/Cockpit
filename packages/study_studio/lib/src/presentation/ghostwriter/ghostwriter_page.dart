import 'dart:async';

import 'package:flutter/material.dart';

import 'ghostwriter_api.dart';

enum GhostWriterStage { idle, typing, generating, finished }

class GhostWriterPage extends StatefulWidget {
  const GhostWriterPage({super.key});

  @override
  State<GhostWriterPage> createState() => _GhostWriterPageState();
}

class _GhostWriterPageState extends State<GhostWriterPage> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final List<String> _chatMessages = [];

  final GhostWriterApi _api = GhostWriterApi();
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  String? _runId;
  String _assistantText = '';
  String? _errorMessage;
  String? _pendingField;
  String? _pendingQuestion;
  Map<String, dynamic> _agentContext = {};

  GhostWriterStage _stage = GhostWriterStage.idle;

  List<Map<String, dynamic>> _threads = [];
  List<Map<String, dynamic>> _folders = [];

  String _sessionName = 'GUEST';
  int _credits = 0;
  bool _workspaceLoading = true;
  bool _saving = false;
  bool _starting = false;

  int _selectedThreadIndex = 0;
  bool _showAskOcto = false;
  final TextEditingController _askOctoController = TextEditingController();
  String _askOctoAnswer =
      'Ask one question. Octo will answer with a single focused reply.';

  static const Color _background = Color(0xFF080909);
  static const Color _panel = Color(0xFF0D0E10);
  static const Color _panelSoft = Color(0xFF131416);
  static const Color _border = Color(0xFF2B2D31);
  static const Color _muted = Color(0xFF85878D);
  static const Color _accent = Color(0xFFFF343C);

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  Future<void> _loadWorkspace() async {
    try {
      final data = await _api.workspace();

      if (!mounted) return;

      final rawThreads = data['threads'];
      final rawFolders = data['folders'];

      setState(() {
        _sessionName = data['sessionName']?.toString() ?? 'GUEST';
        _credits = data['credits'] is int
            ? data['credits'] as int
            : int.tryParse(data['credits']?.toString() ?? '') ?? 0;

        _threads = rawThreads is List
            ? rawThreads
                  .whereType<Map>()
                  .map(
                    (item) => item.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  )
                  .toList()
            : [];

        _folders = rawFolders is List
            ? rawFolders
                  .whereType<Map>()
                  .map(
                    (item) => item.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  )
                  .toList()
            : [];

        _workspaceLoading = false;

        if (_threads.isEmpty) {
          _selectedThreadIndex = 0;
        } else if (_selectedThreadIndex >= _threads.length) {
          _selectedThreadIndex = 0;
        }
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _workspaceLoading = false;
        _errorMessage = 'Workspace failed: $error';
      });
    }
  }

  Future<void> _saveCurrentThread() async {
    if (_saving) return;

    final prompt = _promptController.text.trim();

    if (prompt.isEmpty) {
      setState(() {
        _errorMessage = 'Nothing to save yet.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final draftSettings = _agentContext['draftSettings'];
      final settings = draftSettings is Map
          ? draftSettings.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};

      final exportDoc = _agentContext['exportDoc'];
      final export = exportDoc is Map
          ? exportDoc.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};

      String essay = '';

      for (final key in [
        'essay',
        'essay_content',
        'content',
        'humanizedEssay',
        'finalEssay',
      ]) {
        final value = export[key] ?? _agentContext[key];

        if (value != null && value.toString().trim().isNotEmpty) {
          essay = value.toString();
          break;
        }
      }

      if (essay.isEmpty) {
        essay = _assistantText;
      }

      String bibliography = '';

      for (final key in ['bibliography', 'references', 'referenceList']) {
        final value = export[key] ?? _agentContext[key];

        if (value != null && value.toString().trim().isNotEmpty) {
          bibliography = value.toString();
          break;
        }
      }

      final rawSources =
          _agentContext['sources'] ??
          _agentContext['researchSources'] ??
          _agentContext['scrapedSources'];

      final sources = rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (item) =>
                      item.map((key, value) => MapEntry(key.toString(), value)),
                )
                .toList()
          : <Map<String, dynamic>>[];

      final citationStyle =
          settings['citationStyle']?.toString() ??
          _agentContext['citationStyle']?.toString() ??
          'APA';

      final rawWordCount = settings['wordCount'] ?? _agentContext['wordCount'];

      final wordCount = rawWordCount is int
          ? rawWordCount
          : int.tryParse(rawWordCount?.toString() ?? '') ??
                essay
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((e) => e.isNotEmpty)
                    .length;

      String? folderId;

      if (_folders.isEmpty) {
        final createdFolder = await _api.createFolder('My Essays');

        folderId = createdFolder['id']?.toString();

        if (folderId == null || folderId.isEmpty) {
          throw Exception('Backend created a folder without an id');
        }

        _folders = [
          createdFolder.map((key, value) => MapEntry(key.toString(), value)),
        ];
      } else {
        folderId = _folders.first['id']?.toString();
      }

      await _api.saveThread(
        runId: _runId,
        folderId: folderId,
        title: prompt.length > 60 ? '${prompt.substring(0, 60)}...' : prompt,
        prompt: prompt,
        status: _stage == GhostWriterStage.finished ? 'Finished' : 'Running',
        essay: essay,
        bibliography: bibliography,
        citationStyle: citationStyle,
        wordCount: wordCount,
        sources: sources,
      );

      await _loadWorkspace();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GhostWriter thread saved')));
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Save failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _promptController.dispose();
    _chatController.dispose();
    _askOctoController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;

    final message = _promptController.text.trim();
    if (message.isEmpty) return;

    _starting = true;

    await _eventSubscription?.cancel();

    if (mounted) {
      setState(() {
        _chatMessages
          ..clear()
          ..add(message);
        _assistantText = '';
        _errorMessage = null;
        _pendingField = null;
        _pendingQuestion = null;
        _agentContext = {};
        _stage = GhostWriterStage.generating;
      });
    }

    try {
      final runId = await _api.start(message);

      if (!mounted) return;

      setState(() {
        _runId = runId;
      });

      await _loadWorkspace();

      _eventSubscription = _api
          .events(runId)
          .listen(
            _handleAgentEvent,
            onError: (Object error) {
              if (!mounted) return;

              setState(() {
                _errorMessage = 'Stream disconnected: $error';
              });
            },
          );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Could not start GhostWriter: $error';
      });
    } finally {
      _starting = false;
    }
  }

  Future<void> _retryStream() async {
    final runId = _runId;

    if (runId == null) {
      await _start();
      return;
    }

    await _eventSubscription?.cancel();

    if (!mounted) return;

    setState(() {
      _errorMessage = null;
    });

    try {
      _eventSubscription = _api
          .events(runId)
          .listen(
            _handleAgentEvent,
            onError: (Object error) {
              if (!mounted) return;

              setState(() {
                _errorMessage = 'Stream disconnected: $error';
              });
            },
          );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Reconnect failed: $error';
      });
    }
  }

  void _handleAgentEvent(Map<String, dynamic> event) {
    if (!mounted) return;

    final type = event['type']?.toString();

    setState(() {
      switch (type) {
        case 'assistant_delta':
        case 'essay_delta':
          _assistantText += event['chunk']?.toString() ?? '';
          break;

        case 'assistant_message':
          final text = event['text']?.toString() ?? '';
          if (_assistantText.trim().isEmpty) {
            _assistantText = text;
          }
          break;

        case 'question':
          _pendingField = event['field']?.toString();
          _pendingQuestion = event['question']?.toString();
          break;

        case 'context_update':
          final patch = event['patch'];
          if (patch is Map) {
            _agentContext.addAll(
              patch.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
          break;

        case 'step_error':
        case 'fatal':
          _errorMessage = event['error']?.toString() ?? 'GhostWriter failed.';
          break;

        case 'done':
          _pendingField = null;
          _pendingQuestion = null;
          _stage = GhostWriterStage.finished;
          break;
      }
    });
  }

  Future<void> _sendComposerMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;

    final runId = _runId;

    if (runId == null) {
      setState(() {
        _errorMessage = 'No active GhostWriter session.';
      });
      return;
    }

    _chatController.clear();

    try {
      if (_pendingField != null) {
        final field = _pendingField!;

        setState(() {
          _chatMessages.add(message);
          _pendingField = null;
          _pendingQuestion = null;
        });

        await _api.answer(runId: runId, field: field, value: message);
      } else {
        setState(() {
          _chatMessages.add(message);
        });

        await _api.message(runId: runId, text: message);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Message failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1100;

    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _GhostWriterTopBar(
                  sessionName: _sessionName,
                  credits: _credits,
                  saving: _saving,
                  onSave: _saveCurrentThread,
                ),
                Expanded(
                  child:
                      _stage == GhostWriterStage.idle ||
                          _stage == GhostWriterStage.typing
                      ? _buildLanding()
                      : desktop
                      ? Row(
                          children: [
                            SizedBox(width: 280, child: _buildThreadSidebar()),
                            Expanded(child: _buildWorkspace()),
                            SizedBox(width: 310, child: _buildRightPanel()),
                          ],
                        )
                      : _buildWorkspace(),
                ),
              ],
            ),
          ),
          if (_showAskOcto)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  setState(() {
                    _showAskOcto = false;
                  });
                },
              ),
            ),
          if (_showAskOcto)
            Positioned(left: 16, bottom: 16, child: _buildAskOctoPanel()),
        ],
      ),
    );
  }

  Widget _buildLanding() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compact ? 22 : 40,
            compact ? 70 : 125,
            compact ? 22 : 40,
            50,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 30,
                child: Container(
                  width: 1050,
                  height: 650,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF2F38).withValues(alpha: 0.34),
                        const Color(0xFFB71922).withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    children: [
                      // Temporary mascot until real GhostWriter asset is added.
                      const Text(
                        '👻',
                        style: TextStyle(fontSize: 52, height: 1),
                      ),

                      const SizedBox(height: 28),

                      Text(
                        'Hey there, Ravshanjon',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFFF5258),
                          shadows: [
                            Shadow(
                              color: const Color(
                                0xFFFF3B43,
                              ).withValues(alpha: 0.28),
                              blurRadius: 14,
                            ),
                          ],
                          fontSize: compact ? 43 : 57,
                          height: 1.04,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -2.0,
                        ),
                      ),

                      const SizedBox(height: 20),

                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: const Text(
                          'Draft fast. Revise cleanly. Bring a messy idea, a source pack, '
                          'or a rough section and turn it into sharper prose.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF85878D),
                            fontSize: 16,
                            height: 1.55,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),

                      const SizedBox(height: 34),

                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 236),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E0F10),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFF282629),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFF3038,
                              ).withValues(alpha: 0.055),
                              blurRadius: 65,
                              offset: const Offset(32, 30),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 20, 18, 16),
                        child: Column(
                          children: [
                            TextField(
                              controller: _promptController,

                              // IMPORTANT:
                              // No expands and no fixed gray SizedBox.
                              minLines: 5,
                              maxLines: 8,

                              textAlignVertical: TextAlignVertical.top,

                              onChanged: (value) {
                                setState(() {
                                  _stage = value.trim().isEmpty
                                      ? GhostWriterStage.idle
                                      : GhostWriterStage.typing;
                                });
                              },

                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.45,
                              ),

                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,

                                filled: false,
                                fillColor: Colors.transparent,

                                isDense: true,
                                contentPadding: EdgeInsets.zero,

                                hintText:
                                    'Drop the brief, Ravshanjon. I can shape the draft, '
                                    'rewrite a section, or polish attached sources.',

                                hintStyle: TextStyle(
                                  color: Color(0xFF62646A),
                                  fontSize: 16,
                                  height: 1.45,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            Row(
                              children: [
                                InkWell(
                                  onTap: () {},
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF111214),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF303236),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Color(0xFFD7D7D9),
                                      size: 24,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                InkWell(
                                  onTap: () {},
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    height: 50,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF211012),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFF7A2D31),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.language_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Source',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const Spacer(),

                                InkWell(
                                  onTap: () {},
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF111214),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF303236),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.mic_none_rounded,
                                      color: Color(0xFFD7D7D9),
                                      size: 23,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                InkWell(
                                  onTap: _start,
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    height: 50,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF343C),
                                      borderRadius: BorderRadius.circular(999),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFFFF343C,
                                          ).withValues(alpha: 0.24),
                                          blurRadius: 24,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Start',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          color: Colors.white,
                                          size: 21,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAskOctoPanel() {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101520),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4A3A28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF1B2230),
                child: Text('👻', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask Octo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Quick guidance for the screen you are on.',
                      style: TextStyle(color: Color(0xFF85878D), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 165,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF101622),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF2A3040)),
            ),
            child: Text(
              _askOctoAnswer,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF85878D),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _askOctoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ask Octo about this page...',
                    hintStyle: const TextStyle(color: Color(0xFF62646A)),
                    filled: true,
                    fillColor: const Color(0xFF121A27),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF4A3A28)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF4A3A28)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () {
                    final question = _askOctoController.text.trim();
                    if (question.isEmpty) return;

                    setState(() {
                      _askOctoAnswer =
                          'This GhostWriter page helps you start an essay, manage your writing thread, and ask for revisions or guidance.';
                      _askOctoController.clear();
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7A3030),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Ask'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThreadSidebar() {
    return Container(
      color: const Color(0xFF0B0C0E),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _stage = GhostWriterStage.idle;
                  _promptController.clear();
                  _chatController.clear();
                  _chatMessages.clear();
                  _assistantText = '';
                  _errorMessage = null;
                  _pendingField = null;
                  _pendingQuestion = null;
                  _runId = null;
                  _agentContext = {};
                });
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New chat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'FOLDERS',
            style: TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          if (_workspaceLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_folders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No folders yet',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            )
          else
            for (final folder in _folders)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _panelSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_rounded,
                      size: 18,
                      color: Color(0xFFFF6268),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        (folder['name'] ?? 'Untitled Folder').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

          const SizedBox(height: 18),

          const Text(
            'THREADS',
            style: TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          if (_workspaceLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_threads.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No saved threads yet',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadWorkspace,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _threads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final thread = _threads[index];
                    final selected = _selectedThreadIndex == index;

                    final title =
                        thread['title']?.toString() ??
                        'Untitled GhostWriter Essay';

                    final status = thread['status']?.toString() ?? 'Saved';

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedThreadIndex = index;

                          final prompt = thread['prompt']?.toString() ?? '';

                          final essay = thread['essay']?.toString() ?? '';

                          _promptController.text = prompt;
                          _assistantText = essay;
                          _stage = status.toLowerCase() == 'finished'
                              ? GhostWriterStage.finished
                              : GhostWriterStage.generating;

                          _agentContext = {
                            'bibliography': thread['bibliography'] ?? '',
                            'citationStyle': thread['citationStyle'] ?? '',
                            'wordCount': thread['wordCount'] ?? 0,
                            'sources': thread['sources'] ?? [],
                          };
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? _accent.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFFD0D1D4),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    return Container(
      color: _panel,
      child: Column(
        children: [
          _WorkspaceHeader(
            finished: _stage == GhostWriterStage.finished,
            title: _promptController.text.trim().isEmpty
                ? 'Untitled GhostWriter Essay'
                : _promptController.text.trim(),
            citationStyle:
                (_agentContext['citationStyle'] ??
                        (_agentContext['draftSettings'] is Map
                            ? (_agentContext['draftSettings']
                                  as Map)['citationStyle']
                            : null) ??
                        'APA')
                    .toString(),
            wordCount:
                int.tryParse(
                  (_agentContext['wordCount'] ??
                          (_agentContext['draftSettings'] is Map
                              ? (_agentContext['draftSettings']
                                    as Map)['wordCount']
                              : null) ??
                          0)
                      .toString(),
                ) ??
                0,
          ),
          Expanded(
            child: _stage == GhostWriterStage.finished
                ? _buildFinishedState()
                : _buildGeneratingState(),
          ),
          _buildBottomComposer(),
        ],
      ),
    );
  }

  Widget _buildGeneratingState() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFF0D0E10)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _GhostWriterGridPainter()),
          ),
          Positioned.fill(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
              children: [
                for (final message in _chatMessages)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2C33),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                if (_assistantText.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 700),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF17191D),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _border),
                      ),
                      child: Text(
                        _assistantText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),

                if (_pendingQuestion != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF211012),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF7A2D31)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GhostWriter needs your input',
                            style: TextStyle(
                              color: Color(0xFFFF777D),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _pendingQuestion!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Answer below and press send.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_errorMessage != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 700),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF251013),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFF4B52)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFFF777D),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _retryStream,
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: const Text('Retry'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFF777D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedState() {
    final contextEssay = (_agentContext['essay'] ?? '').toString().trim();
    final essay = contextEssay.isNotEmpty
        ? contextEssay
        : _assistantText.trim();

    final bibliography = (_agentContext['bibliography'] ?? '')
        .toString()
        .trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your GhostWriter draft is complete.',
            style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF12131A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E3154)),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_note_rounded, color: Color(0xFF7C7CFF)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Proceed to Editor',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Review and refine your generated essay',
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: Colors.white70),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'FINAL ESSAY',
            style: TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _panelSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Text(
              essay.isEmpty
                  ? 'No essay content was returned by the backend.'
                  : essay,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
          if (bibliography.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'REFERENCES',
              style: TextStyle(
                color: Color(0xFF5E6065),
                fontSize: 11,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _panelSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Text(
                bibliography,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      color: const Color(0xFF0B0C0E),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: _stage == GhostWriterStage.finished
          ? _buildSourcesPanel()
          : _buildEssayInfoPanel(),
    );
  }

  Widget _buildEssayInfoPanel() {
    final topic = _promptController.text.trim().isEmpty
        ? 'Untitled GhostWriter Essay'
        : _promptController.text.trim();

    final citationStyle =
        (_agentContext['citationStyle'] ??
                (_agentContext['draftSettings'] is Map
                    ? (_agentContext['draftSettings'] as Map)['citationStyle']
                    : null) ??
                'Pending')
            .toString();

    final wordCount =
        (_agentContext['wordCount'] ??
                (_agentContext['draftSettings'] is Map
                    ? (_agentContext['draftSettings'] as Map)['wordCount']
                    : null) ??
                'Pending')
            .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ESSAY INFORMATION',
          style: TextStyle(
            color: Color(0xFF5E6065),
            fontSize: 11,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 26),
        _InfoBlock(label: 'TOPIC', value: topic),
        _InfoBlock(
          label: 'STATUS',
          value: _stage == GhostWriterStage.finished
              ? 'Finished'
              : 'Generating',
        ),
        _InfoBlock(label: 'CITATION', value: citationStyle),
        _InfoBlock(label: 'WORD COUNT', value: wordCount),
      ],
    );
  }

  Widget _buildSourcesPanel() {
    final rawSources =
        _agentContext['compactedSources'] ??
        _agentContext['sources'] ??
        const [];

    final sources = <Map<String, dynamic>>[];

    if (rawSources is List) {
      for (final item in rawSources) {
        if (item is Map) {
          sources.add(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }

    final bibliography = (_agentContext['bibliography'] ?? '')
        .toString()
        .trim();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SOURCES',
            style: TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          if (sources.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: const Text(
                'No sources were returned by the backend.',
                style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
              ),
            )
          else
            for (final source in sources) ...[
              Text(
                (source['title'] ?? 'Untitled source').toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if ((source['author'] ?? '').toString().trim().isNotEmpty)
                Text(
                  source['author'].toString(),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              if ((source['publisher'] ?? '').toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    source['publisher'].toString(),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              if ((source['url'] ?? '').toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    source['url'].toString(),
                    style: const TextStyle(
                      color: Color(0xFFFF6268),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(color: _border, height: 1),
              const SizedBox(height: 16),
            ],
          if (bibliography.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'REFERENCE LIST',
              style: TextStyle(
                color: Color(0xFF5E6065),
                fontSize: 11,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              bibliography,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 12, 30, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              onSubmitted: (_) => _sendComposerMessage(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:
                    _pendingQuestion ??
                    (_stage == GhostWriterStage.finished
                        ? 'Ask Ghostwriter anything about your essay...'
                        : 'Ask for different focus areas, or describe what to emphasize...'),
                hintStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _panelSoft,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _sendComposerMessage,
              icon: const Icon(Icons.send_rounded, color: Color(0xFFFF6C72)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostWriterTopBar extends StatelessWidget {
  const _GhostWriterTopBar({
    required this.sessionName,
    required this.credits,
    required this.saving,
    required this.onSave,
  });

  final String sessionName;
  final int credits;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF090A0B),
        border: Border(bottom: BorderSide(color: Color(0xFF17181B))),
      ),
      child: Row(
        children: [
          _OutlinePillButton(
            icon: Icons.arrow_back_ios_new,
            label: 'Home',
            onTap: () {},
          ),
          const Spacer(),
          const Icon(Icons.notifications_none_rounded, color: Colors.white60),
          const SizedBox(width: 20),
          _TopChip(
            label: sessionName.toUpperCase(),
            dotColor: const Color(0xFFA7D6FF),
          ),
          const SizedBox(width: 10),
          _TopChip(
            label: '$credits OCTOCREDITS',
            dotColor: const Color(0xFFFFD54F),
          ),
          const SizedBox(width: 10),
          _OutlinePillButton(
            icon: Icons.storefront_outlined,
            label: 'Store',
            onTap: () {},
            accent: true,
          ),
          const SizedBox(width: 10),
          _OutlinePillButton(
            icon: saving ? Icons.hourglass_top_rounded : Icons.save_outlined,
            label: saving ? 'Saving...' : 'Save',
            onTap: saving ? () {} : onSave,
          ),
          const SizedBox(width: 18),
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFF25262A),
            child: Icon(Icons.person, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.finished,
    required this.title,
    required this.citationStyle,
    required this.wordCount,
  });

  final bool finished;
  final String title;
  final String citationStyle;
  final int wordCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 18, 30, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF7D2A2D)),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '👻  GHOSTWRITER',
                        style: TextStyle(
                          color: Color(0xFFFF555A),
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      finished ? '●  Finished' : '●  Asking: essayFocus',
                      style: const TextStyle(
                        color: Color(0xFF85878D),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  const _TopChip(label: 'GHOSTWRITER'),
                  _TopChip(label: citationStyle.toUpperCase()),
                  _TopChip(label: '${wordCount.toString()} WORDS'),
                ],
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          minHeight: 2,
          value: finished ? 1 : 0.5,
          color: const Color(0xFFFF343C),
          backgroundColor: const Color(0xFF1B1C1F),
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  const _TopChip({required this.label, this.dotColor});

  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2A2C30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinePillButton extends StatelessWidget {
  const _OutlinePillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent ? const Color(0xFFFF777D) : Colors.white70,
        side: BorderSide(
          color: accent ? const Color(0xFF69272B) : const Color(0xFF2A2C30),
        ),
        backgroundColor: accent
            ? const Color(0xFF1B0D0F)
            : const Color(0xFF101113),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _GhostWriterGridPainter extends CustomPainter {
  const _GhostWriterGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 22.0;

    final linePaint = Paint()
      ..color = const Color(0xFF2A2D32).withValues(alpha: 0.22)
      ..strokeWidth = 0.6;

    final dotPaint = Paint()
      ..color = const Color(0xFF3A3D43).withValues(alpha: 0.34)
      ..style = PaintingStyle.fill;

    // Vertical grid lines
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    // Horizontal grid lines
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Tiny intersection dots
    for (double y = 0; y <= size.height; y += spacing) {
      for (double x = 0; x <= size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.85, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GhostWriterGridPainter oldDelegate) {
    return false;
  }
}
