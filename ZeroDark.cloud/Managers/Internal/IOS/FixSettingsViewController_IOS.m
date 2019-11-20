/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
 **/

#import "FixSettingsViewController_IOS.h"
#import "UIColor+Crayola.h"
#import "ZeroDarkCloudPrivate.h"


@interface FixSettingsViewControllerCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView    *imgStep;
@property (nonatomic, weak) IBOutlet UILabel        *lblStep;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

@end

@implementation FixSettingsViewControllerCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}


+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
    UINib *buttonCellNib = [UINib nibWithNibName:@"FixSettingsViewControllerCell" bundle:bundle];
    [tableView registerNib:buttonCellNib forCellReuseIdentifier:@"FixSettingsViewControllerCell"];
    
}


@end


@implementation FixSettingsViewController_IOS
{
    IBOutlet __weak UIVisualEffectView      * _visEffectsView;
    IBOutlet __weak UIView                  * _containerView;
    
    IBOutlet __weak UILabel                 *lblTitle;
    IBOutlet __weak UILabel                 *lblInformational;
    
    IBOutlet __weak UIButton                *_btnCancel;
    IBOutlet __weak UIButton                *_btnSetting;
    
    IBOutlet __weak UITableView             *_tblSteps;
    IBOutlet __weak NSLayoutConstraint      *_cnstTblStepsHeight;
    
    NSString* title;
    NSString* informational;
    NSArray* steps;
}

@synthesize delegate = delegate;

- (instancetype)initWithDelegate:(nullable id <FixSettingsViewControllerDelegate>)inDelegate
                           title:(NSString*)inTitle
                   informational:(NSString*)inInformational
                           steps:(NSArray*)inSteps
{
    
    self = [super initWithNibName:@"FixSettingsViewController_IOS"
                           bundle:[ZeroDarkCloud frameworkBundle]];
    if (self)
    {
        delegate = inDelegate;
        title = inTitle;
        informational = inInformational;
        steps = inSteps;
    }
    return self;
    
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    [FixSettingsViewControllerCell registerViewsforTable:_tblSteps
                                                  bundle:[ZeroDarkCloud frameworkBundle]];
    
    [_containerView.layer setCornerRadius:8.0f];
    //    _containerView.layer.borderColor = [UIColor redColor].CGColor;
    //    _containerView.layer.borderWidth = 2.0f;
    [_containerView.layer setMasksToBounds:YES];
    
    _tblSteps.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tblSteps.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _tblSteps.frame.size.width, 1)];
    _tblSteps.estimatedSectionHeaderHeight = 0;
    _tblSteps.estimatedSectionFooterHeight = 0;
    _tblSteps.userInteractionEnabled = NO;
    
    _tblSteps.estimatedRowHeight = 50;
    _tblSteps.rowHeight = UITableViewAutomaticDimension;
    
    
    /**  button setup */
    _btnCancel.layer.cornerRadius  = _btnSetting.frame.size.height /2;
    _btnCancel.layer.masksToBounds = YES;
    _btnCancel.layer.backgroundColor   = UIColor.lightGrayColor.CGColor;
    _btnCancel.tintColor   = UIColor.whiteColor;;
    
    _btnSetting.layer.cornerRadius  = _btnSetting.frame.size.height /2;
    _btnSetting.layer.masksToBounds = YES;
    _btnSetting.layer.backgroundColor   = [UIColor crayolaBlueJeansColor].CGColor;
    _btnSetting.tintColor   = UIColor.whiteColor;;
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    lblTitle.text = title;
    lblInformational.text = informational;
}

-(void) updateViewConstraints
{
    [super updateViewConstraints];
    _cnstTblStepsHeight.constant = _tblSteps.contentSize.height;
}

/*
 -(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
 {
 CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
 CGPoint viewPoint = [_containerView convertPoint:locationPoint fromView:self.view];
 
 if ([_containerView pointInside:viewPoint withEvent:event]) return;
 
 if ([delegate  respondsToSelector:@selector(fixSettingsViewController:dismissViewControllerAnimated:)])
 {
 [self.delegate fixSettingsViewController:self dismissViewControllerAnimated:YES  ];
 }
 }
 
 */

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return steps.count;
}

//- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    return 50;
//}


- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    FixSettingsViewControllerCell *cell = (FixSettingsViewControllerCell *)[tv dequeueReusableCellWithIdentifier:@"FixSettingsViewControllerCell"];
    
    NSArray* step = steps[indexPath.row];
    
    NSString* stepText     = step[1];
    UIImage* stepImage     = step[0];
    
    cell.lblStep.text = [NSString stringWithFormat:@"%lu. %@", (unsigned long)indexPath.row+1, stepText];
    cell.lblStep.textColor  =  UIColor.darkGrayColor;
    
    cell.imgStep.image =  stepImage;
    
    return cell;
    
}

-(IBAction)btnCancelTapped:(id)sender
{
    [self.delegate fixSettingsViewController:self dismissViewControllerAnimated:YES  ];
    
}

-(IBAction)btnSettingsTapped:(id)sender
{
    [self.delegate fixSettingsViewController:self dismissViewControllerAnimated:YES  ];
    [self.delegate fixSettingsViewController:self showSettingsHit:sender  ];
}


@end
