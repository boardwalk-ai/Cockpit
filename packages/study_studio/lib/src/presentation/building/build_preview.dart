/// Demo build-result values shared by Screen 3 (Building) and Screen 4 (Ready)
/// so the counters revealed on the success screen match what animated up during
/// the build. All placeholder until the backend returns real build output.
abstract final class BuildPreview {
  static const studioName = 'Computer Networks Final Exam';

  static const topics = 23;
  static const definitions = 87;
  static const flashcards = 42;
  static const quizQuestions = 18;
  static const connections = 126;
  static const studyPaths = 9;

  static const importantTopics = [
    'OSI Model',
    'TCP/IP',
    'Routing',
    'Switching',
    'Network Security',
  ];

  static const estimatedStudyTime = '6.4 hours';
  static const difficulty = 'Intermediate';
  static const confidence = 'High';

  /// The studio the flow lands on once built (Screen 5 dashboard).
  static const dashboardRoute = '/study/bio';

  /// Screen 4 — the "ready" reveal shown before entering the studio.
  static const readyRoute = '/study/bio/ready';
}
