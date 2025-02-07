//
//  MultiCameraPreview.m
//  camerawesome
//
//  Created by Dimitri Dessus on 28/03/2023.
//

#import "MultiCameraPreview.h"

@implementation MultiCameraPreview

- (instancetype)initWithSensors:(NSArray<PigeonSensor *> *)sensors
                   videoOptions:(nullable CupertinoVideoOptions *)videoOptions
              mirrorFrontCamera:(BOOL)mirrorFrontCamera
           enablePhysicalButton:(BOOL)enablePhysicalButton
                aspectRatioMode:(AspectRatio)aspectRatioMode
                    captureMode:(CaptureModes)captureMode
                  dispatchQueue:(dispatch_queue_t)dispatchQueue {
    if (self = [super init]) {
        _dispatchQueue = dispatchQueue;
        
        _motionController = [[MotionController alloc] init];
        _locationController = [[LocationController alloc] init];
        _physicalButtonController = [[PhysicalButtonController alloc] init];
        _videoController = [[VideoController alloc] init];
        
        _aspectRatio = aspectRatioMode;
        _mirrorFrontCamera = mirrorFrontCamera;
        _videoOptions = videoOptions;
        _captureMode = captureMode;
        
        _textures = [NSMutableArray new];
        _devices = [NSMutableArray new];
        _captureVideoOutputs = [NSMutableArray new];
        _captureVideoInputs = [NSMutableArray new];
        _captureConnections = [NSMutableArray new];
        
        
        if (enablePhysicalButton) {
            [_physicalButtonController startListening];
        }
        
        [_motionController startMotionDetection];
        
        [self configInitialSession:sensors];
    }
    
    return self;
}
- (void)configInitialSession:(NSArray<PigeonSensor *> *)sensors {
    self.cameraSession = [[AVCaptureMultiCamSession alloc] init];
    
    for (int i = 0; i < [sensors count]; i++) {
        CameraPreviewTexture *previewTexture = [[CameraPreviewTexture alloc] init];
        [self.textures addObject:previewTexture];
    }
    
    [self setSensors:sensors];
}
- (void)setSensors:(NSArray<PigeonSensor *> *)sensors {
    [self cleanSession];
    
    _sensors = sensors;
    [_cameraSession beginConfiguration];
    for (int i = 0; i < [sensors count]; i++) {
        PigeonSensor *sensor = sensors[i];
        [self addSensor:sensor withIndex:i];
    }
    [_cameraSession commitConfiguration];
}
- (BOOL)addSensor:(PigeonSensor *)sensor withIndex:(int)index {
    AVCaptureDevice *device = [self selectAvailableCamera:sensor];
    if (device == nil) {
        return NO;
    }
    // AVCaptureDeviceInput
    NSError *error = nil;
    AVCaptureDeviceInput *deviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
    if (error != nil) {
        return NO;
    }
    if (![_cameraSession canAddInput:deviceInput]) {
        return NO;
    }
    [_cameraSession addInputWithNoConnections:deviceInput];
    [_captureVideoInputs addObject:deviceInput];
    
    // AVCaptureVideoDataOutput
    AVCaptureVideoDataOutput *captureVideoOutput = [[AVCaptureVideoDataOutput alloc] init];
    captureVideoOutput.videoSettings = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    [captureVideoOutput setSampleBufferDelegate:self queue:self.dispatchQueue];
    
    if ([_cameraSession canAddOutput:captureVideoOutput]) {
        [_cameraSession addOutputWithNoConnections:captureVideoOutput];
        [_captureVideoOutputs addObject:captureVideoOutput]; // Store output in the array
    } else {
        NSLog(@"Failed to add video output for sensor at index %d.", index);
        return NO;
    }
    // AVCaptureConnection
    AVCaptureInputPort *port = [[deviceInput portsWithMediaType:AVMediaTypeVideo
                                               sourceDeviceType:device.deviceType
                                           sourceDevicePosition:device.position] firstObject];
    AVCaptureConnection *captureConnection = [[AVCaptureConnection alloc] initWithInputPorts:@[port] output:_captureVideoOutputs[index]];
    
    if (![_cameraSession canAddConnection:captureConnection]) {
        return NO;
    }
    [_cameraSession addConnection:captureConnection];
    
    [captureConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    [captureConnection setAutomaticallyAdjustsVideoMirroring:NO];
    [captureConnection setVideoMirrored:sensor.position == PigeonSensorPositionFront];
    [_captureConnections addObject:captureConnection];
    
    // Add photo output
    AVCapturePhotoOutput *capturePhotoOutput = [AVCapturePhotoOutput new];
    [capturePhotoOutput setHighResolutionCaptureEnabled:YES];
    [self.cameraSession addOutput:capturePhotoOutput];
    
    // Store camera device info
    CameraDeviceInfo *cameraDevice = [[CameraDeviceInfo alloc] init];
    cameraDevice.captureConnection = captureConnection;
    cameraDevice.deviceInput = deviceInput;
    cameraDevice.videoDataOutput = _captureVideoOutputs[index];
    cameraDevice.device = device;
    cameraDevice.capturePhotoOutput = capturePhotoOutput;
    
    [_devices addObject:cameraDevice];
    return YES;
}
/// Set orientation stream Flutter sink
- (void)setOrientationEventSink:(FlutterEventSink)orientationEventSink {
    if (_motionController != nil) {
        [_motionController setOrientationEventSink:orientationEventSink];
    }
}

/// Set physical button Flutter sink
- (void)setPhysicalButtonEventSink:(FlutterEventSink)physicalButtonEventSink {
    if (_physicalButtonController != nil) {
        [_physicalButtonController setPhysicalButtonEventSink:physicalButtonEventSink];
    }
}

- (void)dispose {
    [self stop];
    [self cleanSession];
    [self.physicalButtonController stopListening];
}

- (void)stop {
    [self.cameraSession stopRunning];
}

- (void)cleanSession {
    [self.cameraSession beginConfiguration];
    
    for (CameraDeviceInfo *camera in self.devices) {
        [self.cameraSession removeConnection:camera.captureConnection];
        [self.cameraSession removeInput:camera.deviceInput];
        [self.cameraSession removeOutput:camera.videoDataOutput];
        
    }
    for (AVCaptureInput *input in [_cameraSession inputs]) {
        [_cameraSession removeInput:input];
    }
    
    for (AVCaptureOutput *output in [_cameraSession outputs]) {
        [_cameraSession removeOutput:output];
    }
    
    [self.devices removeAllObjects];
    [self.captureVideoOutputs removeAllObjects];
    [self.captureVideoInputs removeAllObjects];
    [self.captureConnections removeAllObjects];
    [self.cameraSession commitConfiguration];
}

// Get max zoom level
- (CGFloat)getMaxZoom {
    CGFloat maxZoom = self.devices.firstObject.device.activeFormat.videoMaxZoomFactor;
    // Not sure why on iPhone 14 Pro, zoom at 90 not working, so let's block to 50 which is very high
    return maxZoom > 50.0 ? 50.0 : maxZoom;
}

/// Set zoom level
- (void)setZoom:(float)value error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    AVCaptureDevice *mainDevice = self.devices.firstObject.device;
    
    CGFloat maxZoom = [self getMaxZoom];
    CGFloat scaledZoom = value * (maxZoom - 1.0f) + 1.0f;
    
    NSError *zoomError;
    if ([mainDevice lockForConfiguration:&zoomError]) {
        mainDevice.videoZoomFactor = scaledZoom;
        [mainDevice unlockForConfiguration];
    } else {
        *error = [FlutterError errorWithCode:@"ZOOM_NOT_SET" message:@"can't set the zoom value" details:[zoomError localizedDescription]];
    }
}

- (void)focusOnPoint:(CGPoint)position preview:(CGSize)preview error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    AVCaptureDevice *mainDevice = self.devices.firstObject.device;
    NSError *lockError;
    if ([mainDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus] && [mainDevice isFocusPointOfInterestSupported]) {
        if ([mainDevice lockForConfiguration:&lockError]) {
            if (lockError != nil) {
                *error = [FlutterError errorWithCode:@"FOCUS_ERROR" message:@"impossible to set focus point" details:@""];
                return;
            }
            
            [mainDevice setFocusPointOfInterest:position];
            [mainDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            
            [mainDevice unlockForConfiguration];
        }
    }
}

- (void)setExifPreferencesGPSLocation:(bool)gpsLocation completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
    _saveGPSLocation = gpsLocation;
    
    if (_saveGPSLocation) {
        [_locationController requestWhenInUseAuthorizationOnGranted:^{
            completion(@(YES), nil);
        } declined:^{
            completion(@(NO), nil);
        }];
    } else {
        completion(@(YES), nil);
    }
}

- (void)setMirrorFrontCamera:(bool)value error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    _mirrorFrontCamera = value;
}

- (void)setBrightness:(NSNumber *)brightness error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    AVCaptureDevice *mainDevice = self.devices.firstObject.device;
    NSError *brightnessError = nil;
    if ([mainDevice lockForConfiguration:&brightnessError]) {
        AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        if ([mainDevice isExposureModeSupported:exposureMode]) {
            [mainDevice setExposureMode:exposureMode];
        }
        
        CGFloat minExposureTargetBias = mainDevice.minExposureTargetBias;
        CGFloat maxExposureTargetBias = mainDevice.maxExposureTargetBias;
        
        CGFloat exposureTargetBias = minExposureTargetBias + (maxExposureTargetBias - minExposureTargetBias) * [brightness floatValue];
        exposureTargetBias = MAX(minExposureTargetBias, MIN(maxExposureTargetBias, exposureTargetBias));
        
        [mainDevice setExposureTargetBias:exposureTargetBias completionHandler:nil];
        [mainDevice unlockForConfiguration];
    } else {
        *error = [FlutterError errorWithCode:@"BRIGHTNESS_NOT_SET" message:@"can't set the brightness value" details:[brightnessError localizedDescription]];
    }
}

/// Set flash mode
- (void)setFlashMode:(CameraFlashMode)flashMode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    AVCaptureDevice *mainDevice = self.devices.firstObject.device;
    
    if (![mainDevice hasFlash]) {
        *error = [FlutterError errorWithCode:@"FLASH_UNSUPPORTED" message:@"flash is not supported on this device" details:@""];
        return;
    }
    
    if (mainDevice.position == AVCaptureDevicePositionFront) {
        *error = [FlutterError errorWithCode:@"FLASH_UNSUPPORTED" message:@"can't set flash for portrait mode" details:@""];
        return;
    }
    
    NSError *lockError;
    [self.devices.firstObject.device lockForConfiguration:&lockError];
    if (lockError != nil) {
        *error = [FlutterError errorWithCode:@"FLASH_ERROR" message:@"impossible to change configuration" details:@""];
        return;
    }
    
    switch (flashMode) {
        case None:
            _torchMode = AVCaptureTorchModeOff;
            _flashMode = AVCaptureFlashModeOff;
            break;
        case On:
            _torchMode = AVCaptureTorchModeOff;
            _flashMode = AVCaptureFlashModeOn;
            break;
        case Auto:
            _torchMode = AVCaptureTorchModeAuto;
            _flashMode = AVCaptureFlashModeAuto;
            break;
        case Always:
            _torchMode = AVCaptureTorchModeOn;
            _flashMode = AVCaptureFlashModeOn;
            break;
        default:
            _torchMode = AVCaptureTorchModeAuto;
            _flashMode = AVCaptureFlashModeAuto;
            break;
    }
    
    [mainDevice setTorchMode:_torchMode];
    [mainDevice unlockForConfiguration];
}

- (void)refresh {
    if ([self.cameraSession isRunning]) {
        [self.cameraSession stopRunning];
    }
    [self.cameraSession startRunning];
}

- (void)start {
    [self.cameraSession startRunning];
}

- (CGSize)getEffectivPreviewSize {
    // TODO
    return CGSizeMake(1920, 1080);
}

/// Get the first available camera on device (front or rear)
- (AVCaptureDevice *)selectAvailableCamera:(PigeonSensor *)sensor {
    if (sensor.deviceId != nil) {
        return [AVCaptureDevice deviceWithUniqueID:sensor.deviceId];
    }
    
    // TODO: add dual & triple camera
    NSArray<AVCaptureDevice *> *devices = [[NSArray alloc] init];
    AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInTelephotoCamera, AVCaptureDeviceTypeBuiltInUltraWideCamera, ]
                                                                                                               mediaType:AVMediaTypeVideo
                                                                                                                position:AVCaptureDevicePositionUnspecified];
    devices = discoverySession.devices;
    
    for (AVCaptureDevice *device in devices) {
        if (sensor.type != PigeonSensorTypeUnknown) {
            AVCaptureDeviceType deviceType = [SensorUtils deviceTypeFromSensorType:sensor.type];
            if ([device deviceType] == deviceType) {
                return [AVCaptureDevice deviceWithUniqueID:[device uniqueID]];
            }
        } else if (sensor.position != PigeonSensorPositionUnknown) {
            NSInteger cameraType = (sensor.position == PigeonSensorPositionFront) ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
            if ([device position] == cameraType) {
                return [AVCaptureDevice deviceWithUniqueID:[device uniqueID]];
            }
        }
    }
    return nil;
}

- (void)setAspectRatio:(AspectRatio)ratio {
    _aspectRatio = ratio;
}

- (void)setPreviewSize:(CGSize)previewSize error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    // TODO:
}

- (void)takePhotoSensors:(nonnull NSArray<PigeonSensor *> *)sensors paths:(nonnull NSArray<NSString *> *)paths completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
    for (int i = 0; i < [sensors count]; i++) {
        PigeonSensor *sensor = [sensors objectAtIndex:i];
        NSString *path = [paths objectAtIndex:i];
        
        // TODO: take pictures for each sensors
        CameraPictureController *cameraPicture = [[CameraPictureController alloc] initWithPath:path
                                                                                   orientation:_motionController.deviceOrientation
                                                                                sensorPosition:sensor.position
                                                                               saveGPSLocation:_saveGPSLocation
                                                                             mirrorFrontCamera:_mirrorFrontCamera
                                                                                   aspectRatio:_aspectRatio
                                                                                    completion:completion
                                                                                      callback:^{
            // If flash mode is always on, restore it back after photo is taken
            if (self->_torchMode == AVCaptureTorchModeOn) {
                [self->_devices.firstObject.device lockForConfiguration:nil];
                [self->_devices.firstObject.device setTorchMode:AVCaptureTorchModeOn];
                [self->_devices.firstObject.device unlockForConfiguration];
            }
            
            completion(@(YES), nil);
        }];
        
        // Create settings instance
        AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
        [settings setHighResolutionPhotoEnabled:YES];
        [self.devices[i].capturePhotoOutput setPhotoSettingsForSceneMonitoring:settings];
        
        [self.devices[i].capturePhotoOutput capturePhotoWithSettings:settings
                                                            delegate:cameraPicture];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    // Check if output is video
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        int index = 0;
        for (CameraDeviceInfo *device in self.devices) {
            if (device.videoDataOutput == output) {
                if (_videoController.isRecording) {
                    [_videoController captureOutput:output
                              didOutputSampleBuffer:sampleBuffer
                                     fromConnection:connection
                                 captureVideoOutput:device.videoDataOutput
                                              index:index];
                }
                [_textures[index] updateBuffer:sampleBuffer];
                if (_onPreviewFrameAvailable) {
                    _onPreviewFrameAvailable(@(index));
                }
                break;
            }
            index++;
        }
    }
    // Check if output is audio
    else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]]) {
        if (_videoController.isRecording) {
            [_videoController captureOutput:output
                      didOutputSampleBuffer:sampleBuffer
                             fromConnection:connection
                         captureVideoOutput:nil
                                      index:0]; // Audio is shared across videos
        }
    }
}
- (void)startRecordingToPaths:(NSArray<NSString *> *)paths completion:(void (^)(FlutterError * _Nullable))completion {
    
    
    [_videoController setPreviewSize:[self getEffectivPreviewSize]];
    NSMutableArray<AVCaptureDevice *> *devices = [NSMutableArray new];
    
    for (CameraDeviceInfo *cameraDevice in self.devices) {
        [devices addObject:cameraDevice.device];
    }
    
    [_videoController recordVideoAtPaths:paths
                          captureDevices:devices
                             orientation:AVCaptureVideoOrientationPortrait
                      audioSetupCallback:^{
        [self setUpCaptureSessionForAudioError:^(NSError *error) {
            completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[error localizedDescription]]);
        }];
        NSLog(@"Audio setup completed.");
    }
                     videoWriterCallback:^{
        if (self->_videoController.isAudioEnabled) {
            [self->_audioOutput setSampleBufferDelegate:self queue:self->_dispatchQueue];
        }
        for (AVCaptureVideoDataOutput *output in self->_captureVideoOutputs) {
            [output setSampleBufferDelegate:self queue:self->_dispatchQueue];
        }
        
        NSLog(@"Video writer setup completed.");
        completion(nil);
    }
                                 options:_videoOptions
                                 quality:VideoRecordingQualityFhd
                              completion:completion];
}

- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
    if (_videoController.isRecording) {
        [_videoController stopRecordingVideo:completion];
    } else {
        completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"video is not recording" details:@""]);
    }
}
/// sudo Pause video recording
- (void)sudoPauseVideoRecording:(UIImage * _Nullable)image {
    [_videoController sudoPauseVideoRecording:image];
}

/// Resume video recording after being sudo paused
- (void)resumePseudoPausedVideoRecording {
    [_videoController resumePseudoPausedVideoRecording];
}

/// Pause video recording
- (void)pauseVideoRecording {
    [_videoController pauseVideoRecording];
}

/// Resume video recording after being paused
- (void)resumeVideoRecording {
    [_videoController resumeVideoRecording];
}
- (void)setCaptureMode:(CaptureModes)captureMode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
    if (_videoController.isRecording) {
        *error = [FlutterError errorWithCode:@"CAPTURE_MODE" message:@"impossible to change capture mode, video already recording" details:@""];
        return;
    }
    _captureMode = captureMode;
    
    if (captureMode == Video) {
        [self setUpCaptureSessionForAudioError:^(NSError *audioError) {
            *error = [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[audioError localizedDescription]];
        }];
    }
}
# pragma mark - Audio
// Set audio recording mode
- (void)setRecordingAudioMode:(bool)isAudioEnabled completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
    if (_videoController.isRecording) {
        completion(@(NO), [FlutterError errorWithCode:@"CHANGE_AUDIO_MODE" message:@"impossible to change audio mode, video already recording" details:@""]);
        return;
    }
    
    [_cameraSession beginConfiguration];
    [_videoController setIsAudioEnabled:isAudioEnabled];
    [_videoController setIsAudioSetup:NO];
    [_videoController setAudioIsDisconnected:YES];
    
    // Only remove audio channel input but keep video
    for (AVCaptureInput *input in [_cameraSession inputs]) {
        for (AVCaptureInputPort *port in input.ports) {
            if ([[port mediaType] isEqual:AVMediaTypeAudio]) {
                [_cameraSession removeInput:input];
                break;
            }
        }
    }
    // Only remove audio channel output but keep video
    [_cameraSession removeOutput:_audioOutput];
    
    if (_videoController.isRecording) {
        [self setUpCaptureSessionForAudioError:^(NSError *error) {
            completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[error localizedDescription]]);
        }];
    }
    
    [_cameraSession commitConfiguration];
}
/// Setup audio channel to record audio
- (void)setUpCaptureSessionForAudioError:(nonnull void (^)(NSError *))error {
    NSError *audioError = nil;
    
    // Create audio device and input
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&audioError];
    if (audioError) {
        error(audioError);
        return;
    }
    
    // Setup audio output
    _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [_audioOutput setSampleBufferDelegate:self queue:self.dispatchQueue];
    
    [_cameraSession beginConfiguration];
    if ([_cameraSession canAddInput:audioInput]) {
        [_cameraSession addInput:audioInput];
        if ([_cameraSession canAddOutput:_audioOutput]) {
            [_cameraSession addOutput:_audioOutput];
        } else {
            NSLog(@"Failed to add audio output.");
        }
    } else {
        NSLog(@"Failed to add audio input.");
    }
    [_cameraSession commitConfiguration];
}

@end
