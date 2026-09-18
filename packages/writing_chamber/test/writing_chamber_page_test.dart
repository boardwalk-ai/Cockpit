import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guided_generation/guided_generation.dart';
import 'package:writing_chamber/src/presentation/writing_chamber_page.dart';

void main() {
  testWidgets('renders the empty Writing Chamber and its primary controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WritingChamberPage(repository: _EmptyRepository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Writing Chamber'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Assignment'), findsOneWidget);
    expect(find.text('Essay topic'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Search for sources before generating.'), findsOneWidget);

    await tester.tap(find.text('Generate'));
    await tester.pump();
    expect(find.text('Add an essay topic first.'), findsOneWidget);
  });
}

class _EmptyRepository implements GuidedGenerationRepository {
  @override
  Future<GuidedEditorThread?> loadEditor({String? threadId}) async => null;

  @override
  Future<GuidedEditorThread> saveEditor({
    String? threadId,
    required String title,
    required String plainText,
    required int wordCount,
    required CitationStyle citationStyle,
    required List<dynamic> delta,
    required List<CitationSource> sources,
    Map<String, dynamic> runState = const {},
  }) {
    throw UnimplementedError();
  }
}
