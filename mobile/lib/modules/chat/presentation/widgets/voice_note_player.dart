import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

/// Bubble untuk memutar pesan voice note. Hanya satu player aktif global —
/// kalau user tap play di bubble lain, bubble pertama otomatis pause.
class VoiceNotePlayer extends StatefulWidget {
  final String url;
  final Duration? duration;
  final bool isMine;

  const VoiceNotePlayer({
    super.key,
    required this.url,
    this.duration,
    required this.isMine,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  static AudioPlayer? _activePlayer;
  static String? _activeUrl;

  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    if (widget.duration != null) _total = widget.duration!;

    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _state = PlayerState.stopped;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    if (_activePlayer == _player) {
      _activePlayer = null;
      _activeUrl = null;
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    // Pause player lain yang sedang aktif (single-playback global).
    if (_activePlayer != null && _activePlayer != _player) {
      try {
        await _activePlayer!.pause();
      } catch (_) {}
    }
    _activePlayer = _player;
    _activeUrl = widget.url;
    if (_state == PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMine ? Colors.white : MyloColors.primary;
    final bg = widget.isMine
        ? Colors.white.withAlpha(40)
        : MyloColors.primary.withAlpha(20);
    final progress = (_total.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final remaining = _state == PlayerState.playing
        ? (_total - _position)
        : _total;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _state == PlayerState.playing
                    ? Icons.pause
                    : Icons.play_arrow,
                color: fg,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: fg,
                    inactiveTrackColor: fg.withAlpha(70),
                    thumbColor: fg,
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (v) {
                      if (_total.inMilliseconds == 0) return;
                      final pos = Duration(
                          milliseconds:
                              (v * _total.inMilliseconds).round());
                      _player.seek(pos);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(Icons.mic, size: 12, color: fg.withAlpha(180)),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(remaining),
                        style: TextStyle(
                          fontSize: 11,
                          color: fg.withAlpha(200),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
