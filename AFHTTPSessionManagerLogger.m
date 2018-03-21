//
//  AFHTTPSessionManagerLogger.m
//
// Copyright (c) 2017 Kim Huang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#import "AFHTTPSessionManagerLogger.h"
#import <Foundation/Foundation.h>

#import <objc/runtime.h>


#if __has_include(<CocoaLumberjack/DDLogMacros.h>)
#import <CocoaLumberjack/DDLogMacros.h>
// Global log level for the whole library, not per-file.
extern DDLogLevel ddLogLevel;
// const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
#define DDLogError(...)   NSLog(__VA_ARGS__)
#define DDLogWarn(...)    NSLog(__VA_ARGS__)
#define DDLogInfo(...)    NSLog(__VA_ARGS__)
#define DDLogDebug(...)   NSLog(__VA_ARGS__)
#define DDLogVerbose(...) NSLog(__VA_ARGS__)
#endif

typedef NSString * (^AFHTTPSessionManagerLoggerFormatBlock)(NSURLSessionTask *task, AFHTTPSessionManagerLogLevel level);


@interface AFHTTPSessionManagerLogger ()
@property (readwrite, nonatomic) NSString *baseURLString;
@property (readwrite, nonatomic, copy) AFHTTPSessionManagerLoggerFormatBlock requestStartFormatBlock;
@property (readwrite, nonatomic, copy) AFHTTPSessionManagerLoggerFormatBlock requestFinishFormatBlock;
@property (readwrite, nonatomic, strong) NSOperationQueue *notificationHandlerQueue;
@property (readwrite, nonatomic, strong) id <NSObject> startNotificationObserver;
@property (readwrite, nonatomic, strong) id <NSObject> finishNotificationObserver;
@end

#pragma mark -

@implementation AFHTTPSessionManagerLogger

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    if ((self = [super init])) {
        _baseURLString = [baseURL absoluteString];
        _level = AFHTTPSessionManagerLogLevelInfo;
        _notificationHandlerQueue = [[NSOperationQueue alloc] init];
    }
    
    return self;
}

- (void)dealloc {
    [_notificationHandlerQueue cancelAllOperations];
    [[NSNotificationCenter defaultCenter] removeObserver:_startNotificationObserver name:AFNetworkingTaskDidResumeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:_finishNotificationObserver name:AFNetworkingTaskDidCompleteNotification object:nil];
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled != _enabled) {
        if (enabled) {
            // weakify and strongify
            __weak typeof(self) weakSelf = self;
            self.startNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingTaskDidResumeNotification
                                                                                               object:nil
                                                                                                queue:self.notificationHandlerQueue
                                                                                           usingBlock:^(NSNotification * _Nonnull notification) {
                                                                                               AFHTTPSessionManagerLogger *strongSelf = weakSelf;
                                                                                               [strongSelf taskDidStart:notification];
                                                                                           }];
            self.finishNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingTaskDidCompleteNotification
                                                                                                object:nil
                                                                                                 queue:self.notificationHandlerQueue
                                                                                            usingBlock:^(NSNotification * _Nonnull notification) {
                                                                                                AFHTTPSessionManagerLogger *strongSelf = weakSelf;
                                                                                                [strongSelf taskDidFinish:notification];
                                                                                            }];
        } else {
            if (self.startNotificationObserver) {
                [[NSNotificationCenter defaultCenter] removeObserver:self.startNotificationObserver name:AFNetworkingTaskDidResumeNotification object:nil];
            }
            if (self.finishNotificationObserver) {
                [[NSNotificationCenter defaultCenter] removeObserver:self.finishNotificationObserver name:AFNetworkingTaskDidCompleteNotification object:nil];
            }
        }
        
        _enabled = enabled;
    }
}

- (void)taskDidStart:(NSNotification *)notification {
    NSURLSessionTask *task = [notification object];
    if (![[[task.originalRequest URL] absoluteString] hasPrefix:self.baseURLString]) {
        return;
    }
    
    if (self.requestStartFormatBlock) {
        NSString *formattedString = self.requestStartFormatBlock(task, self.level);
        if (formattedString) {
            DDLogError(@"%@", formattedString);
        }
        return;
    }
    
    id body = nil;
    if ([task.originalRequest HTTPBody] && self.level <= AFHTTPSessionManagerLogLevelVerbose) {
        NSError *error = nil;
        body = [NSJSONSerialization JSONObjectWithData:[task.originalRequest HTTPBody] options:NSJSONReadingAllowFragments error:&error];
        if (error) {
            body = [[NSString alloc] initWithData:[task.originalRequest HTTPBody] encoding:NSUTF8StringEncoding];
        }
    }
    
    switch (self.level) {
        case AFHTTPSessionManagerLogLevelVerbose:
            if (body) {
                DDLogVerbose(@">> %@ %@\n%@\n%@", [task.originalRequest HTTPMethod], [[task.originalRequest URL] absoluteString], [task.originalRequest allHTTPHeaderFields], body);
            } else {
                DDLogVerbose(@">> %@ %@\n%@", [task.originalRequest HTTPMethod], [[task.originalRequest URL] absoluteString], [task.originalRequest allHTTPHeaderFields]);
            }
            break;
        case AFHTTPSessionManagerLogLevelDebug:
            if (body) {
                DDLogDebug(@">> %@ %@\n%@", [task.originalRequest HTTPMethod], [[task.originalRequest URL] absoluteString], body);
            } else {
                DDLogDebug(@">> %@ %@", [task.originalRequest HTTPMethod], [[task.originalRequest URL] absoluteString]);
            }
            break;
        case AFHTTPSessionManagerLogLevelInfo:
            DDLogInfo(@">> %@ %@", [task.originalRequest HTTPMethod], [[task.originalRequest URL] absoluteString]);
            break;
        default:
            break;
    }
}

- (void)taskDidFinish:(NSNotification *)notification {
    NSURLSessionDataTask *operation = [notification object];
    NSDictionary *userInfo = notification.userInfo;
    
    if (![[[operation.originalRequest URL] absoluteString] hasPrefix:self.baseURLString]) {
        return;
    }
    
    if (self.requestFinishFormatBlock) {
        NSString *formattedString = self.requestFinishFormatBlock(operation, self.level);
        if (formattedString) {
            DDLogError(@"%@", formattedString);
        }
        return;
    }
    
    NSURL *URL = (operation.response) ? [operation.response URL] : [operation.originalRequest URL];
    id responseObject = userInfo[AFNetworkingTaskDidCompleteSerializedResponseKey];
    
    if (operation.error && operation.error.code == NSURLErrorCancelled) {
        switch (self.level) {
            case AFHTTPSessionManagerLogLevelVerbose:
                DDLogVerbose(@"Canceled %@: %@", [URL absoluteString], operation.error);
                break;
            case AFHTTPSessionManagerLogLevelDebug:
            case AFHTTPSessionManagerLogLevelInfo:
                DDLogDebug(@"Canceled %@: %@", [URL absoluteString], [operation.error localizedDescription]);
                break;
            default:
                break;
        }
    } else if (operation.error) {
        switch (self.level) {
            case AFHTTPSessionManagerLogLevelVerbose:
                DDLogInfo(@"!! %ld %@: %@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString], operation.error);
                break;
            case AFHTTPSessionManagerLogLevelDebug:
            case AFHTTPSessionManagerLogLevelInfo:
            case AFHTTPSessionManagerLogLevelError:
                DDLogError(@"!! %ld %@: %@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString], [operation.error localizedDescription]);
                break;
        }
    } else {
        switch (self.level) {
            case AFHTTPSessionManagerLogLevelVerbose:
                if (responseObject) {
                    DDLogVerbose(@"<< %ld %@\n%@\n%@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString], [(NSHTTPURLResponse *)operation.response allHeaderFields], responseObject);
                } else {
                    DDLogVerbose(@"<< %ld %@\n%@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString], [(NSHTTPURLResponse *)operation.response allHeaderFields]);
                }
                break;
            case AFHTTPSessionManagerLogLevelDebug:
                if (responseObject) {
                    DDLogDebug(@"<< %ld %@\n%@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString], responseObject);
                } else {
                    DDLogDebug(@"<< %ld %@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString]);
                }
                break;
            case AFHTTPSessionManagerLogLevelInfo:
                DDLogInfo(@"<< %ld %@", (long)[(NSHTTPURLResponse *)operation.response statusCode], [URL absoluteString]);
                break;
            default:
                break;
        }
    }
}


@end

#pragma mark -

@implementation AFHTTPSessionManager (Logger)

static char AFHTTPSessionManagerObject;

- (AFHTTPSessionManagerLogger *)logger {
    AFHTTPSessionManagerLogger *logger = objc_getAssociatedObject(self, &AFHTTPSessionManagerObject);
    if (logger == nil) {
        logger = [[AFHTTPSessionManagerLogger alloc] initWithBaseURL:self.baseURL];
        objc_setAssociatedObject(self, &AFHTTPSessionManagerObject, logger, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    return logger;
}

@end
