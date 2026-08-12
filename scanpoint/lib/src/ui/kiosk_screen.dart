import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'kiosk_face.dart';

/// Adapter between the controller and the presentation-only [KioskFace].
///
/// Keeping the split means the screen can be rendered in a test without a
/// store, an audio device, or a scanner attached.
class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return KioskFace(
      state: controller.state,
      stationId: controller.config.stationId,
      stationName: controller.config.stationName,
      recordedCount: controller.recordedCount,
      cardId: controller.cardId,
      cardLabel: controller.cardLabel,
      recordedAt: controller.recordedAt,
      firstSeenAt: controller.firstSeenAt,
      fault: controller.fault,
      warning: controller.store.lastWriteError,
    );
  }
}
