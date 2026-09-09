import 'package:flutter/material.dart';

/// Supported material kinds (spec §3). More formats come later.
enum MaterialType { pdf, pptx, image, whiteboardPhoto, handout }

extension MaterialTypeMeta on MaterialType {
  IconData get icon {
    switch (this) {
      case MaterialType.pdf:
        return Icons.picture_as_pdf_rounded;
      case MaterialType.pptx:
        return Icons.slideshow_rounded;
      case MaterialType.image:
        return Icons.image_outlined;
      case MaterialType.whiteboardPhoto:
        return Icons.photo_camera_outlined;
      case MaterialType.handout:
        return Icons.description_outlined;
    }
  }

  String get label {
    switch (this) {
      case MaterialType.pdf:
        return 'PDF';
      case MaterialType.pptx:
        return 'PPTX';
      case MaterialType.image:
        return 'Image';
      case MaterialType.whiteboardPhoto:
        return 'Whiteboard';
      case MaterialType.handout:
        return 'Handout';
    }
  }
}

/// Background processing state of a material (spec §28).
enum ProcessingState { uploading, processing, done, fail }

/// OCR confidence for an extracted-text page (spec §15).
enum OcrConfidence { high, medium, low }

/// A page/slide of a [MaterialAsset] (spec §28 `SlidePage`).
@immutable
class SlidePage {
  const SlidePage({
    required this.number,
    required this.title,
    this.ocrText = '',
    this.ocrConfidence = OcrConfidence.high,
    this.activeWindow,
    this.noteBlockLinks = 0,
    this.hasPencilAnnotation = false,
    this.transcriptTime,
  });

  final int number;
  final String title;
  final String ocrText;
  final OcrConfidence ocrConfidence;

  /// When this slide was the active/live slide, e.g. "18:20–21:05".
  final String? activeWindow;
  final int noteBlockLinks;
  final bool hasPencilAnnotation;

  /// A related transcript moment for this slide (spec §11).
  final String? transcriptTime;

  bool get hasTranscriptLink => transcriptTime != null;
}

/// A loaded material file (spec §28 `MaterialAsset`).
class MaterialAsset {
  MaterialAsset({
    required this.id,
    required this.filename,
    required this.type,
    required this.deckPath,
    required this.pages,
    this.processing = ProcessingState.done,
    this.offline = true,
  });

  final String id;
  final String filename;
  final MaterialType type;

  /// e.g. "The Deck / Biology 101 / Resources / Week 4 Slides".
  final String deckPath;
  final List<SlidePage> pages;
  ProcessingState processing;
  bool offline;

  int get pageCount => pages.length;
  String get displayName {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }
}
