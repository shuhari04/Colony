import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'bridge/bridge_client_controller.dart';
import 'bridge/bridge_server_controller.dart';
import 'design/theme.dart';
import 'state/app_state.dart';
import 'ui/bridge/bridge_mobile_screen.dart';
import 'ui/world/world_screen.dart';

class ColonyApp extends StatefulWidget {
  const ColonyApp({super.key});

  @override
  State<ColonyApp> createState() => _ColonyAppState();
}

class _ColonyAppState extends State<ColonyApp> {
  final AppState _state = AppState();
  final BridgeServerController _bridgeServer = BridgeServerController();
  final BridgeClientController _bridgeClient = BridgeClientController();

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _bridgeClient.bootstrap();
    } else {
      _state.bootstrap();
      _bridgeServer.bootstrap();
    }
  }

  @override
  void dispose() {
    _state.dispose();
    _bridgeServer.dispose();
    _bridgeClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Colony',
      debugShowCheckedModeBanner: false,
      theme: ColonyTheme.dark(),
      home: defaultTargetPlatform == TargetPlatform.iOS
          ? BridgeMobileScreen(controller: _bridgeClient)
          : WorldScreen(state: _state, bridgeController: _bridgeServer),
    );
  }
}
