import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'state/app_state.dart';
import 'ui/world/world_screen.dart';

class ColonyApp extends StatefulWidget {
  const ColonyApp({super.key});

  @override
  State<ColonyApp> createState() => _ColonyAppState();
}

class _ColonyAppState extends State<ColonyApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.bootstrap();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Colony',
      debugShowCheckedModeBanner: false,
      theme: ColonyTheme.dark(),
      home: WorldScreen(state: _state),
    );
  }
}

