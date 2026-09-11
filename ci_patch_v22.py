from pathlib import Path

mk = Path('Makefile')
s = mk.read_text()
s = s.replace('ARCHS = arm64 arm64e', 'ARCHS = arm64')
s = s.replace('ARCHS = arm64e arm64', 'ARCHS = arm64')
mk.write_text(s)

p = Path('Sources/AWSLivenessViewController.m')
s = p.read_text()

# Compile fixes.
s = s.replace('[sourceLabel.leadingAnchor', '[self.sourceLabel.leadingAnchor')
s = s.replace('[sourceLabel.trailingAnchor', '[self.sourceLabel.trailingAnchor')
s = s.replace('[sourceLabel.topAnchor', '[self.sourceLabel.topAnchor')
s = s.replace('sourceLabel.bottomAnchor', 'self.sourceLabel.bottomAnchor')

# Do not request camera at root-controller startup.
s = s.replace('    [self requestCameraAndPrepare];\n    [self showStartScreen];', '    [self showStartScreen];')

old = '''- (void)beginCheck {\n    self.savedBrightness = UIScreen.mainScreen.brightness;'''
new = '''- (void)beginCheck {\n    if (!self.sampleVideoMode && !self.session) {\n        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];\n        if (status == AVAuthorizationStatusNotDetermined) {\n            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {\n                dispatch_async(dispatch_get_main_queue(), ^{\n                    if (granted) { [self prepareCamera]; [self beginCheck]; }\n                    else { [self showResultWithTitle:@\"Camera permission required\" detail:@\"Allow camera access in Settings, or choose a local sample video.\" success:NO]; }\n                });\n            }];\n            return;\n        }\n        if (status != AVAuthorizationStatusAuthorized) {\n            [self showResultWithTitle:@\"Camera permission required\" detail:@\"Allow camera access in Settings, or choose a local sample video.\" success:NO];\n            return;\n        }\n        [self prepareCamera];\n    }\n    self.savedBrightness = UIScreen.mainScreen.brightness;'''
if old in s:
    s = s.replace(old, new, 1)

# Cash-Giraffe-like visual proportions.
s = s.replace('self.promptLabel = [self labelWithText:@"Connecting..." size:18 weight:UIFontWeightSemibold color:UIColor.whiteColor];',
              'self.promptLabel = [self labelWithText:@"Connecting..." size:14 weight:UIFontWeightSemibold color:UIColor.whiteColor];')
s = s.replace('self.promptLabel.backgroundColor = [UIColor colorWithRed:0.02 green:0.47 blue:0.52 alpha:0.93];',
              'self.promptLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.72];')
s = s.replace('[self.promptLabel.topAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.topAnchor constant:62]',
              '[self.promptLabel.topAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.topAnchor constant:116]')
s = s.replace('[self.promptLabel.heightAnchor constraintGreaterThanOrEqualToConstant:38]',
              '[self.promptLabel.heightAnchor constraintGreaterThanOrEqualToConstant:30]')
s = s.replace('self.ovalLayer.lineWidth = 3.5;', 'self.ovalLayer.lineWidth = 2.0;')
s = s.replace('CGFloat w = MIN(CGRectGetWidth(b) * 0.72, 330.0);', 'CGFloat w = MIN(CGRectGetWidth(b) * 0.66, 300.0);')
s = s.replace('CGFloat h = w * 1.30;', 'CGFloat h = w * 1.34;')

# Observed Cash Giraffe sequence with opaque WHITE outside the oval during
# Hold still, colored-light challenge and Verifying.
start = s.find('- (void)tick:(CADisplayLink *)link {')
end = s.find('- (void)showResultWithTitle:', start)
if start < 0 or end < 0:
    raise SystemExit('Could not locate tick/showResult methods')

tick = '''- (void)tick:(CADisplayLink *)link {
    if (!self.running) return;
    if (self.sampleVideoMode) [self processCurrentSampleVideoFrame];

    CFTimeInterval elapsed = CACurrentMediaTime() - self.phaseStart;
    NSString *instruction = [self faceFitInstruction];

    if (self.phase == 0) {
        self.countdownLabel.hidden = YES;
        self.recLabel.text = @"";
        self.flashView.alpha = 0;
        self.dimMaskLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
        [self setPrompt:@"Connecting..." detail:@"" good:NO];
        if (elapsed >= 0.85) [self advanceToPhase:1];
    }
    else if (self.phase == 1) {
        self.countdownLabel.hidden = YES;
        self.flashView.alpha = 0;
        if (instruction) {
            self.dimMaskLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
            [self setPrompt:instruction detail:@"" good:NO];
            self.phaseStart = CACurrentMediaTime();
        } else {
            self.dimMaskLayer.fillColor = UIColor.whiteColor.CGColor;
            self.ovalLayer.strokeColor = [UIColor colorWithWhite:0.82 alpha:1].CGColor;
            [self setPrompt:@"Hold still" detail:@"" good:YES];
            if (elapsed >= 0.70) [self advanceToPhase:2];
        }
    }
    else if (self.phase == 2) {
        self.countdownLabel.hidden = YES;
        self.dimMaskLayer.fillColor = UIColor.whiteColor.CGColor;
        self.ovalLayer.strokeColor = [UIColor colorWithWhite:0.82 alpha:1].CGColor;
        [self setPrompt:@"Hold still" detail:@"" good:YES];
        NSArray<UIColor *> *colors = [self localLightSequence];
        NSInteger idx = MIN((NSInteger)(elapsed / 0.50), (NSInteger)colors.count - 1);
        self.flashView.backgroundColor = colors[idx];
        self.flashView.alpha = 0.56;
        if (elapsed >= 4.0) [self advanceToPhase:3];
    }
    else if (self.phase == 3) {
        self.countdownLabel.hidden = YES;
        self.flashView.alpha = 0;
        self.recLabel.text = @"";
        self.dimMaskLayer.fillColor = UIColor.whiteColor.CGColor;
        self.ovalLayer.strokeColor = [UIColor colorWithWhite:0.82 alpha:1].CGColor;
        [self setPrompt:@"Verifying" detail:@"" good:YES];

        if (elapsed >= 2.75) {
            self.running = NO;
            [self.displayLink invalidate]; self.displayLink = nil;
            [UIView animateWithDuration:0.28 animations:^{
                self.challengeOverlay.alpha = 0.0;
            } completion:^(__unused BOOL finished) {
                self.challengeOverlay.alpha = 1.0;
                self.challengeOverlay.hidden = YES;
                self.startView.hidden = NO;
                [self.samplePlayer pause];
                UIScreen.mainScreen.brightness = self.savedBrightness;
                self.sourceLabel.text = self.sampleVideoMode ? @"Input: Sample video — verification sequence complete" : @"Input: Live front camera — verification sequence complete";
            }];
            return;
        }
    }

    CGFloat area = self.faceBox.size.width * self.faceBox.size.height;
    NSString *source = self.sampleVideoMode ? @"VIDEO SAMPLE" : @"LIVE CAMERA";
    self.diagnosticLabel.text = [NSString stringWithFormat:@"LOCAL PRACTICE | %@\\nFaces %ld | Bright %.0f | Area %.3f\\nMotion %.3f | State %ld/4", source, (long)self.faceCount, self.brightness, area, self.motionScore, (long)(self.phase+1)];
}

'''
s = s[:start] + tick + s[end:]

s = s.replace('Version 2 mirrors the public Amplify UI Face Liveness structure more closely:',
              'Version 2.3 follows the observed Cash Giraffe presentation more closely:')
s = s.replace('Version 2.2 follows the observed Cash Giraffe presentation more closely:',
              'Version 2.3 follows the observed Cash Giraffe presentation more closely:')

p.write_text(s)
print('v2.3 white-mask patch applied')
