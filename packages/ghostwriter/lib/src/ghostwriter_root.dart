import 'package:flutter/material.dart';

import 'ghostwriter_page.dart';
import 'mobile/mobile_theme.dart';

/// GhostWriter with its own look, whatever theme the host app uses.
class GhostWriterRoot extends StatelessWidget {
  const GhostWriterRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: GwFonts.primary,
      ),
      child: const GhostWriterPage(),
    );
  }
}
