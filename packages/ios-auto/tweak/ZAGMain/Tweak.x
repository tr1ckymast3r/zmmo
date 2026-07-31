// tweak/ZAGMain/Tweak.x — SpringBoard hooks for OCR, screen capture, touch injection
// Listens for Darwin notifications from daemon → performs Vision OCR on demand

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <CoreML/CoreML.h>
#import <substrate.h>

static void handleOCRRequest(CFNotificationCenterRef c, void *o, CFStringRef n, const void *d, CFDictionaryRef u) {
    NSString *json = (__bridge NSString *)d;
    if (!json) return;
    NSDictionary *req = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (!req) return;

    NSString *action = req[@"action"];

    if ([action isEqualToString:@"findText"]) {
        [self performOCR:req];
    } else if ([action isEqualToString:@"captureScreen"]) {
        [self captureScreenAndSave:req];
    }
}

static void performOCR(NSDictionary *req) {
    CGFloat x = [req[@"x"] floatValue], y = [req[@"y"] floatValue];
    CGFloat w = [req[@"w"] floatValue], h = [req[@"h"] floatValue];

    // Capture screen
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) return;

    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!screenshot) return;

    // Crop region
    CGRect cropRect = CGRectMake(x, y, w > 0 ? w : screenshot.size.width - x,
                                     h > 0 ? h : screenshot.size.height - y);
    CGImageRef cropCG = CGImageCreateWithImageInRect(screenshot.CGImage, cropRect);
    if (!cropCG) return;

    // OCR via Vision
    VNRecognizeTextRequest *textReq = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:
        ^(VNRequest *request, NSError *error) {
            NSMutableString *text = [NSMutableString string];
            for (VNRecognizedTextObservation *obs in request.results) {
                [text appendFormat:@"%@ ", [obs topCandidates:1].firstObject.string];
            }
            [@{@"text": text, @"status": @"ok"} writeToFile:@"/tmp/zmmo_ocr_result.json" atomically:YES];
        }];
    textReq.recognitionLevel = VNRequestTextRecognitionLevelAccurate;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cropCG options:@{}];
    [handler performRequests:@[textReq] error:nil];
    CGImageRelease(cropCG);
}

static void captureScreenAndSave(NSDictionary *req) {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) return;

    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!screenshot) return;

    NSString *path = @"/tmp/zmmo_screenshot.png";
    [UIImagePNGRepresentation(screenshot) writeToFile:path atomically:YES];
    [@{@"path": path, @"w": @(screenshot.size.width), @"h": @(screenshot.size.height)}
     writeToFile:@"/tmp/zmmo_screen_result.json" atomically:YES];
}

%ctor {
    NSLog(@"[ZAGMain] Loaded — OCR + Screen capture hooks");
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL, handleOCRRequest,
        CFSTR("com.zmmo.iosauto.ocrRequest"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}
