import 'package:flutter/services.dart';

import '../application/service_contracts.dart';
import '../domain/visual_chart_models.dart';

class MethodChannelExternalUrlOpener implements ExternalUrlOpener {
  const MethodChannelExternalUrlOpener({
    this.channel = const MethodChannel('music_tabbler/external_url'),
  });

  final MethodChannel channel;

  @override
  Future<void> open(String url) async {
    await channel.invokeMethod<void>('open', normalizeSourceUrl(url));
  }
}
