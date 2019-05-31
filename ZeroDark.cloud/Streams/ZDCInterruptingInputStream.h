#import <Foundation/Foundation.h>
#import "ZDCInputStream.h"

/**
 * The purpose of the ZDCInterruptingInputStream class is to
 * detect file modifications while the stream is being read.
 * If that occurs, this will be NSError.code value you see as the streamError.
 */
extern NSInteger const ZDCFileModifiedDuringRead;

/**
 * ZDCInterruptingInputStream will automatically close itself with an error if
 * it detects the underlying file was modified.
 *
 * It can be used to safely stream a file directly from disk,
 * which may be modified by other processes on the OS.
 */
@interface ZDCInterruptingInputStream : ZDCInputStream <NSCopying>

/**
 * Use this method instead of the usual NSInputStream init methods.
 * The compiler gets mad when we try to override those...
 */
- (instancetype)initWithFileURL:(NSURL *)fileURL;

/**
 * The fileURL parameter used to initialize the stream.
 */
@property (nonatomic, readonly) NSURL *fileURL;

/**
 * The size of the underlying file (in bytes) (value is wrapped uint64_t).
 * Another way to think of it: it will be the output of all read:maxLength: invocations.
 * 
 * This value is available anytime after the stream has been opened.
 */
@property (nonatomic, readonly) NSNumber *fileSize;

@end
