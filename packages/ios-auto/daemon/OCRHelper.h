// daemon/OCRHelper.h

#import <Foundation/Foundation.h>

@interface OCRHelper : NSObject
- (NSDictionary *)findText:(CGRect)region;
- (NSDictionary *)captureScreen;
- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body;
@end
