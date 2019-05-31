//
//  PasswordStrengthUIView.m
//  storm4
//
//  Created by vincent Moscaritolo on 1/5/17.
//  Copyright © 2017 4th-A Technologies, LLC. All rights reserved.
//

#import "PasswordStrengthUIView.h"

@implementation PasswordStrengthUIView
{
    NSUInteger _score;
	BOOL _showZeroScore;
}

-(void)setScore:(NSUInteger)score
{
    _score = score;
    [self setNeedsDisplay];
}

-(void)setShowZeroScore:(BOOL)showZeroScore
{
	_showZeroScore = showZeroScore;
	[self setNeedsDisplay];
}

-(NSUInteger)score
{
    return _score;
}

-(BOOL)showZeroScore
{
	return _showZeroScore;
}


- (void)drawRect:(CGRect)dirtyRect {
    
    //    NSColor* tintColor = [NSColor colorWithRed:0.99 green:0.459 blue:0.996 alpha:1.0];
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat segLength = dirtyRect.size.width / (_showZeroScore?5:4);
    UIColor* tintColor = [UIColor clearColor];

	  UIColor* veryWeakColor  = [UIColor colorWithRed:0.933 green:0.125 blue:0.302 alpha:1.0];
	  UIColor* weakColor = [UIColor orangeColor];
	  UIColor* fairColor = [UIColor colorWithRed:1.000 green:0.859 blue:0.000 alpha:1.0];;
	  UIColor* goodColor = [UIColor colorWithRed:0.000 green:0.506 blue:0.671 alpha:1.0];
	  UIColor* strongColor = [UIColor colorWithRed:0.161 green:0.588 blue:0.090 alpha:1.0];

	if (_score == 0 && _showZeroScore) tintColor = veryWeakColor;
	else if (_score == 1) tintColor = _showZeroScore?weakColor:veryWeakColor;
    else if (_score == 2) tintColor = fairColor;
    else if (_score == 3) tintColor = goodColor;
    else if (_score == 4) tintColor = strongColor;

    CGPoint startPoint = CGPointMake(dirtyRect.origin.x, dirtyRect.origin.y + dirtyRect.size.height);
    CGPoint endPoint = CGPointMake(dirtyRect.origin.x + segLength * (_showZeroScore?_score+1:_score),
								   dirtyRect.origin.y + dirtyRect.size.height);
    
    [path moveToPoint: startPoint];
    [path setLineWidth: dirtyRect.size.height];
    [path addLineToPoint:endPoint];
    [tintColor setStroke];
    [path stroke];
    
}

@end
