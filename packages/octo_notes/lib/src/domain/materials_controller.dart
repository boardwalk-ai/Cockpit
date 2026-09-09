import 'package:flutter/foundation.dart';

import 'materials_models.dart';

/// Panel 8 — Materials & Slides store. Non-destructive: the original source is
/// never modified; OCR, annotations, and AI live in separate layers (spec §2).
class MaterialsController extends ChangeNotifier {
  MaterialsController({required this.sessionId}) {
    _seed();
  }

  final String sessionId;

  final List<MaterialAsset> _materials = [];
  int _materialIndex = 0;

  List<MaterialAsset> get materials => List.unmodifiable(_materials);
  MaterialAsset get current => _materials[_materialIndex];

  /// The page the student is viewing (1-based).
  int currentPageNumber = 7;

  /// The professor's live slide, tracked by Follow Lecture.
  int liveSlide = 7;
  bool followLecture = true;

  String query = '';

  bool get rawPreserved => true;

  SlidePage get page =>
      current.pages.firstWhere((p) => p.number == currentPageNumber,
          orElse: () => current.pages.first);

  SlidePage? get livePage {
    for (final p in current.pages) {
      if (p.number == liveSlide) return p;
    }
    return null;
  }

  // --- navigation ----------------------------------------------------------
  void goToPage(int number, {bool manual = true}) {
    final clamped = number.clamp(1, current.pageCount);
    if (clamped == currentPageNumber) return;
    currentPageNumber = clamped;
    if (manual && clamped != liveSlide) followLecture = false;
    notifyListeners();
  }

  void prev() => goToPage(currentPageNumber - 1);
  void next() => goToPage(currentPageNumber + 1);

  void setFollowLecture(bool v) {
    followLecture = v;
    if (v) {
      currentPageNumber = liveSlide;
    }
    notifyListeners();
  }

  void returnToLiveSlide() => setFollowLecture(true);

  void selectMaterial(int i) {
    if (i < 0 || i >= _materials.length || i == _materialIndex) return;
    _materialIndex = i;
    currentPageNumber = 1;
    followLecture = false;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  List<SlidePage> get visiblePages {
    if (query.trim().isEmpty) return current.pages;
    final q = query.toLowerCase();
    return current.pages
        .where((p) =>
            p.title.toLowerCase().contains(q) ||
            p.ocrText.toLowerCase().contains(q))
        .toList();
  }

  // -------------------------------------------------------------------------
  // Seed (mirrors the Panel 8 mock — Week 4 Slides.pdf, 24 pages)
  // -------------------------------------------------------------------------
  void _seed() {
    final titled = <int, String>{
      5: 'Glycolysis Overview',
      6: 'Pyruvate Oxidation',
      7: 'Electron Transport Chain',
      8: 'ATP Synthase',
      9: 'Cellular Respiration Summary',
    };
    final pages = <SlidePage>[
      for (var n = 1; n <= 24; n++)
        SlidePage(
          number: n,
          title: titled[n] ?? 'Slide $n',
          ocrText: n == 7
              ? 'Electron Transport Chain — Oxidative Phosphorylation. '
                  'Complex I II III IV, ATP synthase, proton gradient.'
              : '',
          ocrConfidence: n == 7 ? OcrConfidence.high : OcrConfidence.medium,
          activeWindow: n == 7 ? '18:20–21:05' : null,
          noteBlockLinks: n == 7 ? 3 : 0,
          hasPencilAnnotation: n == 7,
          transcriptTime: n == 7 ? '18:32' : null,
        ),
    ];
    _materials.add(MaterialAsset(
      id: 'mat-week4',
      filename: 'Week 4 Slides.pdf',
      type: MaterialType.pdf,
      deckPath: 'The Deck / Biology 101 / Resources / Week 4 Slides',
      pages: pages,
    ));
  }
}
