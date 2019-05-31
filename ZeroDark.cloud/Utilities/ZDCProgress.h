#import <Foundation/Foundation.h>

/**
 * ZDCProgress is a container for 1 or more children (of type NSProgress).
 * Children can optionally be marked with a special "progress type" for improved progress reporting.
 */
typedef NS_ENUM(NSInteger, ZDCChildProgressType) {
	
	/**
	 * When uploading large files, a multipart upload process is used,
	 * which splits the large file into several smaller parts, each of which is uploaded separately.
	 * This allows the framework to better recover from network interruptions.
	 *
	 * However, this requires a bit of extra prep work (calculating hashes for each chunk).
	 * When this occurs, a progress item is added for the ZDCCloudOperation of type 'MultipartPrep',
	 * which represents the prep work being peformed prior to starting the upload.
	 */
	ZDCChildProgressType_MultipartPrep = 1,
};

NS_ASSUME_NONNULL_BEGIN

/**
 * Custom key for NSProgress.userInfo dictionary.
 * Value will be a localized string displayable to the user.
 */
extern NSString *const ZDCLocalizedDescriptionKey;

/**
 * Custom key for NSProgress.userInfo dictionary.
 * Value will be a (wrapped) ZDCChildProgressType value.
 */
extern NSString *const ZDCChildProgressTypeKey;


/**
 * A subclass of NSProgress which simplifies the management of children.
 *
 * There are 2 major advantages that ZDCProgress has over NSProgress.
 *
 * 1. It allows children to be removed.
 *    Many networking operations within the framework gracefully recover from temporary networking failures.
 *    In order to properly maintain the progress, this involves removing progress children from the tree.
 *
 * 2. It optionally allows children to control their pendingUnitCount within the parent.
 *    This is useful when it's preferred that the parent's totalUnitCount matches
 *    the sum of the children's totalUnitCount.
 *    (i.e. for proper reporting of bytes downloaded)
 *
 * @see NSProgress
 */
@interface ZDCProgress : NSProgress

/** Designated initializer */
- (instancetype)init;

/**
 * Represents the portion of the progress that comes from already completed child tasks.
 * This is probaly not the value you're looking for.
 *
 * @see `[NSProgress totalUnitCount]`
 * @see `[NSProgress fractionCompleted]`
 */
@property (atomic, assign, readwrite) int64_t baseTotalUnitCount;

/**
 * Represents the portion of the progress that comes from already completed child tasks.
 * This is probaly not the value you're looking for.
 *
 * @see `-[NSProgress completedUnitCount]`
 * @see `-[NSProgress fractionCompleted]`
 */
@property (atomic, assign, readwrite) int64_t baseCompletedUnitCount;

/**
 * @param child
 *   The child progress item to add
 *
 * @param pendingUnitCount
 *   If you pass a positive value, the child will be assigned the given value.
 *   If you pass zero or a negative value,
 *   the child's pendingUnitCount will automatically update according to child.totalUnitCount.
 */
- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)pendingUnitCount;

/**
 * Removes the child from the list of children.
 *
 * @param child
 *   The child progress item to remove
 * 
 * @param success
 *   If YES, the baseCompletedUnitCount is incremented according to the child's pendingUnitCount.
 *   If NO, the baseCompletedUnitCount is unchanged.
 *   If the child was added with a non-positive pendingUnitCount,
 *   then the baseTotalUnitCount will also be incremented if this parameter is YES.
 *   You typically pass YES if the operation was successful,
 *   and NO if the operation failed and will be retried (and thus replaced with a new progress).
 */
- (void)removeChild:(NSProgress *)child andIncrementBaseUnitCount:(BOOL)success;

/**
 * Removes all children from the list of children.
 *
 * @param success
 *   If YES, the baseCompletedUnitCount is incremented according to the child's pendingUnitCount.
 *   If NO, the baseCompletedUnitCount is unchanged.
 *   If the child was added with a non-positive pendingUnitCount,
 *   then the baseTotalUnitCount will also be incremented if this parameter is YES.
 *   You typically pass YES if the operation was successful,
 *   and NO if the operation failed and will be retried (and thus replaced with a new progress).
 */
- (void)removeAllChildrenAndIncrementBaseUnitCount:(BOOL)success;

/**
 * Finds & returns the first child progress with the given type.
 *
 * This is useful when your UI supports more advanced progress logic.
 * For example, imagine a task that is composed of 2 long running operations: A & B.
 * Both A & B are children of a parent progress,
 * but you'd like to update your UI to display the progress for each type of operation independently.
 */
- (nullable NSProgress *)childProgressWithType:(ZDCChildProgressType)type;

@end

NS_ASSUME_NONNULL_END
