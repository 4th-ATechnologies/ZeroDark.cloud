/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

@class ZDCNode;
@class ZDCData;
@class ZDCPollContext;
@class ZDCTouchContext;

@class ZDCCloudOperation_AsyncData;

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates ephemeral information about the operation that isn't stored to disk.
 *
 * This includes information used by the PushManager while the application is running.
 * It is for use solely by the ZeroDarkCloud framework.
 */
@interface ZDCCloudOperation_EphemeralInfo : NSObject

@property (atomic, strong, readwrite, nullable) ZDCCloudOperation_AsyncData *asyncData;

@property (atomic, strong, readwrite, nullable) ZDCData *multipartData;

@property (atomic, strong, readwrite, nullable) ZDCPollContext *pollContext;
@property (atomic, strong, readwrite, nullable) ZDCTouchContext *touchContext;

@property (atomic, assign, readwrite) BOOL abortRequested;
@property (atomic, assign, readwrite) BOOL resolveByPulling;

@property (atomic, copy, readwrite, nullable) NSString *lastChangeToken;
@property (atomic, copy, readwrite, nullable) NSUUID *postResolveUUID;

// Why is the infinite-loop-protections stuff separated ?
//
// Because a common infinite loop is:
// - the S4 server (our serverless code) rejects a request (for whatever reason)
// - the client doesn't properly respond to rejection reason
// - the client performs upload again
//
// If we were to clear a general purpose fail count when S3 succeeds, then we're missing the bigger picture.
// That is, we're missing the larger infinite loop in the system.
//
// I.E.
// - S3      : success
// - Polling : success
// - S4      : fail
// - S3      : success
// - Polling : success
// - S4      : fail
// - S3      : success
// - Polling : success
// - S4      : fail
// ...inifinite loop in system, but only detectable in S4 component...

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation monitoring - S3
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)s3_didFailWithStatusCode:(NSNumber *)statusCode;
- (void)s3_didSucceed;

@property (atomic, readonly) NSUInteger s3_successiveFailCount;
@property (atomic, readonly, nullable) NSNumber *s3_successiveFail_statusCode;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation monitoring - Polling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)polling_didFail;
- (void)polling_didSucceed;

@property (atomic, readonly) NSUInteger polling_successiveFailCount;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation monitoring - S4
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)s4_didFailWithExtStatusCode:(NSNumber *)statusCode;
- (void)s4_didSucceed;

@property (atomic, readonly) NSUInteger s4_successiveFailCount;
@property (atomic, readonly, nullable) NSNumber *s4_successiveFail_extStatusCode;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used to assist when one of the following situations occurs:
 *
 * - nodeData.promise
 * - nodeMetadata.cleartextFileURL
 * - nodeMetadata.cryptoFile
 * - nodeMetadata.promise
 * - nodeThumbnail.cleartextFileURL
 * - nodeThumbnail.cryptoFile
 * - nodeThumbnail.promise
 */
@interface ZDCCloudOperation_AsyncData : NSObject

- (instancetype)initWithNode:(ZDCNode *)node
                        data:(ZDCData *)data
                nodeMetadata:(nullable ZDCData *)nodeMetadata
               nodeThumbnail:(nullable ZDCData *)nodeThumbnail;

@property (atomic, strong, readwrite) ZDCNode *node;

@property (atomic, strong, readwrite) ZDCData *nodeData;
@property (atomic, strong, readwrite, nullable) ZDCData *nodeMetadata;
@property (atomic, strong, readwrite, nullable) ZDCData *nodeThumbnail;

@property (atomic, strong, readwrite, nullable) NSData *rawMetadata;
@property (atomic, strong, readwrite, nullable) NSData *rawThumbnail;

@end

NS_ASSUME_NONNULL_END
