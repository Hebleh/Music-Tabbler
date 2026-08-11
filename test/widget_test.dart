import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/app.dart';
import 'package:music_tabbler/application/app_services.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/application/visual_tab_analysis_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/library_models.dart';
import 'package:music_tabbler/domain/device_preferences.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/features/import/visual_tab_analysis_dialog.dart';

part 'widget_visual_workflow_test.part.dart';
part 'widget_setlist_workflow_test.part.dart';
part 'widget_performance_workflow_test.part.dart';
part 'widget_test_support.part.dart';

void main() {
  _registerVisualWorkflowTests();
  _registerSetlistWorkflowTests();
  _registerPerformanceWorkflowTests();
}
