import 'package:flutter/material.dart';

class ManageStudyStudioPage extends StatelessWidget {
  const ManageStudyStudioPage({required this.studioId, super.key});

  final String studioId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Manage Study Studio')));
  }
}
