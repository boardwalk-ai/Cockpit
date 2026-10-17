import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'main.dart' show signOut;
import 'notify_page.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.email});
  final AdminApi api;
  final String email;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: IndexedStack(
        index: _tab,
        children: [
          TestersPage(api: widget.api, email: widget.email),
          NotifyPage(api: widget.api),
          FlagsPage(api: widget.api),
          PricesPage(api: widget.api),
          HistoryPage(api: widget.api),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group_rounded),
          label: 'Testers',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_none_rounded),
          selectedIcon: Icon(Icons.notifications_rounded),
          label: 'Notify',
        ),
        NavigationDestination(
          icon: Icon(Icons.toggle_off_outlined),
          selectedIcon: Icon(Icons.toggle_on_rounded),
          label: 'Flags',
        ),
        NavigationDestination(
          icon: Icon(Icons.sell_outlined),
          selectedIcon: Icon(Icons.sell_rounded),
          label: 'Prices',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_rounded),
          label: 'History',
        ),
      ],
    ),
  );
}

/// The title row each tab starts with.
class _Header extends StatelessWidget {
  const _Header(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Loads with [load], shows [build], pull to refresh, errors with retry.
class _Loader<T> extends StatefulWidget {
  const _Loader({super.key, required this.load, required this.build});
  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  build;

  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late Future<T> _f = widget.load();

  Future<void> reload() async {
    final f = widget.load();
    setState(() => _f = f);
    await f.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _f,
    builder: (context, s) {
      if (s.hasError) {
        return ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Text(
                '${s.error}',
                style: const TextStyle(color: AdminColors.muted),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(
                onPressed: reload,
                child: const Text('Try again'),
              ),
            ),
          ],
        );
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        color: AdminColors.accent,
        onRefresh: reload,
        child: widget.build(context, s.data as T, reload),
      );
    },
  );
}

// ------------------------------------------------------------- testers

class TestersPage extends StatefulWidget {
  const TestersPage({super.key, required this.api, required this.email});
  final AdminApi api;
  final String email;

  @override
  State<TestersPage> createState() => _TestersPageState();
}

class _TestersPageState extends State<TestersPage> {
  String _q = '';
  final _key = GlobalKey<_LoaderState<(bool, List<AdminUser>)>>();

  Future<void> _reload() async => _key.currentState?.reload();

  Future<void> _invite() async {
    final email = TextEditingController();
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(c).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add a tester',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Their Google account gets into the app within seconds, with 9,999 OctoCredits on first sign-in.',
              style: TextStyle(color: AdminColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'name@gmail.com',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                hintText: 'Note (optional): who is this?',
              ),
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Let them in',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.pop(c, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || email.text.trim().isEmpty) return;
    try {
      await widget.api.allow(
        email.text.trim(),
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      if (mounted) toast(context, '${email.text.trim()} is on the list');
      await _reload();
    } on Object catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _open(AdminUser u) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _UserSheet(api: widget.api, user: u),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Header(
        'Testers',
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (_) => signOut(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'out',
              child: Text('Sign out ${widget.email}'),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Search email or name',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (v) {
            setState(() => _q = v.trim());
            _reload();
          },
        ),
      ),
      Expanded(
        child: Stack(
          children: [
            _Loader<(bool, List<AdminUser>)>(
              key: _key,
              load: () => widget.api.users(_q),
              build: (context, data, reload) {
                final (open, users) = data;
                final invited = users.where((u) => u.invited || u.admin).length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                  children: [
                    if (open)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Panel(
                          highlight: true,
                          child: Text(
                            'open_access is ON — anyone signed in gets into the app, not only this list.',
                            style: TextStyle(color: AdminColors.accent2),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        '$invited on the list · ${users.length} accounts',
                        style: const TextStyle(color: AdminColors.muted),
                      ),
                    ),
                    for (final u in users)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UserTile(u, onTap: () => _open(u)),
                      ),
                  ],
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: GradientButton(
                label: 'Add tester',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: _invite,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.u, {this.size = 44});
  final AdminUser u;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = (u.name?.trim().isNotEmpty == true ? u.name! : u.email)
        .characters
        .first
        .toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: u.invited || u.admin ? AdminColors.gradient : null,
        color: AdminColors.surface2,
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: u.photoUrl != null
            ? Image.network(
                u.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _letter(letter),
              )
            : _letter(letter),
      ),
    );
  }

  Widget _letter(String l) => ColoredBox(
    color: AdminColors.surface2,
    child: Center(
      child: Text(l, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}

class _UserTile extends StatelessWidget {
  const _UserTile(this.u, {required this.onTap});
  final AdminUser u;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        _Avatar(u),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                u.name?.isNotEmpty == true ? u.name! : u.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                u.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AdminColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  if (u.admin) const _Chip('Admin', accent: true),
                  if (u.invited) const _Chip('On the list', accent: true),
                  if (!u.invited && !u.admin) const _Chip('Not invited'),
                  if (u.id == null) const _Chip('Not signed in yet'),
                  if (u.phones > 0)
                    _Chip(
                      '${u.phones} phone${u.phones == 1 ? '' : 's'}',
                      accent: true,
                    )
                  else if (u.phonesSeen > 0)
                    const _Chip('No notifications'),
                ],
              ),
            ],
          ),
        ),
        if (u.id != null) ...[
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(u.credits),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'credits',
                style: TextStyle(color: AdminColors.faint, fontSize: 11),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.accent = false});
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: accent
          ? AdminColors.accent.withValues(alpha: 0.14)
          : Colors.transparent,
      border: Border.all(
        color: accent
            ? AdminColors.accent.withValues(alpha: 0.4)
            : AdminColors.line,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: accent ? AdminColors.accent2 : AdminColors.muted,
      ),
    ),
  );
}

String _fmt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class _UserSheet extends StatefulWidget {
  const _UserSheet({required this.api, required this.user});
  final AdminApi api;
  final AdminUser user;

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late bool _invited = widget.user.invited;
  late int _credits = widget.user.credits;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  late final Future<List<Phone>> _phones = widget.api.phones(widget.user.email);

  Future<void> _setInvited(bool v) async {
    setState(() => _busy = true);
    try {
      if (v) {
        await widget.api.allow(widget.user.email);
      } else {
        await widget.api.disallow(widget.user.email);
      }
      setState(() => _invited = v);
    } on Object catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _move(int sign) async {
    final n = int.tryParse(_amount.text.replaceAll(',', '').trim());
    if (n == null || n <= 0) {
      toast(context, 'Type how many credits');
      return;
    }
    setState(() => _busy = true);
    try {
      final reason = _reason.text.trim().isEmpty
          ? (sign > 0 ? 'top-up' : 'correction')
          : _reason.text.trim();
      final b = await widget.api.moveCredits(widget.user.id!, sign * n, reason);
      setState(() => _credits = b);
      _amount.clear();
      if (mounted)
        toast(context, '${sign > 0 ? '+' : '−'}${_fmt(n)} · now ${_fmt(b)}');
    } on Object catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Avatar(u, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.name?.isNotEmpty == true ? u.name! : u.email,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      GestureDetector(
                        onLongPress: () =>
                            Clipboard.setData(ClipboardData(text: u.email)),
                        child: Text(
                          u.email,
                          style: const TextStyle(color: AdminColors.muted),
                        ),
                      ),
                      if (u.note != null)
                        Text(
                          u.note!,
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
            const SizedBox(height: 18),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'On the test list',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  u.admin
                      ? 'An admin always gets in.'
                      : (_invited
                            ? 'Can use the app.'
                            : 'Sees "not on the test list".'),
                  style: const TextStyle(color: AdminColors.muted),
                ),
                value: _invited,
                onChanged: _busy ? null : _setInvited,
              ),
            ),
            const SizedBox(height: 12),
            _PhonesPanel(phones: _phones),
            if (u.id != null) ...[
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OctoCredits',
                      style: TextStyle(
                        color: AdminColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ShaderMask(
                      shaderCallback: (r) =>
                          AdminColors.gradient.createShader(r),
                      child: Text(
                        _fmt(_credits),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in [100, 1000, 5000, 10000])
                          ActionChip(
                            label: Text(_fmt(n)),
                            onPressed: () => _amount.text = '$n',
                            backgroundColor: AdminColors.surface2,
                            side: const BorderSide(color: AdminColors.line),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Amount'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reason,
                      decoration: const InputDecoration(
                        hintText: 'Reason (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _busy ? null : () => _move(-1),
                            icon: const Icon(Icons.remove_rounded),
                            label: const Text('Take'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GradientButton(
                            label: 'Add',
                            icon: Icons.add_rounded,
                            onPressed: _busy ? null : () => _move(1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- flags

class FlagsPage extends StatefulWidget {
  const FlagsPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<FlagsPage> createState() => _FlagsPageState();
}

class _FlagsPageState extends State<FlagsPage> {
  final _key = GlobalKey<_LoaderState<List<Flag>>>();

  Future<void> _set(
    Flag f, {
    required bool enabled,
    List<String>? emails,
  }) async {
    try {
      await widget.api.putFlag(f.key, enabled: enabled, emails: emails);
      if (mounted)
        toast(
          context,
          '${f.key} ${enabled
              ? 'on'
              : (emails?.isNotEmpty ?? f.emails.isNotEmpty)
              ? 'on for some'
              : 'off'}',
        );
    } on Object catch (e) {
      if (mounted) toast(context, '$e');
    }
    await _key.currentState?.reload();
  }

  Future<void> _editEmails(Flag f) async {
    final c = TextEditingController(text: f.emails.join('\n'));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(s).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${f.key}: only for',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'When the flag is off, it stays on for these emails (one per line).',
              style: TextStyle(color: AdminColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Save',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.pop(s, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final emails = c.text
        .split(RegExp(r'[\s,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await _set(f, enabled: f.enabled, emails: emails);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _Header('Flags'),
      Expanded(
        child: _Loader<List<Flag>>(
          key: _key,
          load: widget.api.flags,
          build: (context, flags, _) {
            final open = flags.where((f) => f.key == 'open_access');
            final rest = flags.where((f) => f.key != 'open_access');
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'Changes reach every phone within seconds.',
                    style: TextStyle(color: AdminColors.muted),
                  ),
                ),
                for (final f in open)
                  _FlagTile(
                    f,
                    danger: true,
                    onChanged: (v) => _set(f, enabled: v),
                    onEmails: () => _editEmails(f),
                  ),
                for (final f in rest)
                  _FlagTile(
                    f,
                    onChanged: (v) => _set(f, enabled: v),
                    onEmails: () => _editEmails(f),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class _FlagTile extends StatelessWidget {
  const _FlagTile(
    this.f, {
    required this.onChanged,
    required this.onEmails,
    this.danger = false,
  });
  final Flag f;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEmails;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Panel(
      highlight: danger && f.enabled,
      onTap: onEmails,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.description ?? f.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  f.key,
                  style: const TextStyle(
                    color: AdminColors.faint,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  f.enabled
                      ? (danger
                            ? 'Anyone signed in gets in'
                            : 'On for everyone')
                      : f.emails.isEmpty
                      ? (danger ? 'Only the test list' : 'Off')
                      : 'Only for ${f.emails.length == 1 ? f.emails.first : '${f.emails.length} people'}',
                  style: TextStyle(
                    color: f.enabled || f.emails.isNotEmpty
                        ? AdminColors.accent2
                        : AdminColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: f.enabled, onChanged: onChanged),
        ],
      ),
    ),
  );
}

// -------------------------------------------------------------- prices

class PricesPage extends StatefulWidget {
  const PricesPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<PricesPage> createState() => _PricesPageState();
}

/// The Study Studio actions that can have a price, and what they are.
const _priced = {
  'study_price_ask': 'Ask AI answer',
  'study_price_build': 'Studio build',
  'study_price_concepts': 'Concept map',
  'study_price_connections': 'Lesson connections',
  'study_price_grade': 'Recall grading',
  'study_credits_per_usd': 'Metered: credits per \$1 of AI',
};

class _PricesPageState extends State<PricesPage> {
  final _key = GlobalKey<_LoaderState<List<Setting>>>();

  Future<void> _edit(String key, String? value) async {
    final c = TextEditingController(text: value ?? '');
    final isPrice = !key.endsWith('_model');
    final res = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(s).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _priced[key] ?? key,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              key,
              style: const TextStyle(
                color: AdminColors.faint,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: isPrice ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                hintText: isPrice ? 'Credits (empty = free)' : 'provider/model',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (value != null)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => Navigator.pop(s, ''),
                      child: Text(isPrice ? 'Make free' : 'Remove'),
                    ),
                  ),
                if (value != null) const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(
                    label: 'Save',
                    onPressed: () => Navigator.pop(s, c.text.trim()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (res == null) return;
    try {
      await widget.api.putSetting(key, res.isEmpty ? null : res);
      if (mounted) toast(context, res.isEmpty ? '$key removed' : '$key = $res');
    } on Object catch (e) {
      if (mounted) toast(context, '$e');
    }
    await _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _Header('Prices'),
      Expanded(
        child: _Loader<List<Setting>>(
          key: _key,
          load: widget.api.settings,
          build: (context, settings, _) {
            final byKey = {for (final s in settings) s.key: s.value};
            final models = settings
                .where((s) => s.key.endsWith('_model'))
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'OctoCredits per action in Study Studio. Empty = free.',
                    style: TextStyle(color: AdminColors.muted),
                  ),
                ),
                for (final e in _priced.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      onTap: () => _edit(e.key, byKey[e.key]),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            byKey[e.key] ?? 'free',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: byKey[e.key] == null
                                  ? AdminColors.faint
                                  : AdminColors.accent2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 14, 4, 10),
                  child: Text(
                    'Models',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                for (final m in models)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      onTap: () => _edit(m.key, m.value),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.key,
                            style: const TextStyle(
                              color: AdminColors.faint,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.value ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------- history

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.api});
  final AdminApi api;

  static const _icons = {
    'allow': Icons.person_add_alt_1_rounded,
    'disallow': Icons.person_remove_alt_1_rounded,
    'credits': Icons.toll_rounded,
    'flag': Icons.toggle_on_rounded,
    'setting': Icons.sell_rounded,
  };

  String _what(AuditEntry a) {
    final d = a.detail is Map ? a.detail as Map : const {};
    return switch (a.action) {
      'allow' => 'Let ${a.target} in',
      'disallow' => 'Took ${a.target} off the list',
      'credits' =>
        '${(d['delta'] as num? ?? 0) > 0 ? '+' : ''}${d['delta']} credits · ${a.target} (${d['before']} → ${d['after']})',
      'flag' => '${a.target} ${d['enabled'] == true ? 'on' : 'off'}',
      'setting' => '${a.target} = ${d['value'] ?? 'removed'}',
      _ => '${a.action} ${a.target ?? ''}',
    };
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _Header('History'),
      Expanded(
        child: _Loader<List<AuditEntry>>(
          load: api.audit,
          build: (context, items, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text(
                      'Nothing changed yet.',
                      style: TextStyle(color: AdminColors.muted),
                    ),
                  ),
                ),
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _icons[a.action] ?? Icons.bolt_rounded,
                          color: AdminColors.accent2,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _what(a),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${a.admin} · ${a.at == null ? '' : _when(a.at!.toLocal())}',
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
          ),
        ),
      ),
    ],
  );

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// The account's phones as each last reported itself.
class _PhonesPanel extends StatelessWidget {
  const _PhonesPanel({required this.phones});
  final Future<List<Phone>> phones;

  static (String, Color) _status(String s) => switch (s) {
    'registered' => ('Gets notifications', AdminColors.good),
    'permission_denied' => ('Notifications off', AdminColors.accent2),
    'token_error' => ('Push error', AdminColors.accent),
    'signed_out' => ('Signed out', AdminColors.faint),
    _ => (s, AdminColors.muted),
  };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phones',
          style: TextStyle(
            color: AdminColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder(
          future: phones,
          builder: (context, s) {
            if (s.hasError) {
              return Text(
                '${s.error}',
                style: const TextStyle(color: AdminColors.muted),
              );
            }
            if (!s.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (s.data!.isEmpty) {
              return const Text(
                'No phone has reported yet. It shows up here when they open '
                'the app (v1.0.2 or newer) signed in.',
                style: TextStyle(color: AdminColors.faint, height: 1.4),
              );
            }
            return Column(
              children: [
                for (final p in s.data!) ...[
                  _PhoneRow(
                    p,
                    status: _status(p.status),
                    ago: p.lastSeen == null ? '' : _ago(p.lastSeen!),
                  ),
                  if (p != s.data!.last)
                    const Divider(color: AdminColors.line, height: 20),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow(this.p, {required this.status, required this.ago});
  final Phone p;
  final (String, Color) status;
  final String ago;

  @override
  Widget build(BuildContext context) {
    final name = [
      p.manufacturer,
      p.model,
    ].whereType<String>().where((x) => x.isNotEmpty).join(' ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AdminColors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.smartphone_rounded,
            color: AdminColors.muted,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Unknown phone' : name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  p.osVersion,
                  if (p.appVersion != null) 'app ${p.appVersion}',
                ].whereType<String>().join(' · '),
                style: const TextStyle(color: AdminColors.muted, fontSize: 12),
              ),
              Text(
                'IP ${p.ip ?? '—'}${ago.isEmpty ? '' : ' · seen $ago'}',
                style: const TextStyle(color: AdminColors.faint, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status.$2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status.$1,
                    style: TextStyle(
                      color: status.$2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (p.error != null && p.status != 'registered')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    p.error!,
                    style: const TextStyle(
                      color: AdminColors.faint,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
