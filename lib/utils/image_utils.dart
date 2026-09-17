import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/detection.dart';

class ImageUtils {
  static img.Image drawAnnotatedImage(img.Image baseImage, List<Detection> detections) {
    final annotated = img.Image.from(baseImage);
    final boxColor = img.ColorRgb8(0, 102, 255);
    final pillBg = img.ColorRgb8(15, 23, 42);
    final textColor = img.ColorRgb8(255, 255, 255);

    for (final det in detections) {
      final x1 = (det.normalizedBox.left * annotated.width).round().clamp(0, annotated.width - 1);
      final y1 = (det.normalizedBox.top * annotated.height).round().clamp(0, annotated.height - 1);
      final x2 = (det.normalizedBox.right * annotated.width).round().clamp(0, annotated.width - 1);
      final y2 = (det.normalizedBox.bottom * annotated.height).round().clamp(0, annotated.height - 1);

      if (x2 <= x1 || y2 <= y1) continue;

      img.drawRect(
        annotated,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: boxColor,
        thickness: 3,
      );

      final label = '${det.className} ${det.confidencePercent}';
      final font = img.arial14;
      final textWidth = label.length * 9;
      const textHeight = 18;
      final pillW = textWidth + 12;
      final pillH = textHeight + 6;

      int pillY = y1 - pillH - 2;
      if (pillY < 0) pillY = y1 + 2;
      int pillX = x1;
      if (pillX + pillW > annotated.width) pillX = annotated.width - pillW;
      if (pillX < 0) pillX = 0;

      img.fillRect(
        annotated,
        x1: pillX,
        y1: pillY,
        x2: (pillX + pillW).clamp(0, annotated.width - 1),
        y2: (pillY + pillH).clamp(0, annotated.height - 1),
        color: pillBg,
      );

      img.drawString(
        annotated,
        label,
        font: font,
        x: pillX + 6,
        y: pillY + 3,
        color: textColor,
      );
    }

    return annotated;
  }

  static Future<String> saveImageToDevice({
    required Uint8List bytes,
    String prefix = 'BIRU_detection',
  }) async {
    Directory? targetDir;
    try {
      if (Platform.isAndroid) {
        final picturesDir = Directory('/storage/emulated/0/Pictures/BIRU');
        if (!await picturesDir.exists()) {
          await picturesDir.create(recursive: true);
        }
        targetDir = picturesDir;
      }
    } catch (_) {}

    if (targetDir == null) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final biruDir = Directory('${extDir.path}/BIRU');
          if (!await biruDir.exists()) {
            await biruDir.create(recursive: true);
          }
          targetDir = biruDir;
        }
      } catch (_) {}
    }

    targetDir ??= await getApplicationDocumentsDirectory();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${targetDir.path}/${prefix}_$timestamp.jpg';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  static img.Image? decodeImageBytes(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return img.bakeOrientation(decoded);
    } catch (_) {
      return null;
    }
  }

  static img.Image convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      return _convertYUV420ToImage(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888ToImage(image);
    } else {
      return _convertYUV420ToImage(image);
    }
  }

  static img.Image convertCameraImageData({
    required int width,
    required int height,
    required String format,
    required List<Uint8List> planeBytes,
    required List<int> planeBytesPerRow,
    required List<int?> planeBytesPerPixel,
  }) {
    if (format == 'yuv420' || planeBytes.length >= 3) {
      return _convertYUV420ToImageRaw(
        width: width,
        height: height,
        yBytes: planeBytes[0],
        uBytes: planeBytes[1],
        vBytes: planeBytes[2],
        yRowStride: planeBytesPerRow[0],
        uvRowStride: planeBytesPerRow[1],
        uvPixelStride: planeBytesPerPixel[1] ?? 1,
      );
    } else if (format == 'bgra8888') {
      return _convertBGRA8888ToImageRaw(
        width: width,
        height: height,
        bytes: planeBytes[0],
      );
    } else {
      return _convertYUV420ToImageRaw(
        width: width,
        height: height,
        yBytes: planeBytes[0],
        uBytes: planeBytes[1],
        vBytes: planeBytes[2],
        yRowStride: planeBytesPerRow[0],
        uvRowStride: planeBytesPerRow[1],
        uvPixelStride: planeBytesPerPixel[1] ?? 1,
      );
    }
  }

  static img.Image _convertYUV420ToImage(CameraImage image) {
    return _convertYUV420ToImageRaw(
      width: image.width,
      height: image.height,
      yBytes: image.planes[0].bytes,
      uBytes: image.planes[1].bytes,
      vBytes: image.planes[2].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
  }

  static img.Image _convertYUV420ToImageRaw({
    required int width,
    required int height,
    required Uint8List yBytes,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final int yLen = yBytes.length;
    final int uLen = uBytes.length;
    final int vLen = vBytes.length;

    final Uint8List rgbaBuffer = Uint8List(width * height * 4);

    int pixelIdx = 0;
    for (int y = 0; y < height; y++) {
      final int yRowOffset = y * yRowStride;
      final int uvRow = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final int yIndex = yRowOffset + x;
        if (yIndex >= yLen) break;

        final int yVal = yBytes[yIndex] & 0xFF;
        final int uvCol = (x >> 1) * uvPixelStride;
        final int uvIndex = uvRow + uvCol;

        int uVal = 0;
        int vVal = 0;
        if (uvIndex < uLen && uvIndex < vLen) {
          uVal = (uBytes[uvIndex] & 0xFF) - 128;
          vVal = (vBytes[uvIndex] & 0xFF) - 128;
        }

        int r = yVal + ((1370705 * vVal) >> 20);
        int g = yVal - ((337633 * uVal + 698001 * vVal) >> 20);
        int b = yVal + ((1732446 * uVal) >> 20);

        rgbaBuffer[pixelIdx]     = r.clamp(0, 255);
        rgbaBuffer[pixelIdx + 1] = g.clamp(0, 255);
        rgbaBuffer[pixelIdx + 2] = b.clamp(0, 255);
        rgbaBuffer[pixelIdx + 3] = 255;
        pixelIdx += 4;
      }
    }

    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbaBuffer.buffer,
      order: img.ChannelOrder.rgba,
    );
  }

  static img.Image _convertBGRA8888ToImage(CameraImage image) {
    return _convertBGRA8888ToImageRaw(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes,
    );
  }

  static img.Image _convertBGRA8888ToImageRaw({
    required int width,
    required int height,
    required Uint8List bytes,
  }) {
    final Uint8List rgbaBuffer = Uint8List(width * height * 4);
    for (int i = 0, j = 0; i < bytes.length - 3; i += 4, j += 4) {
      rgbaBuffer[j]     = bytes[i + 2];
      rgbaBuffer[j + 1] = bytes[i + 1];
      rgbaBuffer[j + 2] = bytes[i];
      rgbaBuffer[j + 3] = 255;
    }

    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbaBuffer.buffer,
      order: img.ChannelOrder.rgba,
    );
  }
}
