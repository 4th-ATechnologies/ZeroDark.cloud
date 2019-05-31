#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

/**
 * Stores cached NSURLResponses in the (encrypted) database.
 * To be replaced with NSURLCache subclass in the future.
 *
 * Objects are automatically deleted from the cache via ZDCDatabaseManager.actionManager.
**/
@interface ZDCCachedResponse : ZDCObject <NSCoding, NSCopying>

- (instancetype)initWithData:(NSData *)data timeout:(NSTimeInterval)timeout;

@property (nonatomic, copy, readonly) NSData *data;
@property (nonatomic, copy, readonly) NSDate *uncacheDate;

@property (nonatomic, copy, readwrite) NSString *eTag;
@property (nonatomic, copy, readwrite) NSDate *lastModified;

@end
