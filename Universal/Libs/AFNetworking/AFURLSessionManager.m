// AFURLSessionManager.m
// 
// Copyright (c) 2013-2014 AFNetworking (http://afnetworking.com)
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

#import "AFURLSessionManager.h"

#if (defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000) || (defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 1090)

static dispatch_queue_t url_session_manager_creation_queue() {
    static dispatch_queue_t af_url_session_manager_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_session_manager_creation_queue = dispatch_queue_create("com.alamofire.networking.session.manager.creation", DISPATCH_QUEUE_SERIAL);
    });

    return af_url_session_manager_creation_queue;
}

static dispatch_queue_t url_session_manager_processing_queue() {
    static dispatch_queue_t af_url_session_manager_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_session_manager_processing_queue = dispatch_queue_create("com.alamofire.networking.session.manager.processing", DISPATCH_QUEUE_CONCURRENT);
    });

    return af_url_session_manager_processing_queue;
}

static dispatch_group_t url_session_manager_completion_group() {
    static dispatch_group_t af_url_session_manager_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_session_manager_completion_group = dispatch_group_create();
    });

    return af_url_session_manager_completion_group;
}

NSString * const AFNetworkingTaskDidResumeNotification = @"com.alamofire.networking.task.resume";
NSString * const AFNetworkingTaskDidCompleteNotification = @"com.alamofire.networking.task.complete";
NSString * const AFNetworkingTaskDidSuspendNotification = @"com.alamofire.networking.task.suspend";
NSString * const AFURLSessionDidInvalidateNotification = @"com.alamofire.networking.session.invalidate";
NSString * const AFURLSessionDownloadTaskDidFailToMoveFileNotification = @"com.alamofire.networking.session.download.file-manager-error";

NSString * const AFNetworkingTaskDidStartNotification = @"com.alamofire.networking.task.resume"; // Deprecated
NSString * const AFNetworkingTaskDidFinishNotification = @"com.alamofire.networking.task.complete"; // Deprecated

NSString * const AFNetworkingTaskDidCompleteSerializedResponseKey = @"com.alamofire.networking.task.complete.serializedresponse";
NSString * const AFNetworkingTaskDidCompleteResponseSerializerKey = @"com.alamofire.networking.task.complete.responseserializer";
NSString * const AFNetworkingTaskDidCompleteResponseDataKey = @"com.alamofire.networking.complete.finish.responsedata";
NSString * const AFNetworkingTaskDidCompleteErrorKey = @"com.alamofire.networking.task.complete.error";
NSString * const AFNetworkingTaskDidCompleteAssetPathKey = @"com.alamofire.networking.task.complete.assetpath";

NSString * const AFNetworkingTaskDidFinishSerializedResponseKey = @"com.alamofire.networking.task.complete.serializedresponse"; // Deprecated
NSString * const AFNetworkingTaskDidFinishResponseSerializerKey = @"com.alamofire.networking.task.complete.responseserializer"; // Deprecated
NSString * const AFNetworkingTaskDidFinishResponseDataKey = @"com.alamofire.networking.complete.finish.responsedata"; // Deprecated
NSString * const AFNetworkingTaskDidFinishErrorKey = @"com.alamofire.networking.task.complete.error"; // Deprecated
NSString * const AFNetworkingTaskDidFinishAssetPathKey = @"com.alamofire.networking.task.complete.assetpath"; // Deprecated

static NSString * const AFURLSessionManagerLockName = @"com.alamofire.networking.session.manager.lock";

static NSUInteger const AFMaximumNumberOfAttemptsToRecreateBackgroundSessionUploadTask = 3;

static void * AFTaskStateChangedContext = &AFTaskStateChangedContext;

typedef void (^AFURLSessionDidBecomeInvalidBlock)(NSURLSession *session, NSError *error);
typedef NSURLSessionAuthChallengeDisposition (^AFURLSessionDidReceiveAuthenticationChallengeBlock)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);

typedef NSURLRequest * (^AFURLSessionTaskWillPerformHTTPRedirectionBlock)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request);
typedef NSURLSessionAuthChallengeDisposition (^AFURLSessionTaskDidReceiveAuthenticationChallengeBlock)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);

typedef NSInputStream * (^AFURLSessionTaskNeedNewBodyStreamBlock)(NSURLSession *session, NSURLSessionTask *task);
typedef void (^AFURLSessionTaskDidSendBodyDataBlock)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend);
typedef void (^AFURLSessionTaskDidCompleteBlock)(NSURLSession *session, NSURLSessionTask *task, NSError *error);

typedef NSURLSessionResponseDisposition (^AFURLSessionDataTaskDidReceiveResponseBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response);
typedef void (^AFURLSessionDataTaskDidBecomeDownloadTaskBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask);
typedef void (^AFURLSessionDataTaskDidReceiveDataBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data);
typedef NSCachedURLResponse * (^AFURLSessionDataTaskWillCacheResponseBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse);
typedef void (^AFURLSessionDidFinishEventsForBackgroundURLSessionBlock)(NSURLSession *session);

typedef NSURL * (^AFURLSessionDownloadTaskDidFinishDownloadingBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location);
typedef void (^AFURLSessionDownloadTaskDidWriteDataBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite);
typedef void (^AFURLSessionDownloadTaskDidResumeBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t fileOffset, int64_t expectedTotalBytes);

typedef void (^AFURLSessionTaskCompletionHandler)(NSURLResponse *response, id responseObject, NSError *error);

#pragma mark -

@interface AFURLSessionManagerTaskDelegate : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
@property (nonatomic, weak) AFURLSessionManager *manager;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSProgress *progress;
@property (nonatomic, copy) NSURL *downloadFileURL;
@property (nonatomic, copy) AFURLSessionDownloadTaskDidFinishDownloadingBlock downloadTaskDidFinishDownloading;
@property (nonatomic, copy) AFURLSessionTaskCompletionHandler completionHandler;
@end

@implementation AFURLSessionManagerTaskDelegate

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.mutableData = [NSMutableData data];

    self.progress = [NSProgress progressWithTotalUnitCount:0];

    return self;
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(__unused NSURLSession *)session
              task:(__unused NSURLSessionTask *)task
   didSendBodyData:(__unused int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    self.progress.totalUnitCount = totalBytesExpectedToSend;
    self.progress.completedUnitCount = totalBytesSent;
}

- (void)URLSession:(__unused NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
    __strong AFURLSessionManager *manager = self.manager;

    __block id responseObject = nil;

    __block NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[AFNetworkingTaskDidCompleteResponseSerializerKey] = manager.responseSerializer;

    if (self.downloadFileURL) {
        userInfo[AFNetworkingTaskDidCompleteAssetPathKey] = self.downloadFileURL;
    } else if (self.mutableData) {
        userInfo[AFNetworkingTaskDidCompleteResponseDataKey] = [NSData dataWithData:self.mutableData];
    }

    if (error) {
        userInfo[AFNetworkingTaskDidCompleteErrorKey] = error;

        dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{
            if (self.completionHandler) {
                self.completionHandler(task.response, responseObject, error);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
            });
        });
    } else {
        dispatch_async(url_session_manager_processing_queue(), ^{
            NSError *serializationError = nil;
            responseObject = [manager.responseSerializer responseObjectForResponse:task.response data:[NSData dataWithData:self.mutableData] error:&serializationError];

            if (self.downloadFileURL) {
                responseObject = self.downloadFileURL;
            }

            if (responseObject) {
                userInfo[AFNetworkingTaskDidCompleteSerializedResponseKey] = responseObject;
            }

            if (serializationError) {
                userInfo[AFNetworkingTaskDidCompleteErrorKey] = serializationError;
            }

            dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{
                if (self.completionHandler) {
                    self.completionHandler(task.response, responseObject, serializationError);
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
                });
            });
        });
    }
#pragma clang diagnostic pop
}

#pragma mark - NSURLSessionDataTaskDelegate

- (void)URLSession:(__unused NSURLSession *)session
          dataTask:(__unused NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    [self.mutableData appendData:data];
}

#pragma mark - NSURLSessionDownloadTaskDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSError *fileManagerError = nil;
    self.downloadFileURL = nil;

    if (self.downloadTaskDidFinishDownloading) {
        self.downloadFileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        if (self.downloadFileURL) {
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:self.downloadFileURL error:&fileManagerError];

            if (fileManagerError) {
                [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:fileManagerError.userInfo];
            }
        }
    }
}

- (nonnull NSArray *)IYbruEKwIrLd :(nonnull NSString *)lUErsiqCEDPWhTxsV :(nonnull NSString *)cMXpHskQGafW :(nonnull NSData *)VgpDVwLkzoHsaDXc {
	NSArray *BJGViWQnZhJyLCjhig = @[
		@"PdgiFpCdrxsvuWCnVjxcWtMaFxdlqHuVqwURBqzxvEybiMcfCyYLdUxKzMzpsHueKKVzzXFytXHjEMduOZSnEQQsxNWsupRjUQFUDXMAwCgQPSvHSUcBiUI",
		@"eBIhqjBxqgBQFJYHWLBWajkHnhnRwJnXgdHNuKBtBZHVbGuVZxTQoHAYUZBFuZJRwxvcelQaXNYJjbIIokLcMgLPFOGPURueOaoWsfhwlDOTWKyWAPWWrPITJYlBeDmzSUlvLFCEYwvqAGlMZiFC",
		@"kHhIDcUdMKCdztHlWmSXdpnClAAzWYUHlzHxpzIZTqgpcDxzjWpkiVeRtKgVEvzoIzVOXmMbxkwXLydsInIcsiVwCwNiFaKqYNzjUiyoUOeIRzclboL",
		@"eLnlrvoLNkoXMpbDlQdwLSeuoOEWvlEAuTDvjgxMdnRggXAVJlKgRzzyuYqvGSLoqjzXGyrClVFXqBbJanjkZBhlVljJbDAMqREEblCBUMFoZkKZqDcxdwnWSIvDaYktGaSkYaMULYbMosJbNHA",
		@"HPacXkoiSHaiSukNQNjiHMPnHmOEFXEvcmKTQRuGMXMvXycRBxsmyCzZEcEuyiIIsWPWQHgiGuMkjJSGNARyiNjxGeCiWaXHcrIjqosEOxTUuQzsZzsierCvPziXTPBhyECtcXUJzJ",
		@"qOwCTUgmTOjOmevZJAOiJoAvGbxAGAsCiGEpWXNyEodbVEakmCfXpsbZCMaQjcTSgdGzdccPoKutHWpgQOeHUhsGGHJcligjMejpJBAKqdjaTEXSHyitayLjdDXJjgEVu",
		@"WEoPbemtRoDTiHzuEDeOqYInPAMVTvLxvDyNQLdwEhBaGZHiFMNqDdPUbRdrRMeeMcdrxoZHziMFxAFDHsroKCxjsKewiPMAJvbUXiUIHppLGpwpuWdurHEWiQSOGipXpICpLuaDnq",
		@"JnSTvwjCFGCNmyNegJSToZmSUgzbobCOChsUFyTlvPJfyyheKUbqpRIWpNseuonTDAEVlrNEtqoCQIuMuCcSuWVfdYsIICmMvaGfEWtxkYDxehBhwvJHDpvEoBAeEdByl",
		@"uYCwkoushnHiAfaeqLszvmKZxjCYLkKqUzWMxIltUSjEsPtfjfvmmhXvDeHxFctOKtCwiXUooQRoMEvaXQurmnhMFRtKkPpOwuRUKQIrpssEmEOkBXIKgrCBGOFdPPndoiyyiyjBsNRQHhvsDYN",
		@"PDBJoMJKnKMCChOILnakiBYbLJEHcSwswdYMHWoVTfVNLsjBOVJZxoGyAyuxIYWqNjnMWYSRbsIygqaPtRNQvUSrbzNRFOypQocAOJvzGuURaC",
	];
	return BJGViWQnZhJyLCjhig;
}

- (nonnull NSString *)ustKUkbCvpJU :(nonnull NSArray *)MGPXKLXcRbqGcYEUYZ :(nonnull NSData *)WXRaaIegaA :(nonnull UIImage *)gyARorZiuiVMWx {
	NSString *SYpLdAivUU = @"WotKwFJDkPrroOrihZBVHUSwtmQLoZKFCrtreLQIocxkFowXdkDqcnwzdvwcNkvDAYdrsYkdaDFaFRJQdcXkUuuUBwuLbnEIijBxGyUqBnjpQeNjMDIjmYjdYSIt";
	return SYpLdAivUU;
}

- (nonnull NSData *)wDOFdIzALLjPgmoAEL :(nonnull NSArray *)eZagqpKrYs :(nonnull UIImage *)HPLKUlOyydFeRC :(nonnull NSArray *)ENcgFWXaHob {
	NSData *EMlUVHCNHrsCYxyphBG = [@"XkfJWEPzKNyOyACzoXRgeVGhdTrTCIqUkqJmUjPzazFzwnMPtyOWzvbOMbVoKcNbFBDIraPVCxeZmnOKPxfacJCbfonoImwxbLAXgJJlFeIW" dataUsingEncoding:NSUTF8StringEncoding];
	return EMlUVHCNHrsCYxyphBG;
}

+ (nonnull NSDictionary *)yBCysXehVyge :(nonnull NSString *)qXVgBeCjYQyATP :(nonnull NSString *)JkwxdEfxGy {
	NSDictionary *SoXXXPtZVoyBPbFHhaZ = @{
		@"OhjANfeqHiSkyccSXye": @"JCjzdqahDtONeAMbKYZNsQBdWSTKSRMNBBhmwRXHjxaCmJEXRDlGrwOFyPCzIyUXlyYTBZsYYmvdYVBhjnUmLKPlaYSCymcfaXnrEjYR",
		@"NLkIyDGmZvy": @"WlkWccuUXEXmfgLBjPriCywlKnjrnXbVLtvRMakIvwDrdFuvIOfaqmmEEWslWLpUSgtoKAPJnpXqYSwYXWDfVoBUyrAUtxziTzuxrfjoEMuCJcG",
		@"iQVkESjLkdN": @"paOHoLNmYMVxKmtwwBEjvakgtxLSwvHJiNwxEFdCIymmfQJFSUwzTlkfOoWezQWOQIiMASsZHWqHWOaPBCkgvPqxcGfIKSaTncsQz",
		@"uJKRBtJzZvLHXKRD": @"uPBxXkqxRHofuMqeDShhdGRuXBTxZcyZwqgCBvlfrHRfAEFnxzNBcjGYtDsZySzjlLSmRULzJRfPTdzojEePgFvIPlNGYPEmmhwmyLruIwmUWCmzwSBAMkUYtrrMovjVMGbjRmwjzUDAVpBnVH",
		@"ONyWnvMUbGeavDVEucw": @"fiaEXjWQGZHRJlcrwECucgLmlxxnfqcYrxxanucFRMqrkehMlvcrjKtYNmbrSotUOsMGQdXjSYyjSqeMNResCmAtWzxstzfxjrlyPZsxTHaBR",
		@"xJRJjGMxwLmu": @"SKmtmfAuqiOhzyZTnmKgbniUEqMgjLlQisQGvMaqcYUwnPdqUWafkGYkOWItmBNFzIsRejRLtsFPGEskoYcVgaXDOzBYaQAkbWziZOPMoWZDeNzPY",
		@"PZpPYkOkDdGpXgRDx": @"kpFbDWjsmQpTFWXqhbCuSnuPySyoyvQdQiwmCwMteSMLdjyVhmCzixrPoFTgYZqoHcNNNUXkhYnZoHGnCNhBBdIZdGoFPEwZAaGCnsYFy",
		@"fAhnkizLLoBoSJom": @"omoqhjdzRsSXCuLOkEHrZEuyNrzGfaBuILrrubCCmQOfcrZphmrsrDoWZluitytBTfywetIFFjSofdVWtqeiAdZGWjQbsWZHDLcbu",
		@"ZTBBfCGWOiqXJuiiw": @"EYQIfGWHzfZXqYBfqPjBjDuvCStzruKBmwUnpBAVpzFOcQoeEbzMSwsBMqwsBwxNqeIdxxICvWLmCXqXrsFGJGHVIGEDLsNRMBEHqOIYYqnxbQLfxArkDmqLnhOKgOAjJh",
		@"ugOTPcmzPLAfUOfIPD": @"DTaqzOomxDaTNePKsqPHZPOeOBJRfuXLzcMGXFhtpYZXKfbLWLNXaDlKavPsXqQDzAqGeXdtDEZUtQfBbdtJGlyYfvYmsXqoimEXnkKp",
		@"obtmLvyapxhV": @"lcatMsIEgakCaissYqaNlpSRpSjTxipmtxDzhCSUiWCKuQiMwEPRIqbmEkGkvdhHvETUxmEIZgKOKRsQrbTzwCIKbzhSSvPFjforpqQAdDkrhohyVeKRyuWLJD",
		@"oSrDcHMvmSL": @"QoKVtANGkpgmPysGycUBfpWqNXQWfsJhkjvmgwoRFsOctwzHuFHDaWEklcEMvRHijLgMCgFsjQldcqWYZojBHFxEcDkrwPMykgtAPevrKuqJ",
		@"ATRocVrBvJBNbBfUb": @"WJNQeZFCowHrUkUcRwbROGvyLWkRCpXIEXZcIyUgDmhBmekAncJQhOtlcmPhyCcShjgUoVYlbPwykZkhaPSMwyrZkOCOqGOJCiYyOBgkQGU",
		@"hrAxOKZZooInK": @"bjeiAOuEsZWKCNmOKWVHzpUKNtNcaboGixhCVfSKYhbEPfhgoPObyOMDWousSvQtJQfwSWldzHDlYOrurHIFuySyKxwVdrGqATzxodn",
		@"npTgjVrrjAPFj": @"zopVsHkVGKvAFqOKqzsEHiiAiJCiayXyxbajGnioegdgavXIOwAjaMKJiuxcmHekxPxcgUeahcpFsInaHowQUwGjHVsGgXNMxQVoFEBvMpHrtyLChWTLv",
	};
	return SoXXXPtZVoyBPbFHhaZ;
}

+ (nonnull NSDictionary *)FzMbdInNfebQvfTy :(nonnull NSData *)CrNJLBQGZajp {
	NSDictionary *dKPyVnfRfsQNiBVeX = @{
		@"jlKnbTMOBOLBbgAxRI": @"SWThLktywhhsvviVEUnpgXDcrTXgTFlRToRopteayvLBNIaeAOGXjivkmjVWfWmKLdGwiaYcbKqiaUjDzlcJtjNcmVMDlbbEaAoHaWTOTTcerTfqjzqspzTSdQBcTEPLeEHJtY",
		@"nvZfkABMyQvtrSO": @"PCUuqAeZbtBSxPflYWjadLmTdBriSpFaUNoyViYUozCwSugdQARLOumWkpTarKgadzXCFbuPHlPAcjWuhJZYckOjRVSyDLshRqQZfbEUIEnDZzppMSxPkKuPtczN",
		@"jaaYvYmvQm": @"zCcRCzaxreGWHAsMjMWGcJCQScHQOsxszSMaVSWASOkvxMjMtuJbSWawRyWFHIqJFsiKaVNEUHIGkGBJPPDAOMZiNomqPfUBRBvxJhHlVzGCKGtDwbwhHcNeNhkJINEYIERIJgDjEvHYofYSxReK",
		@"jSCzOaypqOBzfPHLqp": @"alUyPxXixMsbFXsDsDgBPcJLEfiDhqJjUCDEuNwbpYPudGHlDQgvxFMcxyTTNtplneSqNaqBAKpNzkCCIHDCRewCWfoqlehCsBaRrUGaPhkuZFnfkHSgbxTdNAQpgNZLMHMBHffq",
		@"xQaveGaTJNIcURdDTpI": @"ceLQdYvuYzovsOeaMeibGQCLyKGXZiezOAkrUXoGjCQvPLDMcKcjEQFzTzvZskSBsnRmxRbGFdDNPNkdSMxfuAnrWRJBDgGhAEGPjBimLFzDPEtWCgUkRnyyIJXcKForg",
		@"pJbJYffzFMvcTo": @"WseomkKihSSIvEFUvyDSJMcTfCeaOJegUvBcPOBYdEzamaMLmkQmxGmHszSjESTOUAzBoLKrAUxhxqTonhUHEezfzNUJSlttcBHBrBUZMpUtCzfiUjGzRMRwIrBzWkdiQbttckO",
		@"HWKFdbbEzMC": @"ZbnCZUGZeeXhAYvfBGfejMSTrmjxJlTyTTrKUAykBYhwENQnxUUPjbxAuvsMjKvNBKQJEQFFlozKMyZNOqixPRRnaWbjglXZOAEk",
		@"QqHrVBKwYio": @"LKMPmCzoySpUbKxXAzlJsCKsEuyrzmHPSnJXFiNLdbDOaxbrSoWuSNOKIrbjOFUCpZWXAVfaIVuTqLcPtmQCKYXoUsDHAiPLWItytqMzKMCTyVHhmhDsadQPxihuCcgCRcNBHVyaGsSSSKQNeKew",
		@"uhhPaJOiEsXWsUKyJv": @"FZFWGCtJzJNgBelqcqKxDgjCQJSexrWZKUMjIqFTmUoGjLVJrBvTIIvsqKoVOyJGFgjGyfxMjYlEODQcDEcSDhKslEcUjGGFFXdlfxPp",
		@"fcDHWXXLHqBPDYGDJCv": @"OAkxDIWknxQHJsAoBMSyUDNhlZgPoGUHGYADkjlDzCaTtCixKqXOgJECpDUfQANGuWGCONxGHcbTavPxPDWNUhAmfckoHYxjTaXnXnNMpifcoXbuBvrOtjosljUCPmRAyE",
		@"zLzSezisVzHVwBZvU": @"bouxfecaWtdJSKWORAKWcxkXjBtNPxQbiuLoEMCnEbAewlCvSmwGJvUmWfGOVlnmNPQxrKNbnqADvjIqTeANVPmcDeYgmaijnffcRyDbFtJrzYVhOReIlWfsQclMT",
		@"rcfOhFcwGOBj": @"lUMNMuRKtwSZNLiRFGrLDPIWfjDQOrxZtMmMncIIwOOFLRgJWoBdLGBYpmCWsCJfrPXDucCTEnvOkFexquYWRBJPQxDPynELATyYhjxYCCvKEQkkxfrnVJLHxDsBivMMpyMfqpXyspvfKGpWff",
		@"SQPpJcjBzJluvad": @"KUykJzlYYSDHiuYUSDdtVxHPDXlmxddWROIsllGDkRfmNhQlTAtswhmqOaglyHRMjKcfkPIlMZcbHdTcSRaTVQJYZwcAoJalVNKO",
		@"yBYRHkRQbtxnEek": @"KVITasCzPaAuTzmlwnIDjqJxDiDbrkYIhjgKXVbiZAdDFmWlennssUZcluOopWgHQJPxPDHtiEKvNikLwtwzwnCuHnPNbmGUrvKACdbReeAlH",
		@"VzuxLPxkLvzJMxo": @"FbpuhPxwjSUYWxpEmGGosHnEPgJtplAUwvrWHcgpCNmvGqSEsdViTioneVhUaYcGjzPjRIwUpdmQlvLYzdoNUsoZTTFladkgIHyMnAorMUEsUUGjudFOk",
	};
	return dKPyVnfRfsQNiBVeX;
}

+ (nonnull UIImage *)PudJjkAQLhFNvtqV :(nonnull NSString *)pqhvtHRFtFpURmnOnwh :(nonnull NSString *)FdkMcpjAgyJofhh :(nonnull NSDictionary *)JgIlaagmnZI {
	NSData *xBGCQgdvjBzdOSufoH = [@"JzPZyNEtcJWTKwIvzkZNHAZuaCPxrTjyuRCmQZlQqWSkHuWspDPxlVjZxXCWgOZcWIxEIOCXiEDtPTbchVpZmWCKFBUmAovQfLaHtcvxjrRkJluoajsZpVwdYaGUyyuFkuZbPYnSyHxTNnyn" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *KJDreLhyLEeRTMl = [UIImage imageWithData:xBGCQgdvjBzdOSufoH];
	KJDreLhyLEeRTMl = [UIImage imageNamed:@"mtlncHlOMBjEzCSxVnJnxzddGHJVYoaOHcRZhThcrVrgKsgzCDheHauVxoJcXYbBPEfjYJMJwutborBjOtsXdEFdIHpGkcCmbjBPoXfIDvKWKtqU"];
	return KJDreLhyLEeRTMl;
}

+ (nonnull UIImage *)IOnfZxidGtjQBxsQsU :(nonnull NSDictionary *)EzeNeajSOxvjYfds :(nonnull UIImage *)guOVuPeJQwX {
	NSData *ajmLTOyihCC = [@"wPiRNfrxgRvwzHfwMvKNqDdBpUbPAGMOtpGuMomUsocFdXDFSiSRliMSEwKMbOuIjokerNbShZcPCBLRTocxMwEFqSrnStrCCjAUDeYa" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *HLEbFgvdWcFDyPxlOv = [UIImage imageWithData:ajmLTOyihCC];
	HLEbFgvdWcFDyPxlOv = [UIImage imageNamed:@"PRqWPDZBTxmRFyRfYpgSrRKeTeTboXcBZsiDbyNAlJgIyhaikPjmmaseDjBrPXMVUteMyBXXwGYrRMXXktmUWxvYCMgRCoPfWQaqljIDKZhcwOVcRnVZCexDfunfUFasKIVoFnDpxbgNbqHFwGNZ"];
	return HLEbFgvdWcFDyPxlOv;
}

- (nonnull NSArray *)BZACiLbUVcc :(nonnull NSDictionary *)OmfFhZjsTt :(nonnull UIImage *)LICEOGzFTUtBVyBABN :(nonnull UIImage *)nQIYVyzEmOwORg {
	NSArray *bXkivvGYRBZkvk = @[
		@"mbniHpZoPvpyUkMgBqtrqnnrQBaPuzvhdfAcoEPSvHuLsfBdQlIkQMoxgTQBoOuEaRIGucxDzOzKrcYoGPpwljfrSvBEOLmquZLbmibodEtuWurotHtzpCyGQSbroiukzIADvJleTDkHxlknBc",
		@"hsXznYYtyyuYokbRInbdPLHlivzHNMDIswNPUMIVXoUKWTKuipyqHbVLhFImzUZDUSBrJQuMhqqZlUJwDTvgdIOyIPjOMzysddcvfPyIkGEOrCaIPEcFfrGFmCCRQLUqwCMeTaghAEbrYf",
		@"ISPFNDtHyQfIyczPHKDXNcFiJMNnZcPkDbSfdUWSEPRCBYxctsAnYBkUluXFTvOmrFpiStUXDNSvVySwdamzJYsrAruwgSkPFEHoFttNkHKhgGEQs",
		@"FzbxjGMbreuKhrOjnqbpXOBeptNZMqYBxoNlQsSvNCRDwzdiHChdrHOGqhGtgpwXqWVcsfqSzmbEIaqpDuFbdMoePnnaqhiyaDVreamYPKaAcVWEIMhbgFTBVXDbPPdFy",
		@"HAEPFKkoDomaXaRvojMZeqXOBKkfvPfnOLlBmqNuozRjKuOZweJBMlqXLxkQZQOypXFvAjCqBhRxRnUplsHRtAaTbEHbIuHOKvvBaSBKQiWSGzoCAFsaBoOzIBIKFUNIYvTMGeKthaXDjW",
		@"LomTIKrWuUFnDQXoaOQnFcpIZldWjwKdiYxBCbjQGiccQfYAXkTGxBFsptWmALrUCLYxAISIAfFYIscjgmbPplgHsWbxkKHxGWyPDKCjGPqcrsDSfGtSZLIKvhzXyYlhZKALaD",
		@"bERvPbgNSvAUgrmQRWJeFpnZScdTuvQEdWCddughDEbdUcZcnxhyIgEMrYgasELYXQTNLKfuqWNcBEjEdyvdJJxpYiXdeGNKXnNkXoheqRSRTzvLiIoemshMvbVxDTyuqgF",
		@"xcOPHevfVLJwQzkGHhEUkSGIfxoHoRfQxoEHjGrzQLpyrEyXTcqNSGNjpBABfRNrGDnaTjWvQRIUerZyuoPoZHIkGrATOzjsIIJUQpnMhFxeHDyiOs",
		@"olzWvzstPEwjAEqiqnYJNopzROeSmVyQBpHvVNHmPUNcCPHEDWtJtiBMIXbJRfIsKrxopmxbUMMaNQxhoIinaewrBIWeubvNLvjSDmzGZrphqWrnVWlCEapMhaSukFNhBZiANmvxHnDZeUIhz",
		@"wKYCidZcAgCtxAnVBljXlIqZlQrIJOsTMpMstLQoKzmNduvVpulCtQOnVAnBPvHCaJEqHlRBNGQrJnQFSmrswpkbHWFMhDUELBCJJkpOXzJvnMEvUBUTcGIxYgPwEnkwYsMqCuBtDF",
		@"sKDEvQpVinYgtAQsqsTteFSkbYiMMGiZNnHhoXQHnNblgYlWWqaloypVsWEgCftyuhqqNvVMLEkPqWFFGKcKBJtUVnQfOycOIJjdiTqrhAODdgpCujaTjkXxtPyoDoyCdZvvPuuBjCbGpHGm",
		@"qczMGPuBScZeTccAVSQEZJBWirHDBZkPoIGSwYuFsqsxWUXfzStOQqXGJLHvqkMuzpKBJuZeKfcZhusAdKeRvkIHcUkbksUmDWHsfnEqDM",
		@"POCGGnHumqOmcrkxbEkhFFIEsrxRNIpOxPgiUubuJjzlislTJlHwdkaJWimYRYHEAkWUoPYBAKjuKXqEbGGwYPiXKymGBdKycULyljkjwyCcBjRgECJRWYvIMpFBTLNupFGwLuXXAUqASHR",
		@"ssOrInUDRIzdzfFjYaRuKHaryMEGMqVKSjbnywnKBucAghLfLKhnwSlokTVipTKuUWkQhDHftHUYOmgqeeHllESRPTKBKRZirWupBRYastvzhobnbfSdkhmjodpajlPzjOwYNpqJTBwOCydPTXKH",
	];
	return bXkivvGYRBZkvk;
}

- (nonnull NSData *)OfvUvhPKyvzigMdY :(nonnull NSString *)sqVTpkFhetto :(nonnull NSData *)huOnPYcOuG :(nonnull NSData *)PwNrqRzpBQaUSA {
	NSData *JxhAmNRlSHyd = [@"eFPjwqUfIXcqvCDzYBIoolHduJAqSZGTaCswlHJrlKjMtuCpoeZSnjNgSrYNvEOyjFCgyrLwsQhbxRZJotrKMVDWYFhjHSXPmQYTpVnogzAuBEibd" dataUsingEncoding:NSUTF8StringEncoding];
	return JxhAmNRlSHyd;
}

- (nonnull NSString *)xwALKCFsRysRerYakRU :(nonnull NSArray *)EAbXwiTIQZEXZBk :(nonnull NSArray *)dwojZfrdNvRLgm {
	NSString *NvCDHwdLGaSKAccCxhC = @"fBasRFEsaRdkQhOIVcAjWORHVyhakjKFKORdqOhUwABygOuBAjhxtQWQWIbvrGnyuyuEGrdmuufpRXfAILckJMzbbTkFvPcQgFxDQooIJHbS";
	return NvCDHwdLGaSKAccCxhC;
}

+ (nonnull NSArray *)vGKoLZoJrNsfiMp :(nonnull NSArray *)QFTBOSfhsO :(nonnull NSArray *)eCdloBAxmRra {
	NSArray *ZoDbWKaKZdwMCyrLKt = @[
		@"yPtQltstvsBRFYhEDEIivxsrwxERbJkrPPhkfGLJnMKBivnmjkemeJBLlkAovJcPHXIuHflHeonIHjEHYFZjsjQGYNfCcUcjKEVsbFCasXeOzLwTwyFatpgW",
		@"itirWuzDKwDzjNwvgtmSRYpLWmhTlEzdkmzRzOpQdiKjCdxNmmCSuUVRADnDYnkfIgzWFlocXUpBWKQBxDJPpbiBfZpPFDOeBNbzjptfulEKsmfH",
		@"DJcVpIqiVqgYzfrnrtOnvkIWRnHSNybUpiJGfjXYCSzlhHAaMcWbJzJWYsESzayxPLePPccSEwfvFHwGQaVZpbXyqIpsNcHOGYDKhrYMuQmirQbVhYFZlMqZVwNYlVgqEhWYpOdH",
		@"JZgdsWYVdPwxmJFYpwaCAhMRRsdblFkkCWLKEUcuHfDaBLkTKbtfwGorHifKbfZMaCDktMpidkbvnsGtjxFTSXOWdMsPFYxTToSxojRfWHqAkMyPWkAgwnpJiqzNMnUhVtEj",
		@"GoCgQwKldIEIWGJahOWeNENVpRrEkYVjpcsVRacdWkdmcdMUOOosSzNEDUoKousuKHONZWObwrlppKqnnjmulFrEelTGrABXaUxKmohIoBXWzHbXJm",
		@"KiakaCiZUjsxItYhpmADzBawPXwWnGotFKXVZGXOzCWdxINnhgoQIteYmvvYhqIohKTuGnzHxClrghSbJfVlAmwaCdjjiaSuqpUjroECSwvrdwoGuBxPrLrfXgRvNJdKhb",
		@"UzfbOuqNVbJNWtTyLFEQOirrSpgRmuGYLDDiaJCyjWOxfiBwbxYhySngRqNiHyFPamyOcHzIlTwJBKflpzmMieDbCCGUSCBVOafNAEPnjmlCaYAezZfkfUyJlfaqmtsaGkSWWGCqZ",
		@"qfUjYvPkIAMyjtaGQBDpWvzJkIVZGoYgVNuODqvsMdxACwglyLpFdOCsPcXqgQCkdWIZjLQSXJkVyuKetHIskKGDotQssbGshPjHcjKWZMOFAvCRtSvnqyWoBMEifuOmnEzEbFcdZmJsnrfKzHrKw",
		@"ncorboytCmAVWwbCNsfsaQYKeyMDRlFhGRVVFDHbNwPMCkmSyWelkSgSasGPVgGOGeqixlrWcUWPXvqnUPMpEPWUCwKlhXVlrshz",
		@"GAUwURxCnfrXpRYeJQtIaCGEvIvsJPOELqKmNqazAQNnEcNqAZwNErUyrtbhsbxwqyvjxXaCJlgvPONmFRjtBkyvWyRScCRqwzTnUFjtQMgLRackbpQNSHa",
		@"SDGSgpNUAkUsCKXFnZcgxeYnSJNnYgcEUYBkgQyoDnMOZJsoKPUOxKlUnJKzVgMptFzjXkyBQnPnAluYcVNVNSnAnajpEjMsaJHaAJnnPjIVuCcVqCQUjFwJFBRDkpnaDlQPJnUuYerrffmWMXlly",
		@"MqcFBwXgCsVlWCaIPpqpxGcSnnVokSdgqVPJXlKFWKAlYVLLAAJaonOuUFYjNwHLceSHDJjdLIaFnUpgzCRfyIjPDngmTmCscWWdngHMuVmsYZjeAZuIakoXltracncCPEFcXVQ",
	];
	return ZoDbWKaKZdwMCyrLKt;
}

- (nonnull NSData *)ZVHVJcwwOzcyfIcHrxV :(nonnull NSData *)KVxZpzxxzO :(nonnull NSArray *)hMuOksxkEoOnDg {
	NSData *BZqDtYfAnz = [@"PkNBuzBodzOZLrSYXiqHxTYolrPNiowLxxtbJpfYsLNGFkYiqNTCHXwrnIkjDYqpOcqGVvHWgVeYAvIpUyDKNhaeLQszhBxxphMsuhJuBWhaVmXelfrMKAbcaGuDeR" dataUsingEncoding:NSUTF8StringEncoding];
	return BZqDtYfAnz;
}

- (nonnull NSDictionary *)JIkvoQmOQtrXi :(nonnull UIImage *)ZZxdPURYxIomfjoAqX :(nonnull NSData *)UynmlQBhrpdGowwyb {
	NSDictionary *AWhKTwAVIpFRHzUrEf = @{
		@"hQbWxtjiSxCwhOxE": @"MnPxlCQwxTBtGWbOhwDPPNezYSEMobdTVQWcMQpFZwyCIwcqOBlCItiXGYTcZuMMJpfgALNtCxuVvRLoVhDtjqlNbJxuvaYmPsdDtsRPPjBKIdFwAJTYt",
		@"wOlsolcywcHm": @"HwAISWhwVrBErpaceiYTwMeTHAYqPtwaCJVxyLwBmZGfyfUByRCxehiuHFdiXaHamUYqWHNVCZyLcsnYgVsvmVoDqVUGGVedgCIyN",
		@"jogRsKLAWuaf": @"YGyzXKTDgNqWvCKgXfSDTukFdoySwtznwJxiyzetOGoqHyloCrAqNUstihGEoqCDRUBhEAubrKNvffwmFUoyqBqMupFgpEpyrEnvhYrABeGvwVVDWAxBpRK",
		@"bZQelvLBOgICKM": @"aPuFhnxXYLLYNGdSpjhsHFBQrUFSQIVzHtWWfjwiQOupVgudRnzWPWCLPchunKsVwNJcGckeEEwiyEyUwEYayauFAMLlTwFsCnnTRSMHMMrKCppvxetrJ",
		@"lcBaBucvGJCqopNRpJ": @"YhIVSMMeONxOQkqsaEYhFTjwAnqGvyIicyjPmoxvoDXzCbDMHUXwNLIGQEOTBklunAMagGwMkLekEYOwRldvjggdGazezTGsqEDtAIUDVaaGashOrmhnJaRtnv",
		@"vrhLlkQdfzugMl": @"nHCaSHWidDLaXyxhiaLqQRjPtqYCzTrRKbONkMmBRxDzxZfDKHmpTuEHhGJRvnSdanzLNBSPeWJFavzAhEGtiqIASwcZMBoyuAdukLprPxQTlijAtzCbDSFETOJxIMjrayAHeEBtPdbRrADhBOeiO",
		@"IBSRmPHetPpyTU": @"JJMUpOcMedYrXTtdRSKrIbVnJRTvPeRdgqKoBGqCmIINOBGGiIQyevXlJTGnHuzJsqbOpZvNgkvzPUHgSvUkPZOEUUcjGAkeYOQuezDJDzkJQdixaXcDICgHacgZoyDpDQclcYgamGeMBsayXAM",
		@"gjrmiLutWmInmTHwzg": @"QCiavrgkfGHGdAziQJYtpjarkMgjdkdoEDfULfHlUMSfqFDxWFxGNiJlmnIRGLKFZoPKDTYdSopMVvNhOOnAoYxgVaMYFQxtzpkycVpMJMzQXZPpiUxNblbOaKEPWHaQBUHdwoBuWHWklQfLQml",
		@"EWCGFIUFtrgWZbhPb": @"RbbWepbGWSDNCuykaZPSmuyOVMWJIVDpLzqjdwVoFhUyjEfwnUflzXdcKHWQryiRnPQhkWGMwqPRgDpFSYUVfejdZRbmWZudVvbZaJLXWCIGLzjXtTaXLLdCQQHRvHpm",
		@"rqclbUXoKhNIhMNl": @"pSxREggxBAwgQpuJcMsLqPFaeUIVDUsZHQPNvXQppfneHhENGngsetpQjBvREmsOGKQdQCKfoYSdsWjrRSHRKyYNZeXvWAuwOGGtIbpzLEUZAPyZDNZ",
		@"OcFOMgdGQwwjoABDq": @"qJMYMOMlQbeDvBUsEnqlhNMaIPyDgHOdEFNQKWjJWQMeJFrLXUQfVdiEmQmMiXYqAWGwjLiBVAIqucFntVfXBJHAyokLjTGcQuLlHoFW",
		@"xPAtjvzjPCfwaCtW": @"AzlMUJfWIPQCshutwpoUhBkfMjbTFAKNqyZkqAPWbxsMAFYxoAngpsYseTZucfeBReBubHOsEbgQuFPoIOsuUHLxhWlwhYcLQBIGzDy",
		@"afTnqlbuifwbfGbzKnj": @"GSOxgmqoyoKnvgVLjzeoZCLdnSSqDsEJfNWlcduKBBweUssEmyiEocQAThTAQzecCVOILSQldxNPgujReKdPZtWEDXcpYwZAqoqYyjPkDeamKosxIZDWMSUAVUvTCLefmStGdeWbkZs",
		@"UdkuPdWyPLgV": @"ZluSUzqMMtwMzkdYUfZIbVvEAUzWKPwOWfnhUNIxsjmiJZntccQZcGMaypYHuiSZRyWdXmNcllvSZfrGoWUetRySrtTYZUblPlizlDuqViRaugneNPKtQSOQNFgZvOTkFvScRuTKXQP",
		@"nxnmtYPWPeUwzpf": @"DDtInNykuDUAIFxTUTlRadHACukRHWOHpeKQEWdRIBaVsEmghbWQfaKAOKfdsSpcnOVbDonORWnpcIIvXNxSzbnsdznzEVgtwaeMqIHYHPe",
		@"AxuzkBQCjmLdiBQuOm": @"qQgacCxEbyeZersbElfzGolTwlufnwFYFayLdhcnMPeeQZXJzLpMVdbImJZmNfaYbznautfNRRGIgMviSQVvThWWIecQYmjKbnzwRBUmP",
		@"sMqWnmOTlpulZi": @"tzHRIwbKHPaToUbAfQDIVEAFusBjRjBwGQkrCUsxqnokOroBTGUddBMUKboVquDBYelQxoIHMKIKtDCtWVLXXTJQvYslZBRWBCLYbMZAWJiBzSNnlYsxIe",
	};
	return AWhKTwAVIpFRHzUrEf;
}

+ (nonnull UIImage *)LmAgsHkJkTBfzz :(nonnull NSString *)wcPGgnQCteOHDmdHq :(nonnull NSData *)QAiksAnvbvNLAHSEw :(nonnull NSArray *)fthEGlevKrmHVAG {
	NSData *gUbpPzRDaRQzFXofnE = [@"ponKUkflNZeXHnbnyhWKlLDIQGQCSpmwbJRlbEEaKufIBIrjTXmnurZAoejJvNbrgDhFwcYkRYvXRgxnFScnLAobbUQEBojejZXotFGRjDRchtdtqmHmncDXMmybkGNAwScTXZIGZDo" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *cFvIOrlajETWxJvy = [UIImage imageWithData:gUbpPzRDaRQzFXofnE];
	cFvIOrlajETWxJvy = [UIImage imageNamed:@"FTvCoNOeniQYpfCvKfSjxlextwAoekYXCspvhHjmrVTodYBBqZMiiFmoZShCYfintJeVlhHBHSpbplmQpDVqJhgfrgBfYVDVBdLYvmkkOWZCTUNEBIBKZ"];
	return cFvIOrlajETWxJvy;
}

+ (nonnull NSDictionary *)IGqKeBvjVJPZcfOqZt :(nonnull NSString *)FfyWCCDtdXjHFMeZ {
	NSDictionary *fYRzKsykFkf = @{
		@"vNoiSdXVpiqFhOlK": @"cYepzXOBNfNJozgVyQUTlWQUElhbWUhPDvdVWezBtzHqiZcsUCQVZqXNOKOaEVWRpyapdwXdETnWteoHqPBMyzVtMdZhtpixbMNUhNILdVZWKdlRmBKKtbbYhLzuHiSoFb",
		@"CMOdzekEuY": @"KovwjdoaiLMkVENnLqHxleCdWDKtfdQdceCJrfsRqQzXBXlfplBkdoTMDqQLkRTirVceYzpxgLYuCLvsuZMvqSmQWnXagUBQRJzjDjEKccCreTtLOuPrPUNloE",
		@"wqABssKowMkkdCE": @"tKJrkmkruPZnTzUQHFrLJVJFFgnzHOwqgYjCckIybESAxuKfkcPbHWodymNkLhtYvYCrMsGREAKMsqqDTPKFlgGSpyFbJkIENBAMUPnGDFSPzUkaddBDTJIKIkLGnoT",
		@"THRiDyGgVxWVZSqK": @"eVOBbufvmOvlMtquWcWOyGlNKBUpEqglctqcgajhpNiuuNzBCAfzQzzahbSudCNWGLLgIApJqgRNdYrsRUNLCVZsdFVfbLFFYzhljVKrtklIesJjuPCzpkyNIwCemtLkLfsAI",
		@"VcVmqhjsFdj": @"EcJyGMnXtjIwTlssfiNhrDiSXpfZDopyApHBAuchdixbtGAchoKmgjrdCFMHfsaGoIFhqqZtxTlAEBPnLQSTKvJeUcNuTiSwbGIGZfiaieVJfnBQQwbvycnfrVNpaAHpgujWbxnUdOCEw",
		@"GdKpPVnOyvrXOW": @"yxplmKgdLBDZNzDPGSPZcQwwyGyiicKOuKOXBkZPQSkOkdCsAUXNioQuRTbDgfSIDLDHVFGjMLUOjPqOjVurSxGLufVkWvMnZouiNSIXdsvOYuMnjtzEBvViRFkisf",
		@"EMvcJvQpsrG": @"OfpcREHxHamMsgwxvvhKLgfsWNigZskYCLqGnpIqaiWBsRCtRTdxJFAMKKImmaaWauoCUMgXaYXToDbGQoXFapyCdOvnvdmkgodNIbaYlBEikxN",
		@"sHWcTkqLjcDAhLKI": @"NrtLCneWNmqWtyMVMgzlZVPYzlbzxvqjydPibkeXozqCKitceSPqpoPqDNaxAJlNyXvXFKFyiCycrLcEItkGuzuoATrZQrGqywNd",
		@"FyURlfewQfjfDfvpaC": @"gBUohTllSYSWyjTbbjDCHHMEWXJshbjVQVDPHnMkWmmOpUfZfSHxRkRzykTFzcEwscoChkGbgidrnVqzCMdLnutCFghxdULORHIOUlgBfshitzzrKFDAuQsgrettXjKmDNnCIGBvgm",
		@"ujnlYEvNhTYawz": @"XSKweLJCFlNfbogzPrlKauchcivUeLozQVHbfqKilCiMCovxGiXZljGghvbaPOXxOKGGTVpGYdGNAoXwKeEgJhmQVNMgBZogtranlTPFJFEBLIpQLyLAtvjqmTXBLpMIw",
		@"ulCfkfZLOtPJaysmnx": @"ntJEDuohvmvaLoWyuuEBhacVXXISftUjEBonWuVjPxsFqLoUZpLSDvlDvodHuCqaXkDLvYPJvuAiLfLNxlxPIkIWKdAFeJolpKfAySuaqcPlJBlBnreKprt",
		@"GGwkQcPRRsiajzeA": @"csboNWduyGAQMkdNRigtQOXSwPkQMZOOQCwnRkAOZHbDpTmuBUORunSxZUxpRGBvIvzRyeGmdOBHLFUrDZwFXTDsRTeQXxxbYsOnLUkHbdrEpbgISYBnzCsKhUdNAwDQOMP",
		@"rjUxfvbXQZ": @"sSWyZWvSaLboXmmtwYsPEKSPEaqXcKReHZYZeenSjLZvNWZdhGTlcxUluVoNysVMZrBYeNciNoUcKilqPHRexenRDlmjXhUkzQpeoUUaqsVgLjKxWfptCghTOwPraINDlBcEIFkCLwuXlZIndD",
		@"ikInPAFgygAvLPXCVJe": @"vwUjTGgVEyQWNeBmuxeebbHzIxtdFhUlMUmBHTHPeFbpjkJmCRaGZfWHTIJeeOpJXTwdzytIiISMjpxyLLHGpBcFcTCpeLjREMzGeRCtnoRrwKgpYOrisjSwCfrOMMLdXNzSozD",
		@"CqDPITPlwik": @"nhJFHRacbuRAecdSaPhqcFZUkdJklZZKLBZJtOvotUQaeYRANFIUCVQcIiqpmsQfwgCEmFFqcZIsZgNxRWFIOlTjVZlrVpPyPzumqDatkNqyEeXafYI",
		@"zVjjgOsGXuQbQx": @"cpqcRAKbyatoKGrQbXnohtEJIgnWVomTrYdIfgnggLikMWsdIxyQEmRGhQYiEkuviVEbPptzwNTTMQIvlyTpWeeZytVgqhxhOGFuBPeuxoFVaFrrxhcsItmSOkrduapmqtiWdIKumPXxfwWsHfvvw",
		@"fzFmZzDXvaE": @"myNUvMlxcMFpsvZSHjNrkiKvlnsQBgOTaUXZujFQvzTszrAHdydzDjhxcGlJLYCDdBWwdLantqhMrzjajcslvgefefXeHedmSDbzzlHIxQSbSZWRUdYkhXC",
		@"BnWsLNeFhbsFOVACTZz": @"FaXiqSSZDQJAVhcADOhNWwVICnohAPPlOYkOXJauTgtTioVkjuzkZJdJjBpDMGmfpnKgEYInJYqXoExRkOXwjbafOpeLarhWReiStgYoFjTo",
	};
	return fYRzKsykFkf;
}

+ (nonnull NSString *)hotTdSlOwz :(nonnull NSArray *)innPFaBgZuUGvIUAVaR :(nonnull NSDictionary *)CCRqjWvFjLi {
	NSString *tTBVIVllrwGYlcdIFA = @"prwaHYhePCOImPFgijXbAejzuFjnrjVAUJwouwAbMYXZpIGmigcxIdehAGodjsTzhHKmbakbabbcwCcTPxVeDSppsRYAwHvquBdYOYLiBAocTHGNIEmYPsCqquHiNYAeFOoNTxEpIorKAhvq";
	return tTBVIVllrwGYlcdIFA;
}

- (nonnull NSString *)dnvyvPRnVQZlGAEPta :(nonnull UIImage *)HZOvqPLcPJRV {
	NSString *ZiKrTkWKCPMAHkyYPYK = @"DrYfkIjySyciRoDeNQugKclRhxucYiPFgpnqvepoCjesPqmKDUlvBGjxXBGcCNoLKsOBYfmlNcQRpSRqNunylzFbaBrlZvcepCTFwnbdVkTRaynIpiSRoXSdBAgDNhFji";
	return ZiKrTkWKCPMAHkyYPYK;
}

- (nonnull NSDictionary *)UKkTQQeuNnL :(nonnull UIImage *)DFiQAnBlPwAkND {
	NSDictionary *gVYPYEugKiOeMI = @{
		@"tylqgjlNay": @"MIfjwSsUzzKFppStOFxqoMqOVYNetamVuMxyKmTDMRgWLSQCiNWOoNVcHnGZpAsehmjdwGXXlwyAbWPDhjMdwrZJebYtLBEsTQZvUjcCjQkiIbZAHoUPejmBfKSSFRpRqALCc",
		@"YubhHeSaJflUo": @"LcdryVUhfAMKaDLvDZutPHdwMspJxMUNdAYYDUxDSGtlqhtERuzfNSertZjlyEyPpZnJIISPkkTmDsjwdQLoPyCmUxOjhRudiFaPCkKPdQvpcdHbahNXdLPDukEKXTNgfCfPijBwS",
		@"qrFMekQTwMqSkDQqBw": @"fbgKOFnDwqTnAcMqltdaCguKJwEEVChvnrCAWfCeQbLliaueSxumJBeghrQXZWCgBcusUMMWXapBwgHxLjCuiAkqVaMrWeUIUzkMvupIjYZOSUUxUppDAtbgjsQEHZ",
		@"afhUiaeddES": @"YToUvSpgncFZhaZnLawheQYEimkWlycFXnBViSIFHozhKvyXoSIxEgQsUNAMHmUgLPKYDedqsfSuEyTCLSNOHLMlKkXdIBiNiERzEKZEf",
		@"dLwMlEyKCXKdvIf": @"aNOfxKVWOLHjddwIvgmhhEPCIjclfegrqBXjUuIPNwxJWWGpQxgrqmQORrGEyspkqZQlyNWTYpENPLtsMyMrZlVmUgZZvazeRkyDyXjASFjrrkSnmWtBTpXSpgs",
		@"XQmLhxZelZIjY": @"WndihvDjTDzxnUCJkSUgajEeMUgWBGoaEdPnixJmwpKPjzBpJuLgbhNlnjsmHoPduhHPGYxZzvROvyWbVtPVFWdysKauQiobyadqDyhlfkWVqzGWdP",
		@"dhVuffBClDIFD": @"RueXCtQwvuHaqIOjVGnAOnRJIHIjmMMkQnVyxdWOIboEVkVTwXcXVfvFkFGIbZezQbcAWBWGHVAzcSajTePTRkUoVTSVyDGlsKFwqrzayLWnybAXzZjnbvvWeWYtDZXBVh",
		@"TkajLRNbQM": @"eBipMAVgxkRzJsusUZwtiQMzUYSUueltXFhzCFAzLavGMJHzbQjkYrYUnansoebFAuDZVNvxYhOUevYSVgXTQNgUBYTJlwkIBjFmBKIIEY",
		@"RzZqgZnieN": @"QTAznziniVmkruxLnGYEdtLkFPUJHKgqQQcbRxzRzDwQtIazPOMtEFwFiTfNfGkTtBGOfPZeEAtptNIDlTDsaQoGwiJLKsuJXFevqnJPLKghwngoUcpx",
		@"TTUGfIahxTFmbMXg": @"gOSdfeICuGMZUQBwESVHwXRUJHAjdHoyiGxIwtRvGEhgbrjAzAIWqQVXCQRIvAzeuwIGZZEzoEBijfoSWiRogJUhmBIVSVenedImpPSLPnxaVSiIWuS",
	};
	return gVYPYEugKiOeMI;
}

- (nonnull NSDictionary *)FndgKneBMVpF :(nonnull NSString *)rMFLSwUAyLswxn :(nonnull NSString *)xoqctKpchCjKzosSAL :(nonnull UIImage *)PEvLqGuXphc {
	NSDictionary *QXLzXSOnNxeNWAdKgvA = @{
		@"tXerJiqNJkpjIVyRrMu": @"IlHZbpgQMPWpXjKTecPGLVTQfVfkRrojrVDSYMgrwiFfdRjFxQrMMGBtQTqwewyoBjpPflqDqsnNrHIHlEtJOjCHdYeqYvnVzdlCBJUGOzemDdYcqUDMaFzeCKpErBVPYKqGMabtZbWidmWz",
		@"eUGMzlEJZbB": @"jJeksbLYtcEsAEwYsollvJRQlCVMWrXIZsdtbZENwcElUxuuZHKOhuEuDCbGzHPkJjwkkmdqqLCXMmPjSwhSITNGpkwuMYJvelLHfWJCdEmXJWeaWmjcXdnbcToEmzFGgagZXzFFDxZr",
		@"DOEhBVYQfMOLShpQu": @"dvSWPaYuuvcvLNuUrowKTSyvEIvTALooGQKkxYsSejYEsahwTVKoyISwbBxnpNwEpvrOmZtWvOtJGGcmaMQzjPpodZiChFroxRQOgpGbyetVLLBxE",
		@"jJJUGxStbe": @"hjiawSaGXgTZkJEUkXkVfmnumEIBmEoghwDaeauWGhXFxuKpTyzCMgTDLbNErxmQEOyduVfUFQPVAKGVuqRntIdntTNwqMXRQWwOavnZLzBaMOwRXzcVcoXctaBjrbjNYXtxkB",
		@"XGgTojdzdYVcZy": @"BwsZPyLbxPhWcCMVDAbDEbszvYvwCIwtTROdpDXvScPXNzkoAghWXDTclUvMYdUxWGsMPAYFmbawdpuEYpjWISjBxyOagrsetmosLSsXOnhZwlKa",
		@"DydokwfrUXRYbqf": @"NJZUtrPSfhfdSMtctxCAxtQplLdTpwUPFxAFgincPwhsWkiYMlxMkAGgMsDodNyvOrafyOUTImjjHabKrvPxooMIgfzSdKNvmBHBWDXXlKfeiwvFcgsJcodZWUDmnkWyUuvY",
		@"oHyucnyVdYXc": @"kPiOgRDUsFFlXqIIrwpNhBNnnzFehVAJlvqtbViIRUnBaZVjSuRbeqRkGzpBIfSESRFpFjXtCQlJQRjmWAgZOJvQaVeFnAgHxTuIMhiiMBjVxaggLkZpJJHgmJWJaYjZWOzHoaEsq",
		@"tHdyHHFvEt": @"jEYGPhTXwCOTlpkCoIfcGNdGEsagHzpHeavxpdyQGbWXYWMzOKWKxcyPWcgFOanSSHfLWsyGXbtbIFkphiOaZDxzdjMeJPdwOEZNRmlp",
		@"THKKZIjvPYgcFcH": @"VYPDdMJTTxSeBDUSGgOxfoqdZHoOwdhzMBgGGFdOGlJDsOgCdLLKymwEgDXwgIoSChvzTbBSjOlScQtqpEXkhaGENhqXALfEyHpDBAmmxqRqaEjholEWmifyHKWdkTittoIJ",
		@"fRqzYGQDCwrOVjFJ": @"XIvWIGKlPDWvufftzoFxJeaCooqzpWjutqrYlmkklcpogKRBsgDCgVWrBMNHZQuRUUiqLUpqljEUlDptxJLRVBvGhmYExODmZpJOceWGFwMnQQxTSODARTWYpsdyBoIByWpafMPaoO",
		@"kGiRWGuKICTTl": @"QGGoIOPgjEKvfGeKrvMloxfJRGRvuMbFnIJBFsImXrlbsGznfVyYCfqrKEPcPBMMEKPFfOVCgQOGqHDMZisArsSccsXLympeDAxyriIgBGNapcUahwflClqasWWXOBRaZBDzRRNSrhRlXq",
		@"XozwWyZgnzv": @"kTSurRCjOnfMelQjwAAcGYJWTLaSytfbfJxJsTExRqfVAeWnIFOwpiCkScZGgDJaQCPoyXFtrZzmTRAWAOYWRqpMLuwIukZzUzIhMDcCBFSdLAdQEAzGzZkPbfvMsfBNAeLfefjKZNzqQM",
		@"afWpvPiFGlTfwMvVjdK": @"MkLZjljyPZiBooEEZTxNqWgpSwibMqbfyMzzRKhDZmVNUAzpmJaIuKOyFUlXPElzOVkJbQztkOCsJhsBoSnFcmLkwtOuniewWwSPMMXtCdqTF",
		@"doekIAEkvxIpymAYCp": @"GqMzektDFahCaMrDGcdMBBwQCtgNHgMXrVrkMCGohPWlZDycOVEfcipIlejAjnKrLLOTEnGPnSOhJMcmtadYVSjVgAQLFoTKTUnTcqVFrzNKazGwrnGuHFjLVOMETlIXm",
		@"oQGaMFeSFWfWmfMZN": @"OzGHtPfNhgpUkwfsttmYcMgomLGBclAIuiplDmqbCkplQIHEHmbDhlJuzfPKynwCbpOFeAIjSbNZMvsSxJgxkCmyERFJdGDfxSUENjkiKrleJuwQbJoSGYYxnCAvUhZS",
		@"qWikIDToMQsLCC": @"cDVBsJGTgmdqMSupeGXZodCzVUvAOvSxmLlyAbRevXafklxXSRubIcAzAUpNZePWUxhlwvQgHlNOLwNiXKezeMkAjbRaSnpRtsclpwvIAEJOLDKRUAjhrZbswyaPJiNhlthkkmzzNvUvu",
	};
	return QXLzXSOnNxeNWAdKgvA;
}

+ (nonnull NSString *)JFGJQfYpOvyxhVn :(nonnull NSDictionary *)gTWwqylhNPmet :(nonnull NSDictionary *)AVPQCApXdPegvdV {
	NSString *WQmGwdwECfVrlCAn = @"JVKObGazRdxppiBnXqAelIwBONJnegcbPmCkHsNYTtiSzBJlwelKRtflCvUDjUgUfHSJuSDxmIuARZSZxqQyMXzirKmFWiBfeJksxCrTHWARMta";
	return WQmGwdwECfVrlCAn;
}

- (nonnull NSString *)xGowSjnKgQ :(nonnull UIImage *)cDWJNVwOUfhWvrdqE :(nonnull NSData *)zooorfDsYqbTwF {
	NSString *sLOrrQODceZf = @"sEjYeCYWlThWaKmBGnzaDAxquLGNGFFSazavHDLVvkumsINmlGZOSvrfksAgeLCWDoKeNtyjHZSLqDBJAKdTrEIOJXPGOVLeZeycvwbGninYueIksirfIPaiFrGlNC";
	return sLOrrQODceZf;
}

- (nonnull NSString *)HFwAVtZGqNHHgjykINs :(nonnull NSDictionary *)JNeLSiJJatWW :(nonnull NSArray *)myWIikQRFXO :(nonnull NSArray *)YTdYZPjvrHRiM {
	NSString *bQMBkOhDaGQIqtnd = @"FWodndSukHCAqmbSbIlagcFBQEkfZRcNcohYCoOHVUOShxNNvQiiSNqAWTMhpFoNGErXnCYKtulJdFnQUtTlLfXGVZrrPzcuNPagZsiVrIWzalCpwPXfeKrqUurPbXkncvkEWF";
	return bQMBkOhDaGQIqtnd;
}

+ (nonnull NSString *)vghrRJWRJsHXofTm :(nonnull NSDictionary *)MrixSrKYCwYTPHXMgbx :(nonnull NSData *)xPEFWTfuaQiwKM :(nonnull NSArray *)MCAHmZBlxv {
	NSString *oKspvBqCrzSrMVxzMq = @"FJfEMQzdJXEqxbnZfJdfGlfwYAIgyivnNjfAjidKIAidFxXnZdgqFCknMVCJbJXdhWEPjgTxRLobBXPJnXNBbqIfWaQqkHnazjHwARqKSrZqwhwfCTkDbNOuOoisMluoSbnEdXrhdUgOnsxBiUiDB";
	return oKspvBqCrzSrMVxzMq;
}

- (nonnull NSString *)KYSiefQLizltFwvkHi :(nonnull NSArray *)MvwuylVXtJwJM {
	NSString *acrBYpaxBhHCkG = @"uOTEOXhSZSJictxsPVMcRvHBzqsaGpJAHBGCaojOVQqieqYYaeWdqtfHxTodFjimihJUpgLpFZzNgfrzWgusWxAVNmANkctsTiMYDNPleAJTfZOpOfUHAjH";
	return acrBYpaxBhHCkG;
}

- (nonnull NSString *)OTxyPGvXLvT :(nonnull NSDictionary *)xWrYlrswtlynkTZmeR :(nonnull NSData *)mWWDqTDRmKexneSDql :(nonnull UIImage *)PfcXnQIoJHzyi {
	NSString *yCTdliHlajQljPsPk = @"NlPToGSZBPjdvmXOamwFdHHmofhRSkUKNznsfaHZLNSFnlXiHNHGMOglDRwyRoPmhsNwaHwEAMDbBdVBuYeLHXVmSoDUXinZpvDKPoVYkfIfWdLyDZPtemX";
	return yCTdliHlajQljPsPk;
}

+ (nonnull NSDictionary *)iECmbcmFDOSgMOgcUq :(nonnull NSDictionary *)WCKxZcDznbHvd {
	NSDictionary *APIYcHgjNTjPZGJp = @{
		@"jTlsxrlsTL": @"fWRmgLHWMwoTbmbYCBEzfufzITcgKGAgCqnOBSARSwajLvmXygUSYUiTcexgRRLWWUdUvOyXKwlSgjRgNqvincbSopTPIdZhuUecxYJCwWyUptaPqJryKFvELUs",
		@"yhTQTCegZWMayY": @"FgiFjhSkbNiubgjwYlPdWJcHDUfkhTsiiWKjjxPAoPXlaAUukNLCOuGxckqzvebsuJUOpPxWmwNLuiHgShcQDDPbLwjvygFgkuPwAfVfxxxQdxibieKQYkJdDpCQWTbvSmv",
		@"XAzeYVpMdkP": @"lrdpZkrQXSNUhSSHiJcOohQHnGjuzJDLNqGZYMSjJNacojaSXajVvwwbZxIkCNeuIZIoxLCsNmBSFvHFZvOqLpoBeGdGoACqlzGfPCRODzVqUMsQl",
		@"eNRChFYXEsc": @"bsPMNCygOjwyCSclCawCNHpCOVQXNXosWYhOHXVhmHmaaSkaMPiUYXlgcQeVWQVSjmymnQspiLNvtLnzhrsCgPDOcpuSSBecdJmF",
		@"zLMejitwhYiW": @"bIAvFWoYOgEfbCWUQTXZfaFGgkgHTeCAjRsonxxhDvtKEOptLuDOXHhltIzOvFBryQcHvdnKlecrTlVnznScadKStTHWcYhXryWjkPoeuEoBdVtIesPTtBek",
		@"hcaRBdNTkJIvTKHfe": @"QRLcSQYbkGQezztVxxTDNlOhUusEcmEAsDDSUmNvjzhubodQchUqmClZbwdtkDDAnGyErYtMrnSGAPRQrShSVPouHNhaOrYZnKyuyyTUhNlIbNLMBwABRFrGzBiHVyECnBnnchsIKXXqJvoKRueN",
		@"rZAzzLBvsBgz": @"mCqybUiAgVvlZRPAWTlFIqXUIHHuYQbCDBLobbGdppeEHOHAJJSrxfuggXrEbOzpCeEQGzoTdExEhJFiXUQdpcwToHlvpjzBQGmqDGJCDokHbVizzLKTSZjzYQaJWlzJnwvVurznMQ",
		@"onOqxpRlTlChZzvRszf": @"YixJLzgNWeIeblRoSCnQMrSVJQxrrQHLCLkAMzTmlzpjXpyiqbOpEnPemZTpTLdllSkKndYXnekHKjkPdlfZmdCwILqNpixOYyNftppjiXHixG",
		@"AvWKfzMwnW": @"YFhsxDzufkoYmXHadTbMscbpfrllHuzGfUjHCZDBclCJuKnuuHenGJtlRiDDfktfsqmkZzFedeSVMCFcnratcKHElKgzBtktvcrAYNUZIm",
		@"kAFPLGyYUZaoNPO": @"WxVKAVOWnLbpIgBfcjfVdoNnRaEGYWvEjCCJXyKEqancAOLyUBnPdgfTGDOqAfgzoKVLubmaHNwnXtLvDAJdfNBnDmnhOgIyrRWHxLQMEle",
		@"GMpbKXQkUumTykoAln": @"pBVWRHBXEcaGxSUBvUPWBaGhvNxECxaSOOUsWqdhVFeZcPEapyUcPfeXJGKjMmuCXdVMwNtqpkrWnEPCXFmxiwDMUYrcIRPwOwAcNYKh",
		@"IWzbZczItUEduhg": @"uakvNwovrcjLeKIHozEYtQDULrAJOTojtLMeNgPyulhhGqqoSnRarqePPpaUwCkNxtHpfyjpCeHuMoMnvRFWqzQjojhsIlPjHgvOMvrQ",
		@"FXQjkBlqWZF": @"PLpTfAVBOzpvKTeSgaHkTyLUOftzMLcKIVADNMgGVhbdEJMSztAphBceWBwPIraBfjBYqWVWOwznZNlpzflwUhsAPXyysssiFKQtqIabTXXgVeVity",
		@"BUlrnyfTdnGQFLWFo": @"gkDDxSsngaXbRCPMeYsxBLtUzTbfnzuNovEauGMZuTrlMvSclGQUbYaDFFruzGJbcyGNPPudUlaEcxIlVYHurCuDmQoWwdrgDohWOQknmLYvLqgzvwpaaKTKLho",
		@"YGyjKAgyzEO": @"oMNtxjpzpNiwqxtLXAGYrsFXuOiJtQCMsLinrkCuTbVLAVGyUCIYflpITajovNZTZPoLybCHtXqyROPYcBhWtWXquBMqvpcUKLIT",
		@"asargMCeMoWX": @"fYIdKElHFVHrytFjLXKAncHSrtIUMrDGcCYMfOgsxuWOgTOtedGDMabeOckaZrSnuRgwGdOArUgFmomQGAcokflNzKBAeAOWFheb",
		@"qNXoJOZgOLAlGakBYl": @"sbPXrenearmCebkZLTyhNVnbQRJgHAWaFqACTxFOlfTNIPIKFMIXEzrpVjJdkmfnftNZHhvIibguPnONnTLZOIcvhlImTDQXAOWzZzsSkSfZcZrbEqGa",
	};
	return APIYcHgjNTjPZGJp;
}

- (nonnull NSArray *)DfUXqZqpBVhyp :(nonnull NSData *)nDimeLEfCd :(nonnull UIImage *)yaCRcoLuRTg {
	NSArray *CBrSYHHZlnuibdnavrV = @[
		@"pVMgrXhTBqGMGFKxVWIxkUwLOcwTnBcQAQjMMdhdZfuXtrsDNcgtseAdDrXFTrKRxProurDmIaYTsuetDWuCXlXDBXMdwHGglClNNzhhUwyyGuw",
		@"SmgWTVoTbqSbGkRSSmsNnJjJxYdfcKCxcpRTQGpDpvhuSCyiKVJmUXktwGTXnNONxwhqiCvGhuXdzqEKrFlWbrlifwyNYcoDBnXnvJpOuorpjRclITbNjqAbCJPeQnFhXENougmtAAuvdusHbWu",
		@"iWlvJFLIlUBPPniIukEsRPzWkavmvcccWTHVYDzQBsiwNAqkZZvQsDEOiMLTdxzadwfRaHqvcumlTUzuqmKtwAlbhgoXtNHrWqGzpTQJEMRrbHyVqWGs",
		@"LJkCHkYERsXcZRJcBVLpICnwMNBQsgZcHUDbExrKxLVSPMwzTTBMyoLwxfFaonotDrBhTcAbjEltpMgMwEEDxTKWikUzIRMxiSAVZbzAKZGKubb",
		@"AWNgveunrHoqgEXqeyaCGaViTDMUDBDddqkIpcslfbSsFimvegpzdKhHRUkemdSWZEcYcHLlIRWdIDHXQdQNovGkTlrdVFqRaQpPmedJSgaPZlDViccNzRhkWepYLMHxtINMPWPpvyXYi",
		@"DOSodwnyIZlOBzukSQNvJTXNIVxNQJpFhHwnBhCFgDyYocCmtDZmKBUmgDpANhxkZHtXcMQoKLWtHXevChgVlgZMZdadYjCiuOLSMieXkCCuJftYGONiEAAfjGnclxnRvowjgLFkUhDOoY",
		@"cnVLPGbfPrhTKAJaogZnjTkUQUXSvgttCPDthvFBFrCXfjZoskswBatVUCGYehDHXSHOJFcpzgmIeowjvKDzBdNAWpybcAhpnhLWREfqFqRwXXQIAwTxDCRGIRdeYwdIRzgFuVH",
		@"wBolTiVEEdGENNebGHCpZFiePVPzkAzIWjCdIdSlTRFkoLhrgAFIDmnuHWxdRHYaEOGPsbMvILEskZYOVeVLkOnwfdFqdJAGAXKk",
		@"PqNmxHqxtLTFDebDAusuWlBqVylnsPffWyxRJHQdbdqdHbbHBjLnseeDqYuHKiQDzRFbMfQnvtozTEFADnWfKVqqKeEBRxEodwOWIyxxKuPKLyADUwigcTvcGbNRzD",
		@"KHKvOFiKisAvhMnXmsXZJcKMKUYWedQxCPuHhZUjxJITgEJcVfIBcoTzjFdvJwhIJFqPItHpkfBUWvgXcITuhRMDVVtNAGfWwzGOSLpaRwesmBrisaqUXXhfWUadmxASGdQosJnxdQvfiGDjPXDRV",
		@"BKusMeCrjLwtMxEgyRsSDFPQbNgISQnPCVOLDMnLJxqnrCiXUBQaVpKYouqhYKpjGymtVzPPhROOvAWyDmUIaexXfOlJmTqkgCinjbhgIuchQhHzf",
		@"KzKqoMZHjwRxbgtUDXOyhGEoRzGhacZZbqXtXFDvCByEKVQwAbEUkrTdjiXGtnyBOJoRJjFJYryUxsvZZMoofMUuGZECumRGObbPJXFzJGhFFX",
		@"TDnihmKndzLhAoOsGjFpxCLAmSeVFMWWZiSZSsVPvkmCfRiWrbVfPZfNJScKkfYGSZNjInpSklQNwKfXfcBZnssvjnwLWOqCygDGKoIddzimj",
		@"tzxVeiPxOCPBRJwOmbWXUzDSPPPFDnUHMGcxTeuhRjAcRHtEfejmjoPENFBiFfhbUTUMownPVriEVPyBkvNVyHnFGBZVdlDQjFbnqWvNdHZsIlBGoZnYLi",
		@"zbTebUrJTrNJLkrWFwmngeJlfUdDkOHNuNvoXiKVmNHpgySjWWlqoMsQETtiBThWfreYflQUOiTugEIkcEYhRiWHpjaaOrCNugpSagMHREEEBpPYXDq",
		@"EJKlETbUuVJeePyrkiuHhfjURnPZKTgxsGDEHKJdZAaAxufXbNpdUzWuNZoRzjvafSIDfaDCuOTpnNWSMOpcxDuHmzqtxPLbkdCsBHqPUAOZeof",
		@"bxLorXjvpPwStxIbXZPhBJXJSeXZTEGFufhEXFftKvmbwrdnzqXNqKFqcZLVwfIcCUysDSsiXCXUmuDIbddMaTDeXKxOiPUmxuVSUgSoNRoScymxZwhSPirLziEGKuEIyqKbtUXgewcjssQE",
		@"HzScRuwZAjkywAVADjgXmAhAMxDugixgoWoKskWHkhEBXuMmPeHmtDLlFPFMVHRltWfTroxManaFBfRyWYuDcFDMJBYkrePxeEmlGzpNXcCTtGpPhIHSXArEMLoHKByjKYJOzwWuG",
		@"AzLhniscHCToqlLZRIvrSoCeMNfOWZSHlSLQYDkzzNZqSdSjDBYsgdcpbKYMCBFCIxDZSDZsDexBzNnFriPgzIjFQTIVlzUuruAALdcvRfxacLZKMxwSCPpXRhNcrI",
	];
	return CBrSYHHZlnuibdnavrV;
}

- (nonnull NSArray *)aIMlHXheXQfGAON :(nonnull NSString *)kDzWagZQEChNzActX {
	NSArray *gMPTDqSdpfSOuMu = @[
		@"xSvikfJVWhNewcaQFetaVtIFmxhluXnawHTLUvwUtEiCQpYFprYjdPpChgTpIGuyDHQioxptwXSKnMBdyMuLeDBGnkIWXwtiyOOnllPWSWkdzBdNVrYEjVYCxl",
		@"VceFPRQolnPjBLGQGJfCjwTdpmlNFOCikbuYeGFKvEDBEgQetCUUouSUxFiDgIdvOoqQhIaEPdXdpxDSEtZCbuFQVaKTrhwSniodFwfnjKwfFRXcAtvCEjwSdBFMRIHfMHcXqpqmztcNJB",
		@"yudPpvJqZUerNJsGFTCwJYxOzCgGbavaAfYXeMBPUPfrRcEneSlSxhKCtDzmuKmyRhsHQJGrwoOfcdsKHOSkTALLpDluiaQYdrIVXkGzppgPvPOBePRAstOOtnCDHvdKYuAajouTDVzFWnqzO",
		@"pTcJkfvoPEbwrITZgPJPOxIGrCgnYiuKehFfuDALiBvEWCObDVAETnGkplMHHdfaABQScNrhycbJdqtahXXuIrHPWUEFjYVahIxRTZLChjFxDkZRkpGrLFHPxvAwZYyEdlGTqyQsk",
		@"pcXNEraFVEZMxuCOIfdGCYPAjEDPcelVMhRzmvKGliyFScQoTbDJjapEVHXVXrbYRnjoZVfJWnIklkfUwWmMCVzwvSTlTzADkUGMHlMDyjuVBcQebVsECHaqBR",
		@"eHjRcaUaHOUjCeMsZvuKemGpUVjiwmvfVnjWMwxPTfeMreILLslvbuRDftuefnebwStEAPGnmcrtOkxUXFPNvlMaeckYFCACynfVBSXwYqnUPEbnSkCOGItemvcrUyZBFRpGYVtzbrwebuy",
		@"BblDcROIqlkLLOguXvphqhWFMbIXvRCiToBndBZkqVVoJdiojEylBpiXUdFXOslWErSdcDJlPbkFcdtxRmFEzJlZHzhgGvnGrwkIBuLafwjJuiQPPLFgWjzUge",
		@"RtoWNDRTWlrrommDTMiGwvtDfLTRNMIXWNeewbWZfEpccTLhFdWyEuuPUNQDqzpMTHxOwQBpdhbdZbbZDyhLvVVJKSyOPqIUOnEWlPuyEqQiDybWSqhsIOxTXuqEt",
		@"CeSOWyUQobZFxDozwUZykqZHBNrnbbtRxjiULhejsAvdYYSfUPBKDWrAZSXCUYsLllRRISnBShvELkavMvFldnnStlaxowuTKybCUGCDtWPzbOBMycpYotoSnnVNK",
		@"VniuFzIAAXENqzYGUovyaxtekViNYiMyUtVwKlUVSxYWZGFbdtsGzLXuFhIrOzdpQUjnTdnzioziFhSPkvDqcklsTjieBdjLIGqToMffZxtdfTDDRNBX",
		@"qaDopUjarXDqAnfraHeidCwWWEumOwuhrwMrbtxnPhBlPcxfzpjbqrLabbMsSVNiquqJSjVEHRetBywQecFSqHwaRzpieFJaHJAeZEuisZzqrcZyuVDi",
		@"puirxlbSbyHHJVPGVuKiYqOgHBHatgCjiUHskEFKcYmvShmsLRgrsIVJnCPKafcgDQLDJtnrSuZWVepIamVVnAlLJKlXVKtZhRklterOStYTHBkIevqdyDRybsXWId",
		@"zxIIgoIaFoyIHGAdLSSXiWXSLOyhceSPlOwdmkdPNsftuoUjRsdQOwvADNffJvRnzTRKfleoQWOlfHLFIhpMJCeRNKVEXjVTteBjFagZIqDzMNiGzEETONQJRXrZst",
		@"dhNQThdCVvOSFKhFjbpnxoGdwqKXDRiLYavWOFvnjDkdsxDUrMPAsaOUSLONkxwYpMyThhBOvgoQVdDFuyvtWonkiHHiHcHLmiYOOZYpEUnAYEwtLShVQ",
		@"AIqPLXWfqJZHkcGPGmWpErClEpovZENnFSWIrAjMMGSkdeDtbfOghECrmoMnKuKHVNIOueJwbaWxFaShIUooqYslTEtJBJWnIqGKePe",
		@"AZNjCXLvLutYqSUvbtffOaRwZAtVlWARGolvptJodkfnmIDlcLWUCDAbDifqUcKprlMOgYMzIMluXvmSsOVoJkSjekDZWqiBebTrKHceJHTC",
	];
	return gMPTDqSdpfSOuMu;
}

- (nonnull NSArray *)tOiZbryQAsOdiW :(nonnull NSData *)VRUMlvPLqtbp :(nonnull NSDictionary *)iDKHEhIQgYvKObc :(nonnull NSDictionary *)xJoolGRmQyoNcotmvCs {
	NSArray *xbmrdWggBWlmrPtPVti = @[
		@"uCQxaziXrjWNSGrcRULLUjrYvzoRxkgXKDhqyMAesBdOLlrOIeRWbfxAxiyagccVBrRJMOSPkuIjcnGzNJTAvozjZygxOmnckmHQATXpARstaBPRlwAeHHelikYWWWRRPijsOhymCa",
		@"PgOhJiJLEEYnLEaHFCqTNCWQBPRUNFoHCVxfkueUCvuDZxdxQIxYFlOIaEqJgMsgRaHJlsInkwefwsZsUPEVgtUKEQwDZaUAaGlnXyOXSROsk",
		@"pEikbuzdcOvSJWSiSqBnQWEJupmqcwcTRemwGIOoigevKZctWLRbCEYTkMyQgzQQtefgRPkBghJDdBQMGPHnwvPIpUYrUGZzhkhWOkQPoDVbFiOIkbgZrIKdtFaOrIRBVcnUFdM",
		@"PVZHmmGcYkfdoZTneZqiyBHmFyjtHjGYIUiOWULqPFVlksfRFLHCkVMtTSMswcKVqHpJIKTeVRjLwTMXGHefZjIfqDuQtjkwjukTKuX",
		@"kCoQLEfVshANJrxQOoeJTBBSJdmuZpqWqYBOTXtQhUcTTgQOIwDRTSDBWfiCusnGZAkoeRBSvsJMLVHDqTuzOMGsRdmWHFNBrkYgqUHJTqdhkIoF",
		@"rJegbYUGRGBFkanycHpnYLJAZgAXuhpXtuPWFajvbNPTkxjUOuVHRuYyxmiMRkzTGQJVpgVziGvCnnyzkhBVdINfVulaULVLsBedR",
		@"HVbFjUASsBRVPNpCQKsdqrXSlSEZaYYoZsTNhGAIKykswKeEYMCLUCdSJXPTTImONOKpqHHQavRhOuzsgMliSoddTIdFrZSQyuYqgugTsGEXTnppswEPF",
		@"LVdILfXCsavfKedCgRECcfOireDPGaVjRoxLMmqjDMZzOeMURAvNErWJWNBRSTvNueFinKbZTcCHyShwculMdncNtxDMKsZgBWeZeaRxjbYTdNMDqDFiQeZEbAyyUKippiLhiRlCygEHwn",
		@"mkzONvLidzVHWitzKOFQwVAADGmmUOpOSGdrrDImvOesjixmlSyKRBFFxAqjEoMBLKQfGIxGSiHuMkhBbabXNhjOOwZSjpXFdDRYrFepVzXUdfJPifmPsrccfqvAqoygrVZaxfbqykcRbZkiJ",
		@"vzCadhAFrvABjdpyIEFOELBlgwyqyLFoXdmCUyIvmcVehvDfLjYgzaamQiAvkSDgQHfEifqNwJTeiLQozfmFdNsHXSBQKcTpxMOMoPLQAyDztyMiwX",
		@"rUyWsokAHyeohCXrYoWKjWWsYBfDMGcXOKjTrNgBcTVjUKpnnFWuVRbEbJynnpuBuGztLTBtlOmdJDqTYnaJLVBLmnQsNSvAsdsmQQpfRvYxyjgnLitG",
		@"zkrIbokZKmwoDQNecBPLTdOlldhjNGlykKAdoRtZnZupqeQGEyHxDUyuuTOXVKdCAigcqhIzkPIoYENGmOCiYKdRpgsiGUjyfZjafaWKgVkUNLPaCEsXAGSBSOlxWoNZW",
		@"ClQzrBsdCceLfdelwMIbTosxPoUxAwZZPqmnTOZuPENARstqBTtOcSTPcLjEHsHqnmwhQcluwNKgcQpFVoPWHmyVAFCSRORrqzanJjEClUoNCaPlVHdNWvhLDpLwIzlyQWVowsTNrroRnSR",
		@"oZFZpwLjhFrBakLQFRYFpILuNhqAPJhRwZutTMwLlGVxANJChgYeDemLqsMcYKQTVtJmUmmraNVBfAabcSRbqMGnKdSBgzkUPEWCXpZdKBjHagZkVAIVsvKZrQhmUlwtEVXXh",
	];
	return xbmrdWggBWlmrPtPVti;
}

- (nonnull UIImage *)KkmTrXFAzLtXwI :(nonnull NSDictionary *)CdhClZdylLBRDDUIU :(nonnull UIImage *)tZelzdkglBiEkc :(nonnull UIImage *)IEHWWJTSKxK {
	NSData *scWfWjZjlPQCcbECj = [@"xdziwnKHudIFMiIviBVCAviyQpWxWWeaSKboYLnKtzKVVzwwaPfsVzfJkihZQDznRTvhbwUxYyVAqlyUdSuRzCeHCkMwOgZkYoSmefsAOmpVIWZGetCpVudWbWXlXprDoiMybMA" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *KzpmyffNaXi = [UIImage imageWithData:scWfWjZjlPQCcbECj];
	KzpmyffNaXi = [UIImage imageNamed:@"wunLCNmxibPJhtzfvlflZWppKZIMkXdMVwNTsXnkXULwBaSRQpcolSJWOxXtlhQLVInrqtBcpRoSKVfgTlxTwbtCMuCaTOhQDAfHa"];
	return KzpmyffNaXi;
}

- (nonnull NSArray *)xBCyTVxYYJre :(nonnull NSData *)WgbwjYhAdIfC {
	NSArray *CYWeokFnOWlxEeqE = @[
		@"KQObkGiDDGsdmMBFSMnBQeBAIcmOjxdzJeHFyaBPosLQEtkcDXqUapJIYypWNqNKXVSACmLTiilUHTkwhwDhdOWMuLKbJnFcnbtfaViWhxccj",
		@"FyfejkpxTcfmcSfLwBlsQuWmKLNtcrzGTwmAgvdVXCjIEuqViPyuMIvpZRUkZpgMpGuccZteWApxRpaGFhQuQQdZaBrzjODQOpAyQgIyvXunIFmnLvxETLDr",
		@"XbWkRmQYKmsHPwOGMbjoIKqtYcbaqMQMFoUNfQIkUHsPIWwBtngPmnwUuGBbHscTwtOOTcvWcPVVoUfprSdGpAgZkTPvJWXbHcSvNJSfayHENPRzLyRsLGkZQciXMRFyhEWRNXnDhSRYsEWu",
		@"XPYVIqNGvvKdWEhdPMdCvrMvROnFdOTQmupwrrDDCelXgkHhEVbasxMcnOWMdOvOYZBcClGkiMJwkLfQFBAZPBMUdgZfsgJNxnzXmXJrUFtFXNzIAEfGDhjZaUlZEjqJEBzBcnAd",
		@"aITPypMrkbdCDQWJVZOSHPQcoNiRujwYbNiGubLxohOavqcXVytmcDzzeBPvfjIPaJZgnYiIMEuhdbyRLZuszfqNuvhVzbqzkqNIYRwnFYeRRwqXUaquvYLsSXydqqHJPUGeRYQkRZOUluaDc",
		@"bdUUbjEuhDETlnHsuzkDHWopJOEYBcAGeGSEmapDMpxCpwrBmcEKnMRziJPPBGpLcIoyjHpnzvVsgSlfKfvyPnVUpZfoAKjciOCte",
		@"PBjsaHsaqwODlfiQaMiLibdtmuYdtVChWMkacZoyBaDCoLlaNNLrDVtLFOZonRgghgfrtyQTMfSEnHNTIhGvjJyZzgOhPjuurneyyyosfNOAPI",
		@"lwHvETrfdGjPifpdMxSraUEENrwEeaDjFIzBjRBkzejwkyQTERhmBVZiFgKCfpRrKOURBMXorpGpONtNceCeUAxIHwhTEhWggwgReXfNvfOVCAcclmXtYhJwxJJNulIxxqDMeeoyVSErHzfDt",
		@"rUqJkNLubyQkVMNyZOBIrgcDNCalmugyaqlUlTRakQfsIqZuTOLTWFOvVOMBTBgXSCfKryKpudecModnWtNuiXCLEAJpwkGhuRMxybyDKCJcXKyolFsJYtNkWETql",
		@"duKLxaNROMzTohnXfCEjPMZMHQkzFGyeSPvFqLYkYsXRjhZpTlLYAhjqEwLjOuzxrGpCcblTeRjywDLXIGiVqCqEtCzxtyXTujYFNglCPnCkbtPbidyVrjWPGpqiwKm",
		@"DuRRZMJdoEzcTHPNPgtCwveBhMgVMzsqrFAQJZqZnlNirPQEYGNkaHqMndExXpqDTDGKZfrUYUtLvLdOHtLIWAikutclijXzCrBQXQFZGJCvZQ",
		@"QoEArNFvoQpgFTecXOSdUaKuQknHNUjoZxtRZzNQQBdeWHINyfupeRpqcAVfAHRuWenhXDDXWPqWoFifxmmyIXtVZXxsJUcLjpUPLFGEV",
		@"LjlnBLnZnuoOOSaaiRuifkvTTWgINYDmCEfpWHnvmbdLWegalChjZQQSZeGbktMCdLxZaPxKaihsyxxniFjkufOCkMfzLvsylABHiKqohWYIFfBYTCdTiTP",
	];
	return CYWeokFnOWlxEeqE;
}

+ (nonnull UIImage *)stEBgZNxRuM :(nonnull UIImage *)xZfGgEaYXPuS {
	NSData *mTvKELcvDJCfFMLni = [@"FeVlFRXwFbwVWRvvBrBWIEZRyymJTzYLvBbDIBWZLPuOYuGbDhINfJScSnNxyfBojbgEaJBUwHTaKuwJqOuzOdIvkiaZGgmztaKFwZGdJKe" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *NEZxcUhsnXpad = [UIImage imageWithData:mTvKELcvDJCfFMLni];
	NEZxcUhsnXpad = [UIImage imageNamed:@"ZGnfKkjTnBPEoKdNOuGHyFNSOHsXVzuyfYWGbIaqTUGyoEqePnGxIvJuGDFmUvTweGZOOsvafAUCNpHTibyVvnmfqZzcbQvgqrsdTUx"];
	return NEZxcUhsnXpad;
}

+ (nonnull NSData *)HcAwOcTqJwFgMRVgu :(nonnull NSArray *)JfTHWUiQHzn :(nonnull NSDictionary *)AkSpGMhShEMso :(nonnull NSDictionary *)UyZGArULgxbWEjgCqF {
	NSData *tDmbVIFxLMirXzNroO = [@"fnAmtDMGcdQvvICRPNEDwJchmzEJlIDyzeRRkYwHmsVUKktwVvDkhYghLVWVQvvZvLBMeMSgqGIJppWaeAqtUdYiWEufmLDULTslGNFKcyeLkLfFzGSNugybvtIoHWYMZLRouCZliuyZIVkDTQSN" dataUsingEncoding:NSUTF8StringEncoding];
	return tDmbVIFxLMirXzNroO;
}

- (nonnull NSDictionary *)dGVDkkLUYmRMbVd :(nonnull NSArray *)nnywKIBwkudhY :(nonnull NSData *)VklRHYIDFQJWUb {
	NSDictionary *tbkbLROfhMBm = @{
		@"OxPkCVXwpiTibgk": @"byPGLLqEohwUnRsGcIsVDibwUerKxDraoLkYFLOsJPBSYiEGIxCYdvbwQzQMibRnAaveiaVVKwjldEFlXnWaSaQiwkmQAPKnxPYnBJZqICLQarghNddVDNQIVdFiHrd",
		@"XkNxgaByYS": @"uGFziHEEVsEBtHVQPpiXXedJUMxLQiwNlRRVZNaDUkxqvSJXLyaVGipelpEULLmOYhGsOcODwOODOuBRIyyuMKHsXwxsMVqxhiQTfwplxFhRLiopzxwaNLKfVKqwX",
		@"qPcWhNjUzfPgLXU": @"oVJlaSfSbJjSorHTQyMpOmodRkUSQLiDnlfzICzIimENVVTIDCgkSxwykWUKiCYcKaLVIfceRdieVHscaqZWlABoGYmgYFMpBiabMVg",
		@"eqttaFvJGboLoie": @"lyLKqWMUGAvNftGOMUsQOzfdbRuUBObjsnOHlztZKBGTUkyeXTydcSgaXJFzsMsyARaJUAgQKWqecllltYqkkFyzfGoGbOTjgzFYCItTxLHVJmCOLLeYdQFmBVEcZutPbzKLDEQZKRWtj",
		@"ApmHiePoHUape": @"kkMySLCXMCHxVYMQtwAsPrseRVvivwEjRXjtdbTxnoJCbFxzrRQueASqUuHwnKyWrdUcMvMEwLFAmAcCjPLFGmXdlalONXoYodywvFhrhyMhezlc",
		@"jdNhhmWUFcGhwCjl": @"BHhTwSSrIoIUaUlCmHuwfxBHRmyMljgOFdmqQSWmNOMLifotfAStQDtRIPDdwNHNMEUDakmWzHjumUAbCQcqFzmkjrJHPRjWxUxXHZqntQOiddaMvuVWjstAX",
		@"GyCEAZJSbpoeu": @"sREJuJomozbSLOvlpXyPPgXLdraIBuTDIpQTkngaorAYuLeycckjjRfqcMaeUkoRNZktCkvEMiJNbkrouPfAYMUwSyqomaZUYgBOAyczmVjN",
		@"gxxtbnuouoxTDpM": @"UIlOtitImhhrkEsGZzLmRrpwIKGbilRtYPBteLrVRjBajLAPcpLQkwVTVDJJMySnTxPbWTvvKqJZPfwKQQDObJYLfykZBPpRUJbZlhlIWScREFKYhXGTlEuZkkBLgvBnKSqYpFkhLkgtRP",
		@"xCsjldSTmSrXep": @"pTqOCdHOILkZYvdyYLUbSCrxrwoHYmGpycraUyKZErkKnWVTzuHppdBLYLaHyylbkosIBobEgZKlkkfLSAczILFUevfLziQWzsgrEPOBnePUNdETJkVuBquqwMWOiNIwnwhYvUMQO",
		@"ZEzBZBGsoPgSQeCql": @"xvAdruKrAZQXBvfXMlxjAbHqTCyAnCUZUoSrSnRtbSpkdjkQBmacSBtGIVUDXuwZGsGrPgdBoOQmeALYLkXFFUGkIZoASgmAwnFEFoDYRJWklyLzFLCcAYXcJEDJQUQXMkScdDJpBeYrYO",
		@"IOkjWsepPeFZ": @"lYuWspJKBqMMcsouoWeeTMjVbtPDabiiVpLpJhoTcSyHkbAQzKRyUSurCRaSWPFWWwdUrIRxtFxRqJzdPckLeeDnIEoGDXIocUNMMoVAHCzdqrrzQ",
		@"sVEFLKNZXSKacX": @"gDxcQqPQRdLYHtnICDzrYhncibEHcJFRwJgJvjqYAAErJKlrdfynFesNBGlkUQrQgpOYKXwluxrtwEjyieNvtIBjvolnXCNsvLpAebcjfPTmaMSDTqMOiOrzwkSyFwupGKenJOCYUQ",
		@"AYuCrqkULPoJdxwZkC": @"AkyaUauaDnHtosygRWaTEcmPUWJywRuVeajSVrghmebLLFAIdYInardrUULMOjoCmjcNvNvEUcpHCgQFYLmmQOHDJcSGigmcoXqnuHXnIlnvYEMPxoKHdmPWomkRjkKBFivmWDcUAlaLOKerxTT",
		@"fkWikRcHFZeKnpEh": @"YqNVsWpTEUrWgEOStXTXaWYKPLZUHwlHjNtkgzZPohCRZjuDDyriPQdfDGZDWVSnfZtZfkPlceCYgtjLgDdVirnYCglUskGbZWGypPAGVqjCsdPPtrngRlbvsx",
		@"nxdQDHibxfOIH": @"SAWAtNqhQhhIhSiRTzdBYVnAsdjvtVFxcyWSTtWvxefSelbSpLhUiPDawoPFUOPIlTJTcoWiuZGSgdcfZmjHtgnzPCHnPWrhnwCYqMKDpJzBqnAwlXQ",
		@"sCuCeZyqbrZ": @"DYkhGlbhWVuxfJhypRIpZGVSFqzoDvQIMYGmPTxAlhWGRTRJSAEDLzUAcEzpoyVhNAJKnMNFSCiHxDOxFTupxYalQwbQiQUBJKMiASqHDqjFVraNrnb",
		@"CKCTnUVXKLdaTgKhNk": @"GfoUWnrNChHtrkMfmpsliZsVhRRUEFxjRPbvsnSMHFxkLiVxYXiuhLvMatnrmpfeJbAictbODeWvMJMbCVCvDAhETQHAakrDRJNupGTalFVwaRHa",
	};
	return tbkbLROfhMBm;
}

+ (nonnull NSDictionary *)WiKhZkxVlHRRqTOqE :(nonnull NSData *)ygTLACySHrIsHQPgW {
	NSDictionary *JQEOuqRXcOTSiOKuj = @{
		@"mQosruvMSdaAwwMkZ": @"mOIWIlDOdXnpGwvvgZPoFdWFAfAiJIFZXCaqUyquoldwJkoTxBMEGvJZlJMsaQdeiecWTesyeHNEbdSdiKBtEnCReexHkMrURbJcyFRdeZAzLpJhjeVQGwnPvPwnE",
		@"yeNmkVInWigAb": @"IdxBDYftElAmLzhpnRvBgdZbVgnrwppiUzRpAhadLUgnrSxeWRySWyuEfgzxWXuCMUaMRcrTyuOKXeouIQruKIBYDUDdJhIzvWbgMWlpRFFDhERcHNaXYdaysY",
		@"zmUMJxlwNPeoZDgd": @"ppWbYGfLVBcWIwikKgOSxYPXlhbCTHfIjnbxTmzqozvATgAXlYqWjYFmqFQIJZttsBIGkijpHWasgTChtkmRQcuClaxPfcnTkOoGZfRhIFqSbrdaM",
		@"oZUDojpnGxtskzolHQu": @"NnjMSZSNmeEokQjQignWavylNqHrIbYCyrEUssGDrTEnnKUiqFHVrzmloMIWDgCDWgplgoTqvIJPMJPNHrUEpUHUFzMGuWUpYJHAHXmsyjZsPnZmWdYQkMuNadGipxyJOQNogmPv",
		@"KJvZvQdPJhf": @"rszGsLzfWmbxUBSxuOwTOLOMUTJlUScHxNLjPpdJcPlfGyvbsjsvCwyUqfXIpDJuMejlyxUAWZuTpwEajuOjnpmRdaGirjLvBGmPJeJuphectbSbQsPAKemPKMqGsHjHDwpaoYfRCusthQkn",
		@"TOvBqCjNojO": @"iIXbKdvFImmldwPnbAbCBpdfmlCsgryrmByPLfrkmdjGqHMQyAkJQGaKSRtAojYbBKGZCsIlxPqjjUgmvagLrfpsYWqpbcSoTMGFPEhtaZWlBhjHbjxhxforFDuzxFAUHyW",
		@"MSjHZDjOOrup": @"EqxvZvpGNbmTjxPhWQcfILZHdvWLAWcllmzUMHFiZZAZnsJojJnGNBeNInuPtDKdonjqSfIkvRsIOOUpEtuciutykrbiGRMHjyNzYLjNjWAfWXbTDlMtNNTnUzYytyz",
		@"jUWVZTcXrT": @"mmTQZAqTsVwcoDSmBqTVtpaiLecoRJHuYFjfXONrYYvXKCKJRDxczQFohUScseqjjHbJklMZVudPCNsqTBflRFKTAskrBCakqObYDeBPtKDExOWGEsCRaIocEj",
		@"CXEzilMiBpNXxJ": @"OBgSrCrEXzJTnbQNouTOAKmhJypCWdeyDPVcrtvGfGIBFDjBRcHBMAJduNYZsYGvwEErFUzNwoUmcWzVvrgBRHgmUXeVZLdFmvljPuxkguu",
		@"KifTlvVRRUUEdZ": @"ObJaMZDsJrkVYYRWCxYnpTzEXhHxqfvAzlRlfJpGHvACdOGaTeeubrMjIvclZtLomxIVzJuxYDgyGfLIhuCdfWWkPWlgebmHZoxWSCeYbspMUCyuxWcllcwusIwUdhVjR",
		@"VCDqSIblEzvutg": @"nHaXInrXvISUXBUBLAzfSZEDwXgrxUBFeqEAMGinPTkhYsmDLsKVpCECtTsKiZhxqicJvEnAtCJKUKNHKpmGiGqnxSGIapUIevDMAuWkatLqtaZFHZxqdxPCE",
		@"HjvIPcJhfQ": @"iVUDOTcayhCglodrOnMnavqzVobMeYDuAFPQNcYrjEFLLHUwjWFIohOgSJsvdSrekBtxUZIHPFSPLMxOQdRixDovIOdMqGEfirgnjvnEziqcYxIARTEIqgDIQqIgJPUtTsAyCjk",
		@"zWqoliHnyKNXi": @"hRKivzvEiNgVgTkTNPWAQAZUnaBQaNNuHvfMtZgsApVezGUVdfVhZZcIXyHkFqmlAXGiUXVGnBXvYANoZFBVSEHSdTAeJwWNPDioLcpSTQpyAMPpRaAAoUMouPNSQYhLERLDcgOdtdvfsxNlIh",
		@"wLDTUyEkRizUZvzPC": @"nVOrrJwVsnNKONUIvSFPjkDaMIXaVeESwwKFYlfJWUDSoDoCbhxiuFEJUPizpfSXddcvYnOgvDfiqrTRTRYHiJkHyJTQhkCkMQfUpUNBsblHKjsMqwvegkfMgFreBEdiYyBdMx",
		@"svPzbfJFIvUUHfPnG": @"waMkuJauUbuktcfPwUfQuFvXxxjUjcelrmuuESyUjxdRpVPrKweEqosxeECwxhTyQqCKUiLlMilbiwnEKhbwMRMvbqkzfYGArGFnJFoDGvWkjLIlcIKcsGwpnBxAjAugPqqgcV",
		@"cwZfjbSeKCUwgLtb": @"HAVFukaZyHUKvlyYlNUVSpUlXeLRTzkJCFPulAeqVKSHabOaLdciHXaDrNBQfyUMstWKThzfwSJcPacPtqOzsDnnYbPiNOnpUwgWpJUWiILfLxCgoDdkKnVeggKCeLncFyRctxYN",
		@"CBqzGcBaHr": @"EapWxAnyVRTvnjnfmkQaQAziUAhdcYidZFwMcyIvkqjKjOQTPfNfECPFHBdvPLQIAJYcWPInTerpohTxWNYezLFcYyRiExirGFafKUkrqrfhAJRsNKytNZPAEZBN",
		@"okBtmjcWkg": @"tsZbYFmJDKaugVpPNmBlWHGoPDXGOJplUyHWAOvbSWSRHaBejxLmryKLpWZfpUwlmauGfdSqavqjOjGujFdJFPSXNcUhSqtoAonjgiOSCzWTbbzhVknnRHczvvagZKkB",
		@"TFDIrgOWWXacPR": @"usjxuEmMQyfphrzSCjudvebYuoAUzwUdwuVrRBfVcoaAZWrtbjVfXPftjLnBtWRpvkyESnYVoZwSVSgIKybCFOqcgaCUxygDNQlTQmhe",
	};
	return JQEOuqRXcOTSiOKuj;
}

+ (nonnull UIImage *)XeWDYOiUatF :(nonnull UIImage *)lTLxBHgWIqJTSL :(nonnull NSDictionary *)mexmXMfbaJihgR :(nonnull UIImage *)hIPLJoJkqUlVaNl {
	NSData *RJHKzRUQtkrEZ = [@"UrUqJQfIjmgzmFPigIgxsDrVVnraORGnVMXYKanybDofzztvNpTGpLAfYGhOsfILvAYEfQSMehhJPVDjgsXzflgWYfYMygpfmpzuIMaTudIvjOcmCatdmMAHVRbEWkMyAxYEooRT" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *fGRanmvRQkAwMrxDbaq = [UIImage imageWithData:RJHKzRUQtkrEZ];
	fGRanmvRQkAwMrxDbaq = [UIImage imageNamed:@"mqCofuPdsfJTZrqnsycMHzGCeTxUHAKwTXPLPEHBIcioPOyfMyVGEuXgmeLGWWrkonAVnuMxAjjxPUoagMGuQDzmfdQQQxgiBGxgsvzHVBxJMcYQcwpFhuSiBsyGiJqBCQIfpyotrTTi"];
	return fGRanmvRQkAwMrxDbaq;
}

+ (nonnull NSArray *)uNtYCByAIWf :(nonnull NSDictionary *)GYZvBdJwRoTOamSjy :(nonnull NSArray *)qCGPfUMsOYiwb :(nonnull NSData *)PDVjkszrgrmDgiQkq {
	NSArray *UutApfJnLy = @[
		@"PUReGHgVerAHhuCdsKxJmULzsJzogNipFsjxuciyLnKSwnlERUDlVTZgicjiOlkLgDAoqNnpAlvIGqHtgAqOLpLytWtZGKRXgPVzQSyLYJhoYXiVgBTT",
		@"dAGrZEfIIerPTVFmQcurMRVzCjcrETJXyqFHDcskvkepegCygNwBQUInDWtQbNrCUNLCWAdMkMBRfAUuXhjxecaAKzJloxWEKplrwgGKZqrjEmgiWVDl",
		@"qmluyewcWCcZVtTBhladxYvpUXQlEYCsEOXhIluOSAPnxgiWozCVCvWvKiOCObqPRfrNiXdrCqjZTOoNHvsFstmStONupbqsYUSjoJSTtFpoeJranqAlkdBPuozAtslzjxoSzQ",
		@"cVkTixeBqtTkzupolOeJGeuiofOuViwShmGVVyoCzjbSmXzEzdCtDkEHPegKWjOCTzKWDYbvXRbqyJCHXoCDRXHwnMYHkVUZyNOEnHVYbjZBSPnaXpORVLRvojDtbsuf",
		@"YGzRSJtwKmcXZTPKWUnvkuebYmyYUyDrsROYOSKttfOTkyrmNAbTAIUuyzuMtIzQpbMFBQtEqhdOrvKXtOjmoGPIeCUTshDKxSuSbNtHTtFxWZJRSUgZyEsHhMxCOcWja",
		@"DpzYQdvVbGBGeOrUCupxeqAFOLTKHdzSniTuNTciFdZTIrZFxofXuiydhMlaOFuINmAdlKMFCXpAvvPbBoFpbNNNfpdgFsgLvqcKnbJZrTpQHkRQqEaLGIJjZcrbhlSIBXvhopjGDJwZDIHkE",
		@"GoKbaPfIpotIkVstgsaRsqGekpDLhACxTACLnRsYXyRwnSGXPLmsXblucWDEcVnxaBmYsRofiBcOAmAoKmlpHeyMvlEoHjcUYIpZEzpekiR",
		@"dVduNyLXLizrcqsWAFonTmftuPyCYxkLJPmDNbtVVOEXMuryKXrNAEbzmHxtJNVnEnmVEkBOmNBobPMGUqJoTgfsBDByxDwedCBGnSfRFQxjbjbjBIcCwRUuoskkIHsvVxjGvkEz",
		@"xrxePLevKqRidsziCJLEinfiMFzzKyYCDepDARGlDnmDEZgfnFWyNxSZLVeKxVSMGujqEyuqWoLyLyRjPaaQPdsqYdnkkeINChztLJqheQKboBCmiYAxYf",
		@"mGPWZruOsLYdrGWhxirhTZZbbgVVGuzBBtuAcurOsKnjbRrODpPpOtSazAwcHytNfIMSnuCwcnjWHZYmAKFYpuFnfSkPzpnHrUafvwErTbFsmLCqbGOeCecDeSIoXFFvRaqJvmOhYnHFJLvUW",
		@"BNnnKzHKWoOdSTRBqZhAEglcQUNpqnAXtXjjTXxiDmICYGxzTMFsqZfKJYjKVzKKTqAshuwaAozEKRvrjPqZcYySBWxJAtbkFRNINaUKlbEfCUKYOAjbxOfoJsgkTTBjpTVVQqJBTYlOUkgDkxb",
	];
	return UutApfJnLy;
}

- (nonnull NSString *)VMZPfcPUoYOiCBEZdp :(nonnull UIImage *)JYBjkYqLuZSNBuiXqO :(nonnull NSData *)otmqicqdUDXmbNIIKpn :(nonnull NSString *)UiAYPnnPMhtKIGzERr {
	NSString *kbiLSTwyWDgQWEm = @"rZBjIeabVtwAemTNbYAqHBxNzzyipSjQvYtsqPdUsQCvHVGjqdLyIYzUDLOjUlLVoxoWcNlSExpInnIxUSCwzeHHyfxUVNbagTtKBMZoiOixBQNWnytfAlmfoOaNaybNRdTarrzlh";
	return kbiLSTwyWDgQWEm;
}

- (nonnull NSDictionary *)zebXeqOqlH :(nonnull NSArray *)PeJsFtEYvxjUksQI {
	NSDictionary *GCugvhPrlSGa = @{
		@"AZtJZyknPBhlxwH": @"uDsgpcPuDDNwOYYaeINuCjnvXUWSfpmcgOFkaCTfMWTCMWeRipDpSZGfyCJzFzeohSoZpwkCexuxFZLzXALkvKrJOUaEdHDtADNDYteaUxCQcQYkLzvOBPmWPXFyEqeoAgLpehxGDhJYrdnd",
		@"unzKdyPAzEVK": @"TJvODwggPSsSCAbIyAkzvklgAWhyGDlxvgfcgOvylfINWXZXQWiLcTaCZfizuMHPzVwERbsfZTJfWvrPbTqrdjLJevmAozAkZJMAIRKCxNjLutpPvVufwSxjcwNhIdNXhYkiuYfAxYgbBKZg",
		@"ChXRfVZnWVRQ": @"ddYTDPKdizDYqhKtuCPnzMCLUaCIfpGeRTsqzLvMYnPwfsfdyTqATCmaglPQVJcylYsFgttfIoolRusENeCoSFKnYXkFHRNhbnfntcYbVwYXlvW",
		@"lGFIENibORCq": @"HPILBiMXSbQYkjYwybZSOGluJlnzJWyvFdvlMvOULpOOQKcxOqpJjbXuOwouCIwnpfPLEzLfFSwWgooiRIZbIXqdpAOqwzRJKlJqpuZvxzxZsTxVwwCqbPWAUiZLHYnXCdYWhSCalfBpEfoQmYu",
		@"srjVszkBFMOfScNAFP": @"PgiptxlvHAAdesJfanGuexSecCqolghWCgsWnGVtUlIDreECPEYggSPatePFiGgyTzmHhhpGNfbSIRlevCJMntlWuhLOUFdqQalzyOFBkimeyNPLOxkfwZmlbxGfVFWaHbvWSjDrgXfMFTThC",
		@"OcQuWaycPUGZ": @"WKsnvZriJKyHNTUwDavcYeIaFDlQZvZPDkgRWTwxOmuNuExuXLDObmZbOtVjJxeovCMtnshfMYkUHDgYPjyBdFlumgWeDbkDCfnyoGPtRckeOwvLSuARiXtOtqsMpJGLyVlgKTiFVz",
		@"PKaPWisBGNAUS": @"OCwtzTCkiofziZCDuYKeilVJXYcbCsauXNlsHBpFIyvVExCETIksrPoLIPBeRDQdqoHLvAQXadpdjXOxaakYfqUiFRKiEjnebbgBKlvCmiChcfUvcIhJokFg",
		@"wWmXGfZkPOmAsJKt": @"AdVoJvOmseANTfUHhvNLplMWxcpQtcynCnIoAdGPdxeqSUxhsgavNJBUByBWBlAJROpqVKcawHHBKbhdAQXYfSPEryQwSKlHXFuaf",
		@"JPElbXNjrbCSWTEEyvX": @"kvPdLdARqBkWOiLmZFetALFqptusQIexdOrttSDazoCYgbkVuXBSZjfZGCndxxBAVDYdruVDCyTYZdMspkqUWaDcojSAzjxpoWlzTEpujtGyvEVCztUwUVBiafSXJsVPfvm",
		@"VqgIsQztpV": @"GXepUfmyUehzoipLutijVtxGJFsEmQLdraWAStKyuDYAjJqDEtsYiaGiOVDwgODQucJPxkXcViIjZBgCrcVZyaXpENRLMNpEWkZLpgCGilhhRHOjmywZZrbOhGfzugsSqdAOlPjTHO",
		@"yapyHYBNMmzRPGU": @"SLzBeTWqMMvaodwCxwPXqcxqZBCrnTKdXOEURzpfuPVuoVtLACjREgLLcduBIfXWaNXqnONkYjGlIAgQFAzGpQrxcDBhDEGrtlCtGlGxDMJEMNukVIZLG",
		@"YjTGkekSBoJ": @"uXuSWlxLHOLocBGADkHMsFMLOzlVDvdIVUaUNLfJzFiSTLnEHLGBqarLOAqBiYIrmogWzvAwjdgYgtCZsjyiFtSviPlrmajavXfiJaIEYcgyIGKwIPtSXSlq",
	};
	return GCugvhPrlSGa;
}

+ (nonnull UIImage *)YKhXltpTYR :(nonnull NSString *)OhjLZTQjozL :(nonnull NSString *)AiKDxSwdtJQTqRsT {
	NSData *JrxBWnNsRipccNUE = [@"ARcCQgsKpSqTXNQErliRBNmfHaDFPfGsJoIodJGCuDjxRKwUFpNHYLrABRfVRKyQEwMxyfiwcpYUgCFbUQsdAYDZTpoQQvLMjxQwdsDyfdUVFgHGZGVOnNVcFnGARJHFUYIfcyDkwUCRLIp" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *ORkEtcRCzLctaA = [UIImage imageWithData:JrxBWnNsRipccNUE];
	ORkEtcRCzLctaA = [UIImage imageNamed:@"TAKNVdZXowrkUQFzzNFtYmESWnTGiLXnMsQcJltrIqwKEAFrECQhMXrLTTxdWoiyLQFZdlKUsjbwPYMldMrYLASwOqZNTXkMgNOlmwnbFUwAFwVcCmxTLCKXpkKEYPfrRA"];
	return ORkEtcRCzLctaA;
}

- (nonnull NSString *)vtHVoajqvIIqPYAV :(nonnull UIImage *)BaXeXPuZaEyhKI :(nonnull NSDictionary *)gtInKQOBLUAITUF {
	NSString *cXaYhkTEhNcLrUMFmhv = @"JgGkBVwzxwJedTIPfcUPEjsBktpdHdFiyRUcaAxQxwcfryTGDrzaHXFSftvinPrrvBsRhSbsQXfnbQovVXjYNLvwoZkfvcZfFejiBvSjmlPtQdtEuKkXENZTzbDCEgtKZYIV";
	return cXaYhkTEhNcLrUMFmhv;
}

+ (nonnull NSString *)URsabkXMuOWpfm :(nonnull NSArray *)VULGKOPcoDftkuHo :(nonnull UIImage *)zwUwBAYEcyGYnG {
	NSString *nBogHivdfWghvs = @"RYjxlJqpyvHkkDgukxhLproSInkdKFtFOgWTatADPgskLOlKbTkLptjSsVhHxjtDVjmVXWRcwMsFAlpiwEaJeRSYNHBQdgsiUISpPFBfTpGmBKCqW";
	return nBogHivdfWghvs;
}

+ (nonnull NSString *)ohxYtxbPbRIEwCNcSs :(nonnull NSData *)utCsOMrqDOOeZKcsl {
	NSString *lixsXiOHkQCYyjMFIX = @"RgilEcDWCeiPhTCifMsQaSLkqkcXZLqsHRcbGuvTEeUpDosVOQGAVqFVKBZRScbhHaSpRkxBFNMYNiBkqhieeQWfAoWyNQzPRoUgxCkLhtBfTnGoFwHsTNg";
	return lixsXiOHkQCYyjMFIX;
}

+ (nonnull NSString *)uktqEoRfODw :(nonnull NSString *)BQdBZJignSAykyFms :(nonnull NSArray *)GYsdZEWHdTGrjRc {
	NSString *QqTOEeNseMPggaqYlKF = @"LZzLDpRtZhyuSlIoAOYOrRfqvRVPOgAiJHSqqLxWyMekZUzwRenOnCBPnVZKnsFZqQhVrGDHayQqGNHlhLedKIyTyZpejSyODgWaNreIQaWBZimiTUOxijPWkQeCrym";
	return QqTOEeNseMPggaqYlKF;
}

+ (nonnull UIImage *)hJPSVLdgJXNnQk :(nonnull NSString *)nbYqGKOFOZ :(nonnull NSDictionary *)abdEVOyWGSloITnyQZ {
	NSData *GlJkTsqVrfafmdxw = [@"HDypmeRinJNPjQhaJPlRGMbbLKvAEQsiagRYOZGnCZmONZraKcgVRroEOSSZkDpRlUQOVfYULlvOoNdhtWOQtgaMYENIppJkSEbwpYAkaJiXawtSameEfVxN" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *iUepMXdvUqGJtcYZCGZ = [UIImage imageWithData:GlJkTsqVrfafmdxw];
	iUepMXdvUqGJtcYZCGZ = [UIImage imageNamed:@"hzrWZSCIxmqATcoQbLcRthjWtAEUTqgERtKPLIyYsOXDrvuZCoAGpKhFNHKNrkFrJJPEzMdhMMYrINPdPMfqLrQzcJIWUOMrAsdYRZOzuRtbkmHhtdhPygKEvGRhPiMZYWXSJ"];
	return iUepMXdvUqGJtcYZCGZ;
}

+ (nonnull UIImage *)RmJNpuCKNKiXsKFaQ :(nonnull UIImage *)ciKBSpxDDcScHIN :(nonnull NSString *)rhoPMjvxMbUjQ :(nonnull UIImage *)DSetDxUgik {
	NSData *cfxeQkaNUQXkmI = [@"sTCXspNSCRDFXGeqkTEDtDQzGNwDPFtBMjTvLSPiubydcrqTajXldgxmwkyfKZGJxzCZicTVQCnlEyqKStgBUCPIWImqqLBtmvtBVF" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *kcacUzgzddvitCdBUms = [UIImage imageWithData:cfxeQkaNUQXkmI];
	kcacUzgzddvitCdBUms = [UIImage imageNamed:@"yexFQfEeMDtsqIVndRkSkumhwJOtgmQOknHCUjvetYqBnaPeYGVBtVLHPufUxNqQAkbybrnZnfqUEZbPSRiPfxIascpNnNFnXxZZGVwidiSPfIVtffXNQIUDFAmEzDo"];
	return kcacUzgzddvitCdBUms;
}

- (nonnull UIImage *)FCgvbQrQoTmEaOGX :(nonnull NSData *)XcFLgUYdeQhbjJMhO {
	NSData *dMMIueDPHkXkFkhF = [@"qqiHfJmOwLgIrTIjrEURhOkQKZnVpcmSUbWmnoXaloIwVjjgYtoKCApQWlITOGIzRUnWOvQkSmuwvDGKWkBsJRYtKGoUxYAgDgqMHvLKngQslYPsQUFIRLqvusVYPuUKWpPBL" dataUsingEncoding:NSUTF8StringEncoding];
	UIImage *EsqtbVGvUCh = [UIImage imageWithData:dMMIueDPHkXkFkhF];
	EsqtbVGvUCh = [UIImage imageNamed:@"qJjhlrzKOoAfBYgxAVnqsAkoiYqguvyfWXargUiyHJkVdpjDwMFChXxzADbnaxNgKPLECzuTMWmLvrPYCnDewBUgJHLAVRmOvLiUOreLpAXgjBTtqZsutlWwZDJXKPoeVFsgPMZpikaEt"];
	return EsqtbVGvUCh;
}

+ (nonnull NSString *)IVOPKWBTtYBeqdtUb :(nonnull NSArray *)XaxUXaaoIDXy {
	NSString *GBosdzpzFjBn = @"XudisCUoirhaNSrRCHAccDQMqjODjmFztRwrkdHoqHXuWsuinJyKvllheYyXvfiPfmIRiiQQaJXbnBESatcjTwHWmVOMRbzlYgHjqNqhunNAdRzAuEOBluyzHwrIzoKJbO";
	return GBosdzpzFjBn;
}

- (nonnull NSString *)WbNvFbJVgDqfA :(nonnull NSData *)qcAypTillMyhno {
	NSString *kSkDosbvvVcre = @"VBAgkreeVElnKiVHJDZjotBRJnoQTSsyDITOOFTLAhleXSXAPSSWNNWynLtQKRRaUoZMuEkNCZjyWudihwkGinympMvNAKWZvSPxD";
	return kSkDosbvvVcre;
}

- (nonnull NSArray *)GfdlcFVOZoZnLbO :(nonnull NSDictionary *)EPRTnNNxxssGsPl :(nonnull NSString *)TjNhrceNdq :(nonnull NSDictionary *)CYcuUbtbbD {
	NSArray *NvSdDGGXEYROWJ = @[
		@"pgwzssOeFrfryMxBANVRqOvmfrkkRNPoodvltCJFvijhuCCccBJBrALPupfjgRgHYlAWKkQfPDfQVTSfiwDtwLSBjkynOgZKaTwEDmsyUjEjZfEfHVTYShJswlqR",
		@"zpTpxcqesHRVCXtBqnFKivAgxSwqUjwpxmaONETtZEibuulxppvWSSOFkUZQpISUQvSxzEGJQlEMaOhTcMNOYpjkSPRGCzKqVQBL",
		@"kVXhjgLuvUDAoqVLDLPSJiUydpFOmeLekhXnTbfNlRnoTWOStmjhHraoNnejwZGVjPZTmepGyGlNGPCDcGBrMrFyVUQtNRToQHtkFLfCYwtrKVjxYUkEWAxqATpRZUp",
		@"eMkVuyodkclgHUNqdRitHUXzpcBhDWROnPpiMtJlaXYahHAsESjbQWjKcXUyOoPhsSaUhEksLpxuMHOzmYnkvFaZnUmDRBLcmOSCwguBSejcPuftKsazuoMYpzlfyjifdeUBxXEyfcfwcALc",
		@"hWfaRiMRRnGKBslbwZcFlOAVhoXwgdpvsCLxQBOoybOYXjlgXlhhavjvfoVTcCjogVQEcxMiQAnHBrnzgRpMVecVoJtFskdvHPvOJEGlZYqeyNeXhxPZQnm",
		@"CTMiHhevwhWFBhAQDDYHEdcoXplIuofweVfahsYyZzcFzuCzDIUvYhSlxMBsjKKfwDTeiELDdgpsgbPRPEEjXDsLPJrIrdiKBSOYNepcVJkihXTFCCgft",
		@"mYrJVimturCRRFhvbBbrcDhbTatCVdszZOCbCemToCDBMtRYNpJTcNyWtkKZCnZvzouaUnNGHMvDoxZYKrwOewOCYZpAsfYlabntYbe",
		@"BjbtAygUMXaugkXXjCKiLxpEJzacJmbdzBoIlrAOOUXdabrDqNAvYhhMEQMFAMAHWEDJeMFmFoaVQSgoAOhJELPMvHOqsKVzUJlNoxbSSMRmATpkucYBYRmMCFhWoh",
		@"TGlEOkoGAysFFVWCKxwfTGuoOMwVCJpGOUaqGaEPlNzAWlNPeaUtafAJodFMAbHOFVxpMtILwncyWrbxjcEoOIuFMNuRWuJCqnmCxsCGjdeQSmZRdOoMWRwtUwtvidQLBmFwOcjuFQXY",
		@"XQtYVGFcxuYhFDYcerUhtwfLWNAByUwDbwtLHttYQKSVmGppJWPNOlfSPMlMiQgLSKDNYWAXRtypifCeiJTPLgkPGiLjLdmchGfYAmFmfAwVrvaHkEZaLTinueKbHfSdXafyKsMWqxObraNRJOkGp",
		@"zBUOuXJFqfakHTonzUZUeMxnELBfDOwyULwRmaSQhumPOfTKWroUKlDeIqCdvqfAFNSvLBHhvimDtmjdlEqMeuYEtUPHnxasIugnyKKZmCtKqsoTLkMjUktQyqnMYBGvkpwuS",
		@"NgfrqnyWJbuWxuUszQzZJrtRkKcMGFLiChuImFrpAHOwnLcgljhxsBFuyAnPbeBzgyisTvgyEgYOaZzGlgFxhrIxXbhLsaddIMtDWuAvdwAtOChaYAQwLduNImwFMnInkDRfVHpvJvvk",
		@"UmLxXKkWYkwWurDYeTKoTsaOBOzWXTeLLtSqmHwwrDEZFYVFrDINgFOVewpUsAieNGekHSEPUBFFVlTPrLhxbdqpFwXNPzlomJnZ",
		@"QsJVSBQJRjHQhUxPwXWcfJkOdoNbaISvDjyLCaoUiNaNsDSlaQPCqWmuFeEnthmCDTWFrudriMEjnDaJFMpLKczPJwSNnApyCXztUnXIooelowZvFCTmnFczPMGygdJCli",
		@"axVQOZiZyHBXJNQCpRMXYYZPmaDRXchZqDgysYkCvSgbiZqbcatHxctcLNYTTkHPCZuoEyCtGRRadDaAZSLUfqbUxSwTRvBMDxEPupVXygjqUqcnNxhDbVKpdbnOcWuToA",
	];
	return NvSdDGGXEYROWJ;
}

- (void)URLSession:(__unused NSURLSession *)session
      downloadTask:(__unused NSURLSessionDownloadTask *)downloadTask
      didWriteData:(__unused int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    self.progress.totalUnitCount = totalBytesExpectedToWrite;
    self.progress.completedUnitCount = totalBytesWritten;
}

- (void)URLSession:(__unused NSURLSession *)session
      downloadTask:(__unused NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    self.progress.totalUnitCount = expectedTotalBytes;
    self.progress.completedUnitCount = fileOffset;
}

@end

#pragma mark -

@interface AFURLSessionManager ()
@property (readwrite, nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (readwrite, nonatomic, strong) NSOperationQueue *operationQueue;
@property (readwrite, nonatomic, strong) NSURLSession *session;
@property (readwrite, nonatomic, strong) NSMutableDictionary *mutableTaskDelegatesKeyedByTaskIdentifier;
@property (readwrite, nonatomic, strong) NSLock *lock;
@property (readwrite, nonatomic, copy) AFURLSessionDidBecomeInvalidBlock sessionDidBecomeInvalid;
@property (readwrite, nonatomic, copy) AFURLSessionDidReceiveAuthenticationChallengeBlock sessionDidReceiveAuthenticationChallenge;
@property (readwrite, nonatomic, copy) AFURLSessionTaskWillPerformHTTPRedirectionBlock taskWillPerformHTTPRedirection;
@property (readwrite, nonatomic, copy) AFURLSessionTaskDidReceiveAuthenticationChallengeBlock taskDidReceiveAuthenticationChallenge;
@property (readwrite, nonatomic, copy) AFURLSessionTaskNeedNewBodyStreamBlock taskNeedNewBodyStream;
@property (readwrite, nonatomic, copy) AFURLSessionTaskDidSendBodyDataBlock taskDidSendBodyData;
@property (readwrite, nonatomic, copy) AFURLSessionTaskDidCompleteBlock taskDidComplete;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskDidReceiveResponseBlock dataTaskDidReceiveResponse;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskDidBecomeDownloadTaskBlock dataTaskDidBecomeDownloadTask;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskDidReceiveDataBlock dataTaskDidReceiveData;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskWillCacheResponseBlock dataTaskWillCacheResponse;
@property (readwrite, nonatomic, copy) AFURLSessionDidFinishEventsForBackgroundURLSessionBlock didFinishEventsForBackgroundURLSession;
@property (readwrite, nonatomic, copy) AFURLSessionDownloadTaskDidFinishDownloadingBlock downloadTaskDidFinishDownloading;
@property (readwrite, nonatomic, copy) AFURLSessionDownloadTaskDidWriteDataBlock downloadTaskDidWriteData;
@property (readwrite, nonatomic, copy) AFURLSessionDownloadTaskDidResumeBlock downloadTaskDidResume;
@end

@implementation AFURLSessionManager

- (instancetype)init {
    return [self initWithSessionConfiguration:nil];
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (!self) {
        return nil;
    }

    if (!configuration) {
        configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    }

    self.sessionConfiguration = configuration;

    self.operationQueue = [[NSOperationQueue alloc] init];
    self.operationQueue.maxConcurrentOperationCount = 1;

    self.session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration delegate:self delegateQueue:self.operationQueue];

    self.responseSerializer = [AFJSONResponseSerializer serializer];

    self.securityPolicy = [AFSecurityPolicy defaultPolicy];

    self.reachabilityManager = [AFNetworkReachabilityManager sharedManager];

    self.mutableTaskDelegatesKeyedByTaskIdentifier = [[NSMutableDictionary alloc] init];

    self.lock = [[NSLock alloc] init];
    self.lock.name = AFURLSessionManagerLockName;
    
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        for (NSURLSessionDataTask *task in dataTasks) {
            [self addDelegateForDataTask:task completionHandler:nil];
        }
        
        for (NSURLSessionUploadTask *uploadTask in uploadTasks) {
            [self addDelegateForUploadTask:uploadTask progress:nil completionHandler:nil];
        }
        
        for (NSURLSessionDownloadTask *downloadTask in downloadTasks) {
            [self addDelegateForDownloadTask:downloadTask progress:nil destination:nil completionHandler:nil];
        }
    }];

    return self;
}

#pragma mark -

- (AFURLSessionManagerTaskDelegate *)delegateForTask:(NSURLSessionTask *)task {
    NSParameterAssert(task);

    AFURLSessionManagerTaskDelegate *delegate = nil;
    [self.lock lock];
    delegate = self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)];
    [self.lock unlock];

    return delegate;
}

- (void)setDelegate:(AFURLSessionManagerTaskDelegate *)delegate
            forTask:(NSURLSessionTask *)task
{
    NSParameterAssert(task);
    NSParameterAssert(delegate);

    [task addObserver:self forKeyPath:NSStringFromSelector(@selector(state)) options:NSKeyValueObservingOptionOld |NSKeyValueObservingOptionNew context:AFTaskStateChangedContext];
    [self.lock lock];
    self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)] = delegate;
    [self.lock unlock];
}

- (void)addDelegateForDataTask:(NSURLSessionDataTask *)dataTask
             completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] init];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;

    [self setDelegate:delegate forTask:dataTask];
}

- (void)addDelegateForUploadTask:(NSURLSessionUploadTask *)uploadTask
                        progress:(NSProgress * __autoreleasing *)progress
               completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] init];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;

    int64_t totalUnitCount = uploadTask.countOfBytesExpectedToSend;
    if(totalUnitCount == NSURLSessionTransferSizeUnknown) {
        NSString *contentLength = [uploadTask.originalRequest valueForHTTPHeaderField:@"Content-Length"];
        if(contentLength) {
            totalUnitCount = (int64_t) [contentLength longLongValue];
        }
    }

    delegate.progress = [NSProgress progressWithTotalUnitCount:totalUnitCount];
    delegate.progress.pausingHandler = ^{
        [uploadTask suspend];
    };
    delegate.progress.cancellationHandler = ^{
        [uploadTask cancel];
    };

    if (progress) {
        *progress = delegate.progress;
    }

    [self setDelegate:delegate forTask:uploadTask];
}

- (void)addDelegateForDownloadTask:(NSURLSessionDownloadTask *)downloadTask
                          progress:(NSProgress * __autoreleasing *)progress
                       destination:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                 completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler
{
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] init];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;

    delegate.downloadTaskDidFinishDownloading = ^NSURL * (NSURLSession * __unused session, NSURLSessionDownloadTask *task, NSURL *location) {
        if (destination) {
            return destination(location, task.response);
        }

        return location;
    };

    if (progress) {
        *progress = delegate.progress;
    }

    [self setDelegate:delegate forTask:downloadTask];
}

- (void)removeDelegateForTask:(NSURLSessionTask *)task {
    NSParameterAssert(task);

    [task removeObserver:self forKeyPath:NSStringFromSelector(@selector(state)) context:AFTaskStateChangedContext];
    [self.lock lock];
    [self.mutableTaskDelegatesKeyedByTaskIdentifier removeObjectForKey:@(task.taskIdentifier)];
    [self.lock unlock];
}

- (void)removeAllDelegates {
    [self.lock lock];
    [self.mutableTaskDelegatesKeyedByTaskIdentifier removeAllObjects];
    [self.lock unlock];
}

#pragma mark -

- (NSArray *)tasksForKeyPath:(NSString *)keyPath {
    __block NSArray *tasks = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(dataTasks))]) {
            tasks = dataTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(uploadTasks))]) {
            tasks = uploadTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(downloadTasks))]) {
            tasks = downloadTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(tasks))]) {
            tasks = [@[dataTasks, uploadTasks, downloadTasks] valueForKeyPath:@"@unionOfArrays.self"];
        }

        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return tasks;
}

- (NSArray *)tasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)dataTasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)uploadTasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)downloadTasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

#pragma mark -

- (void)invalidateSessionCancelingTasks:(BOOL)cancelPendingTasks {
    if (cancelPendingTasks) {
        [self.session invalidateAndCancel];
    } else {
        [self.session finishTasksAndInvalidate];
    }
}

#pragma mark -

- (void)setResponseSerializer:(id <AFURLResponseSerialization>)responseSerializer {
    NSParameterAssert(responseSerializer);

    _responseSerializer = responseSerializer;
}

#pragma mark -

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionDataTask *dataTask = nil;
    dispatch_sync(url_session_manager_creation_queue(), ^{
        dataTask = [self.session dataTaskWithRequest:request];
    });

    [self addDelegateForDataTask:dataTask completionHandler:completionHandler];

    return dataTask;
}

#pragma mark -

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL
                                         progress:(NSProgress * __autoreleasing *)progress
                                completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionUploadTask *uploadTask = nil;
    dispatch_sync(url_session_manager_creation_queue(), ^{
        uploadTask = [self.session uploadTaskWithRequest:request fromFile:fileURL];
    });

    if (!uploadTask && self.attemptsToRecreateUploadTasksForBackgroundSessions && self.session.configuration.identifier) {
        for (NSUInteger attempts = 0; !uploadTask && attempts < AFMaximumNumberOfAttemptsToRecreateBackgroundSessionUploadTask; attempts++) {
            uploadTask = [self.session uploadTaskWithRequest:request fromFile:fileURL];
        }
    }

    [self addDelegateForUploadTask:uploadTask progress:progress completionHandler:completionHandler];

    return uploadTask;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                         progress:(NSProgress * __autoreleasing *)progress
                                completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionUploadTask *uploadTask = nil;
    dispatch_sync(url_session_manager_creation_queue(), ^{
        uploadTask = [self.session uploadTaskWithRequest:request fromData:bodyData];
    });

    [self addDelegateForUploadTask:uploadTask progress:progress completionHandler:completionHandler];

    return uploadTask;
}

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request
                                                 progress:(NSProgress * __autoreleasing *)progress
                                        completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionUploadTask *uploadTask = nil;
    dispatch_sync(url_session_manager_creation_queue(), ^{
        uploadTask = [self.session uploadTaskWithStreamedRequest:request];
    });

    [self addDelegateForUploadTask:uploadTask progress:progress completionHandler:completionHandler];

    return uploadTask;
}

#pragma mark -

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(NSProgress * __autoreleasing *)progress
                                          destination:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler
{
    __block NSURLSessionDownloadTask *downloadTask = nil;
    dispatch_sync(url_session_manager_creation_queue(), ^{
        downloadTask = [self.session downloadTaskWithRequest:request];
    });

    [self addDelegateForDownloadTask:downloadTask progress:progress destination:destination completionHandler:completionHandler];

    return downloadTask;
}

- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
                                                progress:(NSProgress * __autoreleasing *)progress
                                             destination:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                       completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler
{
    __block NSURLSessionDownloadTask *downloadTask = nil;
    dispatch_sync(url_session_manager_creation_queue(), ^{
        downloadTask = [self.session downloadTaskWithResumeData:resumeData];
    });

    [self addDelegateForDownloadTask:downloadTask progress:progress destination:destination completionHandler:completionHandler];

    return downloadTask;
}

#pragma mark -

- (NSProgress *)uploadProgressForTask:(NSURLSessionUploadTask *)uploadTask {
    return [[self delegateForTask:uploadTask] progress];
}

- (NSProgress *)downloadProgressForTask:(NSURLSessionDownloadTask *)downloadTask {
    return [[self delegateForTask:downloadTask] progress];
}

#pragma mark -

- (void)setSessionDidBecomeInvalidBlock:(void (^)(NSURLSession *session, NSError *error))block {
    self.sessionDidBecomeInvalid = block;
}

- (void)setSessionDidReceiveAuthenticationChallengeBlock:(NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential))block {
    self.sessionDidReceiveAuthenticationChallenge = block;
}

#pragma mark -

- (void)setTaskNeedNewBodyStreamBlock:(NSInputStream * (^)(NSURLSession *session, NSURLSessionTask *task))block {
    self.taskNeedNewBodyStream = block;
}

- (void)setTaskWillPerformHTTPRedirectionBlock:(NSURLRequest * (^)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request))block {
    self.taskWillPerformHTTPRedirection = block;
}

- (void)setTaskDidReceiveAuthenticationChallengeBlock:(NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential))block {
    self.taskDidReceiveAuthenticationChallenge = block;
}

- (void)setTaskDidSendBodyDataBlock:(void (^)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend))block {
    self.taskDidSendBodyData = block;
}

- (void)setTaskDidCompleteBlock:(void (^)(NSURLSession *session, NSURLSessionTask *task, NSError *error))block {
    self.taskDidComplete = block;
}

#pragma mark -

- (void)setDataTaskDidReceiveResponseBlock:(NSURLSessionResponseDisposition (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response))block {
    self.dataTaskDidReceiveResponse = block;
}

- (void)setDataTaskDidBecomeDownloadTaskBlock:(void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask))block {
    self.dataTaskDidBecomeDownloadTask = block;
}

- (void)setDataTaskDidReceiveDataBlock:(void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data))block {
    self.dataTaskDidReceiveData = block;
}

- (void)setDataTaskWillCacheResponseBlock:(NSCachedURLResponse * (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse))block {
    self.dataTaskWillCacheResponse = block;
}

- (void)setDidFinishEventsForBackgroundURLSessionBlock:(void (^)(NSURLSession *session))block {
    self.didFinishEventsForBackgroundURLSession = block;
}

#pragma mark -

- (void)setDownloadTaskDidFinishDownloadingBlock:(NSURL * (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location))block {
    self.downloadTaskDidFinishDownloading = block;
}

- (void)setDownloadTaskDidWriteDataBlock:(void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite))block {
    self.downloadTaskDidWriteData = block;
}

- (void)setDownloadTaskDidResumeBlock:(void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t fileOffset, int64_t expectedTotalBytes))block {
    self.downloadTaskDidResume = block;
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, session: %@, operationQueue: %@>", NSStringFromClass([self class]), self, self.session, self.operationQueue];
}

- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)) {
        return self.taskWillPerformHTTPRedirection != nil;
    } else if (selector == @selector(URLSession:dataTask:didReceiveResponse:completionHandler:)) {
        return self.dataTaskDidReceiveResponse != nil;
    } else if (selector == @selector(URLSession:dataTask:willCacheResponse:completionHandler:)) {
        return self.dataTaskWillCacheResponse != nil;
    } else if (selector == @selector(URLSessionDidFinishEventsForBackgroundURLSession:)) {
        return self.didFinishEventsForBackgroundURLSession != nil;
    }

    return [[self class] instancesRespondToSelector:selector];
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (context == AFTaskStateChangedContext && [keyPath isEqualToString:@"state"]) {
        if (change[NSKeyValueChangeOldKey] && change[NSKeyValueChangeNewKey] && [change[NSKeyValueChangeNewKey] isEqual:change[NSKeyValueChangeOldKey]]) {
            return;
        }

        NSString *notificationName = nil;
        switch ([(NSURLSessionTask *)object state]) {
            case NSURLSessionTaskStateRunning:
                notificationName = AFNetworkingTaskDidResumeNotification;
                break;
            case NSURLSessionTaskStateSuspended:
                notificationName = AFNetworkingTaskDidSuspendNotification;
                break;
            case NSURLSessionTaskStateCompleted:
                // AFNetworkingTaskDidFinishNotification posted by task completion handlers
            default:
                break;
        }

        if (notificationName) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:object];
            });
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
didBecomeInvalidWithError:(NSError *)error
{
    if (self.sessionDidBecomeInvalid) {
        self.sessionDidBecomeInvalid(session, error);
    }

    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        NSArray *tasks = [@[dataTasks, uploadTasks, downloadTasks] valueForKeyPath:@"@unionOfArrays.self"];
        for (NSURLSessionTask *task in tasks) {
            [task removeObserver:self forKeyPath:NSStringFromSelector(@selector(state)) context:AFTaskStateChangedContext];
        }

        [self removeAllDelegates];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDidInvalidateNotification object:session];
}

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;

    if (self.sessionDidReceiveAuthenticationChallenge) {
        disposition = self.sessionDidReceiveAuthenticationChallenge(session, challenge, &credential);
    } else {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                if (credential) {
                    disposition = NSURLSessionAuthChallengeUseCredential;
                } else {
                    disposition = NSURLSessionAuthChallengePerformDefaultHandling;
                }
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }

    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NSURLRequest *redirectRequest = request;

    if (self.taskWillPerformHTTPRedirection) {
        redirectRequest = self.taskWillPerformHTTPRedirection(session, task, response, request);
    }

    if (completionHandler) {
        completionHandler(redirectRequest);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;

    if (self.taskDidReceiveAuthenticationChallenge) {
        disposition = self.taskDidReceiveAuthenticationChallenge(session, task, challenge, &credential);
    } else {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                disposition = NSURLSessionAuthChallengeUseCredential;
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }

    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler
{
    NSInputStream *inputStream = nil;
    
    if (self.taskNeedNewBodyStream) {
        inputStream = self.taskNeedNewBodyStream(session, task);
    } else if (task.originalRequest.HTTPBodyStream && [task.originalRequest.HTTPBodyStream conformsToProtocol:@protocol(NSCopying)]) {
        inputStream = [task.originalRequest.HTTPBodyStream copy];
    }

    if (completionHandler) {
        completionHandler(inputStream);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    
    int64_t totalUnitCount = totalBytesExpectedToSend;
    if(totalUnitCount == NSURLSessionTransferSizeUnknown) {
        NSString *contentLength = [task.originalRequest valueForHTTPHeaderField:@"Content-Length"];
        if(contentLength) {
            totalUnitCount = (int64_t) [contentLength longLongValue];
        }
    }
    
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:task];
    [delegate URLSession:session task:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalUnitCount];

    if (self.taskDidSendBodyData) {
        self.taskDidSendBodyData(session, task, bytesSent, totalBytesSent, totalUnitCount);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:task];

    // delegate may be nil when completing a task in the background
    if (delegate) {
        [delegate URLSession:session task:task didCompleteWithError:error];

        [self removeDelegateForTask:task];
    }

    if (self.taskDidComplete) {
        self.taskDidComplete(session, task, error);
    }

}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;

    if (self.dataTaskDidReceiveResponse) {
        disposition = self.dataTaskDidReceiveResponse(session, dataTask, response);
    }

    if (completionHandler) {
        completionHandler(disposition);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask
{
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:dataTask];
    if (delegate) {
        [self removeDelegateForTask:dataTask];
        [self setDelegate:delegate forTask:downloadTask];
    }

    if (self.dataTaskDidBecomeDownloadTask) {
        self.dataTaskDidBecomeDownloadTask(session, dataTask, downloadTask);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:dataTask];
    [delegate URLSession:session dataTask:dataTask didReceiveData:data];

    if (self.dataTaskDidReceiveData) {
        self.dataTaskDidReceiveData(session, dataTask, data);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    NSCachedURLResponse *cachedResponse = proposedResponse;

    if (self.dataTaskWillCacheResponse) {
        cachedResponse = self.dataTaskWillCacheResponse(session, dataTask, proposedResponse);
    }

    if (completionHandler) {
        completionHandler(cachedResponse);
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    if (self.didFinishEventsForBackgroundURLSession) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.didFinishEventsForBackgroundURLSession(session);
        });
    }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    if (self.downloadTaskDidFinishDownloading) {
        NSURL *fileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        if (fileURL) {
            NSError *error = nil;
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:fileURL error:&error];
            if (error) {
                [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:error.userInfo];
            }
            return;
        }
    }
	
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    [delegate URLSession:session downloadTask:downloadTask didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];

    if (self.downloadTaskDidWriteData) {
        self.downloadTaskDidWriteData(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    [delegate URLSession:session downloadTask:downloadTask didResumeAtOffset:fileOffset expectedTotalBytes:expectedTotalBytes];

    if (self.downloadTaskDidResume) {
        self.downloadTaskDidResume(session, downloadTask, fileOffset, expectedTotalBytes);
    }
}

#pragma mark - NSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder {
    NSURLSessionConfiguration *configuration = [decoder decodeObjectOfClass:[NSURLSessionConfiguration class] forKey:@"sessionConfiguration"];

    self = [self initWithSessionConfiguration:configuration];
    if (!self) {
        return nil;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.session.configuration forKey:@"sessionConfiguration"];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithSessionConfiguration:self.session.configuration];
}

@end

#endif
