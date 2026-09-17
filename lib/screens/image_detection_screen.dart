import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../models/detection.dart';
import '../models/detection_summary.dart';
import '../services/database_helper.dart';
import '../services/detector_service.dart';
import '../services/model_loader.dart';
import '../utils/image_utils.dart';
import '../widgets/detection_card.dart';
import '../widgets/detection_overlay.dart';
import 'result_screen.dart';

enum ImageSourceMode {
  camera,
  gallery,
}

class ImageDetectionScreen extends StatefulWidget {
  final img.Image? image;
  final String sourceTitle;
  final ImageSourceMode sourceMode;

  const ImageDetectionScreen({
    super.key,
    this.image,
    this.sourceTitle = 'Image Detection',
    this.sourceMode = ImageSourceMode.gallery,
  });

  @override
  State<ImageDetectionScreen> createState() => _ImageDetectionScreenState();
}

class _ImageDetectionScreenState extends State<ImageDetectionScreen> {
  final DetectorService _detectorService = DetectorService();
  final ImagePicker _picker = ImagePicker();

  img.Image? _currentImage;
  Uint8List? _imageBytes;
  List<Detection> _detections = [];
  bool _isProcessing = false;
  bool _isSavingImage = false;
  bool _showBoundingBoxes = true;
  String? _errorMessage;
  int _rotationAngle = 0;
  int? _currentSessionId;

  @override
  void initState() {
    super.initState();
    _detectorService.switchModel(ModelLoader.photoModelAssetPath);

    if (widget.image != null) {
      _currentImage = widget.image;
      _imageBytes = Uint8List.fromList(img.encodeJpg(_currentImage!));
    } else {
      final source = widget.sourceMode == ImageSourceMode.camera
          ? ImageSource.camera
          : ImageSource.gallery;
      _pickImage(source);
    }
  }

  void _rotateImage() {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
      _detections = [];
    });
  }

  String _getOrientationLabel(int angle) {
    switch (angle) {
      case 90:
        return 'Rotated Right (90°)';
      case 180:
        return 'Upside Down (180°)';
      case 270:
        return 'Rotated Left (270°)';
      case 0:
      default:
        return 'Normal (0°)';
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (pickedFile == null) {
        if (_currentImage == null && mounted) {
          Navigator.pop(context);
        }
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      final decoded = ImageUtils.decodeImageBytes(bytes);

      if (decoded == null) {
        throw Exception('Failed to decode selected image file.');
      }

      final bakedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));

      setState(() {
        _currentImage = decoded;
        _imageBytes = bakedBytes;
        _rotationAngle = 0;
        _detections = [];
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading image: $e';
        });
      }
    }
  }

  Future<void> _runInferenceOnCurrentImage() async {
    if (_currentImage == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await _detectorService.switchModel(ModelLoader.photoModelAssetPath);

      img.Image imageToProcess = _currentImage!;
      if (_rotationAngle != 0) {
        imageToProcess = img.copyRotate(_currentImage!, angle: _rotationAngle);
        final newBytes = Uint8List.fromList(img.encodeJpg(imageToProcess, quality: 95));
        _currentImage = imageToProcess;
        _imageBytes = newBytes;
        _rotationAngle = 0;
      }

      final DetectionResult result =
          await _detectorService.detectImage(imageToProcess);

      if (result.detections.isNotEmpty) {
        final summary = DetectionSummary.fromDetections(
          result.detections,
          source: DetectionSource.photoGallery,
        );
        _detectorService.lastSummary = summary;

        try {
          _currentSessionId = await DatabaseHelper.instance.insertSession(summary);
        } catch (e) {
          debugPrint('[ImageDetectionScreen] Failed to save session to DB: $e');
        }
      }

      if (mounted) {
        setState(() {
          _detections = result.detections;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Inference error: $e';
        });
      }
    }
  }

  Future<void> _exportAnnotatedPhoto() async {
    if (_currentImage == null) return;

    Uint8List exportBytes;
    if (_showBoundingBoxes && _detections.isNotEmpty) {
      final annotatedImg = ImageUtils.drawAnnotatedImage(_currentImage!, _detections);
      exportBytes = Uint8List.fromList(img.encodeJpg(annotatedImg, quality: 95));
    } else {
      exportBytes = _imageBytes ?? Uint8List.fromList(img.encodeJpg(_currentImage!, quality: 95));
    }

    final String fileHash = DatabaseHelper.computeHash(exportBytes);

    final bool isDuplicate = await DatabaseHelper.instance.isAlreadyExported(fileHash);
    if (isDuplicate && mounted) {
      final shouldSaveAgain = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Image Already Saved',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          content: const Text(
            'This image has already been saved to your gallery. Would you like to save another copy?',
            style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0066FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save Copy'),
            ),
          ],
        ),
      );

      if (shouldSaveAgain != true) return;
    }

    setState(() {
      _isSavingImage = true;
    });

    try {
      final savedPath = await ImageUtils.saveImageToDevice(
        bytes: exportBytes,
        prefix: _showBoundingBoxes && _detections.isNotEmpty ? 'BIRU_annotated' : 'BIRU_photo',
      );

      final String fileName = savedPath.split(Platform.pathSeparator).last;
      final String speciesSummaryText = _detections.isNotEmpty
          ? _detections.map((d) => '${d.className} (${d.confidencePercent})').join(', ')
          : 'None';
      final double topConf = _detections.isNotEmpty ? _detections.first.confidence : 0.0;

      await DatabaseHelper.instance.insertExport(
        ExportRecord(
          filePath: savedPath,
          fileName: fileName,
          fileHash: fileHash,
          sourceType: 'photo',
          speciesSummary: speciesSummaryText,
          confidenceScore: topConf,
          timestamp: DateTime.now(),
        ),
      );

      if (_currentSessionId != null) {
        try {
          await DatabaseHelper.instance.updateSessionImagePath(_currentSessionId!, savedPath);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isSavingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved to Pictures/BIRU:\n$fileName',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSavingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to save image: $e'),
          ),
        );
      }
    }
  }

  void _openSummary() {
    if (_detections.isEmpty) return;
    final summary = DetectionSummary.fromDetections(
      _detections,
      source: DetectionSource.photoGallery,
    );
    final Size imageSize = _currentImage != null
        ? Size(_currentImage!.width.toDouble(), _currentImage!.height.toDouble())
        : const Size(640, 640);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(
          summary: summary,
          imageBytes: _imageBytes,
          detections: _detections,
          sourceImageSize: imageSize,
          sourceTitle: widget.sourceTitle,
          originalImage: _currentImage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.sourceTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          if (_currentImage != null && !_isProcessing)
            IconButton(
              icon: _isSavingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0066FF)),
                    )
                  : const Icon(Icons.file_download_outlined),
              tooltip: 'Save Image to Gallery',
              onPressed: _isSavingImage ? null : _exportAnnotatedPhoto,
            ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Choose from Gallery',
            onPressed: () => _pickImage(ImageSource.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Take Photo',
            onPressed: () => _pickImage(ImageSource.camera),
          ),
          if (_detections.isNotEmpty)
            TextButton.icon(
              onPressed: _openSummary,
              icon: const Icon(Icons.analytics_outlined,
                  size: 18, color: Color(0xFF0066FF)),
              label: const Text(
                'Summary',
                style: TextStyle(
                  color: Color(0xFF0066FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (_currentImage != null)
                    ElevatedButton.icon(
                      onPressed: _runInferenceOnCurrentImage,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0066FF),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentImage != null ? Colors.grey.shade200 : const Color(0xFF0066FF),
                      foregroundColor: _currentImage != null ? const Color(0xFF0F172A) : Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0052CC),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_currentImage == null || _imageBytes == null) {
      return const Center(
        child: SizedBox.shrink(),
      );
    }

    final Size imageSize = Size(
      _currentImage!.width.toDouble(),
      _currentImage!.height.toDouble(),
    );

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Container(
            color: const Color(0xFF0F172A),
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  maxScale: 4.0,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: _rotationAngle ~/ 90,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.memory(
                            _imageBytes!,
                            fit: BoxFit.contain,
                          ),
                          if (_showBoundingBoxes && _detections.isNotEmpty)
                            Positioned.fill(
                              child: DetectionOverlay(
                                detections: _detections,
                                sourceImageSize: imageSize,
                                fit: BoxFit.contain,
                                enableAnimation: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_isProcessing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF0066FF)),
                          SizedBox(height: 12),
                          Text(
                            'Running YOLO On-Device Inference (640x640)...',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (!_isProcessing && _currentImage != null && _detections.isNotEmpty)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: FloatingActionButton.small(
                      onPressed: _runInferenceOnCurrentImage,
                      backgroundColor: const Color(0xFF0066FF),
                      tooltip: 'Re-run detection',
                      child: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),

        if (!_isProcessing && _currentImage != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: RotatedBox(
                            quarterTurns: _rotationAngle ~/ 90,
                            child: const Icon(
                              Icons.crop_original,
                              size: 20,
                              color: Color(0xFF0066FF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Orientation',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              _getOrientationLabel(_rotationAngle),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _rotateImage,
                      icon: const Icon(Icons.rotate_right, size: 16),
                      label: const Text('Rotate 90°'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0066FF),
                        side: const BorderSide(color: Color(0xFF0066FF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),

                if (_detections.isNotEmpty) ...[
                  const Divider(height: 16, color: Color(0xFFF1F5F9)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.crop_free_rounded, size: 18, color: Color(0xFF0066FF)),
                          SizedBox(width: 8),
                          Text(
                            'Show Bounding Boxes',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _showBoundingBoxes,
                        activeTrackColor: const Color(0xFF0066FF),
                        onChanged: (val) {
                          setState(() {
                            _showBoundingBoxes = val;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),



        if (_detections.isEmpty && !_isProcessing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _runInferenceOnCurrentImage,
                icon: const Icon(Icons.search, size: 20),
                label: const Text(
                  'Start AI Detection',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),

        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Detections (${_detections.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (_detections.isNotEmpty)
                        TextButton.icon(
                          onPressed: _isSavingImage ? null : _exportAnnotatedPhoto,
                          icon: const Icon(Icons.save_alt_rounded, size: 16),
                          label: const Text('Save Image', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF0066FF),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _detections.isEmpty
                      ? Center(
                          child: Text(
                            _isProcessing
                                ? 'Analyzing image with BIRU AI...'
                                : 'Ready to detect. Adjust orientation if needed, then tap Start AI Detection.',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _detections.length,
                          itemBuilder: (context, index) {
                            final item = _detections[index];
                            return DetectionCard(
                              detection: item,
                              index: index,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
