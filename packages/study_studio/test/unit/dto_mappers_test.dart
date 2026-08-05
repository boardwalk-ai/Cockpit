import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/api/dto_mappers.dart';
import 'package:study_studio/src/domain/entities/flashcard.dart';
import 'package:study_studio/src/domain/entities/quiz_question.dart';
import 'package:study_studio/src/domain/entities/source.dart';

void main() {
  test('studioFromJson maps nested studio data', () {
    final studio = studioFromJson({
      'id': 'studio-1',
      'title': 'Biology',
      'subject': 'Science',
      'createdAt': '2026-01-01T10:00:00Z',
      'updatedAt': '2026-01-02T10:00:00Z',
      'lastStudied': '2026-01-03T10:00:00Z',
      'sourceFiles': [
        {
          'id': 'source-1',
          'name': 'biology.pdf',
          'type': 'pdf',
          'processed': true,
        },
      ],
      'topics': [
        {
          'id': 'topic-1',
          'studioId': 'studio-1',
          'title': 'Cells',
          'subject': 'Biology',
          'definition': 'The basic unit of life.',
          'simpleExplanation': 'Cells make up living things.',
          'detailedExplanation': 'A detailed explanation.',
          'whyItMatters': 'Cells are fundamental to biology.',
          'examples': ['Plant cell', 'Animal cell'],
          'commonMistakes': ['All cells are identical'],
          'relatedTopicIds': ['topic-2'],
          'prerequisites': ['Basic biology'],
          'memoryHooks': ['Cells are tiny factories'],
          'difficulty': 4,
          'importance': 5,
          'estimatedStudyTimeMinutes': 15,
          'mastery': 0.75,
          'sources': [
            {
              'fileName': 'biology.pdf',
              'snippet': 'Cells are the basic unit of life.',
              'page': 12,
            },
          ],
          'flashcards': [
            {
              'id': 'card-1',
              'topicId': 'topic-1',
              'front': 'What is a cell?',
              'back': 'The basic unit of life.',
              'type': 'definition',
              'difficulty': 3,
              'status': 'fresh',
              'dueDate': '2026-01-10T10:00:00Z',
            },
          ],
          'quizQuestions': [
            {
              'id': 'question-1',
              'topicId': 'topic-1',
              'type': 'multipleChoice',
              'question': 'What is the basic unit of life?',
              'choices': ['Cell', 'Atom', 'Organ'],
              'answer': 'Cell',
              'explanation': 'Living organisms are made of cells.',
              'difficulty': 2,
              'relatedConcept': 'Cell theory',
            },
          ],
        },
      ],
    });

    expect(studio.id, 'studio-1');
    expect(studio.title, 'Biology');
    expect(studio.subject, 'Science');
    expect(studio.sourceFiles, hasLength(1));
    expect(studio.topics, hasLength(1));

    final topic = studio.topics.first;
    expect(topic.title, 'Cells');
    expect(topic.examples, ['Plant cell', 'Animal cell']);
    expect(topic.difficulty, 4);
    expect(topic.importance, 5);
    expect(topic.mastery, 0.75);

    expect(topic.sources.first.fileName, 'biology.pdf');
    expect(topic.sources.first.page, 12);

    expect(topic.flashcards.first.type, FlashcardType.definition);
    expect(topic.flashcards.first.status, FlashcardStatus.fresh);

    expect(topic.quizQuestions.first.type, QuizType.multipleChoice);
    expect(topic.quizQuestions.first.answer, 'Cell');
  });

  test('mappers use fallback values for missing optional fields', () {
    final topic = topicFromJson({
      'id': 'topic-1',
    });

    expect(topic.studioId, '');
    expect(topic.title, '');
    expect(topic.subject, '');
    expect(topic.examples, isEmpty);
    expect(topic.sources, isEmpty);
    expect(topic.flashcards, isEmpty);
    expect(topic.quizQuestions, isEmpty);
    expect(topic.difficulty, 3);
    expect(topic.importance, 3);
    expect(topic.estimatedStudyTimeMinutes, 10);
    expect(topic.mastery, 0.0);
  });

  test('invalid enum names fall back to default values', () {
    final flashcard = flashcardFromJson({
      'id': 'card-1',
      'type': 'not-a-real-type',
      'status': 'not-a-real-status',
    });

    final question = quizQuestionFromJson({
      'id': 'question-1',
      'type': 'not-a-real-type',
    });

    final source = sourceFileFromJson({
      'id': 'source-1',
      'type': 'not-a-real-type',
    });

    expect(flashcard.type, FlashcardType.definition);
    expect(flashcard.status, FlashcardStatus.fresh);
    expect(question.type, QuizType.multipleChoice);
    expect(source.type, SourceFileType.pdf);
  });
}