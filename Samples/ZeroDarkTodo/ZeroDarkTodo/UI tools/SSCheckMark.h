#import <UIKit/UIKit.h>

//
// from http://stackoverflow.com/questions/18977527/how-do-i-display-the-standard-checkmark-on-a-uicollectionviewcell
//

typedef NS_ENUM( NSUInteger, SSCheckMarkStyle )
{
    SSCheckMarkStyleOpenCircle,
    SSCheckMarkStyleGrayedOut
};

@interface SSCheckMark : UIView

@property (nonatomic) bool checked;
@property (nonatomic) SSCheckMarkStyle checkMarkStyle;

@end