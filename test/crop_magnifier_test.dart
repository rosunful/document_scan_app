import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_documnet_app/widgets/crop_magnifier.dart';

void main() {
  testWidgets(
    'loupe image sits at the preview rect and the finger point maps exactly '
    'to the loupe centre',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const previewSize = Size(400, 600);
      const imageRect = Rect.fromLTWH(40, 80, 320, 440);
      const dragLocal = Offset(150, 200);
      const radius = 90.0;
      const zoom = 3.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              CropMagnifier(
                previewSize: previewSize,
                dragLocal: dragLocal,
                radius: radius,
                zoom: zoom,
                imageChild: Positioned.fromRect(
                  rect: imageRect,
                  child: ColoredBox(
                    key: const Key('magnified-image'),
                    color: Colors.green,
                  ),
                ),
                overlay: const ColoredBox(
                  key: Key('loupe-overlay'),
                  color: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // The magnified source must be laid out at the exact preview rect. Before
      // the fix it was placed outside a Stack, so this Positioned was ignored
      // and the image drifted by the centering offset (the reported
      // "thumb and crop point sit away from the loupe edge point" bug).
      final image = tester.renderObject<RenderBox>(
        find.byKey(const Key('magnified-image')),
      );
      expect(image.size, imageRect.size);
      final parent = image.parent;
      expect(parent, isA<RenderBox>());
      expect(
        image.localToGlobal(Offset.zero, ancestor: parent! as RenderBox),
        imageRect.topLeft,
      );

      // The drag point must land exactly at the loupe centre so the crosshair
      // tracks the thumb/crop point.
      final transform = tester
          .widget<Transform>(find.byType(Transform).first)
          .transform;
      final mapped = MatrixUtils.transformPoint(transform, dragLocal);
      expect(mapped.dx, closeTo(radius, 0.001));
      expect(mapped.dy, closeTo(radius, 0.001));
    },
  );
}