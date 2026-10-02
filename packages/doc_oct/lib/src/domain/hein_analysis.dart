/// Hein's assignment breakdown — same JSON shape as OctopilotWeb `/api/hein/analyze`.
class HeinAnalysis {
  const HeinAnalysis({
    required this.analysis,
    required this.essayTopic,
    required this.essayType,
    required this.scope,
    required this.structure,
  });

  final String analysis;
  final String essayTopic;
  final String essayType;
  final String scope;
  final String structure;

  factory HeinAnalysis.fromJson(Map<String, dynamic> json) => HeinAnalysis(
        analysis: (json['analysis'] ?? '') as String,
        essayTopic: (json['essayTopic'] ?? '') as String,
        essayType: (json['essayType'] ?? '') as String,
        scope: (json['scope'] ?? '') as String,
        structure: (json['structure'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'analysis': analysis,
        'essayTopic': essayTopic,
        'essayType': essayType,
        'scope': scope,
        'structure': structure,
      };
}
