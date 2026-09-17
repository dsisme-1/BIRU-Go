import 'package:flutter/material.dart';
import '../models/detection.dart';
import '../models/detection_summary.dart';
import '../services/camera_service.dart';
import '../services/database_helper.dart';
import '../services/detector_service.dart';
import '../services/model_loader.dart';
import '../widgets/camera_view.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/performance_hud.dart';

class LiveDetectionScreen extends StatefulWidget {
  const LiveDetectionScreen({super.key});

  @override
  State<LiveDetectionScreen> createState() => _LiveDetectionScreenState();
}

class _LiveDetectionScreenState extends State<LiveDetectionScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final DetectorService _detectorService = DetectorService();

  final ValueNotifier<List<Detection>> _detectionsNotifier =
      ValueNotifier<List<Detection>>([]);
  final ValueNotifier<Size> _previewSizeNotifier =
      ValueNotifier<Size>(Size.zero);
  final ValueNotifier<double> _zoomNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> _isPinchingNotifier = ValueNotifier<bool>(false);

  bool _isLoading = true;
  String? _errorMessage;
  bool _showDebugHud = true;

  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  DateTime? _lastPinchTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCameraAndDetector();
  }

  Future<void> _initializeCameraAndDetector() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _detectorService.switchModel(ModelLoader.liveCameraModelAssetPath);
      _detectorService.resetTracker();
      _detectorService.resetLiveSession();

      await _cameraService.initialize();

      _currentZoom = _cameraService.currentZoom;
      _zoomNotifier.value = _currentZoom;

      await _cameraService.startStreaming(
          (List<Detection> detections, _, Size previewSize) {
        _detectionsNotifier.value = detections;
        _previewSizeNotifier.value = previewSize;
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _setPresetZoom(double targetZoom) async {
    final double clamped = targetZoom.clamp(
      _cameraService.minZoom,
      _cameraService.maxZoom,
    );
    _currentZoom = clamped;
    _zoomNotifier.value = clamped;

    _detectorService.resetTracker();

    _showPinchBadge();
    await _cameraService.setZoomLevel(clamped);
  }

  void _showPinchBadge() {
    _isPinchingNotifier.value = true;
    _lastPinchTime = DateTime.now();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_lastPinchTime != null &&
          DateTime.now().difference(_lastPinchTime!).inMilliseconds >= 1400) {
        _isPinchingNotifier.value = false;
      }
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
    _showPinchBadge();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final double newZoom = (_baseZoom * details.scale).clamp(
      _cameraService.minZoom,
      _cameraService.maxZoom,
    );
    final double delta = (newZoom - _currentZoom).abs();
    if (delta >= 0.05) {
      if (delta >= 0.35) {
        _detectorService.resetTracker();
      }
      _currentZoom = newZoom;
      _zoomNotifier.value = newZoom;
      _showPinchBadge();
      _cameraService.setZoomLevel(newZoom);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraService.controller == null ||
        !_cameraService.controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraService.stopStreaming();
    } else if (state == AppLifecycleState.resumed) {
      _cameraService.startStreaming(
          (List<Detection> detections, _, Size previewSize) {
        _detectionsNotifier.value = detections;
        _previewSizeNotifier.value = previewSize;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    _detectionsNotifier.dispose();
    _previewSizeNotifier.dispose();
    _zoomNotifier.dispose();
    _isPinchingNotifier.dispose();
    _saveLiveSession();
    super.dispose();
  }

  bool _hasSavedSession = false;

  Future<void> _saveLiveSession() async {
    if (_hasSavedSession) return;
    final summary = _detectorService.lastSummary;
    if (summary != null &&
        summary.speciesList.isNotEmpty &&
        summary.source == DetectionSource.liveCamera) {
      _hasSavedSession = true;
      try {
        await DatabaseHelper.instance.insertSession(summary);
      } catch (e) {
        debugPrint('[LiveDetectionScreen] Failed to save live session: $e');
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Live Camera Detection',
              style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF0066FF)),
              SizedBox(height: 16),
              Text(
                'Starting camera and loading YOLO model...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFEF4444), size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Camera or Model Initialization Failed',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _initializeCameraAndDetector,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        _saveLiveSession();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: OrientationBuilder(
        builder: (context, orientation) {
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: CameraView(
                  controller: _cameraService.controller!,
                  overlay: ValueListenableBuilder<List<Detection>>(
                    valueListenable: _detectionsNotifier,
                    builder: (_, detections, _) {
                      final Size previewSize =
                          _previewSizeNotifier.value.isEmpty
                              ? Size(
                                  _cameraService.controller!.value.previewSize
                                          ?.height ??
                                      480,
                                  _cameraService.controller!.value.previewSize
                                          ?.width ??
                                      640,
                                )
                              : _previewSizeNotifier.value;
                      return DetectionOverlay(
                        detections: detections,
                        sourceImageSize: previewSize,
                        fit: BoxFit.fill,
                        enableAnimation: false,
                        orientation: orientation,
                      );
                    },
                  ),
                ),
              ),

              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          const Color(0xFF0F172A).withValues(alpha: 0.75),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 20),
                        onPressed: () async {
                          await _saveLiveSession();
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),

                    ValueListenableBuilder<List<Detection>>(
                      valueListenable: _detectionsNotifier,
                      builder: (_, detections, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A)
                                .withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: detections.isNotEmpty
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF0066FF),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                detections.isEmpty
                                    ? 'Scanning...'
                                    : '${detections.length} Bird(s) Detected',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    CircleAvatar(
                      backgroundColor:
                          const Color(0xFF0F172A).withValues(alpha: 0.75),
                      child: IconButton(
                        icon: Icon(
                          _showDebugHud
                              ? Icons.insights
                              : Icons.insights_outlined,
                          color: _showDebugHud
                              ? const Color(0xFF60A5FA)
                              : Colors.white70,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _showDebugHud = !_showDebugHud;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              if (_showDebugHud)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 16,
                  child: ValueListenableBuilder<List<Detection>>(
                    valueListenable: _detectionsNotifier,
                    builder: (_, detections, _) => PerformanceHud(
                      currentFps: _detectorService.currentFps,
                      recentDetections: detections,
                    ),
                  ),
                ),

              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 114,
                left: 0,
                right: 0,
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isPinchingNotifier,
                    builder: (context, isPinching, _) {
                      return AnimatedOpacity(
                        opacity: isPinching ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: ValueListenableBuilder<double>(
                          valueListenable: _zoomNotifier,
                          builder: (context, currentZoom, _) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFF0066FF)
                                        .withValues(alpha: 0.5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Text(
                                '${currentZoom.toStringAsFixed(1)}× Zoom',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),

              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 68,
                left: 0,
                right: 0,
                child: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _zoomNotifier,
                    builder: (context, currentZoom, _) {
                      return Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0F172A).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildZoomButton('1×', 1.0, currentZoom < 2.0),
                            const SizedBox(width: 4),
                            _buildZoomButton('3×', 3.0, currentZoom >= 2.0),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Live Camera Detection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  }

  Widget _buildZoomButton(String label, double zoomTarget, bool isSelected) {
    return InkWell(
      onTap: () => _setPresetZoom(zoomTarget),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0066FF)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
