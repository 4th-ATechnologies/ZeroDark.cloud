/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

@class ZDCData;
@class ZDCNode;

NS_ASSUME_NONNULL_BEGIN

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

- (instancetype)initWithData:(ZDCData *)data;

@property (atomic, strong, readwrite) ZDCData *data;
@property (atomic, strong, readwrite, nullable) ZDCData *metadata;
@property (atomic, strong, readwrite, nullable) ZDCData *thumbnail;

@property (atomic, strong, readwrite, nullable) NSData *rawMetadata;
@property (atomic, strong, readwrite, nullable) NSData *rawThumbnail;

@property (atomic, strong, readwrite, nullable) ZDCNode *node;

@end

NS_ASSUME_NONNULL_END
