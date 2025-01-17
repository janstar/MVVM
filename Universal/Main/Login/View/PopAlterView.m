//
//  PopAlterView.m
//  祥益金服
//
//  Created by zl on 2018/7/4.
//  Copyright © 2018年 com.erongdu.QZW. All rights reserved.
//

#import "PopAlterView.h"
#import "UIView+Extension.h"
#import "UIImage+GIF.h"


#define PRESENTATION_ANIMATION_DURATION 0.5
#define DISMISS_ANIMATION_DURATION 0.5

@interface PopAlterView ()

/** 弹出框里面承载容器的视图 */
@property (nonatomic, strong) UIView *containerView;

@end

@implementation PopAlterView


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
    }
    return self;
}
#pragma mark -- 第一种：右上角删除按钮，顶部固定"提示"title，中间提示文字，确定按钮
+ (PopAlterView *)popViewWithTipStr:(NSString *)tipStr {
    return [[self alloc] initWithTipStr:tipStr];
}

- (PopAlterView *)initWithTipStr:(NSString *)tipStr {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        self.backgroundColor=[UIColor clearColor];
        
        CGFloat hudWidth = 176;
        CGFloat hudHeight = 65;
        CGFloat stringWidth = 0;
        CGFloat stringHeight = 0;
        CGRect labelRect = CGRectZero;

        // 弹出框后面的背景视图
        UIColor *color = UIColorFromRGB(0x000000);
        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor = [color colorWithAlphaComponent:0.45];
        _containerView.layer.masksToBounds = YES;
        _containerView.layer.cornerRadius =5;
        [self addSubview:_containerView];
        
        //CGFloat cHeight = _containerView.height;
        
        UIColor *colorLabel = UIColorFromRGB(0xffffff);
        //中间label
        UILabel *middleL = [[UILabel alloc]init];
        middleL.textColor = [colorLabel colorWithAlphaComponent:1];
        middleL.numberOfLines = 0;
        middleL.font = [UIFont fontWithName:@"PingFang-SC-Medium" size:14];
        middleL.textAlignment = NSTextAlignmentCenter;
        middleL.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_containerView addSubview:middleL];
        
        if(tipStr) {
            CGSize stringSize = [tipStr sizeWithFont:middleL.font constrainedToSize:CGSizeMake(200, 300)];
            stringWidth = stringSize.width;
            stringHeight = stringSize.height;
            hudHeight = 65+stringHeight;
            
            if(stringWidth > hudWidth)
                hudWidth = ceil(stringWidth/2)*2;
            
            if(hudHeight > 176) {
                labelRect = CGRectMake(12, 66, hudWidth, stringHeight);
                hudWidth+=24;
            } else {
                hudWidth+=24;
                labelRect = CGRectMake(0, 66, hudWidth, stringHeight);
            }
        }
        
        self.containerView.frame = CGRectMake((SCREEN_WIDTH -hudWidth)/2,(SCREEN_HEIGHT-hudHeight)/2, hudWidth, hudHeight);
        middleL.frame = CGRectMake(0,0,_containerView.width,_containerView.height);
        middleL.text = tipStr;
        
        [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(dismiss) userInfo:nil repeats:NO];
    }
    return self;
}

#pragma mark -- 第二种：右上角删除按钮，左边gif，中间提示文字
+ (PopAlterView *)popViewWithMiddleTipStr:(NSString *)middleTipStr {
    return  [[self alloc] initWithMiddleTipStr:middleTipStr];
}

- (PopAlterView *)initWithMiddleTipStr:(NSString *)middleTipStr {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        // 弹出框后面的背景视图
        UIView *shawdowView = [[UIView alloc] initWithFrame:self.bounds];
        shawdowView.backgroundColor  = [UIColor blackColor];
        shawdowView.alpha = 0.6;
        [self addSubview:shawdowView];
        
        // 承载容器的视图
        UIImageView *containerView = [[UIImageView alloc] initWithFrame:CGRectMake(30, SCREEN_HEIGHT*0.37, SCREEN_WIDTH-60, SCREEN_HEIGHT*0.26)];
        containerView.userInteractionEnabled = YES;
        containerView.layer.cornerRadius = 5.0f;
        containerView.clipsToBounds = YES;
        containerView.image = [UIImage imageNamed:@"XLPopView"];
        [self addSubview:containerView];
        _containerView = containerView;
        
        // 右上角删除按钮
        UIButton *closeBtn = [UIButton new];
        closeBtn.frame = CGRectMake(_containerView.width-50, 0, 50, 50);
        [closeBtn setBackgroundImage:[UIImage imageNamed:@"closeBtn"] forState:UIControlStateNormal];
        [closeBtn setBackgroundImage:[UIImage imageNamed:@"closeBtn"] forState:UIControlStateHighlighted];
        [closeBtn addTarget:self action:@selector(clickCloseBtn) forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:closeBtn];
        
        CGFloat cHeight = _containerView.height;
        
        UIImageView *gifView = [UIImageView new];
        gifView.frame = CGRectMake(10, (cHeight-30)/2, 30, 30);
        gifView.image = [UIImage sd_animatedGIFNamed:@"loding"];
        [_containerView addSubview:gifView];
        
        // 中间label
        UILabel *middleL = [UILabel new];
        middleL.text = middleTipStr;
        middleL.textColor = [UIColor whiteColor];
        middleL.numberOfLines = 0;
        middleL.font = [UIFont systemFontOfSize:14.0];
        middleL.textAlignment = NSTextAlignmentLeft;
        middleL.lineBreakMode = NSLineBreakByTruncatingMiddle;
        middleL.frame = CGRectMake(CGRectGetMaxX(gifView.frame)+8, gifView.y, _containerView.width-45, 30);
        [_containerView addSubview:middleL];
    }
    
    return self;
}

#pragma mark -- 第三种：右上角删除按钮，顶部title，中间提示文字
+ (PopAlterView *)popViewWithTopTitle:(NSString *)topTitle middleTipStr:(NSString *)middleTipStr {
    return [[self alloc] initWithTopTitle:topTitle middleTipStr:middleTipStr];
}

- (PopAlterView *)initWithTopTitle:(NSString *)topTitle middleTipStr:(NSString *)middleTipStr {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        // 弹出框后面的背景视图
        UIView *shawdowView = [[UIView alloc] initWithFrame:self.bounds];
        shawdowView.backgroundColor  = [UIColor blackColor];
        shawdowView.alpha = 0.6;
        [self addSubview:shawdowView];
        
        // 承载容器的视图
        UIImageView *containerView = [[UIImageView alloc] initWithFrame:CGRectMake(20, SCREEN_HEIGHT*0.36, SCREEN_WIDTH-40, SCREEN_HEIGHT*0.28)];
        containerView.userInteractionEnabled = YES;
        containerView.layer.cornerRadius = 5.0f;
        containerView.clipsToBounds = YES;
        containerView.image = [UIImage imageNamed:@"XLPopView"];
        [self addSubview:containerView];
        _containerView = containerView;
        
        // 顶部label
        UILabel *topL = [UILabel new];
        topL.text = topTitle;
        topL.textColor = [UIColor whiteColor];
        topL.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:17.0];
        topL.textAlignment = NSTextAlignmentCenter;
        topL.frame = CGRectMake(_containerView.width/4, 10, _containerView.width/2, 30);
        [_containerView addSubview:topL];
        
        // 右上角删除按钮
        UIButton *closeBtn = [UIButton new];
        closeBtn.frame = CGRectMake(_containerView.width-50, 0, 50, 50);
        [closeBtn setBackgroundImage:[UIImage imageNamed:@"closeBtn"] forState:UIControlStateNormal];
        [closeBtn setBackgroundImage:[UIImage imageNamed:@"closeBtn"] forState:UIControlStateHighlighted];
        [closeBtn addTarget:self action:@selector(clickCloseBtn) forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:closeBtn];
        
        // topTitle与middleTitle分割线
        UIView *topSeperateLine = [UIView new];
        topSeperateLine.frame = CGRectMake(0, 60, _containerView.width, 1);
        topSeperateLine.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.5];
        [_containerView addSubview:topSeperateLine];
        
        // 中间label
        UILabel *middleL = [UILabel new];
        middleL.text = middleTipStr;
        middleL.textColor = [UIColor whiteColor];
        middleL.numberOfLines = 0;
        middleL.font = [UIFont systemFontOfSize:14.0];
        middleL.textAlignment = NSTextAlignmentCenter;
        middleL.lineBreakMode = NSLineBreakByTruncatingMiddle;
        middleL.frame = CGRectMake(20, topSeperateLine.y+10, _containerView.width-40, 80);
        [_containerView addSubview:middleL];
    }
    
    return self;
}

#pragma mark -- 第四种：顶部title，中间提示文字，左边确定按钮，右边取消按钮
+ (PopAlterView *)popViewWithTopTitle:(NSString *)topTitle middleTipStr:(NSString *)middleTipStr confirmBtnTitle:(NSString *)confirmTitle cancleBtnTitle:(NSString *)cancleTitle {
    return [[self alloc] initWithTopTitle:topTitle middleTipStr:middleTipStr confirmBtnTitle:confirmTitle cancleBtnTitle:cancleTitle];
}


- (PopAlterView *)initWithTopTitle:(NSString *)topTitle middleTipStr:(NSString *)middleTipStr confirmBtnTitle:(NSString *)confirmTitle cancleBtnTitle:(NSString *)cancleTitle {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        // 弹出框后面的背景视图
        UIView *shawdowView = [[UIView alloc] initWithFrame:self.bounds];
        shawdowView.backgroundColor  = [UIColor blackColor];
        shawdowView.alpha = 0.6;
        [self addSubview:shawdowView];
        
        // 承载容器的视图
        UIImageView *containerView = [[UIImageView alloc] initWithFrame:CGRectMake(20, SCREEN_HEIGHT*0.36, SCREEN_WIDTH-40, SCREEN_HEIGHT*0.28)];
        containerView.userInteractionEnabled = YES;
        containerView.layer.cornerRadius = 5.0f;
        containerView.clipsToBounds = YES;
        containerView.image = [UIImage imageNamed:@"XLPopView"];
        [self addSubview:containerView];
        _containerView = containerView;
        
        CGFloat cHeight = containerView.height;
        // 顶部label
        UILabel *topL = [UILabel new];
        topL.text = topTitle;
        topL.textColor = [UIColor whiteColor];
        topL.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:17.0];
        topL.textAlignment = NSTextAlignmentCenter;
        topL.frame = CGRectMake(_containerView.width/4, 0, _containerView.width/2, cHeight/9*2);
        [_containerView addSubview:topL];
        
        // topTitle与middleTitle 分割线
        UIView *topSeperateLine = [UIView new];
        topSeperateLine.frame = CGRectMake(0, CGRectGetMaxY(topL.frame), _containerView.width, 1);
        topSeperateLine.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.5];
        [_containerView addSubview:topSeperateLine];
        
        // 中间label
        UILabel *middleL = [UILabel new];
        middleL.text = middleTipStr;
        middleL.textColor = [UIColor whiteColor];
        middleL.numberOfLines = 0;
        middleL.font = [UIFont systemFontOfSize:14.0];
        middleL.textAlignment = NSTextAlignmentLeft;
        middleL.lineBreakMode = NSLineBreakByTruncatingMiddle;
        middleL.frame = CGRectMake(10, CGRectGetMaxY(topSeperateLine.frame), _containerView.width-20, cHeight/3);
        [_containerView addSubview:middleL];
        
        // middleTitle与按钮 分割线
        UIView *bottomSeperateLine = [UIView new];
        bottomSeperateLine.frame = CGRectMake(0, CGRectGetMaxY(middleL.frame), _containerView.width, 1);
        bottomSeperateLine.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.5];
        [_containerView addSubview:bottomSeperateLine];
        
        // 确认按钮
        UIButton *confirmBtn = [UIButton new];
        confirmBtn.frame = CGRectMake(10, CGRectGetMaxY(bottomSeperateLine.frame)+(cHeight/9*4-40)/2, containerView.width/2-20, 40);
        confirmBtn.backgroundColor = [UIColor whiteColor];
        confirmBtn.titleLabel.font = [UIFont systemFontOfSize:14.0];
        confirmBtn.layer.cornerRadius = 5.0f;
        [confirmBtn setTitle:confirmTitle forState:UIControlStateNormal];
        [confirmBtn setTitleColor:[UIColor colorWithRed:36/255.0 green:160/255.0 blue:241/255.0 alpha:1.0] forState:UIControlStateNormal];
        [_containerView addSubview:confirmBtn];
        [confirmBtn addTarget:self action:@selector(clickConfirmBtn) forControlEvents:UIControlEventTouchUpInside];
        
        // 取消按钮
        UIButton *cancleBtn = [UIButton new];
        cancleBtn.frame = CGRectMake(containerView.width/2+10, CGRectGetMaxY(bottomSeperateLine.frame)+(cHeight/9*4-40)/2, containerView.width/2-20, 40);
        cancleBtn.backgroundColor = [UIColor whiteColor];
        cancleBtn.titleLabel.font = [UIFont systemFontOfSize:14.0];
        cancleBtn.layer.cornerRadius = 5.0f;
        [cancleBtn setTitle:cancleTitle forState:UIControlStateNormal];
        [cancleBtn setTitleColor:[UIColor colorWithRed:36/255.0 green:160/255.0 blue:241/255.0 alpha:1.0] forState:UIControlStateNormal];
        [_containerView addSubview:cancleBtn];
        [cancleBtn addTarget:self action:@selector(clickCloseBtn) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

// 点击右上角关闭按钮,弹出框消失
- (void)clickCloseBtn {
    [self dismiss];
}

// 点击确定按钮，执行代理方法,弹出框消失
- (void)clickConfirmBtn {
    if ([self.delegate respondsToSelector:@selector(popViewClickConfirmBtn)]) {
        [self.delegate popViewClickConfirmBtn];
    }
    [self dismiss];
}

- (void)showInView:(UIView *)view {
    
    _containerView.alpha = 0;
    [view addSubview:self];
    
    _containerView.transform = CGAffineTransformMakeScale(0, 0);
    [UIView animateWithDuration:PRESENTATION_ANIMATION_DURATION
                          delay:0
         usingSpringWithDamping:1.0
          initialSpringVelocity:1
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         _containerView.alpha = 1.0f;
                         _containerView.transform = CGAffineTransformIdentity;
                     } completion:^(BOOL finished) {
                         
                     }];
}

- (void)dismiss {
    [UIView animateWithDuration:DISMISS_ANIMATION_DURATION
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         
                         _containerView.alpha = 0.0;
                         self.alpha = 0.0;
                         
                     }
                     completion:^(BOOL finished) {
                         
                         [self removeFromSuperview];
                         
                     }];
}

@end
