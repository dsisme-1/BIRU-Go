import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/detection.dart';
import '../models/inference_stats.dart';
import '../utils/image_utils.dart';
import '../inference/preprocessor.dart';
import 'detector_service.dart';

typedef CameraFrameCallback = void Function(
  List<Detection> detections,
  InferenceStats stats,
  Size previewSize,
);

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isStreaming = false;
  bool _isProcessingFrame = false;

  int throttleIntervalMs = 30;
  int _lastInferenceTimestamp = 0;

  CameraFrameCallback? onFrameDetected;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  bool get isStreaming => _isStreaming;

  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 5.0;

  double get currentZoom => _currentZoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  Future<void> initialize({
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraException('NoCameraAvailable', 'No camera detected on this device.');
    }

    final CameraDescription backCamera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      backCamera,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    try {
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;
    } catch (e) {
      debugPrint('[CameraService] Zoom levels not supported: $e');
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _currentZoom = 1.0;
    }
  }

  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final double clampedZoom = zoom.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(clampedZoom);
      _currentZoom = clampedZoom;
    } catch (e) {
      debugPrint('[CameraService] Error setting zoom level: $e');
    }
  }

  int get sensorOrientation => _controller?.description.sensorOrientation ?? 0;

  Future<void> startStreaming(CameraFrameCallback callback) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw StateError('Cannot start stream: CameraController is not initialized.');
    }

    if (_isStreaming) return;

    onFrameDetected = callback;
    _isStreaming = true;

    final DetectorService detector = DetectorService();
    if (!detector.isReady) {
      await detector.initialize();
    }

    await _controller!.startImageStream((CameraImage cameraImage) async {
      if (!_isStreaming) return;

      final int now = DateTime.now().millisecondsSinceEpoch;

      if (now - _lastInferenceTimestamp < throttleIntervalMs) {
        return;
      }

      if (_isProcessingFrame || detector.isProcessing) {
        return;
      }

      _isProcessingFrame = true;
      _lastInferenceTimestamp = now;

      try {
        final payload = CameraImagePayload(
          width: cameraImage.width,
          height: cameraImage.height,
          format: cameraImage.format.group == ImageFormatGroup.yuv420 ? 'yuv420' : 
                  (cameraImage.format.group == ImageFormatGroup.bgra8888 ? 'bgra8888' : 'unknown'),
          planeBytes: cameraImage.planes.map((p) => p.bytes).toList(),
          planeBytesPerRow: cameraImage.planes.map((p) => p.bytesPerRow).toList(),
          planeBytesPerPixel: cameraImage.planes.map((p) => p.bytesPerPixel).toList(),
          rotation: sensorOrientation,
        );

        final DetectionResult result = await detector.detectCameraImage(payload);

        if (_isStreaming && onFrameDetected != null) {
          final Size authorizedPreviewSize = Size(
            result.imageWidth.toDouble(),
            result.imageHeight.toDouble(),
          );
          onFrameDetected!(
            result.detections,
            result.stats,
            authorizedPreviewSize,
          );
        }
      } catch (e) {
        debugPrint('[CameraService] Inference error on frame: $e');
        detector.resetInferenceLock();
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> stopStreaming() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    _isProcessingFrame = false;
    if (_controller != null && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (e) {
        debugPrint('[CameraService] Error stopping image stream: $e');
      }
    }
  }

  Future<img.Image?> takePicture({CameraFrameCallback? resumeCallback}) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return null;
    }

    try {
      final bool wasStreaming = _isStreaming;
      final CameraFrameCallback? savedCallback = onFrameDetected;
      if (wasStreaming) {
        await stopStreaming();
      }

      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      final img.Image? result = ImageUtils.decodeImageBytes(bytes);

      if (wasStreaming) {
        final CameraFrameCallback? callbackToUse = resumeCallback ?? savedCallback;
        if (callbackToUse != null) {
          await startStreaming(callbackToUse);
        }
      }

      return result;
    } catch (e) {
      debugPrint('[CameraService] Error taking picture: $e');
      return null;
    }
  }

  bool get isRecordingVideo => _controller?.value.isRecordingVideo ?? false;

  Future<void> startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;

    if (_isStreaming) {
      await stopStreaming();
    }
    await _controller!.startVideoRecording();
  }

  Future<XFile?> stopVideoRecording({CameraFrameCallback? resumeCallback}) async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return null;

    final XFile file = await _controller!.stopVideoRecording();

    final callbackToUse = resumeCallback ?? onFrameDetected;
    if (callbackToUse != null) {
      await startStreaming(callbackToUse);
    }
    return file;
  }

  Future<void> dispose() async {
    await stopStreaming();
    await _controller?.dispose();
    _controller = null;
    _isStreaming = false;
  }
}
