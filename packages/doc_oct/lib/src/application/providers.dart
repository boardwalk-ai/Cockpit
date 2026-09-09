import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/saved_project.dart';
import '../theme/doc_tokens.dart';

/// UI-first mock data. Phase 2 swaps this for the real DocumentService without
/// touching the screens.
final savedProjectsProvider = Provider<List<SavedProject>>((ref) {
  final now = DateTime(2026, 9, 9, 14, 30);
  return [
    SavedProject(
      id: 'p1',
      title: 'The Vikings: Seafaring, Trade, and Settlement',
      style: FormatStyle.apa,
      words: 2140,
      updatedAt: now.subtract(const Duration(hours: 2)),
      snippet:
          'The Vikings were Norse seafarers who, from the late eighth to the eleventh century, raided, traded, and settled across wide areas of Europe.',
    ),
    SavedProject(
      id: 'p2',
      title: 'Photosynthesis and the Carbon Cycle',
      style: FormatStyle.mla,
      words: 1560,
      updatedAt: now.subtract(const Duration(days: 1, hours: 3)),
      snippet:
          'Photosynthesis converts light energy into chemical energy, forming the base of nearly every food web on Earth.',
    ),
    SavedProject(
      id: 'p3',
      title: 'Market Structures and Consumer Welfare',
      style: FormatStyle.chicago,
      words: 3320,
      updatedAt: now.subtract(const Duration(days: 3)),
      snippet:
          'Perfect competition and monopoly sit at opposite ends of a spectrum that shapes prices, output, and welfare.',
    ),
    SavedProject(
      id: 'p4',
      title: 'A Survey of Transformer Architectures',
      style: FormatStyle.ieee,
      words: 4880,
      updatedAt: now.subtract(const Duration(days: 6)),
      snippet:
          'Attention mechanisms allow models to weigh input tokens dynamically, replacing recurrence with parallelizable operations.',
    ),
    SavedProject(
      id: 'p5',
      title: 'Postcolonial Readings of the Modern Novel',
      style: FormatStyle.harvard,
      words: 2760,
      updatedAt: now.subtract(const Duration(days: 9)),
      snippet:
          'Reading the modern novel through a postcolonial lens surfaces the silences and margins of the imperial archive.',
    ),
    SavedProject(
      id: 'p6',
      title: 'Untitled draft',
      style: FormatStyle.mla,
      words: 320,
      updatedAt: now.subtract(const Duration(days: 14)),
      snippet: 'A short opening paragraph, still finding its argument…',
    ),
  ];
});
