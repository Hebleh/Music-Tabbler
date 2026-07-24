import 'package:flutter/services.dart';

import '../application/service_contracts.dart';

class MethodChannelPerformanceModeController
    implements PerformanceModeController {
  const MethodChannelPerformanceModeController({
    this.channel = const MethodChannel('music_tabbler/performance_mode'),
  });

  final MethodChannel channel;

  @override
  Future<void> setActive(bool active) async {
    try {
      await channel.invokeMethod<void>('setActive', active);
    } on MissingPluginException {
      // Desktop preview still works as a distraction-free in-app surface.
    }
  }
}
