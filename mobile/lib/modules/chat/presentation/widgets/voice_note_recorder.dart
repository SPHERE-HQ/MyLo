import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme.dart';

/// Hasil dari sesi rekaman voice note.
class VoiceNoteResult {
  final File file;
  final Duration duration;
  VoiceNoteResult(this.file, this.duration);
}

/// Tombol mic ala WhatsApp:
/// - Tap (tanpa tahan)         → tampilkan tooltip "Tahan untuk merekam".
/// - Tahan                     → mulai merekam, panel rekam menggantikan
///                               input bar lewat callback `onRecordingStateChange`.
/// - Geser ke kiri saat tahan  → masuk zona BATAL, lepaskan = batal.
/// - Geser ke atas saat tahan  → masuk zona KUNCI, lepaskan = lock (terus
///                               merekam tanpa harus menahan, sampai user
///                               tekan tombol stop).
/// - Lepas tanpa kunci/batal   → stop & kirim.
/// - Maks 60 detik, otomatis stop & kirim ketika tercapai.
///
/// Widget ini bertanggung jawab penuh atas siklus AudioRecorder (start, stop,
/// cancel, dispose). Parent cukup menyediakan callback untuk:
///   - update UI input bar (sembunyikan field, tampilkan panel rekam)
///   - menerima file hasil rekam untuk diupload + dikirim sebagai pesan audio.
class HoldToRecordButton extends StatefulWidget {
  final ValueChanged<VoiceNoteResult> onRecorded;
  final ValueChanged<RecordingUiState> onStateChange;
  final VoidCallback? onPermissionDenied;
  final bool enabled;

  const HoldToRecordButton({
    super.key,
    required this.onRecorded,
    required this.onStateChange,
    this.onPermissionDenied,
    this.enabled = true,
  });

  @override
  State<HoldToRecordButton> createState() => HoldToRecordButtonState();
}

/// State publik dari sesi rekaman, dikirim ke parent (chat room) untuk
/// menentukan tampilan input bar.
class RecordingUiState {
  final bool recording;
  final bool locked;
  final bool willCancel;
  final bool willLock;
  final Duration elapsed;
  final double? amplitude; // 0..1 untuk indikator level (boleh null)

  const RecordingUiState({
    required this.recording,
    required this.locked,
    required this.willCancel,
    required this.willLock,
    required this.elapsed,
    this.amplitude,
  });

  static const idle = RecordingUiState(
    recording: false,
    locked: false,
    willCancel: false,
    willLock: false,
    elapsed: Duration.zero,
  );
}

class HoldToRecordButtonState extends State<HoldToRecordButton> {
  static const Duration _maxDuration = Duration(seconds: 60);
  static const double _cancelThreshold = -80; // geser kiri >= 80px
  static const double _lockThreshold = -80; // geser atas >= 80px

  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();

  bool _recording = false;
  bool _locked = false;
  bool _willCancel = false;
  bool _willLock = false;
  Offset _dragOffset = Offset.zero;
  String? _path;
  DateTime? _startedAt;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  double? _amplitude;

  bool get isRecording => _recording;
  bool get isLocked => _locked;

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onStateChange(RecordingUiState(
      recording: _recording,
      locked: _locked,
      willCancel: _willCancel,
      willLock: _willLock,
      elapsed: _startedAt == null
          ? Duration.zero
          : DateTime.now().difference(_startedAt!),
      amplitude: _amplitude,
    ));
  }

  Future<bool> _ensurePermission() async {
    if (await _recorder.hasPermission()) return true;
    final s = await Permission.microphone.request();
    if (s.isGranted) return true;
    widget.onPermissionDenied?.call();
    return false;
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || _recording) return;
    final ok = await _ensurePermission();
    if (!ok) return;

    final dir = await getTemporaryDirectory();
    final file = '${dir.path}/voice_${_uuid.v4()}.m4a';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
          bitRate: 96000,
        ),
        path: file,
      );
    } catch (_) {
      return;
    }

    _path = file;
    _startedAt = DateTime.now();
    _recording = true;
    _locked = false;
    _willCancel = false;
    _willLock = false;
    _dragOffset = Offset.zero;
    _amplitude = null;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_recording) return;
      final elapsed = DateTime.now().difference(_startedAt!);
      if (elapsed >= _maxDuration) {
        _stopAndSend();
        return;
      }
      _emit();
    });

    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      // dBFS biasanya 0 (loud) → -160 (silent). Normalisasi kasar ke 0..1.
      final db = amp.current;
      final norm = ((db + 45) / 45).clamp(0.0, 1.0);
      _amplitude = norm;
    });

    _emit();
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    _recording = false;
    _locked = false;
    _willCancel = false;
    _willLock = false;
    _ticker?.cancel();
    _ampSub?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (_path != null) {
      try {
        await File(_path!).delete();
      } catch (_) {}
    }
    _path = null;
    _emit();
  }

  Future<void> _stopAndSend() async {
    if (!_recording) return;
    final started = _startedAt;
    _recording = false;
    _locked = false;
    _willCancel = false;
    _willLock = false;
    _ticker?.cancel();
    _ampSub?.cancel();
    String? finalPath;
    try {
      finalPath = await _recorder.stop();
    } catch (_) {}
    finalPath ??= _path;
    final duration = started == null
        ? Duration.zero
        : DateTime.now().difference(started);
    _path = null;
    _emit();
    if (finalPath != null && duration.inMilliseconds >= 500) {
      widget.onRecorded(VoiceNoteResult(File(finalPath), duration));
    } else if (finalPath != null) {
      // Terlalu pendek (< 0.5 detik) — hapus, jangan kirim.
      try {
        await File(finalPath).delete();
      } catch (_) {}
    }
  }

  /// Lock recording: user lepas jari, rekam tetap berjalan sampai stop ditekan.
  void _lockRecording() {
    if (!_recording || _locked) return;
    _locked = true;
    _willLock = false;
    _willCancel = false;
    _emit();
  }

  /// Dipanggil dari panel rekam yang ditampilkan parent ketika user tekan
  /// tombol stop saat dalam mode locked.
  Future<void> stopFromLocked() => _stopAndSend();

  /// Dipanggil dari panel rekam ketika user tekan tombol batal (locked).
  Future<void> cancelFromLocked() => _cancelRecording();

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (!_recording || _locked) return;
    _dragOffset = d.localOffsetFromOrigin;
    final cancel = _dragOffset.dx <= _cancelThreshold;
    final lock = _dragOffset.dy <= _lockThreshold && !cancel;
    if (cancel != _willCancel || lock != _willLock) {
      _willCancel = cancel;
      _willLock = lock;
      _emit();
    }
  }

  Future<void> _onLongPressEnd(LongPressEndDetails d) async {
    if (!_recording || _locked) return;
    if (_willLock) {
      _lockRecording();
    } else if (_willCancel) {
      await _cancelRecording();
    } else {
      await _stopAndSend();
    }
  }

  void _showHoldHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Tahan untuk merekam, lepaskan untuk kirim'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? _showHoldHint : null,
      onLongPressStart: widget.enabled ? (_) => _startRecording() : null,
      onLongPressMoveUpdate: widget.enabled ? _onLongPressMove : null,
      onLongPressEnd: widget.enabled ? _onLongPressEnd : null,
      onLongPressCancel: widget.enabled
          ? () {
              if (_recording && !_locked) _cancelRecording();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _recording
              ? MyloColors.primary.withAlpha(40)
              : Colors.transparent,
        ),
        child: Icon(
          Icons.mic,
          color: _recording ? MyloColors.primary : MyloColors.textSecondary,
          size: 24,
        ),
      ),
    );
  }
}

/// Panel yang ditampilkan parent (chat room) menggantikan input bar saat
/// rekaman berlangsung. Dua mode:
///   - holding (belum locked): tampilkan timer + petunjuk geser kiri (batal)
///     & geser atas (kunci).
///   - locked: tampilkan timer + tombol batal + tombol kirim.
class RecordingPanel extends StatelessWidget {
  final RecordingUiState state;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const RecordingPanel({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onSend,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (state.locked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: MyloColors.primary.withAlpha(80)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.delete_outline,
                  color: const Color(0xFFE53935)),
              tooltip: 'Batal',
            ),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE53935),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt(state.elapsed),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Terkunci • tekan kirim',
                style: TextStyle(
                  color: MyloColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  MyloColors.primary,
                  MyloColors.secondary,
                ]),
              ),
              child: IconButton(
                onPressed: onSend,
                icon: const Icon(Icons.send, color: Colors.white),
                tooltip: 'Kirim',
              ),
            ),
          ],
        ),
      );
    }

    // Holding mode (belum dikunci).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: state.willCancel
            ? const Color(0xFFE53935).withAlpha(20)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: state.willCancel
              ? const Color(0xFFE53935)
              : MyloColors.primary.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          AnimatedScale(
            scale: state.willCancel ? 1.3 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              state.willCancel ? Icons.delete : Icons.mic,
              color: state.willCancel ? const Color(0xFFE53935) : MyloColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmt(state.elapsed),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_left,
                    size: 18, color: MyloColors.textSecondary),
                Text(
                  state.willCancel
                      ? 'Lepas untuk batal'
                      : (state.willLock
                          ? 'Lepas untuk kunci'
                          : 'Geser ← batal  •  ↑ kunci'),
                  style: TextStyle(
                    color: state.willCancel
                        ? const Color(0xFFE53935)
                        : MyloColors.textSecondary,
                    fontSize: 12,
                    fontWeight: state.willCancel || state.willLock
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Visual indicator zona kunci (panah ke atas).
          AnimatedOpacity(
            opacity: state.willLock ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.willLock
                    ? MyloColors.primary
                    : MyloColors.primary.withAlpha(30),
              ),
              child: Icon(
                Icons.lock,
                color: state.willLock ? Colors.white : MyloColors.primary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
