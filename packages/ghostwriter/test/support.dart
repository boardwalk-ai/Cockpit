import 'package:flutter/material.dart';
import 'package:ghostwriter/ghostwriter.dart';
import 'package:ghostwriter/src/session/gw_session.dart';

import 'fake_server.dart';

/// GhostWriter hosted the way an app would host it, against a fake API.
class GhostWriterApp extends StatelessWidget {
  const GhostWriterApp({super.key, this.session});

  final GwSession? session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GhostWriterRoot(session: session ?? FakeServer().session()),
    );
  }
}
