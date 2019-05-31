#import <Foundation/Foundation.h>

/**
 * Simple wrapper around NSDictionary for change items coming from the server.
 *
 * ChangeItem = Info about a change that occurred in the cloud.
 *
 * Has the following benefits:
 * - provides improved type safety
 * - facilitates upgrade patterns
 * - protects the client from server bugs
 */
@interface ZDCChangeItem : NSObject <NSCoding, NSCopying, NSMutableCopying>

+ (ZDCChangeItem *)parseChangeInfo:(NSDictionary *)dict;

@property (nonatomic, readonly) NSString *uuid;

@property (nonatomic, readonly) NSDate *timestamp;

@property (nonatomic, readonly) NSString *app;
@property (nonatomic, readonly) NSString *bucket;
@property (nonatomic, readonly) NSString *region;
@property (nonatomic, readonly) NSString *command;

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *fileID;
@property (nonatomic, readonly) NSString *eTag;

@property (nonatomic, readonly) NSString *srcPath; // for move operations
@property (nonatomic, readonly) NSString *dstPath; // for move operations

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used by ZDCChangeList's optimization engine: [ZDCChangeList popNextPendingChange:]
 */
@interface ZDCMutableChangeItem : ZDCChangeItem <NSCopying, NSMutableCopying>

@property (nonatomic, copy, readwrite) NSString *eTag;

@property (nonatomic, copy, readwrite) NSString *path;
@property (nonatomic, copy, readwrite) NSString *dstPath; // for move operations

@end
