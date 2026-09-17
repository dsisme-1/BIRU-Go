import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraView extends StatelessWidget {
  final CameraController controller;
  final Widget? overlay;

  const CameraView({
    super.key,
    required this.controller,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0066FF)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cameraAspect = controller.value.aspectRatio;
        final bool isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final double previewAspect =
            isPortrait ? (1.0 / cameraAspect) : cameraAspect;

        final double targetW = isPortrait
            ? constraints.maxHeight * previewAspect
            : constraints.maxWidth;
        final double targetH = isPortrait
            ? constraints.maxHeight
            : constraints.maxWidth / previewAspect;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: targetW,
                  height: targetH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      ?overlay,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

