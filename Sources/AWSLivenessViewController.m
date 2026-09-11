#import "AWSLivenessViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <QuartzCore/QuartzCore.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>

@interface AWSLivenessViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVPlayer *samplePlayer;
@property (nonatomic, strong) AVPlayerLayer *samplePlayerLayer;
@property (nonatomic, strong) AVPlayerItemVideoOutput *sampleVideoOutput;
@property (nonatomic, strong) NSURL *sampleVideoURL;
@property (nonatomic, assign) BOOL sampleVideoMode;
@property (nonatomic, assign) BOOL sampleVideoEnded;

@property (nonatomic, strong) UIView *startView;
@property (nonatomic, strong) UILabel *sourceLabel;
@property (nonatomic, strong) UIButton *beginButton;
@property (nonatomic, strong) UIButton *sourceButton;
@property (nonatomic, strong) UIButton *infoButton;

@property (nonatomic, strong) UIView *challengeOverlay;
@property (nonatomic, strong) CAShapeLayer *dimMaskLayer;
@property (nonatomic, strong) CAShapeLayer *ovalLayer;
@property (nonatomic, strong) UILabel *promptLabel;
@property (nonatomic, strong) UILabel *subPromptLabel;
@property (nonatomic, strong) UILabel *countdownLabel;
@property (nonatomic, strong) UILabel *recLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *flashView;
@property (nonatomic, strong) UILabel *diagnosticLabel;
@property (nonatomic, strong) CADisplayLink *displayLink;

@property (nonatomic, assign) NSInteger phase;
@property (nonatomic, assign) CFTimeInterval phaseStart;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) CGFloat savedBrightness;
@property (nonatomic, assign) NSInteger countdownValue;

@property (atomic, assign) CGFloat brightness;
@property (atomic, assign) NSInteger faceCount;
@property (atomic, assign) CGRect faceBox;
@property (atomic, assign) CGFloat motionScore;
@property (nonatomic, assign) CGRect previousFaceBox;
@property (nonatomic, assign) BOOL hasPreviousFace;
@end

@implementation AWSLivenessViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.brightness = -1.0;
    self.faceBox = CGRectZero;
    self.savedBrightness = UIScreen.mainScreen.brightness;

    [self buildCameraLayers];
    [self buildStartView];
    [self buildChallengeOverlay];

    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDiagnostics)];
    tripleTap.numberOfTapsRequired = 3;
    [self.view addGestureRecognizer:tripleTap];

    [self requestCameraAndPrepare];
    [self showStartScreen];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self stopAllSources];
    UIScreen.mainScreen.brightness = self.savedBrightness;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    UIScreen.mainScreen.brightness = self.savedBrightness;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
    self.samplePlayerLayer.frame = self.view.bounds;
    self.flashView.frame = self.view.bounds;
    [self updateOvalPath];
}

#pragma mark - UI

- (void)buildCameraLayers {
    self.flashView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.flashView.backgroundColor = UIColor.clearColor;
    self.flashView.alpha = 0;
    self.flashView.userInteractionEnabled = NO;
    [self.view addSubview:self.flashView];
}

- (UILabel *)labelWithText:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (UIView *)tipRowWithSymbol:(NSString *)symbol text:(NSString *)text {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor colorWithRed:0.05 green:0.45 blue:0.52 alpha:1];
    icon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *label = [self labelWithText:text size:15 weight:UIFontWeightRegular color:[UIColor colorWithWhite:0.13 alpha:1]];

    [row addSubview:icon];
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [icon.topAnchor constraintEqualToAnchor:row.topAnchor constant:2],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:row.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (void)buildStartView {
    UIView *v = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = UIColor.systemBackgroundColor;
    [self.view addSubview:v];
    self.startView = v;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.labelColor;
    [close addTarget:self action:@selector(closeStandaloneApp) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:close];

    UILabel *title = [self labelWithText:@"Liveness Check" size:25 weight:UIFontWeightBold color:UIColor.labelColor];
    title.textAlignment = NSTextAlignmentCenter;
    [v addSubview:title];

    UIView *illustration = [UIView new];
    illustration.translatesAutoresizingMaskIntoConstraints = NO;
    illustration.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];
    illustration.layer.cornerRadius = 18;
    [v addSubview:illustration];

    CAShapeLayer *oval = [CAShapeLayer layer];
    oval.fillColor = UIColor.clearColor.CGColor;
    oval.strokeColor = [UIColor colorWithRed:0.10 green:0.53 blue:0.58 alpha:1].CGColor;
    oval.lineWidth = 3;
    oval.frame = CGRectMake(0, 0, 140, 170);
    oval.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(24, 12, 92, 142)].CGPath;
    [illustration.layer addSublayer:oval];

    UIImageView *faceIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle"]];
    faceIcon.translatesAutoresizingMaskIntoConstraints = NO;
    faceIcon.tintColor = [UIColor colorWithWhite:0.28 alpha:1];
    faceIcon.contentMode = UIViewContentModeScaleAspectFit;
    [illustration addSubview:faceIcon];

    UILabel *lead = [self labelWithText:@"Before you start" size:18 weight:UIFontWeightSemibold color:UIColor.labelColor];
    [v addSubview:lead];

    UIView *r1 = [self tipRowWithSymbol:@"sun.max" text:@"Make sure your face is clearly visible and evenly lit."];
    UIView *r2 = [self tipRowWithSymbol:@"iphone" text:@"Hold your phone upright and keep the camera near eye level."];
    UIView *r3 = [self tipRowWithSymbol:@"face.smiling" text:@"Keep only one face in view and follow the on-screen instructions."];
    [v addSubview:r1]; [v addSubview:r2]; [v addSubview:r3];

    UIView *warning = [UIView new];
    warning.translatesAutoresizingMaskIntoConstraints = NO;
    warning.backgroundColor = [UIColor colorWithRed:0.96 green:0.98 blue:0.99 alpha:1];
    warning.layer.cornerRadius = 12;
    [v addSubview:warning];

    UIImageView *warningIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]];
    warningIcon.translatesAutoresizingMaskIntoConstraints = NO;
    warningIcon.tintColor = [UIColor colorWithRed:0.05 green:0.43 blue:0.50 alpha:1];
    [warning addSubview:warningIcon];

    UILabel *warningTitle = [self labelWithText:@"Photosensitivity Warning" size:14 weight:UIFontWeightSemibold color:UIColor.labelColor];
    UILabel *warningBody = [self labelWithText:@"This local practice includes flashing colors similar to the visible AWS challenge. Use caution if you are photosensitive." size:12 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];
    [warning addSubview:warningTitle];
    [warning addSubview:warningBody];

    self.sourceLabel = [self labelWithText:@"Input: Live front camera" size:12 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor];
    self.sourceLabel.textAlignment = NSTextAlignmentCenter;
    [v addSubview:self.sourceLabel];

    UIButton *source = [UIButton buttonWithType:UIButtonTypeSystem];
    source.translatesAutoresizingMaskIntoConstraints = NO;
    [source setTitle:@"Choose input source" forState:UIControlStateNormal];
    source.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [source addTarget:self action:@selector(showSourcePicker) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:source];
    self.sourceButton = source;

    UIButton *info = [UIButton buttonWithType:UIButtonTypeSystem];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    [info setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
    info.tintColor = UIColor.labelColor;
    [info addTarget:self action:@selector(showInfo) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:info];
    self.infoButton = info;

    UIButton *begin = [UIButton buttonWithType:UIButtonTypeSystem];
    begin.translatesAutoresizingMaskIntoConstraints = NO;
    begin.backgroundColor = [UIColor colorWithRed:0.04 green:0.48 blue:0.53 alpha:1];
    [begin setTitle:@"Start video check" forState:UIControlStateNormal];
    [begin setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    begin.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    begin.layer.cornerRadius = 9;
    [begin addTarget:self action:@selector(beginCheck) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:begin];
    self.beginButton = begin;

    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:self.view.topAnchor], [v.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [close.leadingAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.leadingAnchor constant:16], [close.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor constant:8], [close.widthAnchor constraintEqualToConstant:38], [close.heightAnchor constraintEqualToConstant:38],
        [info.trailingAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.trailingAnchor constant:-16], [info.centerYAnchor constraintEqualToAnchor:close.centerYAnchor], [info.widthAnchor constraintEqualToConstant:38], [info.heightAnchor constraintEqualToConstant:38],
        [title.centerYAnchor constraintEqualToAnchor:close.centerYAnchor], [title.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [illustration.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:18], [illustration.centerXAnchor constraintEqualToAnchor:v.centerXAnchor], [illustration.widthAnchor constraintEqualToConstant:140], [illustration.heightAnchor constraintEqualToConstant:170],
        [faceIcon.centerXAnchor constraintEqualToAnchor:illustration.centerXAnchor], [faceIcon.centerYAnchor constraintEqualToAnchor:illustration.centerYAnchor], [faceIcon.widthAnchor constraintEqualToConstant:72], [faceIcon.heightAnchor constraintEqualToConstant:72],
        [lead.leadingAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.leadingAnchor constant:24], [lead.trailingAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.trailingAnchor constant:-24], [lead.topAnchor constraintEqualToAnchor:illustration.bottomAnchor constant:18],
        [r1.leadingAnchor constraintEqualToAnchor:lead.leadingAnchor], [r1.trailingAnchor constraintEqualToAnchor:lead.trailingAnchor], [r1.topAnchor constraintEqualToAnchor:lead.bottomAnchor constant:13],
        [r2.leadingAnchor constraintEqualToAnchor:lead.leadingAnchor], [r2.trailingAnchor constraintEqualToAnchor:lead.trailingAnchor], [r2.topAnchor constraintEqualToAnchor:r1.bottomAnchor constant:10],
        [r3.leadingAnchor constraintEqualToAnchor:lead.leadingAnchor], [r3.trailingAnchor constraintEqualToAnchor:lead.trailingAnchor], [r3.topAnchor constraintEqualToAnchor:r2.bottomAnchor constant:10],
        [warning.leadingAnchor constraintEqualToAnchor:lead.leadingAnchor], [warning.trailingAnchor constraintEqualToAnchor:lead.trailingAnchor], [warning.topAnchor constraintEqualToAnchor:r3.bottomAnchor constant:16],
        [warningIcon.leadingAnchor constraintEqualToAnchor:warning.leadingAnchor constant:12], [warningIcon.topAnchor constraintEqualToAnchor:warning.topAnchor constant:12], [warningIcon.widthAnchor constraintEqualToConstant:22], [warningIcon.heightAnchor constraintEqualToConstant:22],
        [warningTitle.leadingAnchor constraintEqualToAnchor:warningIcon.trailingAnchor constant:8], [warningTitle.trailingAnchor constraintEqualToAnchor:warning.trailingAnchor constant:-12], [warningTitle.topAnchor constraintEqualToAnchor:warning.topAnchor constant:10],
        [warningBody.leadingAnchor constraintEqualToAnchor:warningTitle.leadingAnchor], [warningBody.trailingAnchor constraintEqualToAnchor:warning.trailingAnchor constant:-12], [warningBody.topAnchor constraintEqualToAnchor:warningTitle.bottomAnchor constant:3], [warningBody.bottomAnchor constraintEqualToAnchor:warning.bottomAnchor constant:-11],
        [sourceLabel.leadingAnchor constraintEqualToAnchor:lead.leadingAnchor], [sourceLabel.trailingAnchor constraintEqualToAnchor:lead.trailingAnchor], [sourceLabel.topAnchor constraintGreaterThanOrEqualToAnchor:warning.bottomAnchor constant:12],
        [source.centerXAnchor constraintEqualToAnchor:v.centerXAnchor], [source.topAnchor constraintEqualToAnchor:sourceLabel.bottomAnchor constant:2],
        [begin.leadingAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.leadingAnchor constant:24], [begin.trailingAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.trailingAnchor constant:-24], [begin.heightAnchor constraintEqualToConstant:50], [begin.bottomAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [source.bottomAnchor constraintLessThanOrEqualToAnchor:begin.topAnchor constant:-8],
    ]];
}

- (void)buildChallengeOverlay {
    UIView *overlay = [UIView new];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.hidden = YES;
    overlay.userInteractionEnabled = YES;
    [self.view addSubview:overlay];
    self.challengeOverlay = overlay;

    self.dimMaskLayer = [CAShapeLayer layer];
    self.dimMaskLayer.fillRule = kCAFillRuleEvenOdd;
    self.dimMaskLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.34].CGColor;
    [overlay.layer addSublayer:self.dimMaskLayer];

    self.ovalLayer = [CAShapeLayer layer];
    self.ovalLayer.fillColor = UIColor.clearColor.CGColor;
    self.ovalLayer.strokeColor = UIColor.whiteColor.CGColor;
    self.ovalLayer.lineWidth = 3.5;
    [overlay.layer addSublayer:self.ovalLayer];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.closeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
    self.closeButton.layer.cornerRadius = 18;
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.whiteColor;
    [self.closeButton addTarget:self action:@selector(cancelCheck) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:self.closeButton];

    self.recLabel = [self labelWithText:@"● REC" size:12 weight:UIFontWeightBold color:UIColor.whiteColor];
    self.recLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
    self.recLabel.layer.cornerRadius = 8;
    self.recLabel.clipsToBounds = YES;
    self.recLabel.textAlignment = NSTextAlignmentCenter;
    [overlay addSubview:self.recLabel];

    self.promptLabel = [self labelWithText:@"Connecting..." size:18 weight:UIFontWeightSemibold color:UIColor.whiteColor];
    self.promptLabel.textAlignment = NSTextAlignmentCenter;
    self.promptLabel.backgroundColor = [UIColor colorWithRed:0.02 green:0.47 blue:0.52 alpha:0.93];
    self.promptLabel.layer.cornerRadius = 7;
    self.promptLabel.clipsToBounds = YES;
    [overlay addSubview:self.promptLabel];

    self.subPromptLabel = [self labelWithText:@"" size:13 weight:UIFontWeightMedium color:UIColor.whiteColor];
    self.subPromptLabel.textAlignment = NSTextAlignmentCenter;
    self.subPromptLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.36];
    self.subPromptLabel.layer.cornerRadius = 7;
    self.subPromptLabel.clipsToBounds = YES;
    [overlay addSubview:self.subPromptLabel];

    self.countdownLabel = [self labelWithText:@"" size:72 weight:UIFontWeightBold color:UIColor.whiteColor];
    self.countdownLabel.textAlignment = NSTextAlignmentCenter;
    self.countdownLabel.hidden = YES;
    self.countdownLabel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.countdownLabel.layer.shadowOpacity = 0.45;
    self.countdownLabel.layer.shadowRadius = 5;
    [overlay addSubview:self.countdownLabel];

    self.diagnosticLabel = [self labelWithText:@"" size:10 weight:UIFontWeightRegular color:UIColor.whiteColor];
    self.diagnosticLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.diagnosticLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.68];
    self.diagnosticLabel.layer.cornerRadius = 8;
    self.diagnosticLabel.clipsToBounds = YES;
    self.diagnosticLabel.textAlignment = NSTextAlignmentCenter;
    self.diagnosticLabel.hidden = YES;
    [overlay addSubview:self.diagnosticLabel];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor], [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.closeButton.leadingAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.leadingAnchor constant:14], [self.closeButton.topAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.topAnchor constant:10], [self.closeButton.widthAnchor constraintEqualToConstant:36], [self.closeButton.heightAnchor constraintEqualToConstant:36],
        [self.recLabel.trailingAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.trailingAnchor constant:-14], [self.recLabel.centerYAnchor constraintEqualToAnchor:self.closeButton.centerYAnchor], [self.recLabel.widthAnchor constraintEqualToConstant:62], [self.recLabel.heightAnchor constraintEqualToConstant:28],
        [self.promptLabel.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor], [self.promptLabel.topAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.topAnchor constant:62], [self.promptLabel.widthAnchor constraintLessThanOrEqualToAnchor:overlay.widthAnchor multiplier:0.78], [self.promptLabel.heightAnchor constraintGreaterThanOrEqualToConstant:38],
        [self.subPromptLabel.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor], [self.subPromptLabel.topAnchor constraintEqualToAnchor:self.promptLabel.bottomAnchor constant:7], [self.subPromptLabel.widthAnchor constraintLessThanOrEqualToAnchor:overlay.widthAnchor multiplier:0.86], [self.subPromptLabel.heightAnchor constraintGreaterThanOrEqualToConstant:28],
        [self.countdownLabel.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor], [self.countdownLabel.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor constant:16],
        [self.diagnosticLabel.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor], [self.diagnosticLabel.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-12], [self.diagnosticLabel.widthAnchor constraintLessThanOrEqualToAnchor:overlay.widthAnchor multiplier:0.88],
    ]];
}

- (CGRect)ovalRect {
    CGRect b = self.view.bounds;
    CGFloat w = MIN(CGRectGetWidth(b) * 0.72, 330.0);
    CGFloat h = w * 1.30;
    CGFloat y = MAX(CGRectGetHeight(b) * 0.19, 142.0);
    if (y + h > CGRectGetHeight(b) - 70) y = CGRectGetHeight(b) - h - 70;
    return CGRectMake((CGRectGetWidth(b)-w)/2.0, y, w, h);
}

- (void)updateOvalPath {
    if (!self.challengeOverlay) return;
    CGRect b = self.view.bounds;
    CGRect oval = [self ovalRect];
    UIBezierPath *mask = [UIBezierPath bezierPathWithRect:b];
    [mask appendPath:[UIBezierPath bezierPathWithOvalInRect:oval]];
    self.dimMaskLayer.frame = b;
    self.dimMaskLayer.path = mask.CGPath;
    self.ovalLayer.frame = b;
    self.ovalLayer.path = [UIBezierPath bezierPathWithOvalInRect:oval].CGPath;
}

- (void)showStartScreen {
    self.running = NO;
    self.challengeOverlay.hidden = YES;
    self.startView.hidden = NO;
    self.flashView.alpha = 0;
    self.countdownLabel.hidden = YES;
    self.sampleVideoEnded = NO;
    UIScreen.mainScreen.brightness = self.savedBrightness;
    if (self.sampleVideoMode) {
        self.sourceLabel.text = [NSString stringWithFormat:@"Input: Sample video — %@", self.sampleVideoURL.lastPathComponent ?: @"selected video"];
    } else {
        self.sourceLabel.text = @"Input: Live front camera";
    }
}

#pragma mark - Source selection

- (void)showSourcePicker {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Input source"
                                                                   message:@"Sample videos are processed only inside this local practice app. They are not submitted to AWS or any real verification session."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Live front camera" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self switchToLiveCamera]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose video from Photos" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self chooseVideoFromPhotos]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose video from Files" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self chooseVideoFromFiles]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) { pop.sourceView = self.sourceButton; pop.sourceRect = self.sourceButton.bounds; }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseVideoFromPhotos {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 1;
    config.filter = [PHPickerFilter videosFilter];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)chooseVideoFromFiles {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMovie] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (NSURL *)cachedURLForIncomingURL:(NSURL *)url preferredExtension:(NSString *)ext {
    NSString *name = [NSString stringWithFormat:@"sample-%@.%@", NSUUID.UUID.UUIDString, ext.length ? ext : @"mov"];
    NSURL *dir = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    NSURL *dest = [dir URLByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:dest error:&error]) return dest;
    return nil;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    NSItemProvider *provider = result.itemProvider;
    [provider loadFileRepresentationForTypeIdentifier:UTTypeMovie.identifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (!url || error) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showImportError:error.localizedDescription ?: @"Unable to import video."]; });
            return;
        }
        NSURL *cached = [self cachedURLForIncomingURL:url preferredExtension:url.pathExtension];
        dispatch_async(dispatch_get_main_queue(), ^{ if (cached) [self loadSampleVideoURL:cached]; else [self showImportError:@"Unable to copy selected video."]; });
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSURL *cached = [self cachedURLForIncomingURL:url preferredExtension:url.pathExtension];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (cached) [self loadSampleVideoURL:cached]; else [self showImportError:@"Unable to import the selected file."];
}

- (void)showImportError:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Video import failed" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)switchToLiveCamera {
    self.sampleVideoMode = NO;
    self.sampleVideoEnded = NO;
    [self.samplePlayer pause];
    self.samplePlayerLayer.hidden = YES;
    self.previewLayer.hidden = NO;
    self.faceCount = 0; self.faceBox = CGRectZero; self.brightness = -1; self.hasPreviousFace = NO;
    self.sourceLabel.text = @"Input: Live front camera";
    if (!self.session) [self requestCameraAndPrepare];
    else if (!self.session.isRunning) dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self.session startRunning]; });
}

- (void)loadSampleVideoURL:(NSURL *)url {
    self.sampleVideoMode = YES;
    self.sampleVideoURL = url;
    self.sampleVideoEnded = NO;
    self.faceCount = 0; self.faceBox = CGRectZero; self.brightness = -1; self.motionScore = 0; self.hasPreviousFace = NO;

    if (self.session.isRunning) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self.session stopRunning]; });
    self.previewLayer.hidden = YES;

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
    self.sampleVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
    [item addOutput:self.sampleVideoOutput];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sampleVideoDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];

    self.samplePlayer = [AVPlayer playerWithPlayerItem:item];
    if (!self.samplePlayerLayer) {
        self.samplePlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.samplePlayer];
        self.samplePlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.view.layer insertSublayer:self.samplePlayerLayer atIndex:0];
    } else self.samplePlayerLayer.player = self.samplePlayer;
    self.samplePlayerLayer.hidden = NO;
    self.samplePlayerLayer.frame = self.view.bounds;
    [self.samplePlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    self.sourceLabel.text = [NSString stringWithFormat:@"Input: Sample video — %@", url.lastPathComponent ?: @"video"];
}

- (void)sampleVideoDidEnd:(NSNotification *)note {
    self.sampleVideoEnded = YES;
    if (self.running) dispatch_async(dispatch_get_main_queue(), ^{ [self showResultWithTitle:@"Sample video ended" detail:@"Use a longer sample and try again." success:NO]; });
}

#pragma mark - Camera

- (void)requestCameraAndPrepare {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) { [self prepareCamera]; return; }
    if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (granted) [self prepareCamera]; });
        }];
    }
}

- (AVCaptureDevice *)frontCamera {
    AVCaptureDeviceDiscoverySession *d = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
    return d.devices.firstObject;
}

- (void)prepareCamera {
    if (self.session) return;
    AVCaptureDevice *camera = [self frontCamera]; if (!camera) return;
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error]; if (!input) return;
    AVCaptureSession *s = [AVCaptureSession new];
    if ([s canSetSessionPreset:AVCaptureSessionPreset1280x720]) s.sessionPreset = AVCaptureSessionPreset1280x720;
    if ([s canAddInput:input]) [s addInput:input];
    AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
    dispatch_queue_t q = dispatch_queue_create("com.local.awslivenesspractice.video", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:q];
    if ([s canAddOutput:output]) [s addOutput:output];
    for (AVCaptureConnection *c in output.connections) {
        if (c.isVideoMirroringSupported) c.videoMirrored = YES;
        if (c.isVideoOrientationSupported) c.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    self.session = s;
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:s];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];
    self.previewLayer.frame = self.view.bounds;
    self.previewLayer.hidden = self.sampleVideoMode;
    if (!self.sampleVideoMode) dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [s startRunning]; });
}

#pragma mark - AWS-style local flow

- (void)beginCheck {
    self.savedBrightness = UIScreen.mainScreen.brightness;
    UIScreen.mainScreen.brightness = 1.0;
    self.startView.hidden = YES;
    self.challengeOverlay.hidden = NO;
    [self updateOvalPath];

    self.running = YES;
    self.phase = 0;
    self.phaseStart = CACurrentMediaTime();
    self.countdownValue = 3;
    self.hasPreviousFace = NO;
    self.sampleVideoEnded = NO;
    self.countdownLabel.hidden = YES;
    self.flashView.alpha = 0;
    self.recLabel.text = @"● REC";

    if (self.sampleVideoMode) {
        [self.samplePlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) { if (finished) [self.samplePlayer play]; }];
    } else if (!self.session.isRunning) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self.session startRunning]; });
    }

    [self.displayLink invalidate];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (NSString *)faceFitInstruction {
    if (self.faceCount == 0) return @"Move face in front of camera";
    if (self.faceCount > 1) return @"Only one face per check";
    if (CGRectIsEmpty(self.faceBox)) return @"Center your face";
    CGFloat area = self.faceBox.size.width * self.faceBox.size.height;
    CGFloat cx = CGRectGetMidX(self.faceBox), cy = CGRectGetMidY(self.faceBox);
    if (area > 0.34) return @"Move face farther away";
    if (area < 0.12) return @"Move closer";
    if (cx < 0.43) return @"Move face right";
    if (cx > 0.57) return @"Move face left";
    if (cy < 0.40 || cy > 0.64) return @"Move face to fit in oval";
    if (self.brightness >= 0 && self.brightness < 48) return @"Move to brighter area";
    if (self.brightness > 220) return @"Move to dimmer area";
    return nil;
}

- (void)setPrompt:(NSString *)title detail:(NSString *)detail good:(BOOL)good {
    self.promptLabel.text = [NSString stringWithFormat:@"  %@  ", title ?: @""];
    self.subPromptLabel.text = detail.length ? [NSString stringWithFormat:@"  %@  ", detail] : @"";
    self.subPromptLabel.hidden = detail.length == 0;
    self.ovalLayer.strokeColor = (good ? [UIColor colorWithRed:0.34 green:0.94 blue:0.78 alpha:1] : UIColor.whiteColor).CGColor;
}

- (void)advanceToPhase:(NSInteger)phase {
    self.phase = phase;
    self.phaseStart = CACurrentMediaTime();
    self.countdownLabel.hidden = YES;
    self.flashView.alpha = 0;
}

- (NSArray<UIColor *> *)localLightSequence {
    return @[
        [UIColor colorWithRed:0.92 green:0.98 blue:1 alpha:1],
        [UIColor colorWithRed:0.34 green:0.86 blue:0.95 alpha:1],
        [UIColor colorWithRed:0.76 green:0.46 blue:0.96 alpha:1],
        [UIColor colorWithRed:1.00 green:0.56 blue:0.68 alpha:1],
        [UIColor colorWithRed:1.00 green:0.82 blue:0.38 alpha:1],
        [UIColor colorWithRed:0.52 green:0.95 blue:0.64 alpha:1],
        [UIColor colorWithRed:0.40 green:0.68 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.96 green:0.96 blue:0.96 alpha:1],
    ];
}

- (void)tick:(CADisplayLink *)link {
    if (!self.running) return;
    if (self.sampleVideoMode) [self processCurrentSampleVideoFrame];
    CFTimeInterval elapsed = CACurrentMediaTime() - self.phaseStart;
    NSString *instruction = [self faceFitInstruction];

    if (self.phase == 0) {
        if (instruction) {
            [self setPrompt:instruction detail:@"Center your face" good:NO];
            self.phaseStart = CACurrentMediaTime();
        } else {
            [self setPrompt:@"Hold still" detail:@"Keep your face inside the oval" good:YES];
            if (elapsed > 0.55) [self advanceToPhase:1];
        }
    }
    else if (self.phase == 1) {
        if (self.faceCount == 0) { [self showResultWithTitle:@"Check failed during countdown" detail:@"No face detected during the countdown." success:NO]; return; }
        if (self.faceCount > 1) { [self showResultWithTitle:@"Check failed during countdown" detail:@"Multiple faces detected during the countdown." success:NO]; return; }
        CGFloat area = self.faceBox.size.width * self.faceBox.size.height;
        if (area > 0.36) { [self showResultWithTitle:@"Check failed during countdown" detail:@"Move back and retry. The face moved too close during countdown." success:NO]; return; }
        [self setPrompt:@"Hold still" detail:@"Hold face position during countdown." good:YES];
        NSInteger value = MAX(1, 3 - (NSInteger)floor(elapsed));
        self.countdownLabel.hidden = NO;
        self.countdownLabel.text = [NSString stringWithFormat:@"%ld", (long)value];
        if (elapsed >= 3.0) [self advanceToPhase:2];
    }
    else if (self.phase == 2) {
        self.countdownLabel.hidden = YES;
        if (instruction && ![instruction isEqualToString:@"Move closer"] && ![instruction isEqualToString:@"Move face farther away"]) {
            [self setPrompt:instruction detail:@"Keep your face inside the oval" good:NO];
        } else {
            [self setPrompt:@"Hold still" detail:@"Hold face in oval for colored lights." good:YES];
        }
        NSArray<UIColor *> *colors = [self localLightSequence];
        NSInteger idx = MIN((NSInteger)(elapsed / 0.5), (NSInteger)colors.count - 1);
        self.flashView.backgroundColor = colors[idx];
        self.flashView.alpha = 0.32;
        if (elapsed >= 4.0) [self advanceToPhase:3];
    }
    else if (self.phase == 3) {
        self.flashView.alpha = 0;
        self.recLabel.text = @"";
        [self setPrompt:@"Verifying" detail:@"" good:YES];
        if (elapsed >= 1.4) {
            [self showResultWithTitle:@"Check complete" detail:@"Local AWS-style practice completed. This is not a Rekognition liveness score or biometric decision." success:YES];
            return;
        }
    }

    CGFloat area = self.faceBox.size.width * self.faceBox.size.height;
    NSString *source = self.sampleVideoMode ? @"VIDEO SAMPLE" : @"LIVE CAMERA";
    self.diagnosticLabel.text = [NSString stringWithFormat:@"LOCAL PRACTICE | %@\nFaces %ld | Bright %.0f | Area %.3f\nMotion %.3f | State %ld/4", source, (long)self.faceCount, self.brightness, area, self.motionScore, (long)(self.phase+1)];
}

- (void)showResultWithTitle:(NSString *)title detail:(NSString *)detail success:(BOOL)success {
    self.running = NO;
    [self.displayLink invalidate]; self.displayLink = nil;
    [self.samplePlayer pause];
    self.flashView.alpha = 0;
    UIScreen.mainScreen.brightness = self.savedBrightness;

    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Try again" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self showStartScreen]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { [self showStartScreen]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cancelCheck {
    if (!self.running) { [self showStartScreen]; return; }
    self.running = NO;
    [self.displayLink invalidate]; self.displayLink = nil;
    [self.samplePlayer pause];
    self.flashView.alpha = 0;
    UIScreen.mainScreen.brightness = self.savedBrightness;
    [self showStartScreen];
}

- (void)closeStandaloneApp {
    [self showStartScreen];
}

- (void)toggleDiagnostics { self.diagnosticLabel.hidden = !self.diagnosticLabel.hidden; }

- (void)showInfo {
    NSString *msg = @"Version 2 mirrors the public Amplify UI Face Liveness structure more closely: Liveness Check start view, fixed oval matching, countdown, hold-still prompt, colored-light phase, and verifying state. The app uses Apple Vision only for local framing/lighting diagnostics. It does not call AWS, stream video, run Rekognition anti-spoofing, or produce a genuine biometric result.";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"AWS-style Local Practice" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)stopAllSources {
    self.running = NO;
    [self.displayLink invalidate]; self.displayLink = nil;
    [self.samplePlayer pause];
    AVCaptureSession *s = self.session;
    if (s.isRunning) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [s stopRunning]; });
}

#pragma mark - Frame analysis

- (void)processCurrentSampleVideoFrame {
    if (!self.sampleVideoOutput || !self.samplePlayer.currentItem) return;
    CMTime itemTime = self.samplePlayer.currentTime;
    if (![self.sampleVideoOutput hasNewPixelBufferForItemTime:itemTime]) return;
    CVPixelBufferRef px = [self.sampleVideoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
    if (!px) return;
    [self analyzePixelBuffer:px orientation:kCGImagePropertyOrientationUp];
    CVPixelBufferRelease(px);
}

- (void)analyzePixelBuffer:(CVPixelBufferRef)px orientation:(CGImagePropertyOrientation)orientation {
    if (!px) return;
    CVPixelBufferLockBaseAddress(px, kCVPixelBufferLock_ReadOnly);
    size_t width = CVPixelBufferGetWidth(px), height = CVPixelBufferGetHeight(px), stride = CVPixelBufferGetBytesPerRow(px);
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(px);
    if (base && width && height) {
        size_t stepX = MAX((size_t)1, width/24), stepY = MAX((size_t)1, height/18);
        double sum = 0; size_t count = 0;
        for (size_t y=0; y<height; y+=stepY) {
            uint8_t *row = base + y*stride;
            for (size_t x=0; x<width; x+=stepX) {
                uint8_t *p = row + x*4;
                sum += 0.2126*p[2] + 0.7152*p[1] + 0.0722*p[0]; count++;
            }
        }
        if (count) self.brightness = (CGFloat)(sum/count);
    }
    CVPixelBufferUnlockBaseAddress(px, kCVPixelBufferLock_ReadOnly);

    VNDetectFaceRectanglesRequest *req = [VNDetectFaceRectanglesRequest new];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:px orientation:orientation options:@{}];
    NSError *err = nil; [handler performRequests:@[req] error:&err]; if (err) return;
    NSArray<VNFaceObservation *> *faces = req.results;
    self.faceCount = faces.count;
    if (faces.count == 1) {
        CGRect box = faces.firstObject.boundingBox;
        if (self.hasPreviousFace) {
            CGFloat dx = CGRectGetMidX(box)-CGRectGetMidX(self.previousFaceBox);
            CGFloat dy = CGRectGetMidY(box)-CGRectGetMidY(self.previousFaceBox);
            CGFloat ds = sqrt(pow(box.size.width-self.previousFaceBox.size.width,2)+pow(box.size.height-self.previousFaceBox.size.height,2));
            self.motionScore = (CGFloat)(sqrt(dx*dx+dy*dy)+ds);
        } else self.motionScore = 0;
        self.previousFaceBox = box; self.hasPreviousFace = YES; self.faceBox = box;
    } else {
        self.faceBox = CGRectZero; self.motionScore = 0; self.hasPreviousFace = NO;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef px = CMSampleBufferGetImageBuffer(sampleBuffer); if (!px) return;
    [self analyzePixelBuffer:px orientation:kCGImagePropertyOrientationLeftMirrored];
}

@end
