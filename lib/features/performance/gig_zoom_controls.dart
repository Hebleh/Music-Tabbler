import 'package:flutter/material.dart';

/// Presentation-only zoom controls for the unlocked Gig Mode toolbar.
///
/// Reflow anchoring and persistence remain owned by the Gig screen and its
/// viewport session; this widget only renders values and forwards gestures.
class GigZoomControls extends StatelessWidget {
  const GigZoomControls({
    super.key,
    required this.songZoom,
    required this.setWideZoom,
    required this.onSongZoomChanged,
    required this.onSetWideZoomChanged,
    required this.onSetWideZoomChangeEnd,
  });

  final double songZoom;
  final double setWideZoom;
  final ValueChanged<double> onSongZoomChanged;
  final ValueChanged<double> onSetWideZoomChanged;
  final ValueChanged<double> onSetWideZoomChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 88,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('This song', style: TextStyle(color: Colors.white)),
              ),
            ),
            Expanded(
              child: Slider(
                key: const Key('gig-song-zoom-slider'),
                value: songZoom,
                min: 0.45,
                max: 1.5,
                divisions: 21,
                label: '${(songZoom * 100).round()}%',
                onChanged: onSongZoomChanged,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        Row(
          children: [
            const SizedBox(
              width: 88,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('Whole set', style: TextStyle(color: Colors.white)),
              ),
            ),
            const Icon(Icons.zoom_out, color: Colors.white, size: 20),
            Expanded(
              child: Slider(
                key: const Key('gig-zoom-slider'),
                value: setWideZoom,
                min: 0.45,
                max: 1.5,
                divisions: 21,
                label: '${(setWideZoom * 100).round()}%',
                onChanged: onSetWideZoomChanged,
                onChangeEnd: onSetWideZoomChangeEnd,
              ),
            ),
            const Icon(Icons.zoom_in, color: Colors.white, size: 20),
            SizedBox(
              width: 112,
              child: Text(
                '${(setWideZoom * 100).round()}% zoom',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
