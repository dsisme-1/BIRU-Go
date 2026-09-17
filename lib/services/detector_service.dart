// ignore_for_file: implementation_imports
import 'dart:ffi';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter/src/bindings/bindings.dart';
import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart';
import '../inference/postprocessor.dart';
import '../inference/preprocessor.dart';
import '../inference/tracker/live_session_aggregator.dart';
import '../inference/tracker/object_tracker.dart';
import '../models/detection.dart';
import '../models/detection_summary.dart';
import '../models/inference_stats.dart';
import '../utils/performance_utils.dart';
import 'model_loader.dart';

class DetectionResult {
  final List<Detection> detections;
  final InferenceStats stats;
  final int imageWidth;
  final int imageHeight;
  final DateTime timestamp;

  DetectionResult({
    required this.detections,
    required this.stats,
    required this.imageWidth,
    required this.imageHeight,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class DetectorService {
  static final DetectorService _instance = DetectorService._internal();
  factory DetectorService() => _instance;
  DetectorService._internal();

  final ModelLoader _modelLoader = ModelLoader();
  final ImagePreprocessor _preprocessor = ImagePreprocessor();
  late final YoloPostprocessor _postprocessor = YoloPostprocessor();
  final PerformanceTracker _performanceTracker = PerformanceTracker();
  final ObjectTracker _tracker = ObjectTracker();
  final LiveSessionAggregator _liveAggregator = LiveSessionAggregator();

  bool enableTracker = true;

  final ValueNotifier<DetectionSummary?> summaryNotifier = ValueNotifier<DetectionSummary?>(null);
  DetectionSummary? get lastSummary => summaryNotifier.value;
  set lastSummary(DetectionSummary? summary) {
    summaryNotifier.value = summary;
  }

  static const int _outputChannels = 559;
  int get _outputAnchors => _modelLoader.outputAnchors;
  int get _outputElementCount => 1 * _outputChannels * _outputAnchors;

  Float32List _flatOutputBuffer = Float32List(1 * _outputChannels * 2100);

  bool _isProcessing = false;
  bool _hasLoggedTensorInfo = false;
  bool _isReady = false;

  bool get isReady => _isReady && _modelLoader.isInitialized;
  bool get isProcessing => _isProcessing;

  double get confidenceThreshold => _postprocessor.confidenceThreshold;
  set confidenceThreshold(double value) {
    _postprocessor.confidenceThreshold = value;
  }

  double get nmsThreshold => _postprocessor.nmsThreshold;
  set nmsThreshold(double value) {
    _postprocessor.nmsThreshold = value;
  }

  Future<void> initialize({String? modelPath}) async {
    await _modelLoader.initialize(modelPath: modelPath);
    _preprocessor.updateDimensions(
      width: _modelLoader.inputWidth,
      height: _modelLoader.inputHeight,
    );
    if (_flatOutputBuffer.length != _outputElementCount) {
      _flatOutputBuffer = Float32List(_outputElementCount);
    }
    _isReady = true;
  }

  Future<void> switchModel(String modelAssetPath) async {
    _isReady = false;
    await initialize(modelPath: modelAssetPath);
  }

  void _executeTFLiteInference(PreprocessedInput preprocessed) {
    final Interpreter interp = _modelLoader.interpreter;
    final List<Tensor> inTensors = interp.getInputTensors();
    final List<Tensor> outTensors = interp.getOutputTensors();

    if (!_hasLoggedTensorInfo) {
      _hasLoggedTensorInfo = true;
      debugPrint(
        '[DetectorService] INPUT tensor: type=${inTensors[0].type}, '
        'shape=${inTensors[0].shape}, bytes=${inTensors[0].data.lengthInBytes}',
      );
      debugPrint(
        '[DetectorService] OUTPUT tensor: type=${outTensors[0].type}, '
        'shape=${outTensors[0].shape}, bytes=${outTensors[0].data.lengthInBytes}',
      );
    }

    final TensorType inType = inTensors[0].type;
    final Float32List floatBuf = preprocessed.tensorBuffer;

    if (inType == TensorType.float32) {
      final Uint8List inputBytes = floatBuf.buffer.asUint8List(
        floatBuf.offsetInBytes,
        floatBuf.lengthInBytes,
      );
      inTensors[0].setTo(inputBytes);
    } else {
      final Pointer<TfLiteInterpreter> interpPtr =
          Pointer<TfLiteInterpreter>.fromAddress(interp.address);
      final Pointer<TfLiteTensor> inTensorPtr =
          tfliteBinding.TfLiteInterpreterGetInputTensor(interpPtr, 0);
      final TfLiteQuantizationParams inParams =
          tfliteBinding.TfLiteTensorQuantizationParams(inTensorPtr);
      final double inScale = inParams.scale > 0 ? inParams.scale : (1.0 / 255.0);
      final int inZeroPoint = inParams.zero_point;
      final Uint8List int8Bytes = Uint8List(floatBuf.length);
      for (int i = 0; i < floatBuf.length; i++) {
        final int q = (floatBuf[i] / inScale + inZeroPoint).round().clamp(-128, 127);
        int8Bytes[i] = q & 0xFF;
      }
      inTensors[0].setTo(int8Bytes);
    }

    interp.invoke();

    final TensorType outType = outTensors[0].type;
    final Uint8List outRaw = outTensors[0].data;
    final int currentElementCount = _outputElementCount;

    if (_flatOutputBuffer.length != currentElementCount) {
      _flatOutputBuffer = Float32List(currentElementCount);
    }

    if (outType == TensorType.float32) {
      final Float32List outF32 = outRaw.buffer.asFloat32List(
        outRaw.offsetInBytes,
        currentElementCount,
      );
      _flatOutputBuffer.setRange(0, currentElementCount, outF32);
    } else {
      final Pointer<TfLiteInterpreter> interpPtr =
          Pointer<TfLiteInterpreter>.fromAddress(interp.address);
      final Pointer<TfLiteTensor> outTensorPtr =
          tfliteBinding.TfLiteInterpreterGetOutputTensor(interpPtr, 0);
      final TfLiteQuantizationParams outParams =
          tfliteBinding.TfLiteTensorQuantizationParams(outTensorPtr);
      final double outScale = outParams.scale > 0 ? outParams.scale : 1.0;
      final int outZeroPoint = outParams.zero_point;
      final Int8List int8Out = outRaw.buffer.asInt8List(outRaw.offsetInBytes);
      for (int i = 0; i < currentElementCount; i++) {
        _flatOutputBuffer[i] = (int8Out[i] - outZeroPoint) * outScale;
      }
    }
  }

  Future<DetectionResult> detectImage(
    img.Image image, {
    int? frameIndex,
  }) async {
    if (!_isReady) {
      await initialize();
    }

    if (_isProcessing) {
      throw StateError('Inference lock active: Another detection is currently running.');
    }

    _isProcessing = true;
    try {
      final PreprocessedInput preprocessed = _preprocessor.process(
        image,
        targetW: _modelLoader.inputWidth,
        targetH: _modelLoader.inputHeight,
      );

      final stopwatch = Stopwatch()..start();
      _executeTFLiteInference(preprocessed);
      stopwatch.stop();
      final double inferenceMs = stopwatch.elapsedMicroseconds / 1000.0;

      final postStopwatch = Stopwatch()..start();
      final Float32List activeOutput = Float32List.sublistView(
        _flatOutputBuffer,
        0,
        _outputElementCount,
      );
      final List<Detection> detections = _postprocessor.process(
        rawOutput: activeOutput,
        numAnchors: _outputAnchors,
        letterboxInfo: preprocessed.letterboxInfo,
        classNames: _modelLoader.classLabels,
        frameIndex: frameIndex,
      );
      postStopwatch.stop();
      final double postprocessMs = postStopwatch.elapsedMicroseconds / 1000.0;

      final double totalMs = preprocessed.latencyMs + inferenceMs + postprocessMs;
      _performanceTracker.recordFrame(totalMs);

      final InferenceStats stats = InferenceStats(
        preprocessLatencyMs: preprocessed.latencyMs,
        inferenceLatencyMs: inferenceMs,
        postprocessLatencyMs: postprocessMs,
        inputShape: _modelLoader.inputShape.toString(),
        outputShape: _modelLoader.outputShape.toString(),
        detectionCount: detections.length,
      );

      final List<Detection> finalDetections = (enableTracker && frameIndex != null)
          ? _tracker.update(detections, frameIndex: frameIndex)
          : detections;

      if (finalDetections.isNotEmpty) {
        lastSummary = DetectionSummary.fromDetections(finalDetections);
      }

      return DetectionResult(
        detections: finalDetections,
        stats: stats,
        imageWidth: image.width,
        imageHeight: image.height,
      );

    } finally {
      _isProcessing = false;
    }
  }

  Future<DetectionResult> detectCameraImage(
    CameraImagePayload payload, {
    int? frameIndex,
  }) async {
    if (!_isReady) {
      await initialize();
    }

    if (_isProcessing) {
      throw StateError('Inference lock active: Another detection is currently running.');
    }

    _isProcessing = true;
    try {
      final PreprocessedInput preprocessed = _preprocessor.processCameraPayloadDirect(
        payload,
        targetW: _modelLoader.inputWidth,
        targetH: _modelLoader.inputHeight,
      );

      final stopwatch = Stopwatch()..start();
      _executeTFLiteInference(preprocessed);
      stopwatch.stop();
      final double inferenceMs = stopwatch.elapsedMicroseconds / 1000.0;

      final postStopwatch = Stopwatch()..start();
      final Float32List activeOutput = Float32List.sublistView(
        _flatOutputBuffer,
        0,
        _outputElementCount,
      );
      final List<Detection> detections = _postprocessor.process(
        rawOutput: activeOutput,
        numAnchors: _outputAnchors,
        letterboxInfo: preprocessed.letterboxInfo,
        classNames: _modelLoader.classLabels,
        frameIndex: frameIndex,
      );
      postStopwatch.stop();
      final double postprocessMs = postStopwatch.elapsedMicroseconds / 1000.0;

      final double totalMs = preprocessed.latencyMs + inferenceMs + postprocessMs;
      _performanceTracker.recordFrame(totalMs);

      final InferenceStats stats = InferenceStats(
        preprocessLatencyMs: preprocessed.latencyMs,
        inferenceLatencyMs: inferenceMs,
        postprocessLatencyMs: postprocessMs,
        inputShape: _modelLoader.inputShape.toString(),
        outputShape: _modelLoader.outputShape.toString(),
        detectionCount: detections.length,
      );

      final List<Detection> finalDetections = enableTracker
          ? _tracker.update(detections, frameIndex: frameIndex)
          : detections;

      if (finalDetections.isNotEmpty) {
        _liveAggregator.addFrameDetections(finalDetections);
        lastSummary = _liveAggregator.buildSummary();
      }

      return DetectionResult(
        detections: finalDetections,
        stats: stats,
        imageWidth: preprocessed.imageWidth,
        imageHeight: preprocessed.imageHeight,
      );

    } finally {
      _isProcessing = false;
    }
  }

  void resetInferenceLock() {
    _isProcessing = false;
  }

  void resetPerformance() {
    _performanceTracker.reset();
  }

  void resetTracker() {
    _tracker.reset();
  }

  void resetLiveSession() {
    _liveAggregator.reset();
  }

  double get currentFps => _performanceTracker.currentFps;
}
