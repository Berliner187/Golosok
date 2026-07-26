//
//  STTEngine.m
//  Golosok
//
//  Created by kozak_dev on 26.07.2026.
//

#import <Foundation/Foundation.h>
#import "STTEngine.h"
// Здесь позже будут инклуды реальной либы, например: #include "transcribe.h"

@implementation STTEngine {
    // Здесь мы будем хранить указатель на C++ контекст модели
    // void * ctx;
}

- (instancetype)initWithModelPath:(NSString *)path {
    self = [super init];
    if (self) {
        NSLog(@"[C++ Core] Инициализация модели по пути: %@", path);
        // Тут будет реальная загрузка GGUF файла
        // ctx = model_load([path UTF8String]);
    }
    return self;
}

- (NSString *)transcribeAudio:(float *)audioData length:(int)length {
    NSLog(@"[C++ Core] Получено сэмплов: %d", length);
    
    // Тут мы скормим audioData в GigaAM.
    // Пока возвращаем заглушку, чтобы убедиться, что мост Swift <-> C++ работает!
    
    return @"Бля, это работает! Мост между Swift и C++ установлен. Жду веса GigaAM.";
}

@end
