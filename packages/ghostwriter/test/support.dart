import 'package:flutter/material.dart';
import 'package:ghostwriter/ghostwriter.dart';

/// GhostWriter hosted the way an app would host it.
class GhostWriterApp extends StatelessWidget {
  const GhostWriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GhostWriterRoot(),
    );
  }
}
