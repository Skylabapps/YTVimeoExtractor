//
//  YTVimeoExtractorOperation.m
//  YTVimeoExtractor
//
//  Created by Soneé Delano John on 11/28/15.
//  Copyright © 2015 Louis Larpin. All rights reserved.
//

#import "YTVimeoExtractorOperation.h"
#import "YTVimeoVideo.h"
#import "YTVimeoVideo+Private.h"
#import "YTVimeoError.h"

NSString *const YTVimeoURL = @"https://vimeo.com/%@";
NSString *const YTVimeoPlayerConfigURL = @"https://player.vimeo.com/video/%@/config";

@interface YTVimeoExtractorOperation ()

@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@property (nonatomic, readonly) NSURLSession *networkSession;

@property (nonatomic, readonly) NSString *videoIdentifier;


@property (nonatomic, assign) BOOL isExecuting;
@property (nonatomic, assign) BOOL isFinished;

@property (nonatomic, readonly) NSString* referer;

@property (strong, nonatomic, readonly) NSURL *vimeoURL;

@end
@implementation YTVimeoExtractorOperation

- (instancetype) init
{
    @throw [NSException exceptionWithName:NSGenericException reason:@"Use the `initWithVideoIdentifier:referer`or `initWithURL:referer` method instead." userInfo:nil];
}
-(instancetype)initWithVideoIdentifier:(NSString *)videoIdentifier referer:(NSString *)videoReferer{
    
    NSParameterAssert(videoIdentifier);
    
    self = [super init];
    
    if (self) {
        
    _videoIdentifier = videoIdentifier;
    _vimeoURL = [NSURL URLWithString:[NSString stringWithFormat:YTVimeoPlayerConfigURL, videoIdentifier]];
    
    // use given referer or default to vimeo domain
    if (videoReferer) {
        _referer = videoReferer;
    } else {
        _referer = [NSString stringWithFormat:YTVimeoURL, videoIdentifier];
      }
   
    }

    return self;
}

- (instancetype)initWithURL:(NSString *)videoURL referer:(NSString *)videoReferer{
    
    return [self initWithVideoIdentifier:videoURL.lastPathComponent referer:videoReferer];
}


#pragma mark - NSOperation

-(BOOL)isAsynchronous{
    
    return YES;
}
- (void) cancel
{
    if (self.isCancelled || self.isFinished)
        return;
    
    [super cancel];
    
    [self.dataTask cancel];
    
    [self finish];
}
-(void)start{
    
    if (self.isCancelled) {
        return;
    }
    
    self.isExecuting = YES;
    
    // build request headers
    NSMutableDictionary *sessionHeaders = [NSMutableDictionary dictionaryWithDictionary:@{@"Content-Type" : @"application/json"}];
    if (self.referer) {
        [sessionHeaders setValue:self.referer forKey:@"Referer"];
    }
    
    // configure the session
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.HTTPAdditionalHeaders = sessionHeaders;
    
    _networkSession = [NSURLSession sessionWithConfiguration:sessionConfig];
    // start the request
    self.dataTask = [self.networkSession dataTaskWithURL:self.vimeoURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
        
        if (httpResponse.statusCode != 200) {
            
            if (httpResponse.statusCode == 404) {
                
                NSError *deletedError = [NSError errorWithDomain:YTVimeoVideoErrorDomain code:YTVimeoErrorRemovedVideo userInfo:@{NSLocalizedDescriptionKey:@"The operation was unable to finish successfully.", NSLocalizedFailureReasonErrorKey: @"The requested Vimeo video was deleted."}];
                [self finishOperationWithError:deletedError];
                
            }else if (httpResponse.statusCode == 403){
                
                NSError *privateError = [NSError errorWithDomain:YTVimeoVideoErrorDomain code:YTVimeoErrorRestrictedPlayback userInfo:@{NSLocalizedDescriptionKey:@"The operation was unable to finish successfully.", NSLocalizedFailureReasonErrorKey: @"The requested Vimeo video is private."}];
                [self finishOperationWithError:privateError];
                
            }else{
                NSString *response = [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode];
                
                NSError *unknownError = [NSError errorWithDomain:YTVimeoVideoErrorDomain code:YTVimeoErrorUnknown userInfo:@{NSLocalizedDescriptionKey:@"The operation was unable to finish successfully.", NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"The requested Vimeo video out this reponse: %@",response]}];
                
                [self finishOperationWithError:unknownError];
            }
            
            // cancel the session
            return;
        }
        
        // parse json from buffered data
        NSError *jsonError;
        NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&jsonError];
        if (!jsonData) {
            NSError *invalidIDError = [NSError errorWithDomain:YTVimeoVideoErrorDomain code:YTVimeoErrorInvalidVideoIdentifier userInfo:@{NSLocalizedDescriptionKey:@"The operation was unable to finish successfully.", NSLocalizedFailureReasonErrorKey: @"The video identifier is invalid"}];
            [self finishOperationWithError:invalidIDError];
            return;
        }
        self->_jsonDict = jsonData;
        YTVimeoVideo *video = [[YTVimeoVideo alloc]initWithIdentifier:self.videoIdentifier info:jsonData];
        [video extractVideoInfoWithCompletionHandler:^(NSError * _Nullable error) {
            
            if (error) {
                
                [self finishOperationWithError:error];
                
            }else{
                
                [self finishOperationWithVideo:video];
                
            }
            
        }];
    }];
    [self.dataTask resume];
    
}

+ (BOOL) automaticallyNotifiesObserversForKey:(NSString *)key
{
    SEL selector = NSSelectorFromString(key);
    return selector == @selector(isExecuting) || selector == @selector(isFinished) || [super automaticallyNotifiesObserversForKey:key];
}

-(void)finishOperationWithError:(NSError *)error{
    
    _error = error;
    [self finish];
    
}

-(void)finishOperationWithVideo:(YTVimeoVideo *)video{
    
    _operationVideo = video;
    _error = nil;
    [self finish];
}
- (void)finish
{
    self.isExecuting = NO;
    self.isFinished = YES;
}
    
@end
