#import <Foundation/Foundation.h>
#import <ZDCSyncableObjC/ZDCObject.h>

#import "ZDCCloudDataInfo.h"
#import "ZDCDownloadManager.h"

@class ZDCDownloadContext_EphemeralInfo;
@class ZDCNode;
@class ZDCCloudLocator;
@class ZDCProgress;

/**
 * Utility class used by the DownloadManager.
 */
@interface ZDCDownloadContext : ZDCObject <NSCoding, NSCopying>

- (instancetype)initWithLocalUserID:(NSString *)inLocalUserID
                             nodeID:(NSString *)inNodeID
                             isMeta:(BOOL)isMeta
                         components:(ZDCNodeMetaComponents)components
                            options:(ZDCDownloadOptions *)options;

@property (nonatomic, copy, readonly) NSString * localUserID;
@property (nonatomic, copy, readonly) NSString * nodeID;

@property (nonatomic, assign, readonly) BOOL isMeta;
@property (nonatomic, assign, readonly) ZDCNodeMetaComponents components;
@property (nonatomic, strong, readonly) ZDCDownloadOptions *options;

// For meta downloads
@property (nonatomic, copy, readwrite) ZDCCloudDataInfo *header;
@property (nonatomic, assign, readwrite) NSRange range_data;
@property (nonatomic, assign, readwrite) NSRange range_request;

// For meta & data downloads
@property (nonatomic, readonly) ZDCDownloadContext_EphemeralInfo *ephemeralInfo; // Not stored to disk

@end

#pragma mark -

/**
 * EphemeralInfo characteristics:
 * - not persisted to disk
 * - copies of ZDCDownloadContext share the same EphemeralInfo instance
 */
@interface ZDCDownloadContext_EphemeralInfo : NSObject

@property (nonatomic, strong, readwrite) ZDCNode *node;
@property (nonatomic, strong, readwrite) ZDCCloudLocator *cloudLocator;
@property (nonatomic, strong, readwrite) ZDCProgress *progress;
@property (nonatomic, assign, readwrite) NSUInteger failCount;

@end
