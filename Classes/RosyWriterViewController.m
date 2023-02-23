
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 View controller for camera interface
 */

#import "RosyWriterViewController.h"
#import "RosyWriterViewController+Helper.h"


#import "RosyWriterCapturePipeline.h"
#import "OpenGLPixelBufferView.h"

#import <QuartzCore/QuartzCore.h>
#import <MessageUI/MessageUI.h>
#import <ARKit/ARKit.h>
#import <CoreMotion/CoreMotion.h>
#import "inertialRecorder.h"
#import "VideoTimeConverter.h"
#import <Photos/Photos.h> // for PHAsset



@interface RosyWriterViewController () <RosyWriterCapturePipelineDelegate, UIGestureRecognizerDelegate, MFMailComposeViewControllerDelegate,ARSessionDelegate,CLLocationManagerDelegate>
{
	BOOL _addedObservers;
	BOOL _recording;
	UIBackgroundTaskIdentifier _backgroundRecordingID;
	BOOL _allowedToUseGPU;
	
	NSTimer *_labelTimer;
	OpenGLPixelBufferView *_previewView;
	RosyWriterCapturePipeline *_capturePipeline;
    
    // 老位置
        CLLocation *_oldL;
}

@property (weak, nonatomic) IBOutlet UIView *preview;

@property(nonatomic, strong) IBOutlet UIBarButtonItem *recordButton;
@property(nonatomic, strong) IBOutlet UILabel *framerateLabel;
@property(nonatomic, strong) IBOutlet UILabel *dimensionsLabel;
@property (weak, nonatomic) IBOutlet UILabel *exposureDurationLabel;

@property (weak, nonatomic) IBOutlet UILabel *lockAutoLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *exportButton;


@property (strong, nonatomic) AVCaptureDevice *videoCaptureDevice;
@property (strong, nonatomic) CALayer *focusBoxLayer;
@property (strong, nonatomic) CAAnimation *focusBoxAnimation;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;


@property (nonatomic, strong) ARSCNView *scnView;

@property (nonatomic, strong) ARWorldTrackingConfiguration *arConfiguration;

@property (nonatomic, strong) ARSession *arSession;

@property (nonatomic, strong) NSMutableString  *logStringARPose; //arkit
@property (nonatomic, strong) NSMutableString  *logStringFrameStamps;

@property (nonatomic, strong) NSMutableString  *logStringGps;
@property (nonatomic, strong) NSMutableString  *logStringHeading;



@property (nonatomic,copy) NSString *timeStartImu;

@property (nonatomic, strong) inertialRecorder *recorder;

@property (nonatomic, strong) NSURL *recordingURL;

@property (nonatomic, strong) AVAssetWriter *assetWriter;

@property (nonatomic, strong) AVAssetWriterInput *assetWriterInput;

@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *assetWriterInputPixelBufferAdaptor;

@property (nonatomic, assign) NSInteger frameIndex;

@property (nonatomic, strong) CLLocationManager *locationManager;

@property (nonatomic, strong) CALayer *znzLayer;

@end



@implementation RosyWriterViewController

- (void)dealloc
{
	if ( _addedObservers )
	{
		[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:[UIApplication sharedApplication]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:[UIApplication sharedApplication]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
		[[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
	}
}

#pragma mark - View lifecycle

- (void)applicationDidEnterBackground
{
	// Avoid using the GPU in the background
	_allowedToUseGPU = NO;
	_capturePipeline.renderingEnabled = NO;

	[_capturePipeline stopRecording]; // a no-op if we aren't recording
	
	 // We reset the OpenGLPixelBufferView to ensure all resources have been cleared when going to the background.
	[_previewView reset];
}

- (void)applicationWillEnterForeground
{
	_allowedToUseGPU = YES;
	_capturePipeline.renderingEnabled = YES;
}

- (void)viewDidLoad
{
//	_capturePipeline = [[RosyWriterCapturePipeline alloc] initWithDelegate:self callbackQueue:dispatch_get_main_queue()];
//
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector(applicationDidEnterBackground)
//												 name:UIApplicationDidEnterBackgroundNotification
//											   object:[UIApplication sharedApplication]];
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector(applicationWillEnterForeground)
//												 name:UIApplicationWillEnterForegroundNotification
//											   object:[UIApplication sharedApplication]];
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector(deviceOrientationDidChange)
//												 name:UIDeviceOrientationDidChangeNotification
//											   object:[UIDevice currentDevice]];
//
//	// Keep track of changes to the device orientation so we can update the capture pipeline
//	[[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
//
//	_addedObservers = YES;
//
//	// the willEnterForeground and didEnterBackground notifications are subsequently used to update _allowedToUseGPU
//	_allowedToUseGPU = ( [UIApplication sharedApplication].applicationState != UIApplicationStateBackground );
//	_capturePipeline.renderingEnabled = _allowedToUseGPU;
//
//
//    // preview layer
   // CGRect bounds = self.preview.layer.bounds;
    /*
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] init];
    _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _captureVideoPreviewLayer.bounds = bounds;
    _captureVideoPreviewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    // [self.preview.layer addSublayer:_captureVideoPreviewLayer];
    
    // whether preview.layer addSublayer captureVideoPreviewLayer or not,
    // it's observed that self.preview.frame.size == captureVideoPreviewLayer.frame.size
    NSLog(@"previewlayer frame size %.3f %.3f super preview size %.3f %.3f", _captureVideoPreviewLayer.frame.size.width, _captureVideoPreviewLayer.frame.size.height,
          self.preview.frame.size.width, self.preview.frame.size.height);
    
    AVCaptureDevicePosition devicePosition = AVCaptureDevicePositionBack;
    if(devicePosition == AVCaptureDevicePositionUnspecified) {
        self.videoCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    } else {
        self.videoCaptureDevice = [self cameraWithPosition:devicePosition];
    }
    */
    
    // see https://stackoverflow.com/questions/11355671/how-do-i-implement-the-uitapgesturerecognizer-into-my-application
    // tap to lock auto focus and auto exposure
    _tapToFocus = YES;
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapFrom:)];
    tapGestureRecognizer.numberOfTouchesRequired = 1;
    tapGestureRecognizer.numberOfTapsRequired = 1;
    [self.preview addGestureRecognizer:tapGestureRecognizer];
    tapGestureRecognizer.delegate = self;
    [self addDefaultFocusBox]; // add focus box to view
    
    // long press to unlock auto focus and auto exposure
    UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressFrom:)];
    longPressGestureRecognizer.minimumPressDuration = 0.5;
    [self.preview addGestureRecognizer:longPressGestureRecognizer];
    longPressGestureRecognizer.delegate = self;
    
    [super viewDidLoad];
    
    [self createARKitCamera];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    
}

- (void)createARKitCamera {
    

    _recorder = [[inertialRecorder alloc] init];
   // NSLog(@"width = %lf --%lf",self.view.frame.size.width,self.view.frame.size.height);
  
    [self.view.layer addSublayer:self.scnView.layer];
    self.arSession.delegate = self;
    [self.scnView.session runWithConfiguration:self.arConfiguration];
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.distanceFilter =  kCLDistanceFilterNone;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.headingOrientation = CLDeviceOrientationPortrait;
    self.locationManager.headingFilter = kCLHeadingFilterNone;
    
    if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];
    }
 
    
    _znzLayer = [[CALayer alloc] init];
            
    NSInteger screenHeight = [UIScreen mainScreen].bounds.size.height;
            
    NSInteger y = (screenHeight - 320) / 2;
            
    _znzLayer.frame = CGRectMake(0 , y+200 , 320, 320);
            // 设置znzLayer显示的图片
            
    _znzLayer.contents = (id)[[UIImage imageNamed:@"CoverPlaceholder.png"] CGImage];
            // 将znzLayer添加到系统的UIView中
            
    [self.view.layer addSublayer:_znzLayer];
   
    
    self.logStringGps = [@"Timestamp,currLatitude,currLongitude\r\n" mutableCopy];
    self.logStringHeading = [@"Timestamp,trueHeading,magneticHeading,headingAccuracy\r\n" mutableCopy];
   
    self.logStringARPose = [@"Timestamp,tx,ty,tz,qx,qy,qz,qw\r\n" mutableCopy];
    self.logStringFrameStamps = [@"Timestamp,tx,ty,tz,qx,qy,qz,qw\r\n" mutableCopy];
    
    
}

- (void)createOutputFolderURL
{
   
    
    NSURL *outputFolderURL = createOutputFolderURL();
    _recordingURL = [outputFolderURL URLByAppendingPathComponent:@"movie.mp4" isDirectory:NO];
    
  // _recordingURL =  [[NSURL alloc] initFileURLWithPath:[NSString pathWithComponents:@[NSTemporaryDirectory(), @"Movie.MP4"]]];
    
    NSURL *inertialFileURL = [outputFolderURL URLByAppendingPathComponent:@"gyro_accel.csv" isDirectory:NO];
    NSURL *arURL = [outputFolderURL URLByAppendingPathComponent:@"pose.csv" isDirectory:NO];
    NSURL *arFrameURL = [outputFolderURL URLByAppendingPathComponent:@"frames.csv" isDirectory:NO];
    NSURL *Accel = [outputFolderURL URLByAppendingPathComponent:@"accel.csv" isDirectory:NO];
    NSURL *GPSURL =  [outputFolderURL URLByAppendingPathComponent:@"gps.csv" isDirectory:NO];
    NSURL *headURL =  [outputFolderURL URLByAppendingPathComponent:@"head.csv" isDirectory:NO];
    NSURL *baroURL =  [outputFolderURL URLByAppendingPathComponent:@"baro.csv" isDirectory:NO];
    [_recorder setFileURL:inertialFileURL];
    [_recorder setArURL:arURL];
    [_recorder setArFrameURL:arFrameURL];
    [_recorder setAccelURL:Accel];
    [_recorder setGPSURL:GPSURL];
    [_recorder setHeadURL:headURL];
    [_recorder setBaroURL:baroURL];
    
}


- (ARSCNView *)scnView
{
    if (!_scnView) {
        _scnView = [[ARSCNView alloc] init];
        _scnView.frame = CGRectMake(0, 100, self.view.frame.size.width, self.view.frame.size.height-150);
        _scnView.session.delegate = self;
    }
    return _scnView;
}

- (ARSession *)arSession
{
    if (!_arSession) {
        _arSession = [[ARSession alloc] init];
        
    }
    return _arSession;
}

- (ARWorldTrackingConfiguration *)arConfiguration
{
    if (!_arConfiguration) {
        _arConfiguration = [[ARWorldTrackingConfiguration alloc] init];
        _arConfiguration.worldAlignment = ARWorldAlignmentGravity;
        _arConfiguration.lightEstimationEnabled = NO;//关闭环境光
        _arConfiguration.autoFocusEnabled = NO;//关闭自动对焦
       
        //获取深度信息
        if (@available(iOS 14.0, *)) {
            if ([ARWorldTrackingConfiguration supportsFrameSemantics:ARFrameSemanticSceneDepth]) {
                _arConfiguration.frameSemantics = ARFrameSemanticSceneDepth;
            }
        }
    }
    return _arConfiguration;
}


#pragma mark - ARSessionDelegate
- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame
{
    
    matrix_float3x3 intrinsics = frame.camera.intrinsics;
    CVPixelBufferRef pixelBuffer = frame.capturedImage;
    NSTimeInterval timestamp = frame.timestamp;
    //CMSampleBufferRef
   // CMTime frameTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
   
    [self processImagePixelBuffer:pixelBuffer
                        timestamp:timestamp
                       intrinsics:&intrinsics
                          arFrame:frame];//保存AR
    

   
    
}
#pragma mark --保存AR
- (void)processImagePixelBuffer:(CVPixelBufferRef)pixelBuffer
                      timestamp:(NSTimeInterval)timestamp
                     intrinsics:(matrix_float3x3 *)intrinsics
                        arFrame:(ARFrame *)frame {
    
    
    if (_recording&&_assetWriter==nil) {
        NSError *error = nil;
        NSURL *outputURL = _recordingURL;
       // NSLog(@"~~~~~~~~开始写AR数据到本地~~~~~~%@",outputURL);
        self.assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeMPEG4 error:&error];
        if (!self.assetWriter) {
           // [self alertMessage:[NSString stringWithFormat:@"assetWriter: %@", error]];
            NSLog(@"assetWriter: %@", error);
            return;
        }
        //---
        NSDictionary *writerInputParams = @{
            AVVideoCodecKey :AVVideoCodecTypeHEVC,
            AVVideoWidthKey: @((int)CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)),
            AVVideoHeightKey: @((int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)),
            AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
        };
        
        NSLog(@"~~~~~~~~开始写AR数据到本地~~~~~~%@",writerInputParams);
        
        self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:writerInputParams];
       
        //ARKit画面需要旋转90°
        self.assetWriterInput.transform = CGAffineTransformMakeRotation(M_PI / 2.0);
        
        if ([self.assetWriter canAddInput:self.assetWriterInput]) {
            [self.assetWriter addInput:self.assetWriterInput];
        } else {
            //[self alertMessage:[NSString stringWithFormat:@"assetWriter can't AddInput: %@", self.assetWriter.error]];
        }
        //---
        self.assetWriterInputPixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.assetWriterInput sourcePixelBufferAttributes:nil];
        //---
        [self.assetWriter startWriting];
        [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
    }
    
    
    if (!self.assetWriterInput.isReadyForMoreMediaData) {
        //NSLog(@"assetWriterInput.isReadyForMoreMediaData = NO!");
        return;
    }
    if (![self.assetWriterInputPixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(self.frameIndex, 30)]&&_recording) {
        NSLog(@"assetWriterInput cant appendPixelBuffer!");
        
        return;
    }
    
    else{
        double msDate =  timestamp;
        simd_float4x4 transform = frame.camera.transform;
        simd_quatf quaternion = simd_quaternion(transform);
       
        [self.logStringARPose appendString: [NSString stringWithFormat:@"%@,%f,%f,%f,%f,%f,%f,%f\r\n",
                                             secDoubleToNanoString(msDate),
                                             transform.columns[3][0],
                                             transform.columns[3][1],
                                             transform.columns[3][2],
                                             quaternion.vector[3],
                                             quaternion.vector[0],
                                             quaternion.vector[1],
                                             quaternion.vector[2]
                                        ]];
        
       
        
        if(intrinsics!=nil){
            [self.logStringFrameStamps appendString:[NSString stringWithFormat:@"%@,%f,%f,%f,%f\r\n",
                                                     secDoubleToNanoString(msDate),
                                                 intrinsics->columns[0][0],
                                                 intrinsics->columns[1][1],
                                                 intrinsics->columns[2][0],
                                                 intrinsics->columns[2][1]]];
        }
        else{
            [self.logStringFrameStamps appendString: [NSString stringWithFormat:@"%@\r\n",
                                                      secDoubleToNanoString(msDate)
                                                  ]];
        }
        
        self.frameIndex += 1;
    }
    
}




// Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition) position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) return device;
    }
    return nil;
}


- (void)showFocusBox:(CGPoint)point
{
    if(self.focusBoxLayer) {
        [self.focusBoxLayer removeAllAnimations];
        
        [CATransaction begin];
        [CATransaction setValue: (id) kCFBooleanTrue forKey: kCATransactionDisableActions];
        self.focusBoxLayer.position = point;
        [CATransaction commit];
    }
    
    if(self.focusBoxAnimation) {
        [self.focusBoxLayer addAnimation:self.focusBoxAnimation forKey:@"animateOpacity"];
    }
}

- (void)alterFocusBox:(CALayer *)layer animation:(CAAnimation *)animation
{
    self.focusBoxLayer = layer;
    self.focusBoxAnimation = animation;
}


- (void)addDefaultFocusBox
{
    CALayer *focusBox = [[CALayer alloc] init];
    focusBox.cornerRadius = 5.0f;
    focusBox.bounds = CGRectMake(0.0f, 0.0f, 70, 60);
    focusBox.borderWidth = 3.0f;
    focusBox.borderColor = [[UIColor yellowColor] CGColor];
    focusBox.opacity = 0.0f;
    [self.view.layer addSublayer:focusBox];
    
    CABasicAnimation *focusBoxAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    focusBoxAnimation.duration = 0.75;
    focusBoxAnimation.autoreverses = NO;
    focusBoxAnimation.repeatCount = 0.0;
    focusBoxAnimation.fromValue = [NSNumber numberWithFloat:1.0];
    focusBoxAnimation.toValue = [NSNumber numberWithFloat:0.0];
    if (_capturePipeline.autoLocked) {
        [self.lockAutoLabel setText:@"AE/AF locked"];
        [self.lockAutoLabel setHidden:FALSE];
    } else {
        [self.lockAutoLabel setText:@"AE/AF"];
        [self.lockAutoLabel setHidden:FALSE];
    }
    [self alterFocusBox:focusBox animation:focusBoxAnimation];
}


- (void) handleTapFrom: (UITapGestureRecognizer *)gestureRecognizer
{
    if(!self.tapToFocus) {
        return;
    }
    
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        CGPoint touchedPoint = [gestureRecognizer locationInView:gestureRecognizer.view];
        
        CGPoint pointOfInterest = [self convertToPointOfInterestFromViewCoordinates:touchedPoint                                                                   previewLayer:self.captureVideoPreviewLayer                                                                 ports:_capturePipeline.videoDeviceInput.ports];
        [_capturePipeline focusAtPoint:pointOfInterest];
        if (_capturePipeline.autoLocked) {
            [self.lockAutoLabel setText:@"AE/AF locked"];
            [self.lockAutoLabel setHidden:FALSE];
            [self showFocusBox:touchedPoint];
        } else {
            [self.lockAutoLabel setText:@"AE/AF"];
            [self.lockAutoLabel setHidden:FALSE];
        }
    }
}

- (void) handleLongPressFrom: (UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [_capturePipeline unlockFocusAndExposure];
        if (_capturePipeline.autoLocked) {
            [self.lockAutoLabel setText:@"AE/AF locked"];
            [self.lockAutoLabel setHidden:FALSE];
        } else {
            [self.lockAutoLabel setText:@"AE/AF"];
            [self.lockAutoLabel setHidden:FALSE];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	[_capturePipeline startRunning];
	
	_labelTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateLabels) userInfo:nil repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	
	[_labelTimer invalidate];
	_labelTimer = nil;
	
	[_capturePipeline stopRunning];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}


#pragma mark - UI

- (IBAction)toggleRecording:(UIButton *)sender
{
    sender.selected = !sender.selected;
    if (sender.selected) {
       
        self.frameIndex = -1;
        [self createOutputFolderURL];
        self.recordButton.title = @"Stop";
        [self.locationManager startUpdatingLocation]; //开始更新位置
        if ([CLLocationManager headingAvailable]) {
            [self.locationManager startUpdatingHeading];
        }
        _recording = YES;
        NSLog(@"开始录制");
        //[self.recorder switchRecording];
    }
    else{
        
        //[self.arSession ]
        self.recordButton.title = @"Record";
        [self.locationManager stopUpdatingLocation];//停止更新位置
        if ([CLLocationManager headingAvailable]) {
            [self.locationManager stopUpdatingHeading];
        }
        _recording = NO;
        NSLog(@"结束录制");
        [self.assetWriterInput markAsFinished];
        [self.assetWriter finishWritingWithCompletionHandler:^{
            if (self.assetWriter.error) {
                NSLog(@"%@",self.assetWriter.error);
               // [self alertMessage:[NSString stringWithFormat:@"assetWriter: %@", self.assetWriter.error]];
                return;
            }
            // outputURL
        }];
        
        NSData *settingsData = [self.logStringARPose dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];
       
        NSData *arFrameData = [self.logStringFrameStamps dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];
        
        NSData *gpsData = [self.logStringGps dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];
        
        NSData *headData = [self.logStringHeading dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];
        
       
        
        if ([settingsData writeToURL:self.recorder.arURL atomically:YES]) {
            NSLog(@"Written inertial data to %@", self.recorder.arURL);
        }
        if ([arFrameData writeToURL:self.recorder.arFrameURL atomically:YES]) {
            NSLog(@"Written inertial data to %@", self.recorder.arFrameURL);
        }
        
        if ([gpsData writeToURL:self.recorder.GPSURL atomically:YES]) {
            NSLog(@"Written inertial data to %@", self.recorder.GPSURL);
        }
        
        if ([headData writeToURL:self.recorder.headURL atomically:YES]) {
            NSLog(@"Written inertial data to %@", self.recorder.headURL);
        }
        
        
        self.logStringARPose = [@"Timestamp,tx,ty,tz,qx,qy,qz,qw\r\n" mutableCopy];
        self.logStringFrameStamps = [@"Timestamp,tx,ty,tz,qx,qy,qz,qw\r\n" mutableCopy];
        self.logStringGps = [@"Timestamp,currLatitude,currLongitude,currHorAccur,currAltitude,currVertAccur,currFloor,currCource,currSpeed\r\n" mutableCopy];
        self.logStringHeading = [@"Timestamp,trueHeading,magneticHeading,headingAccuracy\r\n" mutableCopy];
        
        
        self.assetWriter = nil;
        self.assetWriterInput = nil;
        self.assetWriterInputPixelBufferAdaptor = nil;
        
        
        
        [self requestAuthorizationWithRedirectionToSettings];
        
        
        
    }
    [self.recorder switchRecording];
    
    
//	if ( _recording )
//	{
//        _recording = NO;
//        self.recordButton.title = @"Record";
//		[_capturePipeline stopRecording];
//	}
//	else
//	{
//		// Disable the idle timer while recording
//		[UIApplication sharedApplication].idleTimerDisabled = YES;
//
//		// Make sure we have time to finish saving the movie if the app is backgrounded during recording
//		if ( [[UIDevice currentDevice] isMultitaskingSupported] ) {
//			_backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
//		}
//
//		self.recordButton.enabled = NO; // re-enabled once recording has finished starting
//		self.recordButton.title = @"Stop";
//
//		[_capturePipeline startRecording];
//
//		_recording = YES;
//	}
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    CLLocation *location = [locations lastObject];
   // NSLog(@"location==%@",location);
    if (location!=nil) {
        double currLatitude = location.coordinate.latitude;
        double currLongitude = location.coordinate.longitude;
//        double currHorAccur = location.horizontalAccuracy;
//        double currAltitude = location.altitude;
//        double currVertAccur = location.verticalAccuracy;
//        long currFloor = location.floor.level;
//        double currCource = location.course;
//        double currSpeed = location.speed;
        double msDate = [location.timestamp timeIntervalSince1970];
        [self.logStringGps appendString: [NSString stringWithFormat:@"%@,%f,%f\r\n",
                                          secDoubleToNanoString(msDate),
                                          currLatitude,
                                          currLongitude
//                                          currHorAccur,
//                                          currAltitude,
//                                          currVertAccur,
//                                          currFloor,
//                                          currCource,
//                                          currSpeed
                                         ]];
    }
   
    
    
}
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
    //NSLog(@"CLHeading===%@",newHeading);
    if (newHeading !=nil) {
       // NSLog(@"%@",newHeading.magneticHeading);
        
          // 将设备的方向角度换算成弧度
            CGFloat headings = -1.0f * M_PI * newHeading.magneticHeading / 180.0f;
            // 创建不断改变CALayer的transform属性的属性动画
            CABasicAnimation* anim = [CABasicAnimation
                animationWithKeyPath:@"transform"];
            CATransform3D fromValue = _znzLayer.transform;
            // 设置动画开始的属性值
            anim.fromValue = [NSValue valueWithCATransform3D: fromValue];
            // 绕Z轴旋转heading弧度的变换矩阵
            CATransform3D toValue = CATransform3DMakeRotation(headings , 0 , 0 , 1);
            // 设置动画结束的属性
            anim.toValue = [NSValue valueWithCATransform3D: toValue];
            anim.duration = 0.5;
            anim.removedOnCompletion = YES;
            // 设置动画结束后znzLayer的变换矩阵
            _znzLayer.transform = toValue;
            // 为znzLayer添加动画
            [_znzLayer addAnimation:anim forKey:nil];
        
        
        double currTrueHeading = newHeading.trueHeading;
        double currMagneticHeading = newHeading.magneticHeading;
        double currHeadingAccuracy = newHeading.headingAccuracy;
        double msDate = [newHeading.timestamp timeIntervalSince1970];
        [self.logStringHeading appendString: [NSString stringWithFormat:@"%@,%f,%f,%f\r\n",
                                              secDoubleToNanoString(msDate),
                                              currTrueHeading,
                                              currMagneticHeading,
                                              currHeadingAccuracy]];
    }
    
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {

    NSLog(@"位置调用失败==%@",error);
    
}
    


- (void)requestAuthorizationWithRedirectionToSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusAuthorized) {
            [self saveVideoToAlbum];
        } else {
            //No permission. Trying to normally request it
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status != PHAuthorizationStatusAuthorized)
                {
                    //User don't give us permission. Showing alert with redirection to settings
                    //Getting description string from info.plist file
                    NSString *accessDescription = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPhotoLibraryUsageDescription"];
                    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:accessDescription message:@"To give permissions tap on 'Change Settings' button" preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];

                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"Change Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                    }];
                    [alertController addAction:settingsAction];

                    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
                }
            }];
        }
    });
}

- (void)saveVideoToAlbum {
    // Save to the album, see
    // https://stackoverflow.com/questions/33500266/how-to-use-phphotolibrary-like-alassetslibrary
    __block PHObjectPlaceholder *placeholder;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest* createAssetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:_recordingURL];
        placeholder = [createAssetRequest placeholderForCreatedAsset];
    } completionHandler:^(BOOL success, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtURL:self.recordingURL error:NULL];
        
        if (success) {
            NSLog(@"didFinishRecordingToOutputFileAtURL - success!");
        } else {
            NSLog(@"保存到相册%@", error);
        }
    }];
}





- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    switch (result) {
        case MFMailComposeResultSent:
            NSLog(@"Email sent");
            break;
        case MFMailComposeResultSaved:
            NSLog(@"Email saved");
            break;
        case MFMailComposeResultCancelled:
            NSLog(@"Email cancelled");
            break;
        case MFMailComposeResultFailed:
            NSLog(@"Email failed");
            break;
        default:
            NSLog(@"Error occured during email creation");
            break;
    }
    
    [self dismissViewControllerAnimated:YES completion:NULL];
}

// see https://stackoverflow.com/questions/43581351/how-to-give-toast-message-in-objective-c
- (void)showAlert:(NSString *)Message {
    UIAlertController * alert=[UIAlertController alertControllerWithTitle:nil
                                                                  message:@""
                                                           preferredStyle:UIAlertControllerStyleAlert];
    UIView *firstSubview = alert.view.subviews.firstObject;
    UIView *alertContentView = firstSubview.subviews.firstObject;
    for (UIView *subSubView in alertContentView.subviews) {
        subSubView.backgroundColor = [UIColor colorWithRed:141/255.0f green:0/255.0f blue:254/255.0f alpha:1.0f];
    }
    NSMutableAttributedString *AS = [[NSMutableAttributedString alloc] initWithString:Message];
    [AS addAttribute: NSForegroundColorAttributeName value: [UIColor whiteColor] range: NSMakeRange(0,AS.length)];
    [alert setValue:AS forKey:@"attributedTitle"];
    [self presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:^{
        }];
    });
}

- (IBAction)exportButtonPressed:(id)sender {
    
    NSURL *videoMetadataFile = _capturePipeline.metadataFileURL;
    NSURL *inertialDataFile = [_capturePipeline getInertialFileURL];
    
    if ( videoMetadataFile == nil || inertialDataFile == nil) {
        NSLog(@"Video metadata file is %@ and inertial data file %@, so no export will be done!", videoMetadataFile, inertialDataFile);
        return;
    }
    if ( _recording == YES) {
        NSLog(@"In recording state no export will be done!");
        return;
    }
    if ([MFMailComposeViewController canSendMail])
    {
        MFMailComposeViewController *mailVC = [[MFMailComposeViewController alloc] init];
        mailVC.mailComposeDelegate = self;
        NSURL *outputURL = [videoMetadataFile URLByDeletingLastPathComponent];
        NSString *outputBasename = [outputURL lastPathComponent];
        [mailVC setSubject:outputBasename];
        NSString *message = [NSString stringWithFormat:
                             @"The attached metadata of camera frames and inertial data "
                             "were captured by the MARS logger starting from %@!\n"
                             "The associated video was the most recent one found with "
                             "the Photos App at the time of sending this email.", outputBasename];
        [mailVC setMessageBody:message isHTML:NO];
//        [mailVC setToRecipients:@[@"recipient@gmail.com"]];
        NSData *metaData = [NSData dataWithContentsOfURL:videoMetadataFile];
       
        NSString *videoBasename = [videoMetadataFile lastPathComponent];
        [mailVC addAttachmentData: metaData mimeType:@"text/csv" fileName:videoBasename];
        
        NSData *inertialData = [NSData dataWithContentsOfURL:inertialDataFile];
        NSString *inertialBasename = [inertialDataFile lastPathComponent];

        [mailVC addAttachmentData: inertialData mimeType:@"text/csv" fileName:inertialBasename];
        [self presentViewController:mailVC animated:YES completion:NULL];
    }
    else
    {
        [self showAlert:@"This device cannot send email. Have you setup the mailbox?"];
    }
}

- (void)recordingStopped
{
	_recording = NO;
	self.recordButton.enabled = YES;
	self.recordButton.title = @"Record";
	
	[UIApplication sharedApplication].idleTimerDisabled = NO;
	
	[[UIApplication sharedApplication] endBackgroundTask:_backgroundRecordingID];
	_backgroundRecordingID = UIBackgroundTaskInvalid;
}

- (void)setupPreviewView
{
	// Set up GL view
	_previewView = [[OpenGLPixelBufferView alloc] initWithFrame:CGRectZero];
	_previewView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	
	UIInterfaceOrientation currentInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
	_previewView.transform = [_capturePipeline transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)currentInterfaceOrientation withAutoMirroring:YES]; // Front camera preview should be mirrored

	[self.view insertSubview:_previewView atIndex:0];
	CGRect bounds = CGRectZero;
	bounds.size = [self.view convertRect:self.view.bounds toView:_previewView].size;
	_previewView.bounds = bounds;
	_previewView.center = CGPointMake( self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0 );
}

- (void)deviceOrientationDidChange
{
	UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
	
	// Update the recording orientation if the device changes to portrait or landscape orientation (but not face up/down)
	if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) )
	{
		_capturePipeline.recordingOrientation = (AVCaptureVideoOrientation)deviceOrientation;
	}
}

- (void)updateLabels
{	
	NSString *frameRateString = [NSString stringWithFormat:@"%.1f FPS %.2f",  _capturePipeline.videoFrameRate, _capturePipeline.fx];
	self.framerateLabel.text = frameRateString;
	
	NSString *dimensionsString = [NSString stringWithFormat:@"%d x %d", _capturePipeline.videoDimensions.width, _capturePipeline.videoDimensions.height];
	self.dimensionsLabel.text = dimensionsString;
    
    NSString *exposureDurationString = [NSString stringWithFormat:@"%.2f ms", _capturePipeline.exposureDuration / 1000000.0];
    self.exposureDurationLabel.text = exposureDurationString;
}

- (void)showError:(NSError *)error
{
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:error.localizedDescription
														message:error.localizedFailureReason
													   delegate:nil
											  cancelButtonTitle:@"OK"
											  otherButtonTitles:nil];
	[alertView show];
}

#pragma mark - RosyWriterCapturePipelineDelegate

- (void)capturePipeline:(RosyWriterCapturePipeline *)capturePipeline didStopRunningWithError:(NSError *)error
{
	[self showError:error];
	
	self.recordButton.enabled = NO;
}

// Preview
- (void)capturePipeline:(RosyWriterCapturePipeline *)capturePipeline previewPixelBufferReadyForDisplay:(CVPixelBufferRef)previewPixelBuffer
{
	if ( ! _allowedToUseGPU ) {
		return;
	}
	
	if ( ! _previewView ) {
		[self setupPreviewView];
	}
	
	[_previewView displayPixelBuffer:previewPixelBuffer];
}

- (void)capturePipelineDidRunOutOfPreviewBuffers:(RosyWriterCapturePipeline *)capturePipeline
{
	if ( _allowedToUseGPU ) {
		[_previewView flushPixelBufferCache];
	}
}

// Recording
- (void)capturePipelineRecordingDidStart:(RosyWriterCapturePipeline *)capturePipeline
{
	self.recordButton.enabled = YES;
}

- (void)capturePipelineRecordingWillStop:(RosyWriterCapturePipeline *)capturePipeline
{
	// Disable record button until we are ready to start another recording
	self.recordButton.enabled = NO;
	self.recordButton.title = @"Record";
}

- (void)capturePipelineRecordingDidStop:(RosyWriterCapturePipeline *)capturePipeline
{
	[self recordingStopped];
}

- (void)capturePipeline:(RosyWriterCapturePipeline *)capturePipeline recordingDidFailWithError:(NSError *)error
{
	[self recordingStopped];
	[self showError:error];
}

@end
