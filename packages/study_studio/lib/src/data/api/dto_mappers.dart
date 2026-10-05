import '../../domain/entities/flashcard.dart';
import '../../domain/entities/me.dart';
import '../../domain/entities/quiz_question.dart';
import '../../domain/entities/scenario.dart';
import '../../domain/entities/source.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';

/// JSON → domain entity mappers for the backend's camelCase payloads.
///
/// Kept in the data layer so the domain entities stay serialization-free. Enum
/// values are matched by name (the backend emits the Dart member names).

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime? _dateOrNull(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

List<String> _stringList(Object? v) =>
    v is List ? v.map((e) => '$e').toList() : const [];

Studio studioFromJson(Map<String, dynamic> j) {
  return Studio(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    subject: j['subject'] as String? ?? '',
    createdAt: _dateOrNull(j['createdAt']) ?? DateTime.now(),
    updatedAt: _dateOrNull(j['updatedAt']) ?? DateTime.now(),
    lastStudied: _dateOrNull(j['lastStudied']),
    sourceFiles: (j['sourceFiles'] as List? ?? [])
        .map((e) => sourceFileFromJson(e as Map<String, dynamic>))
        .toList(),
    topics: (j['topics'] as List? ?? [])
        .map((e) => topicFromJson(e as Map<String, dynamic>))
        .toList(),
    scenarios: (j['scenarios'] as List? ?? [])
        .map((e) => scenarioFromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

Scenario scenarioFromJson(Map<String, dynamic> j) {
  return Scenario(
    id: j['id'] as String,
    studioId: j['studioId'] as String? ?? '',
    title: j['title'] as String? ?? '',
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 3,
    estimatedMinutes: (j['estimatedMinutes'] as num?)?.toInt() ?? 6,
    skills: _stringList(j['skills']),
    aiNote: j['aiNote'] as String? ?? '',
    problem: j['problem'] as String? ?? '',
    question: j['question'] as String? ?? '',
    clues: (j['clues'] as List? ?? [])
        .map((e) => ScenarioClue(
              id: (e as Map)['id'] as String? ?? '',
              label: e['label'] as String? ?? '',
              detail: e['detail'] as String? ?? '',
            ))
        .toList(),
    options: (j['options'] as List? ?? [])
        .map((e) => ScenarioOption(
              id: (e as Map)['id'] as String? ?? '',
              label: e['label'] as String? ?? '',
            ))
        .toList(),
    correctOptionId: j['correctOptionId'] as String? ?? '',
    reasoning: j['reasoning'] as String? ?? '',
    outcomeLabel: j['outcomeLabel'] as String? ?? '',
    relatedTopics: _stringList(j['relatedTopics']),
  );
}

Topic topicFromJson(Map<String, dynamic> j) {
  return Topic(
    id: j['id'] as String,
    studioId: j['studioId'] as String? ?? '',
    title: j['title'] as String? ?? '',
    subject: j['subject'] as String? ?? '',
    definition: j['definition'] as String? ?? '',
    simpleExplanation: j['simpleExplanation'] as String? ?? '',
    detailedExplanation: j['detailedExplanation'] as String? ?? '',
    whyItMatters: j['whyItMatters'] as String? ?? '',
    summary: _stringList(j['summary']),
    examples: _stringList(j['examples']),
    commonMistakes: _stringList(j['commonMistakes']),
    relatedTopicIds: _stringList(j['relatedTopicIds']),
    prerequisites: _stringList(j['prerequisites']),
    memoryHooks: _stringList(j['memoryHooks']),
    sources: (j['sources'] as List? ?? [])
        .map((e) => sourceReferenceFromJson(e as Map<String, dynamic>))
        .toList(),
    flashcards: (j['flashcards'] as List? ?? [])
        .map((e) => flashcardFromJson(e as Map<String, dynamic>))
        .toList(),
    quizQuestions: (j['quizQuestions'] as List? ?? [])
        .map((e) => quizQuestionFromJson(e as Map<String, dynamic>))
        .toList(),
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 3,
    importance: (j['importance'] as num?)?.toInt() ?? 3,
    estimatedStudyTimeMinutes:
        (j['estimatedStudyTimeMinutes'] as num?)?.toInt() ?? 10,
    mastery: (j['mastery'] as num?)?.toDouble() ?? 0.0,
  );
}

Flashcard flashcardFromJson(Map<String, dynamic> j) {
  return Flashcard(
    id: j['id'] as String,
    topicId: j['topicId'] as String? ?? '',
    front: j['front'] as String? ?? '',
    back: j['back'] as String? ?? '',
    type: _enumByName(FlashcardType.values, j['type'], FlashcardType.definition),
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 2,
    status:
        _enumByName(FlashcardStatus.values, j['status'], FlashcardStatus.fresh),
    dueDate: _dateOrNull(j['dueDate']),
    reps: (j['reps'] as num?)?.toInt() ?? 0,
    intervalDays: (j['intervalDays'] as num?)?.toDouble() ?? 0,
    ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
    lapses: (j['lapses'] as num?)?.toInt() ?? 0,
  );
}

QuizQuestion quizQuestionFromJson(Map<String, dynamic> j) {
  return QuizQuestion(
    id: j['id'] as String,
    topicId: j['topicId'] as String? ?? '',
    type: _enumByName(QuizType.values, j['type'], QuizType.multipleChoice),
    question: j['question'] as String? ?? '',
    choices: _stringList(j['choices']),
    answer: j['answer'] as String? ?? '',
    explanation: j['explanation'] as String? ?? '',
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 2,
    relatedConcept: j['relatedConcept'] as String?,
  );
}

SourceFile sourceFileFromJson(Map<String, dynamic> j) {
  return SourceFile(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    type: _enumByName(SourceFileType.values, j['type'], SourceFileType.pdf),
    processed: j['processed'] as bool? ?? true,
  );
}

Me meFromJson(Map<String, dynamic> j) {
  return Me(
    id: j['id'] as String,
    email: j['email'] as String?,
    displayName: j['displayName'] as String?,
    credits: (j['credits'] as num?)?.toInt(),
  );
}

SourceReference sourceReferenceFromJson(Map<String, dynamic> j) {
  return SourceReference(
    fileName: j['fileName'] as String? ?? '',
    snippet: j['snippet'] as String? ?? '',
    page: (j['page'] as num?)?.toInt(),
  );
}
