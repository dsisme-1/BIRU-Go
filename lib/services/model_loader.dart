// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/src/bindings/bindings.dart';
import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class ModelLoader {
  static final ModelLoader _instance = ModelLoader._internal();
  factory ModelLoader() => _instance;
  ModelLoader._internal();

  static const String photoModelAssetPath = 'assets/models/yolov8n.tflite';
  static const String photoAndVideoModelAssetPath = photoModelAssetPath;
  static const String liveCameraModelAssetPath = 'assets/models/yolo11n.tflite';
  static const String fastModelAssetPath = 'assets/models/yolo11n.tflite';
  static const String legacyModelAssetPath = 'assets/models/yolo11n.tflite';
  static const String labelsAssetPath = 'assets/labels/classes.txt';

  String _currentModelAssetPath = fastModelAssetPath;
  Interpreter? _interpreter;
  List<String> _classLabels = [];
  bool _isInitialized = false;
  String? _initError;

  List<int> _inputShape = [1, 3, 320, 320];
  TensorType? _inputType;
  List<int> _outputShape = [1, 559, 2100];
  TensorType? _outputType;

  bool get isInitialized => _isInitialized && _interpreter != null;
  String? get initError => _initError;
  String get currentModelAssetPath => _currentModelAssetPath;
  Interpreter get interpreter => _interpreter!;
  List<String> get classLabels => List.unmodifiable(_classLabels);
  List<int> get inputShape => _inputShape;
  TensorType? get inputType => _inputType;
  List<int> get outputShape => _outputShape;
  TensorType? get outputType => _outputType;

  int get inputWidth => _inputShape.length >= 4 ? _inputShape[3] : 320;
  int get inputHeight => _inputShape.length >= 3 ? _inputShape[2] : 320;
  int get outputAnchors => _outputShape.length >= 3 ? _outputShape[2] : 2100;

  Future<void> initialize({String? modelPath}) async {
    final String targetModel = modelPath ?? _currentModelAssetPath;
    if (_isInitialized && _interpreter != null && _currentModelAssetPath == targetModel) {
      return;
    }

    if (_interpreter != null) {
      _interpreter?.close();
      _interpreter = null;
      _isInitialized = false;
    }

    try {
      _currentModelAssetPath = targetModel;

      if (_classLabels.isEmpty) {
        debugPrint('[ModelLoader] Loading class labels from $labelsAssetPath...');
        final String labelsData = await rootBundle.loadString(labelsAssetPath);
        final LineSplitter splitter = const LineSplitter();
        _classLabels = splitter
            .convert(labelsData)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        debugPrint('[ModelLoader] Loaded ${_classLabels.length} bird classes.');
      }

      debugPrint('[ModelLoader] Loading TFLite model bytes from $targetModel...');
      ByteData? assetData;
      try {
        assetData = await rootBundle.load(targetModel);
      } catch (e) {
        debugPrint('[ModelLoader] Failed to load $targetModel, trying fallback: $e');
        assetData = await rootBundle.load(legacyModelAssetPath);
        _currentModelAssetPath = legacyModelAssetPath;
      }

      final Uint8List modelBytes = Uint8List.fromList(
        assetData.buffer.asUint8List(assetData.offsetInBytes, assetData.lengthInBytes),
      );
      debugPrint('[ModelLoader] Model bytes loaded: ${modelBytes.length} bytes for $_currentModelAssetPath');

      Interpreter? interpreter;

      bool testWarmup(Interpreter candidate) {
        try {
          final Pointer<TfLiteInterpreter> p =
              Pointer<TfLiteInterpreter>.fromAddress(candidate.address);
          final Pointer<TfLiteTensor> t = tfliteBinding.TfLiteInterpreterGetInputTensor(p, 0);
          return tfliteBinding.TfLiteTensorByteSize(t) > 0;
        } catch (e) {
          debugPrint('[ModelLoader] Warmup check failed: $e');
          return false;
        }
      }

      final List<Map<String, dynamic>> tiers = [
        {
          'name': 'GPU Delegate V2 (4-threads)',
          'create': () {
            final opts = InterpreterOptions()..threads = 4;
            if (defaultTargetPlatform == TargetPlatform.android) {
              try {
                opts.addDelegate(GpuDelegateV2());
              } catch (_) {
                try {
                  opts.addDelegate(GpuDelegate());
                } catch (_) {}
              }
            }
            return opts;
          },
        },
        {
          'name': 'NNAPI / Hardware Accelerator (4-threads)',
          'create': () {
            final opts = InterpreterOptions()..threads = 4;
            if (defaultTargetPlatform == TargetPlatform.android) {
              opts.useNnApiForAndroid = true;
            }
            return opts;
          },
        },
        {
          'name': 'Multi-Threaded CPU (4-threads)',
          'create': () => InterpreterOptions()..threads = 4,
        },
        {
          'name': 'Multi-Threaded CPU (2-threads)',
          'create': () => InterpreterOptions()..threads = 2,
        },
        {
          'name': 'Default CPU fallback',
          'create': () => InterpreterOptions()..threads = 1,
        },
      ];

      for (int i = 0; i < tiers.length; i++) {
        final tier = tiers[i];
        final String name = tier['name'] as String;
        try {
          final optionsBuilder = tier['create'] as InterpreterOptions Function();
          final Interpreter c = Interpreter.fromBuffer(modelBytes, options: optionsBuilder());
          c.allocateTensors();
          if (testWarmup(c)) {
            interpreter = c;
            debugPrint('[ModelLoader] Successfully initialized tier $i: $name');
            break;
          }
          debugPrint('[ModelLoader] Tier $i ($name) failed warmup check.');
          c.close();
        } catch (e) {
          debugPrint('[ModelLoader] Tier $i ($name) exception: $e');
        }
      }

      if (interpreter == null) {
        debugPrint('[ModelLoader] All tiers failed - bare fallback.');
        interpreter = Interpreter.fromBuffer(modelBytes);
        interpreter.allocateTensors();
      }

      _interpreter = interpreter;

      final inputTensors = _interpreter!.getInputTensors();
      if (inputTensors.isNotEmpty) {
        _inputShape = inputTensors[0].shape;
        _inputType = inputTensors[0].type;
        debugPrint('[ModelLoader] Input: $_inputShape, type: $_inputType');
      }

      final outputTensors = _interpreter!.getOutputTensors();
      if (outputTensors.isNotEmpty) {
        _outputShape = outputTensors[0].shape;
        _outputType = outputTensors[0].type;
        debugPrint('[ModelLoader] Output: $_outputShape, type: $_outputType');
      }

      if (_outputShape.length >= 2) {
        final int expectedClasses = _outputShape[1] - 4;
        if (expectedClasses != _classLabels.length) {
          throw Exception(
            'Model output class dimension ($expectedClasses) does not match '
            'classes.txt count (${_classLabels.length}).',
          );
        }
      }

      _isInitialized = true;
      _initError = null;
      debugPrint('[ModelLoader] Successfully initialized model $_currentModelAssetPath');
    } catch (e, stackTrace) {
      _isInitialized = false;
      _initError = e.toString();
      debugPrint('[ModelLoader] Initialization failed: $e\n$stackTrace');
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
