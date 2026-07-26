//
//  STTEngine.h
//  Golosok
//
//  Created by kozak_dev on 26.07.2026.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface STTEngine : NSObject

- (instancetype)initWithModelPath:(NSString *)path;

- (NSString *)transcribeAudio:(float *)audioData length:(int)length;

@end

NS_ASSUME_NONNULL_END
