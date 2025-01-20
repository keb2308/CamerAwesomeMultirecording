//
//  VideoController.m
//  camerawesome
//
//  Created by Dimitri Dessus on 17/12/2020.
//

#import "VideoController.h"

FourCharCode const videoFormat = kCVPixelFormatType_32BGRA;

@implementation VideoController

- (instancetype)init {
  self = [super init];
  _isRecording = NO;
  _isAudioEnabled = YES;
  _isPaused = NO;
  
  return self;
}

# pragma mark - User video interactions
- (void)recordVideoAtPaths:(NSArray<NSString *> *)paths
            captureDevices:(NSArray<AVCaptureDevice *> *)devices
               orientation:(NSInteger)orientation
          audioSetupCallback:(OnAudioSetup)audioSetupCallback
       videoWriterCallback:(OnVideoWriterSetup)videoWriterCallback
                   options:(CupertinoVideoOptions *)options
                   quality:(VideoRecordingQuality)quality
                completion:(nonnull void (^)(FlutterError * _Nullable))completion {
    if (paths.count != devices.count) {
        completion([FlutterError errorWithCode:@"PATH_DEVICE_MISMATCH"
                                       message:@"Number of paths does not match number of devices"
                                       details:nil]);
        return;
    }
    if (![self setupWritersForPaths:paths audioSetupCallback:audioSetupCallback options:options completion:completion]) {
        completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to write video at path" details:paths]);
      return;
    }
    videoWriterCallback();
    
    _isRecording = YES;
    _videoTimeOffset = CMTimeMake(0, 1);
    _audioTimeOffset = CMTimeMake(0, 1);
    _videoIsDisconnected = NO;
    _audioIsDisconnected = NO;
    _orientation = orientation;
    _captureDevices = devices;
    
    // Change video FPS if provided
    if (_options && _options.fps != nil && _options.fps > 0) {
        for (AVCaptureDevice *device in devices) {
            [self adjustCameraFPS:_options.fps ofCaptureDevice:device];
        }
      
    }
    completion(nil);
}


/// Stop recording video

- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
    if (_options && _options.fps != nil && _options.fps > 0) {
        // Reset camera FPS
        for (AVCaptureDevice *device in _captureDevices) {
            [self adjustCameraFPS:@(30) ofCaptureDevice:device];
        }
    }

    if (_isRecording) {
        _isRecording = NO;

        // Create a dispatch group to wait for all recordings to complete
        dispatch_group_t group = dispatch_group_create();
        __block BOOL allSucceeded = YES;

        for (NSUInteger i = 0; i < self.videoWriters.count; i++) {
            AVAssetWriter *writer = self.videoWriters[i];
            
            if (writer.status != AVAssetWriterStatusUnknown) {
                dispatch_group_enter(group);
                
                [writer finishWritingWithCompletionHandler:^{
                    if (writer.status != AVAssetWriterStatusCompleted) {
                        allSucceeded = NO;
                        NSLog(@"Error: Failed to finish writing for video %lu", (unsigned long)i);
                    }
                    dispatch_group_leave(group);
                }];
            }
        }

        // Call the completion handler once all writers have finished
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (allSucceeded) {
                completion(@(YES), nil);
            } else {
                completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR"
                                                     message:@"One or more videos failed to completely write"
                                                     details:@""]);
            }
        });
    } else {
        completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR"
                                             message:@"video is not recording"
                                             details:@""]);
    }
}



- (void)pauseVideoRecording {
  _isPaused = YES;
}

- (void)resumeVideoRecording {
  _isPaused = NO;
}

# pragma mark - Audio & Video writers

/// Setup video channel & write file on path
- (BOOL)setupWritersForPaths:(NSArray<NSString *> *)paths
          audioSetupCallback:(OnAudioSetup)audioSetupCallback
                     options:(CupertinoVideoOptions *)options
                  completion:(nonnull void (^)(FlutterError * _Nullable))completion {

    if (paths.count == 0) {
         completion([FlutterError errorWithCode:@"NO_PATHS"
                                        message:@"No paths provided for video recording"
                                        details:nil]);
         return NO;
     }

    NSError *error = nil;

    // Initialize arrays to store writers and inputs for each camera
    _videoWriters = [NSMutableArray array];
    _videoWriterInputs = [NSMutableArray array];
    _videoAdaptors = [NSMutableArray array];
    _audioWriterInputs = [NSMutableArray array]; // Added for audio inputs

    
    for (NSUInteger i = 0; i < paths.count; i++) {
        NSString *path = paths[i];
        NSURL *outputURL = [NSURL fileURLWithPath:path];

        if (_isAudioEnabled && !_isAudioSetup && i == 0) {
            // Only call audio setup once
            audioSetupCallback();
        }

        // Get video settings
        AVVideoCodecType codecType = [self getBestCodecTypeAccordingOptions:options];
        AVFileType fileType = [self getBestFileTypeAccordingOptions:options];
        CGSize videoSize = [self getBestVideoSizeAccordingQuality:_recordingQuality];
        if (videoSize.width <= 0 || videoSize.height <= 0) {
            
            completion([FlutterError errorWithCode:@"VIDEO_ERROR"
                                           message:@"Unable to create video writer. videoSize is zero."
                                           details:nil]);
            return NO;
        }
        NSDictionary *videoSettings = @{
            AVVideoCodecKey   : codecType,
            AVVideoWidthKey   : @(videoSize.height),
            AVVideoHeightKey  : @(videoSize.width),
        };

        // Create video writer input
        AVAssetWriterInput *videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                                   outputSettings:videoSettings];
        [videoWriterInput setTransform:[self getVideoOrientation]];
        videoWriterInput.expectsMediaDataInRealTime = YES;

        // Create pixel buffer adaptor
        AVAssetWriterInputPixelBufferAdaptor *videoAdaptor = [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                  sourcePixelBufferAttributes:@{
                                      (NSString *)kCVPixelBufferPixelFormatTypeKey: @(videoFormat)
                                  }];

        // Create video writer
        AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                                               fileType:fileType
                                                                  error:&error];
        if (error) {
            completion([FlutterError errorWithCode:@"VIDEO_ERROR"
                                           message:@"Unable to create video writer. Check options."
                                           details:error.description]);
            return NO;
        }

        [videoWriter addInput:videoWriterInput];

        // Store writer, input, and adaptor
        [self.videoWriters addObject:videoWriter];
        [self.videoWriterInputs addObject:videoWriterInput];
        [self.videoAdaptors addObject:videoAdaptor];
        

    }

    // Set up audio for the first video writer (shared across all videos)
    if (_isAudioEnabled) {
        AudioChannelLayout acl;
                bzero(&acl, sizeof(acl));
                acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;

                NSDictionary *audioOutputSettings = @{
                    AVFormatIDKey: @(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: @(44100.0),
                    AVNumberOfChannelsKey: @(1),
                    AVChannelLayoutKey: [NSData dataWithBytes:&acl length:sizeof(acl)]
                };

                for (AVAssetWriter *videoWriter in self.videoWriters) {
                    AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                                       outputSettings:audioOutputSettings];
                    audioInput.expectsMediaDataInRealTime = YES;

                    [videoWriter addInput:audioInput];
                    [self.audioWriterInputs addObject:audioInput];
                }
        
    }

    return YES;
}

- (CGAffineTransform)getVideoOrientation {
  CGAffineTransform transform;
  
  switch ([[UIDevice currentDevice] orientation]) {
    case UIDeviceOrientationLandscapeLeft:
      transform = CGAffineTransformMakeRotation(-M_PI_2);
      break;
    case UIDeviceOrientationLandscapeRight:
      transform = CGAffineTransformMakeRotation(M_PI_2);
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      transform = CGAffineTransformMakeRotation(M_PI);
      break;
    default:
      transform = CGAffineTransformIdentity;
      break;
  }
  
  return transform;
}

/// Append audio data to the first video writer
- (void)newAudioSample:(CMSampleBufferRef)sampleBuffer {
    if (self.videoWriters.count == 0 || self.audioWriterInputs.count == 0) {
        NSLog(@"No video writers or audio writer inputs available for audio sample.");
        return;
    }

    for (NSUInteger i = 0; i < self.videoWriters.count; i++) {
        AVAssetWriter *currentVideoWriter = self.videoWriters[i];
        AVAssetWriterInput *currentAudioWriterInput = self.audioWriterInputs[i];

        // Check the status of the current video writer
        if (currentVideoWriter.status != AVAssetWriterStatusWriting) {
            if (currentVideoWriter.status == AVAssetWriterStatusFailed) {
                NSLog(@"Writing video failed for index %lu: %@", (unsigned long)i, currentVideoWriter.error.localizedDescription);
            }
            continue;
        }

        // Append audio sample to the current writer's audio input
        if (currentAudioWriterInput.readyForMoreMediaData) {
            if (![currentAudioWriterInput appendSampleBuffer:sampleBuffer]) {
                NSLog(@"Failed to append audio sample to writer for index %lu: %@", (unsigned long)i, currentVideoWriter.error.localizedDescription);
            }
        } else {
            NSLog(@"Audio writer input not ready for more media data for index %lu.", (unsigned long)i);
        }
    }
}
/// Adjust time to sync audio & video
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset CF_RETURNS_RETAINED {
  CMItemCount count;
  CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
  CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
  CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
  for (CMItemCount i = 0; i < count; i++) {
    pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
    pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
  }
  CMSampleBufferRef sout;
  CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
  free(pInfo);
  return sout;
}

/// Adjust video preview & recording to specified FPS
- (void)adjustCameraFPS:(NSNumber *)fps ofCaptureDevice: (AVCaptureDevice *) captureDevice {
  NSArray *frameRateRanges = captureDevice.activeFormat.videoSupportedFrameRateRanges;
  
  if (frameRateRanges.count > 0) {
    AVFrameRateRange *frameRateRange = frameRateRanges.firstObject;
    NSError *error = nil;
    
    if ([captureDevice lockForConfiguration:&error]) {
      CMTime frameDuration = CMTimeMake(1, [fps intValue]);
      if (CMTIME_COMPARE_INLINE(frameDuration, <=, frameRateRange.maxFrameDuration) && CMTIME_COMPARE_INLINE(frameDuration, >=, frameRateRange.minFrameDuration)) {
        captureDevice.activeVideoMinFrameDuration = frameDuration;
      }
      [captureDevice unlockForConfiguration];
    }
  }
}

# pragma mark - Camera Delegates
- (void)captureOutput:(AVCaptureOutput *)output
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
 captureVideoOutput:(AVCaptureVideoDataOutput * _Nullable)captureVideoOutput
                index: (NSUInteger)index {
    
    if (self.isPaused) {
            return;
        }

        if ([_videoWriters count] <= index || [_videoWriterInputs count] <= index) {
            NSLog(@"Index out of bounds for video writers or inputs.");
            return;
        }

        AVAssetWriter *currentVideoWriter = self.videoWriters[index];
        AVAssetWriterInput *currentVideoInput = self.videoWriterInputs[index];
        AVAssetWriterInputPixelBufferAdaptor *currentVideoAdaptor = self.videoAdaptors[index];

        CFRetain(sampleBuffer);
        CMTime currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);

        // Validate CMTime
        if (!CMTIME_IS_VALID(currentSampleTime)) {
            NSLog(@"Invalid sample time for index: %lu", (unsigned long)index);
            CFRelease(sampleBuffer);
            return;
        }

        // Handle video writer failures
        if (currentVideoWriter.status == AVAssetWriterStatusFailed) {
            NSLog(@"Video Writer Error for index %lu: %@", (unsigned long)index, currentVideoWriter.error);
            CFRelease(sampleBuffer);
            return;
        }

        // Start writing if not already started
        if (currentVideoWriter.status != AVAssetWriterStatusWriting) {
            [currentVideoWriter startWriting];
            [currentVideoWriter startSessionAtSourceTime:currentSampleTime];
        }

        // Handle video output
        if (output == captureVideoOutput) {
            if (self.videoIsDisconnected) {
                self.videoIsDisconnected = NO;

                if (CMTIME_IS_INVALID(self.lastVideoSampleTime)) {
                    _videoTimeOffset = CMTimeSubtract(currentSampleTime, kCMTimeZero);
                } else {
                    CMTime offset = CMTimeSubtract(currentSampleTime, self.lastVideoSampleTime);
                    _videoTimeOffset = CMTimeAdd(self.videoTimeOffset, offset);
                }

                CFRelease(sampleBuffer);
                return;
            }

            _lastVideoSampleTime = currentSampleTime;

            CVPixelBufferRef nextBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            CMTime nextSampleTime = CMTimeSubtract(currentSampleTime, self.videoTimeOffset);

            if (!CMTIME_IS_VALID(nextSampleTime)) {
                NSLog(@"Invalid nextSampleTime, skipping frame.");
                CFRelease(sampleBuffer);
                return;
            }

            if (currentVideoInput.isReadyForMoreMediaData) {
                [currentVideoAdaptor appendPixelBuffer:nextBuffer withPresentationTime:nextSampleTime];
            } else {
                NSLog(@"Video Input not ready.");
            }

        
    } else {
        // Handle audio output
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);

        if (duration.value > 0) {
            currentSampleTime = CMTimeAdd(currentSampleTime, duration);
        }

        if (self.audioIsDisconnected) {
            self.audioIsDisconnected = NO;

            if (self.audioTimeOffset.value == 0) {
                self.audioTimeOffset = CMTimeSubtract(currentSampleTime, self.lastAudioSampleTime);
            } else {
                CMTime offset = CMTimeSubtract(currentSampleTime, self.lastAudioSampleTime);
                self.audioTimeOffset = CMTimeAdd(self.audioTimeOffset, offset);
            }

            CFRelease(sampleBuffer);
            return;
        }

        self.lastAudioSampleTime = currentSampleTime;

        if (self.audioTimeOffset.value != 0) {
            CFRelease(sampleBuffer);
            sampleBuffer = [self adjustTime:sampleBuffer by:self.audioTimeOffset];
        }

        [self newAudioSample:sampleBuffer];
    }

    CFRelease(sampleBuffer);
}




# pragma mark - Settings converters

- (AVFileType)getBestFileTypeAccordingOptions:(CupertinoVideoOptions *)options {
  AVFileType fileType = AVFileTypeQuickTimeMovie;
  
  if (options && options != (id)[NSNull null]) {
    CupertinoFileType type = options.fileType;
    switch (type) {
      case CupertinoFileTypeQuickTimeMovie:
        fileType = AVFileTypeQuickTimeMovie;
        break;
      case CupertinoFileTypeMpeg4:
        fileType = AVFileTypeMPEG4;
        break;
      case CupertinoFileTypeAppleM4V:
        fileType = AVFileTypeAppleM4V;
        break;
      case CupertinoFileTypeType3GPP:
        fileType = AVFileType3GPP;
        break;
      case CupertinoFileTypeType3GPP2:
        fileType = AVFileType3GPP2;
        break;
      default:
        break;
    }
  }
  
  return fileType;
}

- (AVVideoCodecType)getBestCodecTypeAccordingOptions:(CupertinoVideoOptions *)options {
  AVVideoCodecType codecType = AVVideoCodecTypeH264;
  if (options && options != (id)[NSNull null]) {
    CupertinoCodecType codec = options.codec;
    switch (codec) {
      case CupertinoCodecTypeH264:
        codecType = AVVideoCodecTypeH264;
        break;
      case CupertinoCodecTypeHevc:
        codecType = AVVideoCodecTypeHEVC;
        break;
      case CupertinoCodecTypeHevcWithAlpha:
        codecType = AVVideoCodecTypeHEVCWithAlpha;
        break;
      case CupertinoCodecTypeJpeg:
        codecType = AVVideoCodecTypeJPEG;
        break;
      case CupertinoCodecTypeAppleProRes4444:
        codecType = AVVideoCodecTypeAppleProRes4444;
        break;
      case CupertinoCodecTypeAppleProRes422:
        codecType = AVVideoCodecTypeAppleProRes422;
        break;
      case CupertinoCodecTypeAppleProRes422HQ:
        codecType = AVVideoCodecTypeAppleProRes422HQ;
        break;
      case CupertinoCodecTypeAppleProRes422LT:
        codecType = AVVideoCodecTypeAppleProRes422LT;
        break;
      case CupertinoCodecTypeAppleProRes422Proxy:
        codecType = AVVideoCodecTypeAppleProRes422Proxy;
        break;
      default:
        break;
    }
  }
  return codecType;
}

- (CGSize)getBestVideoSizeAccordingQuality:(VideoRecordingQuality)quality {
  CGSize size;
  switch (quality) {
    case VideoRecordingQualityUhd:
    case VideoRecordingQualityHighest:
      if (@available(iOS 9.0, *)) {
          if ([_captureDevices.firstObject supportsAVCaptureSessionPreset:AVCaptureSessionPreset3840x2160]) {
          size = CGSizeMake(3840, 2160);
        } else {
          size = CGSizeMake(1920, 1080);
        }
      } else {
        return CGSizeMake(1920, 1080);
      }
      break;
    case VideoRecordingQualityFhd:
      size = CGSizeMake(1920, 1080);
      break;
    case VideoRecordingQualityHd:
      size = CGSizeMake(1280, 720);
      break;
    case VideoRecordingQualitySd:
    case VideoRecordingQualityLowest:
      size = CGSizeMake(960, 540);
      break;
  }
    
  // ensure video output size does not exceed capture session size
  if (size.width > _previewSize.width) {
    size = _previewSize;
  }
  
  return size;
}

# pragma mark - Setter
- (void)setVideoIsDisconnected:(bool)isVideoDisconnected {
    _videoIsDisconnected = isVideoDisconnected;
}
- (void)setIsAudioEnabled:(bool)isAudioEnabled {
  _isAudioEnabled = isAudioEnabled;
}
- (void)setIsAudioSetup:(bool)isAudioSetup {
  _isAudioSetup = isAudioSetup;
}

- (void)setPreviewSize:(CGSize)previewSize {
  _previewSize = previewSize;
}

- (void)setAudioIsDisconnected:(bool)audioIsDisconnected {
  _audioIsDisconnected = audioIsDisconnected;
}

@end
