import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import 'camera_pervious_screen.dart';

enum _ScreenState { loading, ready, error }

/// Custom document-capture camera. Pops with a `List<String>` of captured
/// page file paths when the user taps Done, or `null` if they cancel
/// without capturing anything.
class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({super.key});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();

  CameraController? _controller;
  _ScreenState _state = _ScreenState.loading;
  String _errorMessage = '';
  bool _torchOn = false;
  bool _isCapturing = false;
  final List<String> _capturedPages = [];

  // Set while the user is retaking a specific page from the review screen —
  // the next capture replaces that page instead of appending a new one.
  int? _retakeIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // Release the camera when the app is backgrounded and re-acquire it when
  // it returns, or the OS may kill the session (or leave it locked) while
  // you're away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (appState == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (appState == AppLifecycleState.resumed) {
      _setup();
    }
  }

  Future<void> _setup() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final cameras = await CameraService.loadCameras();
      final camera = CameraService.pickRearCamera(cameras);
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _state = _ScreenState.ready;
      });
    } on CameraServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _state = _ScreenState.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not open the camera. Check that permission is granted.';
        _state = _ScreenState.error;
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {
      // Some devices/emulators don't support torch mode — fail quietly.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final file = await controller.takePicture();
      setState(() {
        final retakeIndex = _retakeIndex;
        if (retakeIndex != null) {
          _capturedPages.insert(retakeIndex.clamp(0, _capturedPages.length), file.path);
          _retakeIndex = null;
        } else {
          _capturedPages.add(file.path);
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture the photo. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Opens the gallery, then hands the picked photo straight to the crop
  /// screen. Image enhancement (B&W, contrast, etc.) is a later step —
  /// cropping is all we do here for now.
  Future<void> _pickFromGallery() async {
    final colors = context.myAppColors;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (picked == null || !mounted) return; // user cancelled the picker

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Document',
            toolbarColor: colors.cardColor,
            toolbarWidgetColor: colors.headingTextColor,
            activeControlsWidgetColor: colors.buttonColor,
            backgroundColor: colors.backgroundColor,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Document',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: false,
          ),
        ],
      );

      if (cropped == null || !mounted) return; // user cancelled the crop
      setState(() => _capturedPages.add(cropped.path));
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not access your photos.')),
        );
      }
    }
  }

  void _removePage(int index) => setState(() => _capturedPages.removeAt(index));

  Future<void> _openPageReview(int index) async {
    final result = await Navigator.of(context).push<ReviewResult>(
      MaterialPageRoute(
        builder: (_) => PageReviewScreen(imagePaths: List.of(_capturedPages), initialIndex: index),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      switch (result.type) {
        case ReviewResultType.retake:
          _capturedPages.removeAt(result.index);
          _retakeIndex = result.index;
          break;
        case ReviewResultType.delete:
          _capturedPages.removeAt(result.index);
          break;
      }
    });
  }

  void _reorderPages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final page = _capturedPages.removeAt(oldIndex);
      _capturedPages.insert(newIndex, page);
    });
  }

  void _finish() => Navigator.of(context).pop(List<String>.from(_capturedPages));

  void _cancel() {
    Navigator.of(context).pop(_capturedPages.isEmpty ? null : _capturedPages);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        body: SafeArea(
          child: switch (_state) {
            _ScreenState.loading => const Center(child: CircularProgressIndicator()),
            _ScreenState.error => _buildError(colors),
            _ScreenState.ready => _buildCamera(colors),
          },
        ),
      ),
    );
  }

  Widget _buildError(CustomAppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.no_photography_rounded, color: colors.descriptionColor, size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.headingTextColor, fontSize: 15),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: TextStyle(color: colors.descriptionColor)),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: colors.buttonColor, foregroundColor: Colors.white),
                onPressed: _setup,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCamera(CustomAppColors colors) {
    final controller = _controller!;

    return Column(
      children: [
        // Top bar: close, title, flash toggle.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundIconButton(icon: Icons.close_rounded, onTap: _cancel, colors: colors),
              Text(
                'Scan Document',
                style: TextStyle(color: colors.headingTextColor, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              _RoundIconButton(
                icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                onTap: _toggleTorch,
                colors: colors,
              ),
            ],
          ),
        ),

        // Boxed live preview — intentionally not full screen.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  _BoxedCameraPreview(controller: controller),
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.86,
                      heightFactor: 0.86,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_isCapturing) Container(color: Colors.black26),
                ],
              ),
            ),
          ),
        ),

        // Everything below the preview shares the remaining space.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _retakeIndex != null
                    ? 'Retaking page ${_retakeIndex! + 1} — capture to replace it'
                    : _capturedPages.isEmpty
                        ? 'Align document in frame'
                        : '${_capturedPages.length} page${_capturedPages.length == 1 ? '' : 's'} captured',
                style: TextStyle(color: colors.descriptionColor, fontSize: 12.5),
              ),
              if (_capturedPages.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    onReorder: _reorderPages,
                    itemCount: _capturedPages.length,
                    itemBuilder: (context, i) {
                      final path = _capturedPages[i];
                      return ReorderableDragStartListener(
                        key: ValueKey(path),
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _PageThumbnail(
                            path: path,
                            onTap: () => _openPageReview(i),
                            onRemove: () => _removePage(i),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        // Bottom controls: Done, shutter, gallery import.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 56,
                child: _capturedPages.isNotEmpty
                    ? TextButton(
                        onPressed: _finish,
                        child: Text(
                          'Done',
                          style: TextStyle(color: colors.buttonColor, fontWeight: FontWeight.w700),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.buttonColor, width: 4),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isCapturing ? colors.descriptionColor : colors.buttonColor,
                    ),
                  ),
                ),
              ),
              _RoundIconButton(icon: Icons.photo_library_rounded, onTap: _pickFromGallery, colors: colors, size: 48),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fills its bounding box with the camera feed (cropping to fit) rather
/// than letterboxing it, whatever size that box is.
class _BoxedCameraPreview extends StatelessWidget {
  final CameraController controller;

  const _BoxedCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxAspect = constraints.maxWidth / constraints.maxHeight;
        var scale = boxAspect * controller.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;
        return Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(controller)),
        );
      },
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final CustomAppColors colors;
  final double size;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.colors,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.cardColor,
          border: Border.all(color: colors.borderColor),
        ),
        child: Icon(icon, color: colors.headingTextColor, size: size * 0.48),
      ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final String path;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PageThumbnail({required this.path, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(path), width: 44, height: 56, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black87),
              child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}











// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:image_cropper/image_cropper.dart';
// import 'package:image_picker/image_picker.dart';
// import '../services/scan_service.dart';
// import '../theme/app_theme.dart';

// enum _ScreenState { loading, ready, error }

// /// Custom document-capture camera. Pops with a `List<String>` of captured
// /// page file paths when the user taps Done, or `null` if they cancel
// /// without capturing anything.
// class CustomCameraScreen extends StatefulWidget {
//   const CustomCameraScreen({super.key});

//   @override
//   State<CustomCameraScreen> createState() => _CustomCameraScreenState();
// }

// class _CustomCameraScreenState extends State<CustomCameraScreen> with WidgetsBindingObserver {
//   final ImagePicker _picker = ImagePicker();

//   CameraController? _controller;
//   _ScreenState _state = _ScreenState.loading;
//   String _errorMessage = '';
//   bool _torchOn = false;
//   bool _isCapturing = false;
//   final List<String> _capturedPages = [];

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _setup();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _controller?.dispose();
//     super.dispose();
//   }

//   // Release the camera when the app is backgrounded and re-acquire it when
//   // it returns, or the OS may kill the session (or leave it locked) while
//   // you're away.
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState appState) {
//     final controller = _controller;
//     if (controller == null || !controller.value.isInitialized) return;
//     if (appState == AppLifecycleState.inactive) {
//       controller.dispose();
//     } else if (appState == AppLifecycleState.resumed) {
//       _setup();
//     }
//   }

//   Future<void> _setup() async {
//     setState(() => _state = _ScreenState.loading);
//     try {
//       final cameras = await CameraService.loadCameras();
//       final camera = CameraService.pickRearCamera(cameras);
//       final controller = CameraController(
//         camera,
//         ResolutionPreset.high,
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.jpeg,
//       );
//       await controller.initialize();
//       if (!mounted) return;
//       setState(() {
//         _controller = controller;
//         _state = _ScreenState.ready;
//       });
//     } on CameraServiceException catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _errorMessage = e.message;
//         _state = _ScreenState.error;
//       });
//     } catch (_) {
//       if (!mounted) return;
//       setState(() {
//         _errorMessage = 'Could not open the camera. Check that permission is granted.';
//         _state = _ScreenState.error;
//       });
//     }
//   }

//   Future<void> _toggleTorch() async {
//     final controller = _controller;
//     if (controller == null) return;
//     final next = !_torchOn;
//     try {
//       await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
//       setState(() => _torchOn = next);
//     } catch (_) {
//       // Some devices/emulators don't support torch mode — fail quietly.
//     }
//   }

//   Future<void> _capture() async {
//     final controller = _controller;
//     if (controller == null || !controller.value.isInitialized || _isCapturing) return;
//     setState(() => _isCapturing = true);
//     try {
//       final file = await controller.takePicture();
//       setState(() => _capturedPages.add(file.path));
//     } catch (_) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Could not capture the photo. Try again.')),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _isCapturing = false);
//     }
//   }

//   /// Opens the gallery, then hands the picked photo straight to the crop
//   /// screen. Image enhancement (B&W, contrast, etc.) is a later step —
//   /// cropping is all we do here for now.
//   Future<void> _pickFromGallery() async {
//     final colors = context.myAppColors;
//     try {
//       final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
//       if (picked == null || !mounted) return; // user cancelled the picker

//       final cropped = await ImageCropper().cropImage(
//         sourcePath: picked.path,
//         compressQuality: 90,
//         uiSettings: [
//           AndroidUiSettings(
//             toolbarTitle: 'Crop Document',
//             toolbarColor: colors.cardColor,
//             toolbarWidgetColor: colors.headingTextColor,
//             activeControlsWidgetColor: colors.buttonColor,
//             backgroundColor: colors.backgroundColor,
//             lockAspectRatio: false,
//           ),
//           IOSUiSettings(
//             title: 'Crop Document',
//             doneButtonTitle: 'Done',
//             cancelButtonTitle: 'Cancel',
//             aspectRatioLockEnabled: false,
//           ),
//         ],
//       );

//       if (cropped == null || !mounted) return; // user cancelled the crop
//       setState(() => _capturedPages.add(cropped.path));
//     } on PlatformException catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text(e.message ?? 'Could not access your photos.')),
//         );
//       }
//     }
//   }

//   void _removePage(int index) => setState(() => _capturedPages.removeAt(index));

//   void _finish() => Navigator.of(context).pop(List<String>.from(_capturedPages));

//   void _cancel() {
//     Navigator.of(context).pop(_capturedPages.isEmpty ? null : _capturedPages);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final colors = context.myAppColors;

//     return PopScope(
//       canPop: false,
//       onPopInvoked: (didPop) {
//         if (!didPop) _cancel();
//       },
//       child: Scaffold(
//         backgroundColor: colors.backgroundColor,
//         body: SafeArea(
//           child: switch (_state) {
//             _ScreenState.loading => const Center(child: CircularProgressIndicator()),
//             _ScreenState.error => _buildError(colors),
//             _ScreenState.ready => _buildCamera(colors),
//           },
//         ),
//       ),
//     );
//   }

//   Widget _buildError(CustomAppColors colors) {
//     return Padding(
//       padding: const EdgeInsets.all(24),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.no_photography_rounded, color: colors.descriptionColor, size: 48),
//           const SizedBox(height: 16),
//           Text(
//             _errorMessage,
//             textAlign: TextAlign.center,
//             style: TextStyle(color: colors.headingTextColor, fontSize: 15),
//           ),
//           const SizedBox(height: 20),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               TextButton(
//                 onPressed: () => Navigator.of(context).pop(),
//                 child: Text('Cancel', style: TextStyle(color: colors.descriptionColor)),
//               ),
//               const SizedBox(width: 12),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(backgroundColor: colors.buttonColor, foregroundColor: Colors.white),
//                 onPressed: _setup,
//                 child: const Text('Try Again'),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCamera(CustomAppColors colors) {
//     final controller = _controller!;

//     return Column(
//       children: [
//         // Top bar: close, title, flash toggle.
//         Padding(
//           padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               _RoundIconButton(icon: Icons.close_rounded, onTap: _cancel, colors: colors),
//               // Text(
//               //   'Scan Document',
//               //   style: TextStyle(color: colors.headingTextColor, fontWeight: FontWeight.w700, fontSize: 15),
//               // ),
//               _RoundIconButton(
//                 icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
//                 onTap: _toggleTorch,
//                 colors: colors,
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 60,),

//         // Boxed live preview — intentionally not full screen.
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 32),
//           child: AspectRatio(
//             aspectRatio: 3 / 4,
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(20),
//               child: Stack(
//                 fit: StackFit.expand,
//                 children: [
//                   Container(color: Colors.black),
//                   _BoxedCameraPreview(controller: controller),
//                   Center(
//                     child: FractionallySizedBox(
//                       widthFactor: 0.86,
//                       heightFactor: 0.86,
//                       // child: DecoratedBox(
//                       //   decoration: BoxDecoration(
//                       //     border: Border.all(color: Colors.white70, width: 2),
//                       //     borderRadius: BorderRadius.circular(12),
//                       //   ),
//                       // ),
//                     ),
//                   ),
//                   if (_isCapturing) Container(color: Colors.black26),
//                 ],
//               ),
//             ),
//           ),
//         ),

//         // Everything below the preview shares the remaining space.
//         Expanded(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Text(
//                 _capturedPages.isEmpty
//                     ? 'Align document in frame'
//                     : '${_capturedPages.length} page${_capturedPages.length == 1 ? '' : 's'} captured',
//                 style: TextStyle(color: colors.descriptionColor, fontSize: 12.5),
//               ),
//               if (_capturedPages.isNotEmpty) ...[
//                 const SizedBox(height: 12),
//                 SizedBox(
//                   height: 56,
//                   child: ListView.separated(
//                     scrollDirection: Axis.horizontal,
//                     padding: const EdgeInsets.symmetric(horizontal: 24),
//                     itemCount: _capturedPages.length,
//                     separatorBuilder: (_, __) => const SizedBox(width: 8),
//                     itemBuilder: (context, i) => _PageThumbnail(
//                       path: _capturedPages[i],
//                       onRemove: () => _removePage(i),
//                     ),
//                   ),
//                 ),
//               ],
//             ],
//           ),
//         ),

//         // Bottom controls: Done, shutter, gallery import.
//         Padding(
//           padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               SizedBox(
//                 width: 56,
//                 child: _capturedPages.isNotEmpty
//                     ? TextButton(
//                         onPressed: _finish,
//                         child: Text(
//                           'Done',
//                           style: TextStyle(color: colors.buttonColor, fontWeight: FontWeight.w700),
//                         ),
//                       )
//                     : const SizedBox.shrink(),
//               ),
//               GestureDetector(
//                 onTap: _isCapturing ? null : _capture,
//                 child: Container(
//                   width: 72,
//                   height: 72,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     border: Border.all(color: colors.buttonColor, width: 4),
//                   ),
//                   padding: const EdgeInsets.all(4),
//                   child: DecoratedBox(
//                     decoration: BoxDecoration(
//                       shape: BoxShape.circle,
//                       color: _isCapturing ? colors.descriptionColor : colors.buttonColor,
//                     ),
//                   ),
//                 ),
//               ),
//               _RoundIconButton(icon: Icons.photo_library_rounded, onTap: _pickFromGallery, colors: colors, size: 48),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// /// Fills its bounding box with the camera feed (cropping to fit) rather
// /// than letterboxing it, whatever size that box is.
// class _BoxedCameraPreview extends StatelessWidget {
//   final CameraController controller;

//   const _BoxedCameraPreview({required this.controller});

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final boxAspect = constraints.maxWidth / constraints.maxHeight;
//         var scale = boxAspect * controller.value.aspectRatio;
//         if (scale < 1) scale = 1 / scale;
//         return Transform.scale(
//           scale: scale,
//           child: Center(child: CameraPreview(controller)),
//         );
//       },
//     );
//   }
// }

// class _RoundIconButton extends StatelessWidget {
//   final IconData icon;
//   final VoidCallback? onTap;
//   final CustomAppColors colors;
//   final double size;

//   const _RoundIconButton({
//     required this.icon,
//     required this.onTap,
//     required this.colors,
//     this.size = 40,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         width: size,
//         height: size,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           color: colors.cardColor,
//           border: Border.all(color: colors.borderColor),
//         ),
//         child: Icon(icon, color: colors.headingTextColor, size: size * 0.48),
//       ),
//     );
//   }
// }

// class _PageThumbnail extends StatelessWidget {
//   final String path;
//   final VoidCallback onRemove;

//   const _PageThumbnail({required this.path, required this.onRemove});

//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       clipBehavior: Clip.none,
//       children: [
//         ClipRRect(
//           borderRadius: BorderRadius.circular(8),
//           child: Image.file(File(path), width: 44, height: 56, fit: BoxFit.cover),
//         ),
//         Positioned(
//           top: -6,
//           right: -6,
//           child: GestureDetector(
//             onTap: onRemove,
//             child: Container(
//               width: 18,
//               height: 18,
//               decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black87),
//               child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }





