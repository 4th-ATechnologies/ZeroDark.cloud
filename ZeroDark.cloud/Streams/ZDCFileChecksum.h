/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

@class ZDCFileChecksumInstruction;

NS_ASSUME_NONNULL_BEGIN

/**
 * ZDCFileChecksum can generate 1 or more checksums of a file in a single pass.
 * It supports all the algorithms in the S4Crypto library.
 */
@interface ZDCFileChecksum : NSObject

/**
 * Convenience method for checksuming an entire file with the given algorithm.
 * 
 * @param fileURL
 *   A valid file URL.
 *
 * @param algorithm
 *   The hash algorithm to use.
 *   E.g.: kHASH_Algorithm_SHA1
 *
 * @param completionQueue
 *   The dispatch_queue to invoke the completionBlock on.
 *   If NULL, the main queue will be used.
 * 
 * @param completionBlock
 *   This block will be called once the checksum process has completed.
 *   If an error occurred, the error value will be set, and the checksum value should be ignored.
 * 
 * @return progress
 *   The progress can be used to monitor the process, or to cancel it (via [progress cancel]).
 */
+ (nullable NSProgress *)checksumFileURL:(NSURL *)fileURL
                           withAlgorithm:(HASH_Algorithm)algorithm
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(void (^)(NSData *_Nullable hash, NSError *_Nullable error))completionBlock;

/**
 * Convenience method for checksuming an entire stream with the given algorithm.
 * 
 * @param fileStream
 *   The input stream to read from.
 * 
 * @params streamSize
 *   The NSInputStream class has no way of getting the total length.
 *   So if you want the progress to be determinate, you'll need to pass the length explicitly.
 *
 * @param algorithm
 *   The hash algorithm to use.
 *   E.g.: kHASH_Algorithm_SHA1
 *
 * @param completionQueue
 *   The dispatch_queue to invoke the completionBlock on.
 *   If NULL, the main queue will be used.
 * 
 * @param completionBlock
 *   This block will be called once the checksum process has completed.
 *   If an error occurred, the error value will be set, and the checksum value should be ignored.
 * 
 * @return progress
 *   The progress can be used to monitor the process, or to cancel it (via [progress cancel]).
 */
+ (nullable NSProgress *)checksumFileStream:(NSInputStream *)fileStream
                             withStreamSize:(uint64_t)streamSize
                                  algorithm:(HASH_Algorithm)algorithm
                            completionQueue:(nullable dispatch_queue_t)completionQueue
                            completionBlock:(void (^)(NSData *_Nullable hash, NSError *_Nullable error))completionBlock;

/**
 * Starts a checksum process to read given file, and calculate the checksum(s).
 * 
 * @param fileURL
 *   A valid file URL.
 * 
 * @param instructions
 *   A list of checksum operations to perform.
 *   The method will process the instructions, and automatically determine how to peform the optimum IO.
 * 
 * @param errorPtr
 *   If an error occurs while validating the parameters, or trying to setup the IO,
 *   then nil will be returned, and this param (if non-nil) will be set with an error explaining the problem.
 *
 * @return progress
 *   The progress can be used to monitor the process, or to cancel it (via [progress cancel]).
 */
+ (nullable NSProgress *)checksumFileURL:(NSURL *)fileURL
                        withInstructions:(NSArray<ZDCFileChecksumInstruction *> *)instructions
                                   error:(NSError **)errorPtr;

/**
 * Starts a checksum process to read given file, and calculate the checksum(s).
 * 
 * @param fileStream
 *   A valid file input stream.
 * 
 * @params streamSize
 *   The NSInputStream class has no way of getting the total length.
 *   So if you want the progress to be determinate, you'll need to pass the length explicitly.
 * 
 * @param instructions
 *   A list of checksum operations to perform.
 *   The method will process the instructions, and automatically determine how to peform the optimum IO.
 * 
 * @param errorPtr
 *   If an error occurs while validating the parameters, or trying to setup the IO,
 *   then nil will be returned, and this param (if non-nil) will be set with an error explaining the problem.
 *
 * @return progress
 *   The progress can be used to monitor the process, or to cancel it (via [progress cancel]).
 */
+ (nullable NSProgress *)checksumFileStream:(NSInputStream *)fileStream
                             withStreamSize:(uint64_t)streamSize
                               instructions:(NSArray<ZDCFileChecksumInstruction *> *)instructions
                                      error:(NSError **)errorPtr;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCFileChecksumInstruction : NSObject <NSCopying>

/**
 * Specifies the algorithm to use when calculating the checksum.
 * The default value is kHASH_Algorithm_Invalid, meaning this property MUST be set.
 */
@property (nonatomic, readwrite) HASH_Algorithm algorithm;

/**
 * If set, then only a subsection of the file/stream will be part of the checksum.
 * If nil, then the whole file/stream will be part of the checksum.
 */
@property (nonatomic, readwrite, nullable) NSValue *range;

/**
 * If set, then a separate checksum will be calculated for each chunkSize block.
 * And the callbackBlock will be invoked with increasing chunkIndex numbers.
 *
 * If a range is configured, then a checksum will be calculated for each chunkSize block in the range.
 * Otherwise, a checksum will be calculated for each chunkSize block in the file/stream.
 * 
 * If the range/file/stream is not an exact multiple of the chunkSize
 * then the last chunk will be smaller than chunkSize.
 */
@property (nonatomic, readwrite, nullable) NSNumber *chunkSize;

/**
 * The dispatch queue on which to invoke the callbackBlock.
 * If nil, then the dispatch_get_main_queue() is used.
 */
@property (nonatomic, readwrite, nullable) dispatch_queue_t callbackQueue;

/**
 * @param hash
 *   The calculated checksum value.
 *   The size of the hash will correspond with the algorithm used.
 *
 * @param chunkIndex
 *   If a chunkSize is configured, this value will start at zero, and increase with each additional chunk found.
 *   If a chunkSize is not configured, this value will be zero.
 *
 * @param done
 *   If set, this is the last invocation of the callback block you'll receive.
 *   See important note below concerning this value when using chunks.
 *
 * @param error
 *   If non-nil, then some kind of error occurred with the underlying file/stream.
 *   The hash value will be nil and the done value with be YES.
 * 
 * IMPORTANT:
 *   If you're checksuming the entire file/stream:
 *     - this block will be called exactly once
 *     - when called the done value will be YES, and you'll either have a non-nil hash, or a non-nil error
 *   If you're checksuming in chunks:
 *     - this block may be called multiple times
 *     - the very last time this block is called the done value will be YES and the hash will be nil
 */
typedef void(^ZDCFileChecksumCallbackBlock)(NSData *_Nullable hash,
                                           uint64_t chunkIndex,
                                           BOOL done,
                                           NSError *_Nullable error);

/**
 * The block to invoke with the checksum information.
 * 
 * If a chunkSize is set, this block may be called multiple times, with increasing chunkIndex values.
 * If a chunkSize is not set, this block is invoked once at the end of the range/file/stream.
 */
@property (nonatomic, readwrite, nullable) ZDCFileChecksumCallbackBlock callbackBlock;

@end

NS_ASSUME_NONNULL_END
