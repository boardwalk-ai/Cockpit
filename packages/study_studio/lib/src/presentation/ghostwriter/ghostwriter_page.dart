import 'package:flutter/material.dart';

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

  GhostWriterStage _stage = GhostWriterStage.idle;

  final List<String> _threads = [
    'Artificial Intelligence in Education',
    'Genghis Khan',
    '400 words essay about alex...',
    'Alexander Pope',
    'Alexander Pope',
  ];

  int _selectedThreadIndex = 0;
  int? _hoveredThreadIndex;
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
  void dispose() {
    _promptController.dispose();
    _chatController.dispose();
    _askOctoController.dispose();
    super.dispose();
  }

  void _start() {
    final message = _promptController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _chatMessages.add(message);
      _stage = GhostWriterStage.generating;
    });
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
                const _GhostWriterTopBar(),
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
            'THREADS',
            style: TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: _threads.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final selected = _selectedThreadIndex == index;
                final hovered = _hoveredThreadIndex == index;

                final status = index == 0
                    ? 'Running...'
                    : index == 3
                    ? 'Finished'
                    : 'Error';

                return MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _hoveredThreadIndex = index;
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      _hoveredThreadIndex = null;
                    });
                  },
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedThreadIndex = index;
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
                            : hovered
                            ? const Color(0xFF181A1D)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _threads[index],
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
                          if (hovered || selected)
                            PopupMenuButton<String>(
                              tooltip: '',
                              color: const Color(0xFF1A1B1E),
                              elevation: 8,
                              offset: const Offset(0, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Color(0xFF34363A),
                                ),
                              ),
                              icon: const Icon(
                                Icons.more_horiz,
                                color: Color(0xFF8C8E93),
                                size: 22,
                              ),
                              onSelected: (value) {
                                if (value == 'delete') {
                                  setState(() {
                                    _threads.removeAt(index);

                                    if (_threads.isEmpty) {
                                      _selectedThreadIndex = 0;
                                    } else if (_selectedThreadIndex >=
                                        _threads.length) {
                                      _selectedThreadIndex =
                                          _threads.length - 1;
                                    }

                                    _hoveredThreadIndex = null;
                                  });
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem<String>(
                                  value: 'folder',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.folder_outlined,
                                        color: Color(0xFFBFC0C4),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Add to folder',
                                        style: TextStyle(
                                          color: Color(0xFFD0D1D4),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuDivider(),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFFF4B52),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Delete thread',
                                        style: TextStyle(
                                          color: Color(0xFFFF4B52),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: InkWell(
              onTap: () {
                setState(() {
                  _showAskOcto = !_showAskOcto;
                });
              },
              borderRadius: BorderRadius.circular(999),
              child: const CircleAvatar(
                radius: 34,
                backgroundColor: Color(0xFF15100B),
                child: Text('👻', style: TextStyle(fontSize: 30)),
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
          _WorkspaceHeader(finished: _stage == GhostWriterStage.finished),
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
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                final message = _chatMessages[_chatMessages.length - 1 - index];

                return Align(
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
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFFF343C,
                          ).withValues(alpha: 0.18),
                          blurRadius: 28,
                        ),
                      ],
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All done. Your humanized essay is packaged and ready to download. Let me know if you’d like any revisions, a full rewrite, or anything else.',
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
                        'Refine the humanized essay before your final download',
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
            'HUMANIZED · STEALTHGPT',
            style: TextStyle(
              color: Color(0xFF5E6065),
              fontSize: 11,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _panelSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: const Text(
              'Artificial intelligence is rapidly reshaping education by supporting personalized learning, reducing repetitive workloads, and helping students access information more efficiently. At the same time, responsible use requires careful attention to privacy, fairness, transparency, and the continuing role of human teachers.\n\nAI systems can adapt lessons to a learner’s pace and provide targeted feedback. Yet these tools should augment human judgment rather than replace it. The strongest educational systems will combine technological capability with human empathy, creativity, and accountability.\n\nAs adoption expands, schools and universities must establish clear policies that ensure artificial intelligence strengthens learning without narrowing it into purely data-driven outcomes.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ESSAY INFORMATION',
          style: TextStyle(
            color: Color(0xFF5E6065),
            fontSize: 11,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 26),
        _InfoBlock(
          label: 'TOPIC',
          value: 'Artificial Intelligence in Education',
        ),
        _InfoBlock(label: 'ESSAY TYPE', value: 'Argumentative'),
        _InfoBlock(label: 'CITATION', value: 'APA'),
        _InfoBlock(label: 'WORD COUNT', value: '1000'),
        SizedBox(height: 20),
        Text(
          'Outlines',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildSourcesPanel() {
    const sources = [
      ('Artificial intelligence in education – AI', 'UNESCO'),
      ('AI in Education: Benefits, Risks, and Real Examples', 'Netguru'),
      (
        'Artificial Intelligence in Education: Benefits, Risks and Challenges',
        'Fairmont School of Business',
      ),
      ('How Khan Academy Is Building a Better AI Tutor', 'Khan Academy'),
      ('What is MATHia?', 'Carnegie Learning'),
    ];

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
          for (final source in sources) ...[
            Text(
              source.$1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              source.$2,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'https://example.com/source',
              style: TextStyle(color: Color(0xFFFF6268), fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Divider(color: _border, height: 1),
            const SizedBox(height: 16),
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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _stage == GhostWriterStage.finished
                    ? 'Ask Ghostwriter anything about your essay...'
                    : 'Ask for different focus areas, or describe what to emphasize...',
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
              onPressed: () {
                final message = _chatController.text.trim();

                if (message.isEmpty) return;

                setState(() {
                  _chatMessages.add(message);
                  _chatController.clear();
                });
              },
              icon: const Icon(Icons.send_rounded, color: Color(0xFFFF6C72)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostWriterTopBar extends StatelessWidget {
  const _GhostWriterTopBar();

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
          _TopChip(label: 'GUEST', dotColor: Color(0xFFA7D6FF)),
          const SizedBox(width: 10),
          const _TopChip(
            label: '2,067 OCTOCREDITS',
            dotColor: Color(0xFFFFD54F),
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
            icon: Icons.save_outlined,
            label: 'Save',
            onTap: () {},
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
  const _WorkspaceHeader({required this.finished});

  final bool finished;

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
                    const Text(
                      'Artificial Intelligence in Education',
                      style: TextStyle(
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
              const Wrap(
                spacing: 8,
                children: [
                  _TopChip(label: 'ARGUMENTATIVE'),
                  _TopChip(label: 'APA'),
                  _TopChip(label: '1,000 WORDS'),
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
