import 'package:camera/camera.dart';

/// Thrown when cameras can't be loaded or accessed (no hardware, permission
/// denied, a native-side error) so the UI can show a real message instead
/// of failing silently.
class CameraServiceException implements Exception {
  final String message;
  CameraServiceException(this.message);

  @override
  String toString() => message;
}

class CameraService {
  CameraService._();

  /// Loads the device's cameras. Throws [CameraServiceException] if none
  /// are available or the platform denies access.
  static Future<List<CameraDescription>> loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraServiceException('No camera was found on this device.');
      }
      return cameras;
    } on CameraException catch (e) {
      throw CameraServiceException(e.description ?? 'Could not access the camera.');
    }
  }

  /// Prefers the rear camera for document scanning; falls back to
  /// whatever's first (e.g. front-only devices, some emulators).
  static CameraDescription pickRearCamera(List<CameraDescription> cameras) {
    return cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
  }
}