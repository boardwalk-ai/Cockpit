import 'source.dart';
import 'topic.dart';

/// A Study Studio: the environment generated from uploaded materials. Holds the
/// source files and the Study Objects ([topics]) every tool draws from.
class Studio {
  const Studio({
    required this.id,
    required this.title,
    required this.subject,
    required this.createdAt,
    required this.updatedAt,
    this.sourceFiles = const [],
    this.topics = const [],
    this.lastStudied,
  });

  final String id;
  final String title;
  final String subject;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastStudied;
  final List<SourceFile> sourceFiles;
  final List<Topic> topics;

  int get topicCount => topics.length;

  int get flashcardCount =>
      topics.fold(0, (sum, t) => sum + t.flashcards.length);

  int get quizCount =>
      topics.fold(0, (sum, t) => sum + t.quizQuestions.length);

  List<Topic> get weakTopics => topics.where((t) => t.isWeak).toList();

  double get overallMastery {
    if (topics.isEmpty) return 0;
    final total = topics.fold<double>(0, (sum, t) => sum + t.mastery);
    return total / topics.length;
  }

  Studio copyWith({List<Topic>? topics, DateTime? lastStudied, DateTime? updatedAt}) {
    return Studio(
      id: id,
      title: title,
      subject: subject,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastStudied: lastStudied ?? this.lastStudied,
      sourceFiles: sourceFiles,
      topics: topics ?? this.topics,
    );
  }
}
