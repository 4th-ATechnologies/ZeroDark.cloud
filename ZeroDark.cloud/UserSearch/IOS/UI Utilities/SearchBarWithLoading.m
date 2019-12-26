/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "SearchBarWithLoading.h"

@implementation SearchBarWithLoading
{
	UIActivityIndicatorView *_activityIndicatorView;
	UIImage *_searchIcon;
}

@synthesize isLoading;

- (NSMutableArray*)allSubViewsForView:(UIView*)viewIn
{
    NSMutableArray *array = NSMutableArray.array;
    [array addObject:viewIn];
    for (UIView *subview in viewIn.subviews)
    {
        [array addObjectsFromArray:[self allSubViewsForView:subview]];
    }
    return array;
}

-(UIActivityIndicatorView*) activityIndicatorView
{
    if (!_activityIndicatorView)
    {
        UITextField *searchField = nil;
        
        for(UIView* view in [self allSubViewsForView:self])
        {
            if([view isKindOfClass:[UITextField class]]){
                searchField= (UITextField *)view;
                break;
            }
        }
  
        if(searchField)
        {
            // save old search icon
            _searchIcon =  [((UIImageView*) searchField.leftView) image];
            
            // create an activity view
            UIActivityIndicatorView *taiv = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            taiv.backgroundColor = UIColor.clearColor;
            
            taiv.center = CGPointMake(searchField.leftView.bounds.origin.x + searchField.leftView.bounds.size.width/2,
                                      searchField.leftView.bounds.origin.y + searchField.leftView.bounds.size.height/2);
            taiv.hidesWhenStopped = YES;
            _activityIndicatorView = taiv;
            [searchField.leftView addSubview:_activityIndicatorView];
        }
        
    }
    return _activityIndicatorView;
}

-(void)setIsLoading:(BOOL)isLoading
{
    if (isLoading)
    {
        [self.activityIndicatorView startAnimating];
        [self setImage:[[UIImage alloc] init]
                forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    }
    else
    {
        [self.activityIndicatorView stopAnimating];
        [self setImage:_searchIcon  forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    }
    [self layoutSubviews];
}

@end
