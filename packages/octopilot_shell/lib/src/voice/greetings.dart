import 'dart:math' as math;

import 'voice_engine.dart';

/// What the voice says first when voice mode opens: one of a few presets,
/// some for any time and some for the time of day, at random (never the
/// same twice in a row). The next one is picked and voiced ahead, while
/// the app is idle, so opening voice mode can speak at once.
class Greeter {
  Greeter({math.Random? random, DateTime Function()? clock})
    : _random = random ?? math.Random(),
      _clock = clock ?? DateTime.now;

  final math.Random _random;
  final DateTime Function() _clock;

  String? _next;
  String? _last;

  /// For any time of day. `{name}` is the user's first name; presets with
  /// it are left out when the name is not known.
  static const anytime = [
    'Hello there, how can I help you?',
    'Hi! What can I do for you today?',
    'Hey {name}, how can I help?',
    'Hey superstar, what are we working on?',
    "I'm all ears. What's up?",
  ];

  static const morning = [
    'Good morning! How can I help you?',
    'Morning, {name}. Coffee ready? What are we working on?',
    "Rise and shine. What's on today's list?",
  ];

  static const afternoon = [
    'Good afternoon! How can I help?',
    "Hey {name}, how's the day going? What do you need?",
    'Afternoon! Need a hand with something?',
  ];

  static const evening = [
    'Good evening. What can I do for you?',
    'Evening, {name}. Winding down, or just getting started?',
  ];

  static const lateNight = [
    'Hey night owl. What are we working on?',
    "Burning the midnight oil? I'm here. What do you need?",
    "Still up, {name}? Let's get it done.",
  ];

  /// The presets for [time]: 5–11 morning, 12–16 afternoon, 17–21 evening,
  /// 22–4 late night.
  static List<String> forTime(DateTime time) => switch (time.hour) {
    >= 5 && < 12 => morning,
    >= 12 && < 17 => afternoon,
    >= 17 && < 22 => evening,
    _ => lateNight,
  };

  /// The ones that can be said now to [name] (null when not known).
  List<String> choices({String? name}) {
    final known = name != null && name.trim().isNotEmpty;
    return [
      for (final line in [...anytime, ...forTime(_clock())])
        if (known)
          line.replaceAll('{name}', name.trim())
        else if (!line.contains('{name}'))
          line,
    ];
  }

  /// The greeting to say next: the one picked ahead if it still fits.
  String upcoming({String? name}) {
    final options = choices(name: name);
    final ahead = _next;
    if (ahead != null && options.contains(ahead)) return ahead;
    final fresh = [
      for (final o in options)
        if (o != _last) o,
    ];
    final pool = fresh.isEmpty ? options : fresh;
    return _next = pool[_random.nextInt(pool.length)];
  }

  /// The greeting to say now; the next one is picked afresh.
  String take({String? name}) {
    final line = upcoming(name: name);
    _last = line;
    _next = null;
    return line;
  }

  /// Voices the upcoming greeting in [voice] ahead of time (the engine
  /// keeps it), so the next voice mode starts without a wait.
  Future<void> prepare(VoiceEngine engine, String voice, {String? name}) async {
    try {
      await engine.prepare(upcoming(name: name), voice: voice, keep: true);
    } on Object {
      // Made when it is needed instead.
    }
  }
}
