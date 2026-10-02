import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'mobile_motion.dart';
import 'mobile_theme.dart';
import 'mobile_top_bar.dart';

/// Phone side drawer: new chat, search, folders, saved threads and the
/// account row. Rows slide in one after another each time it opens.
class GhostWriterMobileDrawer extends StatefulWidget {
  const GhostWriterMobileDrawer({
    super.key,
    required this.threads,
    required this.folders,
    required this.loading,
    required this.selectedIndex,
    required this.sessionName,
    required this.credits,
    required this.onNewChat,
    required this.onOpenThread,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> threads;
  final List<Map<String, dynamic>> folders;
  final bool loading;

  /// Index into [threads] of the open thread, or null on the landing screen.
  final int? selectedIndex;

  final String sessionName;
  final int credits;
  final VoidCallback onNewChat;
  final ValueChanged<int> onOpenThread;
  final Future<void> Function() onRefresh;

  @override
  State<GhostWriterMobileDrawer> createState() =>
      _GhostWriterMobileDrawerState();
}

class _GhostWriterMobileDrawerState extends State<GhostWriterMobileDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entry.value = 1;
    } else if (_entry.status == AnimationStatus.dismissed) {
      _entry.forward();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _search.dispose();
    super.dispose();
  }

  static String _titleOf(Map<String, dynamic> thread) =>
      thread['title']?.toString() ?? 'Untitled GhostWriter Essay';

  void _close() => Navigator.of(context).pop();

  /// Slides row number [order] in a little after the one before it.
  Widget _staggered(int order, Widget child) {
    final start = math.min(0.08 * order, 0.6);

    return GwReveal(
      animation: _entry,
      from: start,
      to: math.min(start + 0.4, 1),
      offset: const Offset(-26, 0),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 340.0);

    final matches = [
      for (final (index, thread) in widget.threads.indexed)
        if (_titleOf(thread).toLowerCase().contains(_query)) index,
    ];

    var order = 0;

    return Drawer(
      width: width,
      elevation: 0,
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xEB1B1C1C),
            border: Border(right: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _staggered(order++, _Header(onClose: _close)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: _staggered(
                    order++,
                    _NewChatButton(
                      onTap: () {
                        _close();
                        widget.onNewChat();
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _staggered(
                    order++,
                    _SearchField(
                      controller: _search,
                      onChanged: (value) {
                        setState(() => _query = value.trim().toLowerCase());
                      },
                    ),
                  ),
                ),
                if (widget.loading)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: GwColors.accent,
                      backgroundColor: Color(0x22FFFFFF),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: widget.onRefresh,
                    color: GwColors.accent,
                    backgroundColor: GwColors.chip,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                      children: [
                        if (widget.folders.isNotEmpty) ...[
                          _staggered(order++, const _SectionLabel('Folders')),
                          for (final folder in widget.folders)
                            _staggered(
                              order++,
                              _FolderRow(
                                name: (folder['name'] ?? 'Untitled Folder')
                                    .toString(),
                              ),
                            ),
                          const SizedBox(height: 14),
                        ],
                        _staggered(
                          order++,
                          _SectionLabel(
                            'Threads',
                            trailing: widget.threads.isEmpty
                                ? null
                                : '${matches.length}',
                          ),
                        ),
                        if (matches.isEmpty && !widget.loading)
                          _staggered(
                            order++,
                            _EmptyThreads(searching: _query.isNotEmpty),
                          ),
                        for (final index in matches)
                          _staggered(
                            order++,
                            _ThreadRow(
                              title: _titleOf(widget.threads[index]),
                              status:
                                  widget.threads[index]['status']?.toString() ??
                                  'Saved',
                              selected: widget.selectedIndex == index,
                              onTap: () {
                                _close();
                                widget.onOpenThread(index);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _AccountRow(name: widget.sessionName, credits: widget.credits),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Image.asset(GwAssets.ghost, width: 34, height: 34),
          const SizedBox(width: 10),
          const Expanded(child: GwWordmark(fontSize: 19)),
          GwPressable(
            tooltip: 'Close',
            onTap: onClose,
            child: const SizedBox(
              width: kGwButton,
              height: kGwButton,
              child: Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GwPressable(
      haptic: GwHaptic.medium,
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF4A4F), Color(0xFFE8202A)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55FF343C),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 21),
            SizedBox(width: 8),
            Text(
              'New chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: GwColors.hint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: GwColors.accent,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: GwFonts.secondary,
                fontFamilyFallback: GwFonts.secondaryFallback,
                fontSize: 14.5,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search threads',
                hintStyle: TextStyle(
                  color: GwColors.hint,
                  fontFamily: GwFonts.secondary,
                  fontFamilyFallback: GwFonts.secondaryFallback,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: GwColors.hint,
      fontSize: 11,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w700,
    );
    final trailing = this.trailing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: style),
          const Spacer(),
          if (trailing != null) Text(trailing, style: style),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(
        children: [
          const Icon(
            Icons.folder_rounded,
            size: 19,
            color: GwColors.accentSoft,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD7D7D9),
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.title,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final finished = status.toLowerCase() == 'finished';

    return GwPressable(
      haptic: GwHaptic.selection,
      pressedScale: 0.97,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 11, 12, 11),
        decoration: BoxDecoration(
          color: selected
              ? GwColors.accent.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? GwColors.accent.withValues(alpha: 0.38)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: finished ? const Color(0xFF3DDC84) : GwColors.gold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFD7D7D9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GwColors.muted,
                      fontFamily: GwFonts.secondary,
                      fontFamilyFallback: GwFonts.secondaryFallback,
                      fontSize: 12,
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

class _EmptyThreads extends StatelessWidget {
  const _EmptyThreads({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
      child: Column(
        children: [
          Opacity(
            opacity: 0.45,
            child: Image.asset(GwAssets.ghost, width: 76, height: 76),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No threads match' : 'No saved threads yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD7D7D9),
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            searching
                ? 'Try a different word.'
                : 'Drafts you save will show up here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GwColors.muted,
              fontFamily: GwFonts.secondary,
              fontFamilyFallback: GwFonts.secondaryFallback,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.name, required this.credits});

  final String name;
  final int credits;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final display = trimmed.isEmpty
        ? 'Guest'
        : trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF4A4F), Color(0xFF8E1218)],
              ),
            ),
            child: Text(
              display[0],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OctoCreditsPill(credits: credits),
        ],
      ),
    );
  }
}
