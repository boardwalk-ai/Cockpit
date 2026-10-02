/// A run's chat timeline, rebuilt from its events (CONTRACT.md section 6).
///
/// The same events arrive live and on replay, so [RunTimeline.apply] is the
/// only way state changes: a reconnect replays from the last `seq` and ends up
/// exactly where a client that never dropped would be.
library;

enum StepStatus { running, done, failed, stopped }

enum RunPhase { running, waiting, finished, failed, cancelled }

sealed class TimelineItem {}

class UserItem extends TimelineItem {
  UserItem(this.text);
  final String text;
}

class AssistantItem extends TimelineItem {
  AssistantItem(this.text, {this.streaming = false});
  String text;

  /// Still typing out (live `assistant_delta`s, no final message yet).
  bool streaming;
}

class StepItem extends TimelineItem {
  StepItem({required this.stepId, required this.tool, required this.title});
  final String stepId;
  final String tool;
  final String title;
  StepStatus status = StepStatus.running;
  final List<String> details = [];
  final List<String> thoughts = [];
  String? summary;
  String? error;
}

class QuestionOption {
  const QuestionOption(this.label, this.value);
  final String label;
  final String value;
}

class QuestionItem extends TimelineItem {
  QuestionItem({
    required this.field,
    required this.question,
    required this.inputType,
    required this.options,
    required this.suggestions,
    required this.allowCustom,
    required this.sources,
  });

  factory QuestionItem.fromEvent(Map<String, dynamic> e) => QuestionItem(
    field: e['field']?.toString() ?? '',
    question: e['question']?.toString() ?? '',
    inputType: e['inputType']?.toString() ?? 'text',
    options: [
      for (final o in _list(e['options']))
        if (o is Map)
          QuestionOption(
            o['label']?.toString() ?? '',
            (o['value'] ?? o['label'])?.toString() ?? '',
          )
        else if (o != null)
          QuestionOption(o.toString(), o.toString()),
    ],
    suggestions: [for (final s in _list(e['suggestions'])) s.toString()],
    allowCustom: e['allowCustom'] == true,
    sources: [
      for (final s in _list(e['sources']))
        if (s is Map) _map(s),
    ],
  );

  final String field;
  final String question;

  /// `text`, `number`, `select`, `multiselect` or `sourceReview`.
  final String inputType;
  final List<QuestionOption> options;
  final List<String> suggestions;
  final bool allowCustom;
  final List<Map<String, dynamic>> sources;

  bool answered = false;
  Object? answer;
}

/// The word-count progress bar shown while the essay is written.
class WritingItem extends TimelineItem {
  WritingItem(this.targetWords);
  int targetWords;
  int words = 0;
  bool done = false;
}

/// The run's last word: finished (with the "Proceed to Editor" card when an
/// essay was written), failed, or stopped.
class EndItem extends TimelineItem {
  EndItem(this.phase, {this.error, this.wroteEssay = false});
  final RunPhase phase;
  final String? error;
  final bool wroteEssay;
}

class RunTimeline {
  final List<TimelineItem> items = [];

  /// The last stored event applied; reconnect with `sinceSeq` = this.
  int lastSeq = 0;
  RunPhase phase = RunPhase.running;

  /// The question waiting for an answer, if any.
  QuestionItem? pending;

  /// GhostWriter asked in plain text and waits on the chat box.
  bool awaitingReply = false;

  /// Set by `sources_ready`: the Sources pill shows from then on.
  List<Map<String, dynamic>>? sources;
  int sourceCount = 0;

  /// Set by `writing_started`: the Open Editor pill shows from then on.
  WritingItem? writing;

  /// What the run has worked out (`essayTopic`, `thesis`, ...).
  final Map<String, dynamic> context = {};

  int? documentRev;

  /// OctoCredits balance after the latest charge.
  int? credits;

  bool get ended =>
      phase == RunPhase.finished ||
      phase == RunPhase.failed ||
      phase == RunPhase.cancelled;

  /// Applies one event. Returns false if it was a stored event already seen.
  bool apply(Map<String, dynamic> event) {
    final seq = _int(event['seq']);
    if (seq != null) {
      if (seq <= lastSeq) return false;
      lastSeq = seq;
    }

    switch (event['type']) {
      case 'user_message':
        items.add(UserItem(_text(event)));

      case 'assistant_delta':
        final last = items.isEmpty ? null : items.last;
        if (last is AssistantItem && last.streaming) {
          last.text += event['chunk']?.toString() ?? '';
        } else {
          items.add(
            AssistantItem(event['chunk']?.toString() ?? '', streaming: true),
          );
        }

      case 'assistant_message':
        final last = items.isEmpty ? null : items.last;
        if (last is AssistantItem && last.streaming) {
          last
            ..text = _text(event)
            ..streaming = false;
        } else {
          items.add(AssistantItem(_text(event)));
        }

      case 'step_start':
        items.add(
          StepItem(
            stepId: event['stepId']?.toString() ?? '',
            tool: event['tool']?.toString() ?? '',
            title: event['title']?.toString() ?? '',
          ),
        );

      case 'step_progress':
        final detail = event['detail']?.toString();
        if (detail != null) _step(event['stepId'])?.details.add(detail);

      case 'step_done':
        _step(event['stepId'])
          ?..status = StepStatus.done
          ..summary = event['summary']?.toString();

      case 'step_error':
        _step(event['stepId'])
          ?..status = StepStatus.failed
          ..error = event['error']?.toString();

      case 'thought':
        final step = _step(event['stepId']) ?? _runningStep();
        step?.thoughts.add(_text(event));

      case 'question':
        final question = QuestionItem.fromEvent(event);
        items.add(question);
        pending = question;
        phase = RunPhase.waiting;

      case 'question_answered':
        final field = event['field']?.toString();
        for (final item in items.reversed) {
          if (item is QuestionItem && item.field == field && !item.answered) {
            item
              ..answered = true
              ..answer = event['value'];
            break;
          }
        }
        if (pending?.field == field) pending = null;
        if (!ended) phase = RunPhase.running;

      case 'awaiting_reply':
        awaitingReply = true;
        phase = RunPhase.waiting;

      case 'context_update':
        event.forEach((key, value) {
          if (key != 'type' && key != 'seq') context[key] = value;
        });

      case 'sources_ready':
        sources = [
          for (final s in _list(event['sources']))
            if (s is Map) _map(s),
        ];
        sourceCount = _int(event['count']) ?? sources!.length;

      case 'writing_started':
        final target = _int(event['targetWords']) ?? 0;
        if (writing == null) {
          writing = WritingItem(target);
          items.add(writing!);
        } else {
          writing!
            ..targetWords = target
            ..done = false;
        }

      case 'write_progress':
        final w = writing;
        if (w != null) {
          w.words = _int(event['words']) ?? w.words;
          w.targetWords = _int(event['targetWords']) ?? w.targetWords;
        }

      case 'document_updated':
        documentRev = _int(event['rev']) ?? documentRev;

      case 'credits':
        credits = _int(event['balance']) ?? credits;

      case 'done':
        _end(RunPhase.finished);
        writing?.done = true;
        items.add(EndItem(RunPhase.finished, wroteEssay: writing != null));

      case 'fatal':
        _end(RunPhase.failed);
        items.add(
          EndItem(
            RunPhase.failed,
            error: event['error']?.toString() ?? 'GhostWriter stopped.',
            wroteEssay: writing != null,
          ),
        );

      case 'cancelled':
        _end(RunPhase.cancelled);
        items.add(EndItem(RunPhase.cancelled, wroteEssay: writing != null));
    }

    // Anything after a chat-box question means the reply arrived.
    if (event['type'] == 'user_message') awaitingReply = false;
    if (awaitingReply == false &&
        phase == RunPhase.waiting &&
        pending == null) {
      phase = RunPhase.running;
    }
    return true;
  }

  void _end(RunPhase end) {
    phase = end;
    pending = null;
    awaitingReply = false;
    for (final item in items) {
      if (item is StepItem && item.status == StepStatus.running) {
        item.status = StepStatus.stopped;
      }
      if (item is AssistantItem) item.streaming = false;
    }
  }

  StepItem? _step(Object? stepId) {
    if (stepId == null) return null;
    final id = stepId.toString();
    for (final item in items.reversed) {
      if (item is StepItem && item.stepId == id) return item;
    }
    return null;
  }

  StepItem? _runningStep() {
    for (final item in items.reversed) {
      if (item is StepItem && item.status == StepStatus.running) return item;
    }
    return null;
  }
}

String _text(Map<String, dynamic> e) => e['text']?.toString() ?? '';

int? _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

List<Object?> _list(Object? v) => v is List ? v : const [];

Map<String, dynamic> _map(Map m) => m.map((k, v) => MapEntry(k.toString(), v));
