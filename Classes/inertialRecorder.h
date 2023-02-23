
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 View controller for camera interface
 */


#import <UIKit/UIKit.h>

@interface inertialRecorder : NSObject

- (void)switchRecording;

@property NSURL *fileURL;
@property NSURL *arURL;
@property NSURL *arFrameURL;
@property NSURL *accelURL;
@property NSURL *GPSURL;
@property NSURL *headURL;
@property NSURL *baroURL;

@property BOOL isRecording;

@end


@interface NodeWrapper : NSObject
@property NSTimeInterval time;
@property double x;
@property double y;
@property double z;
@property BOOL isGyro;

- (NSComparisonResult)compare:(NodeWrapper *)otherObject;

@end

NSURL *getFileURL(const NSString *filename);

NSURL *createOutputFolderURL(void);
