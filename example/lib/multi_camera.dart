import 'dart:io';
import 'dart:math';

import 'package:camera_app/utils/file_utils.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const CameraAwesomeApp());
}

class CameraAwesomeApp extends StatelessWidget {
  const CameraAwesomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'camerAwesome',
      // home: CameraPage(),
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (context) => const MainPage(),
          );
        } else if (settings.name == '/gallery') {
          final multipleCaptureRequest =
              settings.arguments as MultipleCaptureRequest;
          return MaterialPageRoute(
            builder: (context) => GalleryPage(
              multipleCaptureRequest: multipleCaptureRequest,
            ),
          );
        }
        return null;
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool isMulti = true;
  bool isBack = true;
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Row(
            children: [
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isMulti = true;
                  });
                },
                child: const Text('Both Camera'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isMulti = false;
                    isBack = false;
                  });
                },
                child: const Text('Front Camera'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isMulti = false;
                    isBack = true;
                  });
                },
                child: const Text('Back Camera'),
              ),
            ],
          ),
          Expanded(
              child: isMulti
                  ? const CameraPage()
                  : CameraPageSingle(
                      isBack: isBack,
                    ))
        ],
      ),
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  SensorDeviceData? sensorDeviceData;
  bool? isMultiCamSupported;
  PipShape shape = PipShape.circle;

  @override
  void initState() {
    super.initState();

    CamerawesomePlugin.getSensors().then((value) {
      setState(() {
        sensorDeviceData = value;
      });
    });

    CamerawesomePlugin.isMultiCamSupported().then((value) {
      setState(() {
        debugPrint("📸 isMultiCamSupported: $value");
        isMultiCamSupported = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: sensorDeviceData != null && isMultiCamSupported != null
            ? CameraAwesomeBuilder.awesome(
                saveConfig: SaveConfig.photoAndVideo(
                    // initialCaptureMode: CaptureMode.video,
                    ),
                sensorConfig: isMultiCamSupported == true
                    ? SensorConfig.multiple(
                        sensors: (Platform.isIOS)
                            ? [
                                Sensor.type(SensorType.wideAngle),
                                Sensor.position(SensorPosition.front),
                              ]
                            : [
                                Sensor.position(SensorPosition.back),
                                Sensor.position(SensorPosition.front),
                              ],
                        flashMode: FlashMode.auto,
                        aspectRatio: CameraAspectRatios.ratio_16_9,
                      )
                    : SensorConfig.single(
                        sensor: Sensor.position(SensorPosition.back),
                        flashMode: FlashMode.auto,
                        aspectRatio: CameraAspectRatios.ratio_16_9,
                      ),
                // TODO: create factory for multi cam & single
                // sensors: sensorDeviceData!.availableSensors
                //     .map((e) => Sensor.id(e.uid))
                //     .toList(),
                previewFit: CameraPreviewFit.fitWidth,
                onMediaTap: (mediaCapture) {
                  mediaCapture.captureRequest.when(
                    single: (single) => single.file?.open(),
                    multiple: (multiple) => Navigator.of(context).pushNamed(
                      '/gallery',
                      arguments: multiple,
                    ),
                  );
                },
                pictureInPictureConfigBuilder: (index, sensor) {
                  const width = 300.0;
                  return PictureInPictureConfig(
                    isDraggable: true,
                    startingPosition: Offset(
                      -50,
                      screenSize.height - 420,
                    ),
                    onTap: () {
                      debugPrint('on preview tap');
                    },
                    sensor: sensor,
                    pictureInPictureBuilder: (preview, aspectRatio) {
                      return SizedBox(
                        width: width,
                        height: width,
                        child: ClipPath(
                          clipper: _MyCustomPipClipper(
                            width: width,
                            height: width * aspectRatio,
                            shape: shape,
                          ),
                          child: SizedBox(
                            width: width,
                            child: preview,
                          ),
                        ),
                      );
                    },
                  );
                },
                previewDecoratorBuilder: (state, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: Colors.white70,
                        margin: const EdgeInsets.only(left: 8),
                        child: const Text("Change picture in picture's shape:"),
                      ),
                      GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 16 / 9,
                        ),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: PipShape.values.length,
                        itemBuilder: (context, index) {
                          final shape = PipShape.values[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                this.shape = shape;
                              });
                            },
                            child: Container(
                              color: Colors.red.withOpacity(0.5),
                              margin: const EdgeInsets.all(8.0),
                              child: Center(
                                child: Text(
                                  shape.name,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class CameraPage2 extends StatefulWidget {
  const CameraPage2({super.key});

  @override
  State<CameraPage2> createState() => _CameraPageState2();
}

class _CameraPageState2 extends State<CameraPage2> {
  SensorDeviceData? sensorDeviceData;
  bool? isMultiCamSupported;
  PipShape shape = PipShape.circle;

  @override
  void initState() {
    super.initState();

    CamerawesomePlugin.getSensors().then((value) {
      setState(() {
        sensorDeviceData = value;
      });
    });

    CamerawesomePlugin.isMultiCamSupported().then((value) {
      setState(() {
        debugPrint("📸 isMultiCamSupported: $value");
        isMultiCamSupported = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: sensorDeviceData != null && isMultiCamSupported != null
            ? CameraAwesomeBuilder.awesome(
                saveConfig: SaveConfig.photoAndVideo(
                    // initialCaptureMode: CaptureMode.video,
                    ),
                sensorConfig: isMultiCamSupported == true
                    ? SensorConfig.multiple(
                        sensors: (Platform.isIOS)
                            ? [
                                Sensor.type(SensorType.wideAngle),
                                Sensor.position(SensorPosition.front),
                              ]
                            : [
                                Sensor.position(SensorPosition.back),
                                Sensor.position(SensorPosition.front),
                              ],
                        flashMode: FlashMode.auto,
                        aspectRatio: CameraAspectRatios.ratio_16_9,
                      )
                    : SensorConfig.single(
                        sensor: Sensor.position(SensorPosition.back),
                        flashMode: FlashMode.auto,
                        aspectRatio: CameraAspectRatios.ratio_16_9,
                      ),
                // TODO: create factory for multi cam & single
                // sensors: sensorDeviceData!.availableSensors
                //     .map((e) => Sensor.id(e.uid))
                //     .toList(),
                previewFit: CameraPreviewFit.fitWidth,
                onMediaTap: (mediaCapture) {
                  mediaCapture.captureRequest.when(
                    single: (single) => single.file?.open(),
                    multiple: (multiple) => Navigator.of(context).pushNamed(
                      '/gallery',
                      arguments: multiple,
                    ),
                  );
                },
                pictureInPictureConfigBuilder: (index, sensor) {
                  const width = 300.0;
                  return PictureInPictureConfig(
                    isDraggable: true,
                    startingPosition: Offset(
                      -50,
                      screenSize.height - 420,
                    ),
                    onTap: () {
                      debugPrint('on preview tap');
                    },
                    sensor: sensor,
                    pictureInPictureBuilder: (preview, aspectRatio) {
                      return SizedBox(
                        width: width,
                        height: width,
                        child: ClipPath(
                          clipper: _MyCustomPipClipper(
                            width: width,
                            height: width * aspectRatio,
                            shape: shape,
                          ),
                          child: SizedBox(
                            width: width,
                            child: preview,
                          ),
                        ),
                      );
                    },
                  );
                },
                previewDecoratorBuilder: (state, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: Colors.white70,
                        margin: const EdgeInsets.only(left: 8),
                        child: const Text("Change picture in picture's shape:"),
                      ),
                      GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 16 / 9,
                        ),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: PipShape.values.length,
                        itemBuilder: (context, index) {
                          final shape = PipShape.values[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                this.shape = shape;
                              });
                            },
                            child: Container(
                              color: Colors.red.withOpacity(0.5),
                              margin: const EdgeInsets.all(8.0),
                              child: Center(
                                child: Text(
                                  shape.name,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class CameraPageSingle extends StatefulWidget {
  final bool isBack;
  const CameraPageSingle({super.key, required this.isBack});

  @override
  State<CameraPageSingle> createState() => _CameraPageSingleState();
}

class _CameraPageSingleState extends State<CameraPageSingle> {
  SensorDeviceData? sensorDeviceData;

  @override
  void initState() {
    super.initState();

    CamerawesomePlugin.getSensors().then((value) {
      setState(() {
        sensorDeviceData = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: sensorDeviceData != null
            ? CameraAwesomeBuilder.awesome(
                saveConfig: SaveConfig.photoAndVideo(
                    // initialCaptureMode: CaptureMode.video,
                    ),
                sensorConfig: SensorConfig.single(
                  sensor: Sensor.position(widget.isBack
                      ? SensorPosition.back
                      : SensorPosition.front),
                  flashMode: FlashMode.auto,
                  aspectRatio: CameraAspectRatios.ratio_16_9,
                ),
                previewFit: CameraPreviewFit.fitWidth,
                onMediaTap: (mediaCapture) {
                  mediaCapture.captureRequest.when(
                    single: (single) => single.file?.open(),
                    multiple: (multiple) => Navigator.of(context).pushNamed(
                      '/gallery',
                      arguments: multiple,
                    ),
                  );
                },
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

enum PipShape {
  square,
  circle,
  roundedSquare,
  triangle,
  hexagon;

  Path getPath(Offset center, double width, double height) {
    switch (this) {
      case PipShape.square:
        return Path()
          ..addRect(Rect.fromCenter(
            center: center,
            width: min(width, height),
            height: min(width, height),
          ));
      case PipShape.circle:
        return Path()
          ..addOval(Rect.fromCenter(
            center: center,
            width: min(width, height),
            height: min(width, height),
          ));
      case PipShape.triangle:
        return Path()
          ..moveTo(center.dx, center.dy - min(width, height) / 2)
          ..lineTo(center.dx + min(width, height) / 2,
              center.dy + min(width, height) / 2)
          ..lineTo(center.dx - min(width, height) / 2,
              center.dy + min(width, height) / 2)
          ..close();
      case PipShape.roundedSquare:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: min(width, height),
              height: min(width, height),
            ),
            const Radius.circular(20.0),
          ));
      case PipShape.hexagon:
        return Path()
          ..moveTo(center.dx, center.dy - min(width, height) / 2)
          ..lineTo(center.dx + min(width, height) / 2,
              center.dy - min(width, height) / 4)
          ..lineTo(center.dx + min(width, height) / 2,
              center.dy + min(width, height) / 4)
          ..lineTo(center.dx, center.dy + min(width, height) / 2)
          ..lineTo(center.dx - min(width, height) / 2,
              center.dy + min(width, height) / 4)
          ..lineTo(center.dx - min(width, height) / 2,
              center.dy - min(width, height) / 4)
          ..close();
    }
  }
}

class _MyCustomPipClipper extends CustomClipper<Path> {
  final double width;
  final double height;
  final PipShape shape;

  const _MyCustomPipClipper({
    required this.width,
    required this.height,
    required this.shape,
  });

  @override
  Path getClip(Size size) {
    return shape.getPath(
      size.center(Offset.zero),
      width,
      height,
    );
  }

  @override
  bool shouldReclip(covariant _MyCustomPipClipper oldClipper) {
    return width != oldClipper.width ||
        height != oldClipper.height ||
        shape != oldClipper.shape;
  }
}

class GalleryPage extends StatefulWidget {
  final MultipleCaptureRequest multipleCaptureRequest;

  const GalleryPage({super.key, required this.multipleCaptureRequest});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
      ),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
        ),
        itemCount: widget.multipleCaptureRequest.fileBySensor.length,
        itemBuilder: (context, index) {
          final sensor =
              widget.multipleCaptureRequest.fileBySensor.keys.toList()[index];
          final file = widget.multipleCaptureRequest.fileBySensor[sensor];
          return GestureDetector(
            onTap: () => file.open(),
            child: file!.path.endsWith("jpg")
                ? Image.file(
                    File(file.path),
                    fit: BoxFit.cover,
                  )
                : VideoPreview(file: File(file.path)),
          );
        },
      ),
    );
  }
}

class VideoPreview extends StatefulWidget {
  final File file;

  const VideoPreview({super.key, required this.file});

  @override
  State<StatefulWidget> createState() {
    return _VideoPreviewState();
  }
}

class _VideoPreviewState extends State<VideoPreview> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..setLooping(true)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _controller.value.isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          : const SizedBox.shrink(),
    );
  }
}
