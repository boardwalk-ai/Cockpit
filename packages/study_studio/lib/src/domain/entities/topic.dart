import 'flashcard.dart';
import 'quiz_question.dart';
import 'source.dart';

/// The central **Study Object**. Every learning tool (Teach Me, Quiz, Flashcards,
/// Scenario, Visualize, Progress) reads from this one structure.
class Topic {
  const Topic({
    required this.id,
    required this.studioId,
    required this.title,
    required this.subject,
    required this.definition,
    required this.simpleExplanation,
    required this.detailedExplanation,
    required this.whyItMatters,
    this.examples = const [],
    this.commonMistakes = const [],
    this.relatedTopicIds = const [],
    this.prerequisites = const [],
    this.memoryHooks = const [],
    this.sources = const [],
    this.flashcards = const [],
    this.quizQuestions = const [],
    this.difficulty = 3,
    this.importance = 3,
    this.estimatedStudyTimeMinutes = 10,
    this.mastery = 0.0,
  });

  final String id;
  final String studioId;
  final String title;
  final String subject;

  final String definition;
  final String simpleExplanation;
  final String detailedExplanation;
  final String whyItMatters;

  final List<String> examples;
  final List<String> commonMistakes;
  final List<String> relatedTopicIds;
  final List<String> prerequisites;
  final List<String> memoryHooks;
  final List<SourceReference> sources;

  final List<Flashcard> flashcards;
  final List<QuizQuestion> quizQuestions;

  final int difficulty; // 1–5
  final int importance; // 1–5
  final int estimatedStudyTimeMinutes;

  /// 0.0–1.0
  final double mastery;

  bool get isWeak => mastery < 0.6;

  Topic copyWith({double? mastery}) {
    return Topic(
      id: id,
      studioId: studioId,
      title: title,
      subject: subject,
      definition: definition,
      simpleExplanation: simpleExplanation,
      detailedExplanation: detailedExplanation,
      whyItMatters: whyItMatters,
      examples: examples,
      commonMistakes: commonMistakes,
      relatedTopicIds: relatedTopicIds,
      prerequisites: prerequisites,
      memoryHooks: memoryHooks,
      sources: sources,
      flashcards: flashcards,
      quizQuestions: quizQuestions,
      difficulty: difficulty,
      importance: importance,
      estimatedStudyTimeMinutes: estimatedStudyTimeMinutes,
      mastery: mastery ?? this.mastery,
    );
  }
}
