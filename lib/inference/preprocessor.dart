import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../utils/coordinate_utils.dart';

class CameraImagePayload {
  final int width;
  final int height;
  final String format;
  final List<Uint8List> planeBytes;
  final List<int> planeBytesPerRow;
  final List<int?> planeBytesPerPixel;
  final int rotation;

  CameraImagePayload({
    required this.width,
    required this.height,
    required this.format,
    required this.planeBytes,
    required this.planeBytesPerRow,
    required this.planeBytesPerPixel,
    required this.rotation,
  });
}

class PreprocessedInput {
  final Float32List tensorBuffer;
  final LetterboxInfo letterboxInfo;
  final double latencyMs;
  final int imageWidth;
  final int imageHeight;

  PreprocessedInput({
    required this.tensorBuffer,
    required this.letterboxInfo,
    required this.latencyMs,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class ImagePreprocessor {
  int inputWidth;
  int inputHeight;
  static const int inputChannels = 3;

  int get tensorElementCount => 1 * inputChannels * inputHeight * inputWidth;
  int get channelSize => inputHeight * inputWidth;

  Float32List _reusableBuffer;

  ImagePreprocessor({
    this.inputWidth = 320,
    this.inputHeight = 320,
  }) : _reusableBuffer = Float32List(1 * inputChannels * inputHeight * inputWidth);

  void updateDimensions({required int width, required int height}) {
    if (inputWidth == width && inputHeight == height) return;
    inputWidth = width;
    inputHeight = height;
    _reusableBuffer = Float32List(tensorElementCount);
  }

  PreprocessedInput process(
    img.Image originalImage, {
    int? targetW,
    int? targetH,
  }) {
    final int tw = targetW ?? inputWidth;
    final int th = targetH ?? inputHeight;

    if (tw != inputWidth || th != inputHeight || _reusableBuffer.length != 1 * inputChannels * th * tw) {
      updateDimensions(width: tw, height: th);
    }

    final stopwatch = Stopwatch()..start();

    final int origW = originalImage.width;
    final int origH = originalImage.height;

    final LetterboxInfo letterbox = CoordinateUtils.computeLetterbox(
      originalWidth: origW,
      originalHeight: origH,
      targetWidth: tw,
      targetHeight: th,
    );

    final int targetScaledW = (origW * letterbox.scale).round().clamp(1, tw);
    final int targetScaledH = (origH * letterbox.scale).round().clamp(1, th);

    final img.Image resized = img.copyResize(
      originalImage,
      width: targetScaledW,
      height: targetScaledH,
      interpolation: img.Interpolation.linear,
    );

    final int startX = letterbox.dx.round();
    final int startY = letterbox.dy.round();

    const double padValue = 114.0 / 255.0;

    final int totalCount = 1 * inputChannels * th * tw;
    final int cSize = th * tw;
    _reusableBuffer.fillRange(0, totalCount, padValue);

    for (int y = 0; y < targetScaledH; y++) {
      final int canvasY = startY + y;
      if (canvasY < 0 || canvasY >= th) continue;

      final int canvasRowOffset = canvasY * tw;

      for (int x = 0; x < targetScaledW; x++) {
        final int canvasX = startX + x;
        if (canvasX < 0 || canvasX >= tw) continue;

        final int pixelIndex = canvasRowOffset + canvasX;
        if (pixelIndex >= cSize) continue;

        final pixel = resized.getPixel(x, y);

        _reusableBuffer[pixelIndex]               = pixel.r / 255.0;
        _reusableBuffer[cSize + pixelIndex]       = pixel.g / 255.0;
        _reusableBuffer[2 * cSize + pixelIndex]   = pixel.b / 255.0;
      }
    }

    stopwatch.stop();

    return PreprocessedInput(
      tensorBuffer: Float32List.fromList(_reusableBuffer),
      letterboxInfo: letterbox,
      latencyMs: stopwatch.elapsedMicroseconds / 1000.0,
      imageWidth: origW,
      imageHeight: origH,
    );
  }

  PreprocessedInput processCameraPayloadDirect(
    CameraImagePayload payload, {
    int? targetW,
    int? targetH,
  }) {
    final int tw = targetW ?? inputWidth;
    final int th = targetH ?? inputHeight;

    if (tw != inputWidth || th != inputHeight || _reusableBuffer.length != 1 * inputChannels * th * tw) {
      updateDimensions(width: tw, height: th);
    }

    final stopwatch = Stopwatch()..start();

    final int rawW = payload.width;
    final int rawH = payload.height;
    final int rotation = payload.rotation;

    final bool isSwapped = rotation == 90 || rotation == 270;
    final int rotW = isSwapped ? rawH : rawW;
    final int rotH = isSwapped ? rawW : rawH;

    final LetterboxInfo letterbox = CoordinateUtils.computeLetterbox(
      originalWidth: rotW,
      originalHeight: rotH,
      targetWidth: tw,
      targetHeight: th,
    );

    final double scale = letterbox.scale;
    final double invScale = 1.0 / scale;
    final int startX = letterbox.dx.round();
    final int startY = letterbox.dy.round();
    final int targetScaledW = (rotW * scale).round().clamp(1, tw);
    final int targetScaledH = (rotH * scale).round().clamp(1, th);

    const double padValue = 114.0 / 255.0;
    final int totalCount = 1 * inputChannels * th * tw;
    final int cSize = th * tw;
    _reusableBuffer.fillRange(0, totalCount, padValue);

    final bool isYuv = payload.format == 'yuv420' || payload.planeBytes.length >= 3;

    if (isYuv) {
      final Uint8List yBytes = payload.planeBytes[0];
      final Uint8List uBytes = payload.planeBytes[1];
      final Uint8List vBytes = payload.planeBytes[2];
      final int yRowStride = payload.planeBytesPerRow[0];
      final int uvRowStride = payload.planeBytesPerRow[1];
      final int uvPixelStride = payload.planeBytesPerPixel[1] ?? 1;
      final int yLen = yBytes.length;
      final int uLen = uBytes.length;
      final int vLen = vBytes.length;

      for (int y = 0; y < targetScaledH; y++) {
        final int canvasY = startY + y;
        if (canvasY < 0 || canvasY >= th) continue;

        final int yRot = (y * invScale).toInt().clamp(0, rotH - 1);
        final int canvasRowOffset = canvasY * tw;

        for (int x = 0; x < targetScaledW; x++) {
          final int canvasX = startX + x;
          if (canvasX < 0 || canvasX >= tw) continue;

          final int xRot = (x * invScale).toInt().clamp(0, rotW - 1);

          int xRaw;
          int yRaw;
          if (rotation == 90) {
            xRaw = yRot;
            yRaw = rawH - 1 - xRot;
          } else if (rotation == 180) {
            xRaw = rawW - 1 - xRot;
            yRaw = rawH - 1 - yRot;
          } else if (rotation == 270) {
            xRaw = rawW - 1 - yRot;
            yRaw = xRot;
          } else {
            xRaw = xRot;
            yRaw = yRot;
          }

          final int yIndex = yRaw * yRowStride + xRaw;
          final int uvIndex = (yRaw >> 1) * uvRowStride + (xRaw >> 1) * uvPixelStride;

          if (yIndex < yLen) {
            final int yVal = yBytes[yIndex] & 0xFF;
            int uVal = 0;
            int vVal = 0;
            if (uvIndex < uLen && uvIndex < vLen) {
              uVal = (uBytes[uvIndex] & 0xFF) - 128;
              vVal = (vBytes[uvIndex] & 0xFF) - 128;
            }

            final int r = (yVal + ((1370705 * vVal) >> 20)).clamp(0, 255);
            final int g = (yVal - ((337633 * uVal + 698001 * vVal) >> 20)).clamp(0, 255);
            final int b = (yVal + ((1732446 * uVal) >> 20)).clamp(0, 255);

            final int pixelIndex = canvasRowOffset + canvasX;
            _reusableBuffer[pixelIndex]             = r / 255.0;
            _reusableBuffer[cSize + pixelIndex]     = g / 255.0;
            _reusableBuffer[2 * cSize + pixelIndex] = b / 255.0;
          }
        }
      }
    } else {
      final Uint8List bytes = payload.planeBytes[0];
      final int rowStride = payload.planeBytesPerRow[0];
      final int pixelStride = payload.planeBytesPerPixel[0] ?? 4;
      final int bytesLen = bytes.length;

      for (int y = 0; y < targetScaledH; y++) {
        final int canvasY = startY + y;
        if (canvasY < 0 || canvasY >= th) continue;

        final int yRot = (y * invScale).toInt().clamp(0, rotH - 1);
        final int canvasRowOffset = canvasY * tw;

        for (int x = 0; x < targetScaledW; x++) {
          final int canvasX = startX + x;
          if (canvasX < 0 || canvasX >= tw) continue;

          final int xRot = (x * invScale).toInt().clamp(0, rotW - 1);

          int xRaw;
          int yRaw;
          if (rotation == 90) {
            xRaw = yRot;
            yRaw = rawH - 1 - xRot;
          } else if (rotation == 180) {
            xRaw = rawW - 1 - xRot;
            yRaw = rawH - 1 - yRot;
          } else if (rotation == 270) {
            xRaw = rawW - 1 - yRot;
            yRaw = xRot;
          } else {
            xRaw = xRot;
            yRaw = yRot;
          }

          final int idx = yRaw * rowStride + xRaw * pixelStride;
          if (idx + 2 < bytesLen) {
            final int b = bytes[idx];
            final int g = bytes[idx + 1];
            final int r = bytes[idx + 2];

            final int pixelIndex = canvasRowOffset + canvasX;
            _reusableBuffer[pixelIndex]             = r / 255.0;
            _reusableBuffer[cSize + pixelIndex]     = g / 255.0;
            _reusableBuffer[2 * cSize + pixelIndex] = b / 255.0;
          }
        }
      }
    }

    stopwatch.stop();

    return PreprocessedInput(
      tensorBuffer: Float32List.fromList(_reusableBuffer),
      letterboxInfo: letterbox,
      latencyMs: stopwatch.elapsedMicroseconds / 1000.0,
      imageWidth: rotW,
      imageHeight: rotH,
    );
  }

  Future<PreprocessedInput> processCameraImageIsolate(CameraImagePayload payload) async {
    return processCameraPayloadDirect(payload);
  }
}
