/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZeroDarkCloud.h"

#import <YapDatabase/YapActionable.h>
#import <ZDCSyncableObjC/ZDCObject.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates the information & logic to perform a one-off task.
 *
 * When a one-off task needs to be performed, and that action requires some kind of Internet request,
 * we persist the task to disk and let the YapActionManager ensure it eventually gets done.
 *
 * This is the generica base class for all tasks.
 * To actually perform some task, create a subclass to store the data & logic required for the task.
 */
@interface ZDCTask : ZDCObject <NSCoding, NSCopying>

/** All tasks need an identifier so we can store them in the database. */
@property (nonatomic, strong, readonly) NSString *uuid;

/** Subclasses must override this method. */
- (YapActionItem *)actionItem:(YapActionItemBlock)block;

/** Subclasses must override this method. */
- (void)performTask:(ZeroDarkCloud *)owner;

@end

NS_ASSUME_NONNULL_END
