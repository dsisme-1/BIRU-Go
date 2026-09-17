import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/detection.dart';
import '../models/detection_summary.dart';
import '../services/database_helper.dart';
import '../utils/image_utils.dart';
import '../widgets/confidence_badge.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/summary_card.dart';

class ResultScreen extends StatefulWidget {
  final DetectionSummary? summary;
  final Uint8List? imageBytes;
  final List<Detection>? detections;
  final Size? sourceImageSize;
  final String sourceTitle;
  final img.Image? originalImage;

  const ResultScreen({
    super.key,
    this.summary,
    this.imageBytes,
    this.detections,
    this.sourceImageSize,
    this.sourceTitle = 'Detection Results',
    this.originalImage,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _showBoundingBoxes = true;
  bool _isExporting = false;

  List<DetectionSummary> _savedSessions = [];
  bool _isLoadingHistory = true;
  DetectionSource? _selectedFilter;
  final Set<int> _expandedSessionIds = {};

  @override
  void initState() {
    super.initState();
    _loadHistorySessions();
    DatabaseHelper.instance.sessionsVersionNotifier.addListener(_onSessionsUpdated);
  }

  @override
  void dispose() {
    DatabaseHelper.instance.sessionsVersionNotifier.removeListener(_onSessionsUpdated);
    super.dispose();
  }

  void _onSessionsUpdated() {
    if (mounted) {
      _loadHistorySessions();
    }
  }

  Future<void> _loadHistorySessions() async {
    try {
      final sessions = await DatabaseHelper.instance.getAllSessions(
        filterSource: _selectedFilter,
      );
      if (mounted) {
        setState(() {
          _savedSessions = sessions;
          _isLoadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _deleteSession(DetectionSummary session) async {
    if (session.id == null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Record',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
        ),
        content: const Text(
          'Remove this detection record from your history?',
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
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteSession(session.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('Detection record deleted.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _clearAllHistory() async {
    if (_savedSessions.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear All History',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
        ),
        content: const Text(
          'Are you sure you want to delete all saved detection sessions? This action cannot be undone.',
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
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.clearAllSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('All detection history cleared.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _exportAnnotatedPhoto() async {
    if (widget.imageBytes == null) return;

    Uint8List exportBytes;
    if (_showBoundingBoxes &&
        widget.detections != null &&
        widget.detections!.isNotEmpty &&
        widget.originalImage != null) {
      final annotatedImg = ImageUtils.drawAnnotatedImage(
        widget.originalImage!,
        widget.detections!,
      );
      exportBytes = Uint8List.fromList(img.encodeJpg(annotatedImg, quality: 95));
    } else {
      exportBytes = widget.imageBytes!;
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
      _isExporting = true;
    });

    try {
      final savedPath = await ImageUtils.saveImageToDevice(
        bytes: exportBytes,
        prefix: _showBoundingBoxes ? 'BIRU_annotated' : 'BIRU_result',
      );

      final String fileName = savedPath.split(Platform.pathSeparator).last;
      final String speciesSummaryText = widget.detections != null && widget.detections!.isNotEmpty
          ? widget.detections!.map((d) => '${d.className} (${d.confidencePercent})').join(', ')
          : 'None';
      final double topConf = widget.detections != null && widget.detections!.isNotEmpty
          ? widget.detections!.first.confidence
          : 0.0;

      await DatabaseHelper.instance.insertExport(
        ExportRecord(
          filePath: savedPath,
          fileName: fileName,
          fileHash: fileHash,
          sourceType: 'result_photo',
          speciesSummary: speciesSummaryText,
          confidenceScore: topConf,
          timestamp: DateTime.now(),
        ),
      );

      if (mounted) {
        setState(() {
          _isExporting = false;
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
          _isExporting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to export image: $e'),
          ),
        );
      }
    }
  }

  IconData _getSourceIcon(DetectionSource source) {
    switch (source) {
      case DetectionSource.liveCamera:
        return Icons.videocam_rounded;
      case DetectionSource.localVideo:
        return Icons.movie_filter_outlined;
      case DetectionSource.photoGallery:
        return Icons.photo_library_outlined;
    }
  }

  Color _getSourceColor(DetectionSource source) {
    switch (source) {
      case DetectionSource.liveCamera:
        return const Color(0xFF0066FF);
      case DetectionSource.localVideo:
        return const Color(0xFF6366F1);
      case DetectionSource.photoGallery:
        return const Color(0xFF0284C7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasActivePhoto = widget.imageBytes != null;
    final bool hasDetections = widget.detections != null && widget.detections!.isNotEmpty;
    final Size imageSize = widget.sourceImageSize ?? const Size(640, 640);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          hasActivePhoto ? widget.sourceTitle : 'Detection Results',
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
          if (hasActivePhoto)
            IconButton(
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0066FF),
                      ),
                    )
                  : const Icon(Icons.file_download_outlined),
              tooltip: 'Save Image to Gallery',
              onPressed: _isExporting ? null : _exportAnnotatedPhoto,
            ),
          if (!hasActivePhoto && _savedSessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFF64748B)),
              tooltip: 'Clear All History',
              onPressed: _clearAllHistory,
            ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF0066FF),
        onRefresh: _loadHistorySessions,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (hasActivePhoto) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        widget.imageBytes!,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                      if (hasDetections && _showBoundingBoxes)
                        Positioned.fill(
                          child: DetectionOverlay(
                            detections: widget.detections!,
                            sourceImageSize: imageSize,
                            fit: BoxFit.cover,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              if (hasDetections)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
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
                ),

              if (widget.summary != null)
                SummaryCard(summary: widget.summary!),

              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Past Detection History',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],

            _buildFilterChipsBar(),

            if (_isLoadingHistory)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0066FF)),
                ),
              )
            else if (_savedSessions.isEmpty)
              _buildEmptyState()
            else
              ..._savedSessions.map((session) => _buildSessionCard(session)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChipsBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip(
            label: 'All (${_savedSessions.length})',
            isSelected: _selectedFilter == null,
            onSelected: () {
              setState(() => _selectedFilter = null);
              _loadHistorySessions();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Live Camera',
            icon: Icons.videocam_rounded,
            isSelected: _selectedFilter == DetectionSource.liveCamera,
            onSelected: () {
              setState(() => _selectedFilter = DetectionSource.liveCamera);
              _loadHistorySessions();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Photo & Gallery',
            icon: Icons.photo_library_outlined,
            isSelected: _selectedFilter == DetectionSource.photoGallery,
            onSelected: () {
              setState(() => _selectedFilter = DetectionSource.photoGallery);
              _loadHistorySessions();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0066FF) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0066FF) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(DetectionSummary session) {
    final int sessionId = session.id ?? session.sessionTimestamp.millisecondsSinceEpoch;
    final bool isExpanded = _expandedSessionIds.contains(sessionId);
    final Color sourceColor = _getSourceColor(session.source);
    final bool hasImage = session.imagePath != null && File(session.imagePath!).existsSync();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: sourceColor.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedSessionIds.remove(sessionId);
              } else {
                _expandedSessionIds.add(sessionId);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: sourceColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getSourceIcon(session.source),
                        color: sourceColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.sourceTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${session.formattedDate} • ${session.formattedTime}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: session.speciesList.isNotEmpty
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : const Color(0xFF64748B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        session.speciesList.isNotEmpty
                            ? '${session.speciesList.length} Species'
                            : '0 Birds',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: session.speciesList.isNotEmpty
                              ? const Color(0xFF059669)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                      tooltip: 'Delete record',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _deleteSession(session),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (session.speciesList.isNotEmpty) ...[
                  Row(
                    children: [
                      if (hasImage)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(session.imagePath!),
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.flutter_dash,
                            size: 18,
                            color: Color(0xFF0066FF),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.speciesList.first.speciesName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${session.totalDetections} total detection${session.totalDetections == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConfidenceBadge(
                        confidence: session.speciesList.first.highestConfidence,
                        compact: true,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: const Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ],
                  ),
                ],

                if (isExpanded && session.speciesList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 8),
                  ...session.speciesList.map((sp) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.flutter_dash,
                              size: 14,
                              color: Color(0xFF0066FF),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                sp.speciesName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Text(
                              '${sp.detectionCount}×',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConfidenceBadge(
                              confidence: sp.highestConfidence,
                              compact: true,
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: Color(0xFF94A3B8),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Detection History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your bird detections from live camera and photos will be saved here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
