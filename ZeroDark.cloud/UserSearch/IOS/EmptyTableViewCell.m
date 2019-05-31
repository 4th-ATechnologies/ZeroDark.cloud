/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import "EmptyTableViewCell.h"

NSString *const kEmptyTableViewCellIdentifier = @"EmptyTableViewCell";

@implementation EmptyTableViewCell

@synthesize lblText;

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
    UINib *buttonCellNib = [UINib nibWithNibName:@"EmptyTableViewCell" bundle:bundle];
    [tableView registerNib:buttonCellNib forCellReuseIdentifier:kEmptyTableViewCellIdentifier];
}

 
+ (CGFloat)heightForCell
{
	return 60;
}


- (UITableView *)tableView
{
	UIView *tableView = self.superview;
	while (tableView)
	{
		if (![tableView isKindOfClass:[UITableView class]]) {
			tableView = tableView.superview;
		}
		else {
			return (UITableView *)tableView;
		}
	}
	return nil;
}

- (IBAction)buttonTapped:(id)sender
{
	if ([self.delegate respondsToSelector:@selector(tableView:emptyCellButtonTappedAtCell:)])
	{
		UITableView *tableView = [self tableView];

		[(id <EmptyTableViewCellDelegate>)self.delegate tableView:tableView
										  emptyCellButtonTappedAtCell:self];
	}
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}


@end
