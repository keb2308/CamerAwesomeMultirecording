//
//  VideoController.h
//  camerawesome
//
//  Created by Dimitri Dessus on 17/12/2020.
//

#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "Pigeon.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^OnAudioSetup)(void);
typedef void(^OnVideoWriterSetup)(void);

@interface VideoController : NSObject

@property(readonly, nonatomic) bool isRecording;
@property(readonly, nonatomic) bool isPaused;
@property(readonly, nonatomic) bool isAudioEnabled;
@property(readonly, nonatomic) bool isAudioSetup;
@property(readonly, nonatomic) VideoRecordingQuality recordingQuality;
@property(readonly, nonatomic) CupertinoVideoOptions *options;
@property NSInteger orientation;
@property(readonly, nonatomic) NSArray <AVCaptureDevice *> *captureDevices;
@property(readonly, nonatomic) NSMutableArray<AVAssetWriter *> *videoWriters;
@property(readonly, nonatomic) NSMutableArray<AVAssetWriterInput *> *videoWriterInputs;
@property(readonly, nonatomic) NSMutableArray<AVAssetWriterInputPixelBufferAdaptor *> *videoAdaptors;
@property(readonly, nonatomic) NSMutableArray<AVAssetWriterInput *> *audioWriterInputs;
@property (readonly, nonatomic) CMTime lastVideoSampleTime;
@property (readonly, nonatomic) CMTime videoTimeOffset;
@property (readonly, nonatomic) BOOL videoIsDisconnected;
@property(readonly, nonatomic) bool audioIsDisconnected;
@property(readonly, nonatomic) CGSize previewSize;
@property(assign, nonatomic) CMTime lastAudioSampleTime;
@property(assign, nonatomic) CMTime audioTimeOffset;

- (instancetype)init;
- (void)recordVideoAtPaths:(NSArray<NSString *> *)paths
            captureDevices:(NSArray<AVCaptureDevice *> *)devices
               orientation:(NSInteger)orientation
          audioSetupCallback:(OnAudioSetup)audioSetupCallback
       videoWriterCallback:(OnVideoWriterSetup)videoWriterCallback
                   options:(CupertinoVideoOptions *)options
                   quality:(VideoRecordingQuality)quality
                completion:(nonnull void (^)(FlutterError * _Nullable))completion;

- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion;
- (void)pauseVideoRecording;
- (void)resumeVideoRecording;
- (void)captureOutput:(AVCaptureOutput *)output
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
 captureVideoOutput:(AVCaptureVideoDataOutput * _Nullable)captureVideoOutput
                index: (NSUInteger)index;
- (void)setIsAudioEnabled:(bool)isAudioEnabled;
- (void)setIsAudioSetup:(bool)isAudioSetup;
- (void)setVideoIsDisconnected:(bool)videoIsDisconnected;
- (void)setAudioIsDisconnected:(bool)audioIsDisconnected;
- (void)setPreviewSize:(CGSize)previewSize;

@end

NS_ASSUME_NONNULL_END
