import 'package:flutter/material.dart';

import 'knowledge_map_phone_page.dart';

/// Visualize: the studio's real knowledge map (topics, and each topic's
/// concepts) on every screen. It replaced a fixed demo graph.
class KnowledgeGraphPage extends StatelessWidget {
  const KnowledgeGraphPage({super.key, required this.studioId});

  final String studioId;

  @override
  Widget build(BuildContext context) =>
      KnowledgeMapPhonePage(studioId: studioId);
}
