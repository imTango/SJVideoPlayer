//
//  SJVideoPlayer.m
//  SJVideoPlayerProject
//
//  Created by 畅三江 on 2018/5/29.
//  Copyright © 2018年 畅三江. All rights reserved.
//

#import "SJVideoPlayer.h"
#import "UIView+SJVideoPlayerSetting.h"
#if __has_include(<SJObserverHelper/NSObject+SJObserverHelper.h>)
#import <SJObserverHelper/NSObject+SJObserverHelper.h>
#else
#import "NSObject+SJObserverHelper.h"
#endif
#if __has_include(<SJBaseVideoPlayer/SJBaseVideoPlayer.h>)
#import <SJBaseVideoPlayer/SJBaseVideoPlayer+PlayStatus.h>
#else
#import "SJBaseVideoPlayer+PlayStatus.h"
#endif

NS_ASSUME_NONNULL_BEGIN
@interface _SJEdgeControlButtonItemDelegate : NSObject<SJEdgeControlButtonItemDelegate>
@property (nonatomic, strong, readonly) SJEdgeControlButtonItem *item;
- (instancetype)initWithItem:(SJEdgeControlButtonItem *)item;

@property (nonatomic, copy, nullable) void(^updatePropertiesIfNeeded)(SJEdgeControlButtonItem *item, __kindof SJBaseVideoPlayer *player);
@property (nonatomic, copy, nullable) void(^clickedItemExeBlock)(SJEdgeControlButtonItem *item);
@end

@implementation _SJEdgeControlButtonItemDelegate
- (instancetype)initWithItem:(SJEdgeControlButtonItem *)item {
    self = [super init];
    if ( !self ) return nil;
    _item = item;
    _item.delegate = self;
    [_item addTarget:self action:@selector(clickedItem:)];
    return self;
}
- (void)updatePropertiesIfNeeded:(SJEdgeControlButtonItem *)item videoPlayer:(__kindof SJBaseVideoPlayer *)player {
    if ( _updatePropertiesIfNeeded)  _updatePropertiesIfNeeded(item, player);
}
- (void)clickedItem:(SJEdgeControlButtonItem *)item {
    if ( _clickedItemExeBlock ) _clickedItemExeBlock(item);
}
@end

@interface _SJPlayerPlayFailedObserver : NSObject
- (instancetype)initWithPlayer:(SJBaseVideoPlayer *)player;
@property (nonatomic, copy, nullable) void(^playFailedExeBlock)(SJBaseVideoPlayer *player);
@end
@implementation _SJPlayerPlayFailedObserver
static NSString *_kPlayStatus = @"playStatus";
- (instancetype)initWithPlayer:(SJBaseVideoPlayer *)player {
    self = [super init];
    if ( !self ) return nil;
    [player sj_addObserver:self forKeyPath:_kPlayStatus context:&_kPlayStatus];
    return self;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable SJBaseVideoPlayer *)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context {
    if ( context == &_kPlayStatus ) {
        if ( [object playStatus_isInactivity_ReasonPlayFailed] ) {
            if ( _playFailedExeBlock ) _playFailedExeBlock(object);
        }
    }
}
@end







@interface SJVideoPlayer ()<SJFilmEditingControlLayerDelegate, SJEdgeLightweightControlLayerDelegate>
@property (nonatomic, strong, readonly) SJVideoPlayerControlSettingRecorder *recorder;
@property (nonatomic, strong, readonly) SJControlLayerCarrier *defaultEdgeCarrier;
@property (nonatomic, strong, readonly) SJControlLayerCarrier *defaultFilmEditingCarrier;
@property (nonatomic, strong, readonly) SJControlLayerCarrier *defaultEdgeLightweightCarrier;
@property (nonatomic, strong, readonly) SJControlLayerCarrier *defaultMoreSettingCarrier;
@property (nonatomic, strong, readonly) SJControlLayerCarrier *defaultLoadFailedCarrier;

@property (nonatomic, strong, readonly) _SJPlayerPlayFailedObserver *playFailedObserver;
@end

@implementation SJVideoPlayer {
    /// common
    void(^_Nullable _clickedBackEvent)(SJVideoPlayer *player);
    BOOL _hideBackButtonWhenOrientationIsPortrait;
    BOOL _disablePromptWhenNetworkStatusChanges;
    
    /// lightweight control layer
    NSArray<SJLightweightTopItem *> *_Nullable _topControlItems;
    void(^_Nullable _clickedTopControlItemExeBlock)(SJVideoPlayer *player, SJLightweightTopItem *item);

    /// default control layer
    BOOL _showMoreItemForTopControlLayer;
    NSArray<SJVideoPlayerMoreSetting *> *_Nullable _moreSettings;
    _SJEdgeControlButtonItemDelegate *_moreItemDelegate;
    
    /// film editing control layer
    BOOL _enableFilmEditing;
    SJVideoPlayerFilmEditingConfig *_filmEditingConfig;
    _SJEdgeControlButtonItemDelegate *_filmEditingItemDelegate;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%d - %s", (int)__LINE__, __func__);
#endif
}

+ (NSString *)version {
    return @"v2.2.9";
}

+ (instancetype)player {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [self _init];
    if ( !self ) return nil;
    /// 添加一个控制层
    [self.switcher addControlLayer:self.defaultEdgeCarrier];
    /// 切换到添加的控制层
    [self.switcher switchControlLayerForIdentitfier:SJControlLayer_Edge];
    /// 显示更多按钮
    self.showMoreItemForTopControlLayer = YES;
    return self;
}

+ (instancetype)lightweightPlayer {
    SJVideoPlayer *videoPlayer = [[SJVideoPlayer alloc] _init];
    /// 添加一个控制层
    [videoPlayer.switcher addControlLayer:videoPlayer.defaultEdgeLightweightCarrier];
    /// 切换到添加的控制层
    [videoPlayer.switcher switchControlLayerForIdentitfier:SJControlLayer_Edge];
    return videoPlayer;
}

- (instancetype)_init {
    self = [super init];
    if ( !self ) return nil;
    __weak typeof(self) _self = self;
    _recorder = [[SJVideoPlayerControlSettingRecorder alloc] initWithSettings:^(SJEdgeControlLayerSettings * _Nonnull setting) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        [self _updateCommonProperties];
    }];
    [self _updateCommonProperties];
    [self playFailedObserver];
    return self;
}

- (void)_updateCommonProperties {
    if ( !self.placeholderImageView.image )
        self.placeholderImageView.image = SJVideoPlayerSettings.commonSettings.placeholder;
}

@synthesize switcher = _switcher;
- (SJControlLayerSwitcher *)switcher {
    if ( _switcher ) return _switcher;
    return _switcher = [[SJControlLayerSwitcher alloc] initWithPlayer:self];
}

#pragma mark -
@synthesize defaultEdgeCarrier = _defaultEdgeCarrier;
- (SJControlLayerCarrier *)defaultEdgeCarrier {
    if ( _defaultEdgeCarrier ) return _defaultEdgeCarrier;
    SJEdgeControlLayer *controlLayer = [SJEdgeControlLayer new];
    controlLayer.hideBackButtonWhenOrientationIsPortrait = _hideBackButtonWhenOrientationIsPortrait;
    __weak typeof(self) _self = self;
    controlLayer.clickedBackItemExeBlock = ^(SJEdgeControlLayer * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.clickedBackEvent(self);
    };
    _defaultEdgeCarrier = [[SJControlLayerCarrier alloc] initWithIdentifier:SJControlLayer_Edge controlLayer:controlLayer];
    
    return _defaultEdgeCarrier;
}

- (nullable SJEdgeControlLayer *)defaultEdgeControlLayer {
    if ( [_defaultEdgeCarrier.controlLayer isKindOfClass:[SJEdgeControlLayer class]] ) {
        return (id)_defaultEdgeCarrier.controlLayer;
    }
    return nil;
}
/// 右侧按钮被点击
- (void)clickedFilmEditingBtnOnControlLayer:(SJEdgeControlLayer *)controlLayer {
    [self.switcher switchControlLayerForIdentitfier:SJControlLayer_FilmEditing];
}

#pragma mark -
@synthesize defaultFilmEditingCarrier = _defaultFilmEditingCarrier;
- (SJControlLayerCarrier *)defaultFilmEditingCarrier {
    if ( _defaultFilmEditingCarrier ) return _defaultFilmEditingCarrier;
    SJFilmEditingControlLayer *filmEditingControlLayer = [SJFilmEditingControlLayer new];
    filmEditingControlLayer.delegate = self;
    _defaultFilmEditingCarrier = [[SJControlLayerCarrier alloc] initWithIdentifier:SJControlLayer_FilmEditing controlLayer:filmEditingControlLayer];
    return _defaultFilmEditingCarrier;
}

- (nullable SJFilmEditingControlLayer *)defaultFilmEditingControlLayer {
    if ( [_defaultFilmEditingCarrier.controlLayer isKindOfClass:[SJFilmEditingControlLayer class]] ) {
        return (id)_defaultFilmEditingCarrier.controlLayer;
    }
    return nil;
}

/// 用户点击空白区域
- (void)userTappedBlankAreaOnControlLayer:(SJFilmEditingControlLayer *)controlLayer {
    [self.switcher switchControlLayerForIdentitfier:self.switcher.previousIdentifier];
}

/// 用户点击了取消按钮
- (void)userClickedCancelBtnOnControlLayer:(SJFilmEditingControlLayer *)controlLayer {
    [self.switcher switchControlLayerForIdentitfier:self.switcher.previousIdentifier];
}

/// 状态改变的回调
- (void)filmEditingControlLayer:(SJFilmEditingControlLayer *)controlLayer
                  statusChanged:(SJFilmEditingStatus)status { /*...*/ }

#pragma mark -
@synthesize defaultEdgeLightweightCarrier = _defaultEdgeLightweightCarrier;
- (SJControlLayerCarrier *)defaultEdgeLightweightCarrier {
    if ( _defaultEdgeLightweightCarrier ) return _defaultEdgeLightweightCarrier;
    SJEdgeLightweightControlLayer *edgeControlLayer = [SJEdgeLightweightControlLayer new];
    edgeControlLayer.hideBackButtonWhenOrientationIsPortrait = _hideBackButtonWhenOrientationIsPortrait;
    edgeControlLayer.delegate = self;
    _defaultEdgeLightweightCarrier = [[SJControlLayerCarrier alloc] initWithIdentifier:SJControlLayer_Edge controlLayer:edgeControlLayer];
    
    return _defaultEdgeLightweightCarrier;
}

- (nullable SJEdgeLightweightControlLayer *)defaultEdgeLightweightControlLayer {
    if ( [_defaultEdgeLightweightCarrier.controlLayer isKindOfClass:[SJEdgeLightweightControlLayer class]] ) {
        return (id)_defaultEdgeLightweightCarrier.controlLayer;
    }
    return nil;
}
/// 返回按钮被点击
- (void)clickedBackBtnOnLightweightControlLayer:(SJEdgeLightweightControlLayer *)controlLayer {
    self.clickedBackEvent(self);
}
/// 点击顶部控制层上的item
- (void)lightwieghtControlLayer:(SJEdgeLightweightControlLayer *)controlLayer clickedTopControlItem:(SJLightweightTopItem *)item {
    if ( self.clickedTopControlItemExeBlock ) self.clickedTopControlItemExeBlock(self, item);
}
/// 右侧按钮被点击
- (void)clickedFilmEditingBtnOnLightweightControlLayer:(SJEdgeLightweightControlLayer *)controlLayer {
    [self.switcher switchControlLayerForIdentitfier:SJControlLayer_FilmEditing];
}

#pragma mark -
@synthesize defaultMoreSettingCarrier = _defaultMoreSettingCarrier;
- (SJControlLayerCarrier *)defaultMoreSettingCarrier {
    if ( _defaultMoreSettingCarrier ) return _defaultMoreSettingCarrier;
    SJMoreSettingControlLayer *moreControlLayer = [SJMoreSettingControlLayer new];
    moreControlLayer.moreSettings = self.moreSettings;
    __weak typeof(self) _self = self;
    moreControlLayer.disappearExeBlock = ^(SJMoreSettingControlLayer * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        [self.switcher switchToPreviousControlLayer];
    };
    
    _defaultMoreSettingCarrier = [[SJControlLayerCarrier alloc] initWithIdentifier:SJControlLayer_MoreSettting controlLayer:moreControlLayer];
    return _defaultMoreSettingCarrier;
}

- (nullable SJMoreSettingControlLayer *)defaultMoreSettingControlLayer {
    if ( [_defaultMoreSettingCarrier.controlLayer isKindOfClass:[SJMoreSettingControlLayer class]] ) {
        return (id)_defaultMoreSettingCarrier.controlLayer;
    }
    return nil;
}
#pragma mark -
@synthesize playFailedObserver = _playFailedObserver;
- (_SJPlayerPlayFailedObserver *)playFailedObserver {
    if ( _playFailedObserver ) return _playFailedObserver;
    _playFailedObserver = [[_SJPlayerPlayFailedObserver alloc] initWithPlayer:self];
    __weak typeof(self) _self = self;
    _playFailedObserver.playFailedExeBlock = ^(SJBaseVideoPlayer * _Nonnull player) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( ![self.switcher controlLayerForIdentifier:SJControlLayer_LoadFailed] ) {
            [self.switcher addControlLayer:self.defaultLoadFailedCarrier];
        }
        [self.switcher switchControlLayerForIdentitfier:SJControlLayer_LoadFailed];
    };
    return _playFailedObserver;
}

@synthesize defaultLoadFailedCarrier = _defaultLoadFailedCarrier;
- (SJControlLayerCarrier *)defaultLoadFailedCarrier {
    if ( _defaultLoadFailedCarrier ) return _defaultLoadFailedCarrier;
    SJLoadFailedControlLayer *controlLayer = [SJLoadFailedControlLayer new];
    controlLayer.hideBackButtonWhenOrientationIsPortrait = _hideBackButtonWhenOrientationIsPortrait;
    __weak typeof(self) _self = self;
    controlLayer.clickedBackItemExeBlock = ^(SJLoadFailedControlLayer * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.clickedBackEvent(self);
    };
    
    controlLayer.clickedFaliedButtonExeBlock = ^(SJLoadFailedControlLayer * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        [self.switcher switchControlLayerForIdentitfier:SJControlLayer_Edge];
        [self refresh];
    };
    
    controlLayer.prepareToPlayNewAssetExeBlock = ^(SJLoadFailedControlLayer * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self.switcher switchControlLayerForIdentitfier:SJControlLayer_Edge];
    };
    
    _defaultLoadFailedCarrier = [[SJControlLayerCarrier alloc] initWithIdentifier:SJControlLayer_LoadFailed controlLayer:controlLayer];
    return _defaultLoadFailedCarrier;
}

- (nullable SJLoadFailedControlLayer *)defaultLoadFailedControlLayer {
    if ( [_defaultLoadFailedCarrier.controlLayer isKindOfClass:[SJLoadFailedControlLayer class]] ) {
        return (id)_defaultLoadFailedCarrier.controlLayer;
    }
    return nil;
}
@end


@implementation SJVideoPlayer (CommonSettings)
+ (void (^)(void (^ _Nonnull)(SJVideoPlayerSettings * _Nonnull)))update {
    return SJVideoPlayerSettings.update;
}

+ (void)resetSetting {
    SJVideoPlayer.update(^(SJVideoPlayerSettings * _Nonnull commonSettings) {
        [commonSettings reset];
    });
}

- (void)setClickedBackEvent:(nullable void (^)(SJVideoPlayer * _Nonnull))clickedBackEvent {
    _clickedBackEvent = clickedBackEvent;
}

- (void (^)(SJVideoPlayer * _Nonnull))clickedBackEvent {
    if ( _clickedBackEvent )
        return _clickedBackEvent;
    return ^ (SJVideoPlayer *player) {
        UIViewController *vc = [player atViewController];
        [vc.view endEditing:YES];
        if ( vc.presentingViewController ) {
            [vc dismissViewControllerAnimated:YES completion:nil];
        }
        else {
            [vc.navigationController popViewControllerAnimated:YES];
        }
    };
}

- (void)setHideBackButtonWhenOrientationIsPortrait:(BOOL)hideBackButtonWhenOrientationIsPortrait {
    _hideBackButtonWhenOrientationIsPortrait = hideBackButtonWhenOrientationIsPortrait;
    [self defaultEdgeControlLayer].hideBackButtonWhenOrientationIsPortrait = hideBackButtonWhenOrientationIsPortrait;
    [self defaultEdgeLightweightControlLayer].hideBackButtonWhenOrientationIsPortrait = hideBackButtonWhenOrientationIsPortrait;
    [self defaultLoadFailedControlLayer].hideBackButtonWhenOrientationIsPortrait = hideBackButtonWhenOrientationIsPortrait;
}

- (BOOL)hideBackButtonWhenOrientationIsPortrait {
    return _hideBackButtonWhenOrientationIsPortrait;
}

- (void)setDisablePromptWhenNetworkStatusChanges:(BOOL)disablePromptWhenNetworkStatusChanges {
    _disablePromptWhenNetworkStatusChanges = disablePromptWhenNetworkStatusChanges;
    [self defaultEdgeControlLayer].disablePromptWhenNetworkStatusChanges = disablePromptWhenNetworkStatusChanges;
    [self defaultEdgeLightweightControlLayer].disablePromptWhenNetworkStatusChanges = disablePromptWhenNetworkStatusChanges;
}

- (BOOL)disablePromptWhenNetworkStatusChanges {
    return _disablePromptWhenNetworkStatusChanges;
}
@end



@implementation SJVideoPlayer (SettingLightweightControlLayer)

- (void)setTopControlItems:(nullable NSArray<SJLightweightTopItem *> *)topControlItems {
    _topControlItems = topControlItems.copy;
    [self defaultEdgeLightweightControlLayer].topItems = topControlItems;
}

- (nullable NSArray<SJLightweightTopItem *> *)topControlItems {
    return _topControlItems;
}

- (void)setClickedTopControlItemExeBlock:(nullable void (^)(SJVideoPlayer * _Nonnull, SJLightweightTopItem * _Nonnull))clickedTopControlItemExeBlock {
    _clickedTopControlItemExeBlock = clickedTopControlItemExeBlock;
}

- (nullable void (^)(SJVideoPlayer * _Nonnull, SJLightweightTopItem * _Nonnull))clickedTopControlItemExeBlock {
    return _clickedTopControlItemExeBlock;
}
@end


#pragma mark -
@implementation SJVideoPlayer (SettingDefaultControlLayer)

- (void)setGeneratePreviewImages:(BOOL)generatePreviewImages {
    [self defaultEdgeControlLayer].generatePreviewImages = generatePreviewImages;
}

- (BOOL)generatePreviewImages {
    return [self defaultEdgeControlLayer].generatePreviewImages;
}

- (void)setMoreSettings:(nullable NSArray<SJVideoPlayerMoreSetting *> *)moreSettings {
    [self defaultMoreSettingControlLayer].moreSettings = moreSettings;
}

- (nullable NSArray<SJVideoPlayerMoreSetting *> *)moreSettings {
    return [self defaultMoreSettingControlLayer].moreSettings;
}

- (void)setShowMoreItemForTopControlLayer:(BOOL)showMoreItemForTopControlLayer {
    if ( showMoreItemForTopControlLayer == _showMoreItemForTopControlLayer )
        return;
    _showMoreItemForTopControlLayer = showMoreItemForTopControlLayer;
    if ( showMoreItemForTopControlLayer ) {
        [self.defaultEdgeControlLayer.topAdapter addItem:[self moreItemDelegate].item];
        [self.switcher addControlLayer:[self defaultMoreSettingCarrier]];
    }
    else {
        [self.defaultEdgeControlLayer.topAdapter removeItemForTag:SJEdgeControlLayerTopItem_More];
        [self.switcher deleteControlLayerForIdentifier:SJControlLayer_MoreSettting];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.defaultEdgeControlLayer.topAdapter reload];
    });
}

- (BOOL)showMoreItemForTopControlLayer {
    return _showMoreItemForTopControlLayer;
}

- (_SJEdgeControlButtonItemDelegate *)moreItemDelegate {
    if ( _moreItemDelegate )
        return _moreItemDelegate;
    _moreItemDelegate = [[_SJEdgeControlButtonItemDelegate alloc] initWithItem:[SJEdgeControlButtonItem placeholderWithSize:58 tag:SJEdgeControlLayerTopItem_More]];
    _moreItemDelegate.item.image = SJVideoPlayerSettings.commonSettings.moreBtnImage;
    _moreItemDelegate.updatePropertiesIfNeeded = ^(SJEdgeControlButtonItem * _Nonnull item, __kindof SJBaseVideoPlayer * _Nonnull player) {
        item.hidden = !player.isFullScreen;
        item.image = SJVideoPlayerSettings.commonSettings.moreBtnImage;
    };
    
    __weak typeof(self) _self = self;
    _moreItemDelegate.clickedItemExeBlock = ^(SJEdgeControlButtonItem * _Nonnull item) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self.switcher switchControlLayerForIdentitfier:SJControlLayer_MoreSettting];
    };
    return _moreItemDelegate;
}

@end


@implementation SJVideoPlayer (FilmEditing)
- (void)setEnableFilmEditing:(BOOL)enableFilmEditing {
    if ( enableFilmEditing == _enableFilmEditing ) return;
    _enableFilmEditing = enableFilmEditing;
   
    [self defaultEdgeLightweightControlLayer].enableFilmEditing = enableFilmEditing;
    if ( enableFilmEditing ) {
        // 将剪辑控制层加入到切换器中
        [self.switcher addControlLayer:self.defaultFilmEditingCarrier];
        [self defaultFilmEditingControlLayer].config = self.filmEditingConfig;
        
        // 将item加入到边缘控制层中
        [[self defaultEdgeControlLayer].rightAdapter addItem:[self filmEditingItemDelegate].item];
    }
    else {
        // 移除
        [self.switcher deleteControlLayerForIdentifier:SJControlLayer_FilmEditing];
        _defaultFilmEditingCarrier = nil;
        [[self defaultEdgeControlLayer].rightAdapter removeItemForTag:SJEdgeControlLayerBottomItem_FilmEditing];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self defaultEdgeControlLayer].rightAdapter reload];
    });
}

- (BOOL)enableFilmEditing {
    return _enableFilmEditing;
}

// 历史遗留问题, 此处不应该readonly. 应该由外界配置...
- (SJVideoPlayerFilmEditingConfig *)filmEditingConfig {
    if ( _filmEditingConfig ) return _filmEditingConfig;
    _filmEditingConfig = [SJVideoPlayerFilmEditingConfig new];
    __weak typeof(self) _self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self defaultFilmEditingControlLayer].config = self.filmEditingConfig;
    });
    return _filmEditingConfig;
}

- (void)dismissFilmEditingViewCompletion:(void(^__nullable)(SJVideoPlayer *player))completion {
    [self.switcher switchControlLayerForIdentitfier:SJControlLayer_Edge];
    if ( completion ) completion(self);
}

- (_SJEdgeControlButtonItemDelegate *)filmEditingItemDelegate {
    if ( _filmEditingItemDelegate )
        return _filmEditingItemDelegate;
    
    _filmEditingItemDelegate = [[_SJEdgeControlButtonItemDelegate alloc] initWithItem:[SJEdgeControlButtonItem placeholderWithType:SJButtonItemPlaceholderType_49x49 tag:SJEdgeControlLayerBottomItem_FilmEditing]];
    _filmEditingItemDelegate.item.image = SJVideoPlayerSettings.commonSettings.filmEditingBtnImage;
    _filmEditingItemDelegate.updatePropertiesIfNeeded = ^(SJEdgeControlButtonItem * _Nonnull item, __kindof SJBaseVideoPlayer * _Nonnull player) {
        // 小屏或者 M3U8的时候 自动隐藏
        // M3u8 暂时无法剪辑
        item.hidden = (!player.isFullScreen || player.URLAsset.isM3u8) || !player.URLAsset;
        item.image = SJVideoPlayerSettings.commonSettings.filmEditingBtnImage;
    };
    
    __weak typeof(self) _self = self;
    _filmEditingItemDelegate.clickedItemExeBlock = ^(SJEdgeControlButtonItem * _Nonnull item) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self switchControlLayerForIdentitfier:SJControlLayer_FilmEditing];
    };
    return _filmEditingItemDelegate;
}
@end


@implementation SJVideoPlayer (SwitcherExtension)
- (void)switchControlLayerForIdentitfier:(SJControlLayerIdentifier)identifier {
    [self.switcher switchControlLayerForIdentitfier:identifier];
}
@end

SJControlLayerIdentifier const SJControlLayer_Edge = LONG_MAX - 1;
SJControlLayerIdentifier const SJControlLayer_FilmEditing = LONG_MAX - 2;
SJControlLayerIdentifier const SJControlLayer_MoreSettting = LONG_MAX - 3;
SJControlLayerIdentifier const SJControlLayer_LoadFailed = LONG_MAX - 4;

SJEdgeControlButtonItemTag const SJEdgeControlLayerBottomItem_FilmEditing = LONG_MAX - 1;   // GIF/导出/截屏
SJEdgeControlButtonItemTag const SJEdgeControlLayerTopItem_More = LONG_MAX - 2;             // More


@implementation SJVideoPlayer (SJVideoPlayerDeprecated)

- (void)setDisableNetworkStatusChangePrompt:(BOOL)disableNetworkStatusChangePrompt __deprecated_msg("use `disablePromptWhenNetworkStatusChanges`") {
    [self setDisablePromptWhenNetworkStatusChanges:disableNetworkStatusChangePrompt];
}
- (BOOL)disableNetworkStatusChangePrompt __deprecated_msg("use `disablePromptWhenNetworkStatusChanges`") {
    return [self disablePromptWhenNetworkStatusChanges];
}

@end
NS_ASSUME_NONNULL_END
