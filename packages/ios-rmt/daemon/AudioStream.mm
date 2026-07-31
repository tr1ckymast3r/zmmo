// daemon/AudioStream.mm — Microphone audio capture via AVAudioEngine
// Streams PCM audio chunks via notification (consumed by RMTDaemon for WS broadcast)

#import "AudioStream.h"
#import <AVFoundation/AVFoundation.h>

@interface AudioStream ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioInputNode *input;
@property (nonatomic, assign) BOOL active;
@end

@implementation AudioStream

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine = [[AVAudioEngine alloc] init];
        _input  = [_engine inputNode];
    }
    return self;
}

- (NSDictionary *)start {
    if (_active) return @{@"status": @"already active"};

    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                   error:nil];
    [session setActive:YES error:nil];

    AVAudioFormat *fmt = [_input outputFormatForBus:0];
    [_input installTapOnBus:0 bufferSize:4096 format:fmt block:
     ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        // Convert to NSData for streaming
        NSData *pcmData = [NSData dataWithBytes:buffer.floatChannelData[0]
                                        length:buffer.frameLength * sizeof(float)];

        // Post to notification → daemon broadcasts to clients
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.zmmo.iosrmt.audioChunk"),
            (__bridge CFDataRef)pcmData, NULL, YES);
    }];

    [_engine prepare];
    [_engine startAndReturnError:nil];
    _active = YES;

    return @{@"status": @"started", @"format": fmt.description};
}

- (NSDictionary *)stop {
    if (!_active) return @{@"status": @"not active"};
    [_input removeTapOnBus:0];
    [_engine stop];
    _active = NO;
    return @{@"status": @"stopped"};
}

- (BOOL)isActive { return _active; }

@end
