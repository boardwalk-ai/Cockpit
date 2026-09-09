import 'package:flutter/material.dart';

/// Magic Pencil tools (spec §5).
enum InkTool {
  pen,
  pencil,
  highlighter,
  eraser,
  lasso,
  rect,
  circle,
  line,
  text,
  pointer,
}

extension InkToolMeta on InkTool {
  bool get isDrawing =>
      this == InkTool.pen ||
      this == InkTool.pencil ||
      this == InkTool.highlighter;
  bool get isShape =>
      this == InkTool.rect || this == InkTool.circle || this == InkTool.line;

  IconData get icon {
    switch (this) {
      case InkTool.pen:
        return Icons.edit_rounded;
      case InkTool.pencil:
        return Icons.create_rounded;
      case InkTool.highlighter:
        return Icons.brush_rounded;
      case InkTool.eraser:
        return Icons.auto_fix_normal_rounded;
      case InkTool.lasso:
        return Icons.gesture_rounded;
      case InkTool.rect:
        return Icons.crop_square_rounded;
      case InkTool.circle:
        return Icons.circle_outlined;
      case InkTool.line:
        return Icons.horizontal_rule_rounded;
      case InkTool.text:
        return Icons.text_fields_rounded;
      case InkTool.pointer:
        return Icons.near_me_outlined;
    }
  }
}

/// Paper background for a page (spec §4).
enum PaperBackground { blank, lined, grid, dotted }

extension PaperBackgroundMeta on PaperBackground {
  String get label {
    switch (this) {
      case PaperBackground.blank:
        return 'Blank';
      case PaperBackground.lined:
        return 'Lined';
      case PaperBackground.grid:
        return 'Grid';
      case PaperBackground.dotted:
        return 'Dotted';
    }
  }
}

/// A single vector stroke — never a flattened image (spec §6). Freehand strokes
/// keep every sampled point (with pressure); shapes keep [start, end]; a text
/// element keeps a single anchor point + [text].
@immutable
class Stroke {
  const Stroke({
    required this.id,
    required this.tool,
    required this.points,
    required this.pressures,
    required this.color,
    required this.width,
    required this.pageId,
    this.text,
    this.audioTimestamp,
    this.revision = 1,
  });

  final String id;
  final InkTool tool;
  final List<Offset> points;
  final List<double> pressures;
  final Color color;
  final double width;
  final String pageId;
  final String? text;
  final String? audioTimestamp;
  final int revision;

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      minX = p.dx < minX ? p.dx : minX;
      maxX = p.dx > maxX ? p.dx : maxX;
      minY = p.dy < minY ? p.dy : minY;
      maxY = p.dy > maxY ? p.dy : maxY;
    }
    final pad = width + (text != null ? 40 : 6);
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  Stroke translated(Offset delta) => Stroke(
        id: id,
        tool: tool,
        points: [for (final p in points) p + delta],
        pressures: pressures,
        color: color,
        width: width,
        pageId: pageId,
        text: text,
        audioTimestamp: audioTimestamp,
        revision: revision + 1,
      );

  Stroke copyWith({Color? color, double? width}) => Stroke(
        id: id,
        tool: tool,
        points: points,
        pressures: pressures,
        color: color ?? this.color,
        width: width ?? this.width,
        pageId: pageId,
        text: text,
        audioTimestamp: audioTimestamp,
        revision: revision + 1,
      );
}

/// A canvas page holding its strokes and background (spec §4, §5).
class InkPage {
  InkPage({
    required this.id,
    required this.title,
    this.background = PaperBackground.dotted,
    List<Stroke>? strokes,
  }) : strokes = strokes ?? [];

  final String id;
  String title;
  PaperBackground background;
  final List<Stroke> strokes;

  InkPage clone() => InkPage(
        id: id,
        title: title,
        background: background,
        strokes: List.of(strokes),
      );
}

/// A mock handwriting-recognition result for a selection (spec §7).
@immutable
class RecognitionResult {
  const RecognitionResult({required this.text, required this.confidence});
  final String text;
  final double confidence; // 0..1

  bool get isHigh => confidence >= 0.85;
  bool get isMedium => confidence >= 0.6 && confidence < 0.85;
  bool get isLow => confidence < 0.6;
}
