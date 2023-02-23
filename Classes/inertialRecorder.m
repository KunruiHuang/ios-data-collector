
#import "inertialRecorder.h"
#import <CoreMotion/CoreMotion.h>
#import "VideoTimeConverter.h"

const double GRAVITY = 9.80; // see https://developer.apple.com/documentation/coremotion/getting_raw_accelerometer_events
const double RATE = 100; // fps for inertial data

@interface inertialRecorder ()
{
    
}
@property CMMotionManager *motionManager;
@property(nonatomic,strong) CMAltimeter *altimeter;//气压计
@property NSOperationQueue *queue;
@property NSTimer *timer;

@property NSMutableArray *rawAccelGyroData;

@property NSMutableString  *logStringAccel;

@property NSMutableString  *logStringbaro;


@property BOOL interpolateAccel; // interpolate accelerometer data at gyro timestamps?
@property NSString *timeStartImu;

@end

@implementation inertialRecorder

- (instancetype)init {
    self = [super init];
    if ( self )
    {
        _isRecording = false;
        _motionManager = [[CMMotionManager alloc] init];
        if (!_motionManager.isDeviceMotionAvailable) {
            NSLog(@"Device does not support motion capture."); }
        _fileURL = nil;
        _interpolateAccel = TRUE;

    }
    return self;
}

- (NSMutableArray *) removeDuplicates:(NSArray *)array {
    // see https://stackoverflow.com/questions/1025674/the-best-way-to-remove-duplicate-values-from-nsmutablearray-in-objective-c
    NSMutableArray *mutableArray = [array mutableCopy];
    NSInteger index = [array count] - 1;
    for (id object in [array reverseObjectEnumerator]) {
        if ([mutableArray indexOfObject:object inRange:NSMakeRange(0, index)] != NSNotFound) {
            [mutableArray removeObjectAtIndex:index];
        }
        index--;
    }
    return mutableArray;
}

- (NSMutableString*)interpolate:(NSMutableArray*) accelGyroData startTime:(NSString *) startTime {
    
    NSMutableArray *gyroArray = [[NSMutableArray alloc] init];
    NSMutableArray *accelArray = [[NSMutableArray alloc] init];
    
    for (int i=0;i<[accelGyroData count];i++) {
        NodeWrapper *nw =[accelGyroData objectAtIndex:i];
        if (nw.time <= 0)
            continue;
        if (nw.isGyro)
            [gyroArray addObject:nw];
        else
            [accelArray addObject:nw];
    }
    
    NSArray *sortedArrayGyro = [gyroArray sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sortedArrayAccel = [accelArray sortedArrayUsingSelector:@selector(compare:)];
    
    NSMutableArray *mutableGyroCopy = [self removeDuplicates:sortedArrayGyro];
    NSMutableArray *mutableAccelCopy = [self removeDuplicates:sortedArrayAccel];
    
    // interpolate
    NSMutableString *mainString = [[NSMutableString alloc]initWithString:@""];
    int accelIndex = 0;
    [mainString appendFormat:@"Timestamp[nanosec], gx[rad/s], gy[rad/s], gz[rad/s], ax[m/s^2], ay[m/s^2], az[m/s^2]\n"];
    for (int gyroIndex = 0; gyroIndex < [mutableGyroCopy count]; ++gyroIndex) {
        NodeWrapper *nwg = [mutableGyroCopy objectAtIndex:gyroIndex];
        NodeWrapper *nwa = [mutableAccelCopy objectAtIndex:accelIndex];
        if (nwg.time < nwa.time) {
            continue;
        } else if (nwg.time == nwa.time) {
            [mainString appendFormat:@"%@, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f\n", secDoubleToNanoString(nwg.time), nwg.x, nwg.y, nwg.z, nwa.x, nwa.y, nwa.z];
        } else {
            int lowerIndex = accelIndex;
            int upperIndex = accelIndex + 1;
            for (int iterIndex = accelIndex + 1; iterIndex < [mutableAccelCopy count]; ++iterIndex) {
                NodeWrapper *nwa1 = [mutableAccelCopy objectAtIndex:iterIndex];
                if (nwa1.time < nwg.time) {
                    lowerIndex = iterIndex;
                } else if (nwa1.time > nwg.time) {
                    upperIndex = iterIndex;
                    break;
                } else {
                    lowerIndex = iterIndex;
                    upperIndex = iterIndex;
                    break;
                }
            }
            
            if (upperIndex >= [mutableAccelCopy count])
                break;
            
            if (upperIndex == lowerIndex) {
                NodeWrapper *nwa1 = [mutableAccelCopy objectAtIndex:upperIndex];
                [mainString appendFormat:@"%@, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f\n", secDoubleToNanoString(nwg.time), nwg.x, nwg.y, nwg.z, nwa1.x, nwa1.y, nwa1.z];
            } else if (upperIndex == lowerIndex + 1) {
                //存储的是gyro_accel.cvs 文件
                NodeWrapper *nwa = [mutableAccelCopy objectAtIndex:lowerIndex];
                NodeWrapper *nwa1 = [mutableAccelCopy objectAtIndex:upperIndex];
                double ratio = (nwg.time - nwa.time) / (nwa1.time - nwa.time);
                double interpax = nwa.x + (nwa1.x - nwa.x) * ratio;
                double interpay = nwa.y + (nwa1.y - nwa.y) * ratio;
                double interpaz = nwa.z + (nwa1.z - nwa.z) * ratio;
                [mainString appendFormat:@"%@, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f\n", secDoubleToNanoString(nwg.time), nwg.x, nwg.y, nwg.z, interpax, interpay, interpaz];
            } else {
                NSLog(@"Impossible lower and upper bound %d %d for gyro timestamp %.5f", lowerIndex, upperIndex, nwg.time);
            }
            accelIndex = lowerIndex;
        }
    }
    if ([gyroArray count])
        [gyroArray removeAllObjects];
    if ([accelArray count])
        [accelArray removeAllObjects];
    return mainString;
}

- (void)switchRecording {
    if (_isRecording) {
        
        _isRecording = false;
        [_motionManager stopGyroUpdates];
        [_motionManager stopAccelerometerUpdates];
        if (self.altimeter) {
            [self.altimeter stopRelativeAltitudeUpdates];//停止气压值
            self.altimeter = nil;
        }
        NSMutableString *mainString = [[NSMutableString alloc]initWithString:@""];
        if (!_interpolateAccel) {
            [mainString appendFormat:@"Timestamp[nanosec], x, y, z[(a:m/s^2)/(g:rad/s)], isGyro?\n"];
            for(int i=0;i<[_rawAccelGyroData count];i++ ) {
                NodeWrapper *nw =[_rawAccelGyroData objectAtIndex:i];
                [mainString appendFormat:@"%.7f, %.5f, %.5f, %.5f, %d\n", nw.time, nw.x, nw.y, nw.z, nw.isGyro];
            }
        } else { // linearly interpolate acceleration offline
            // TODO(jhuai): Though offline interpolation is enough for practical needs,
            // eg., 20 min recording, online interpolation may be still desirable.
            // It can be implemented referring to Vins Mobile and MarsLogger Android.
            mainString = [self interpolate:_rawAccelGyroData startTime:_timeStartImu];
        }
        if ([_rawAccelGyroData count])
            [_rawAccelGyroData removeAllObjects];

        NSData *settingsData;
        settingsData = [mainString dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];
        
        NSData *logStringAccelData = [_logStringAccel dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];//磁力计写到本地
      
        if (_logStringbaro.length>=1) {
           
            NSData *logStringbaroData = [_logStringbaro dataUsingEncoding: NSUTF8StringEncoding allowLossyConversion:false];//气压计写入到本地
            if ([logStringbaroData writeToURL:_baroURL atomically:YES]) {
                NSLog(@"Written inertial data to %@", _baroURL);
             }
            _logStringbaro = [@"" mutableCopy];
        }
       
        if ([logStringAccelData writeToURL:_accelURL atomically:YES]) {
            NSLog(@"Written inertial data to %@", _accelURL);
        }
        
        if ([settingsData writeToURL:_fileURL atomically:YES]) {
            NSLog(@"Written inertial data to %@", _fileURL);
        }
        else {
            NSLog(@"Failed to record inertial data at %@", _fileURL);
        }
        
        NSLog(@"Stopped recording inertial data!");
    } else {
        _isRecording = true;
        
        NSLog(@"Start recording inertial data!");
        _rawAccelGyroData = [[NSMutableArray alloc] init];
        _motionManager.gyroUpdateInterval = 1/RATE;
        _motionManager.accelerometerUpdateInterval = 1/RATE;
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"EEE_MM_dd_yyyy_HH_mm_ss"];
        _timeStartImu = [dateFormatter stringFromDate:[NSDate date]];
        _logStringAccel = [@"Timestamp,x,y,z\r\n" mutableCopy];
        
        
        if (_motionManager.gyroAvailable && _motionManager.accelerometerAvailable) {
//            _queue = [NSOperationQueue currentQueue]; // mainQueue, run on main UI thread
            _queue = [[NSOperationQueue alloc] init]; // background thread
            [_motionManager startGyroUpdatesToQueue:_queue withHandler: ^ (CMGyroData *gyroData, NSError *error) {
               
                CMRotationRate rotate = gyroData.rotationRate;
                
                NodeWrapper *nw = [[NodeWrapper alloc] init];
                nw.isGyro = true;
                nw.time = gyroData.timestamp;
                nw.x = rotate.x;
                nw.y = rotate.y;
                nw.z = rotate.z;
               // NSLog(@"x1======%lf",rotate.x);
                [self->_rawAccelGyroData addObject:nw];
                
                //NSLog(@"timestamp2-:%@",secDoubleToNanoString(gyroData.timestamp));
            }];
            [_motionManager startAccelerometerUpdatesToQueue:_queue withHandler: ^ (CMAccelerometerData *accelData, NSError *error) {
               
                CMAcceleration accel = accelData.acceleration;
                double x = accel.x;
                double y = accel.y;
                double z = accel.z;
                
                NodeWrapper *nw = [[NodeWrapper alloc] init];
                nw.isGyro = false;
                // The time stamp is the amount of time in seconds since the device booted.
                nw.time = accelData.timestamp;
                nw.x = - x * GRAVITY;
                nw.y = - y * GRAVITY;
                nw.z = - z * GRAVITY;
                
                [self->_logStringAccel appendString: [NSString stringWithFormat:@"%@,%f,%f,%f\r\n",
                                               secDoubleToNanoString(accelData.timestamp),
                                               x, //G-units
                                               y,
                                               z]]; //磁力计
                
                [self->_rawAccelGyroData addObject:nw];
              
               // NSLog(@"x2======%lf",accelData.timestamp);
            }];
         
            if (![CMAltimeter isRelativeAltitudeAvailable]){//检测气压计当前设备是否可用
                NSLog(@"Barometer is not available on this device. Sorry!");
                return;
            }
            
            _logStringbaro = [@"Timestamp,baro\r\n" mutableCopy];
            self.altimeter = [[CMAltimeter alloc] init]; //获取气压值
            [self.altimeter startRelativeAltitudeUpdatesToQueue:_queue withHandler:^(CMAltitudeData * _Nullable altitudeData, NSError * _Nullable error) {
                if (error) {
                    [self.altimeter stopRelativeAltitudeUpdates];//停止气压计
                    return;
                }
                
                [self.logStringbaro appendString: [NSString stringWithFormat:@"%@,%0.2f\r\n",
                                                          secDoubleToNanoString(altitudeData.timestamp),
                                                          [altitudeData.pressure floatValue]
                                                      ]];
                
                NSLog(@"高度：%0.2f m  气压值：%0.2f kPa",[altitudeData.relativeAltitude floatValue],[altitudeData.pressure floatValue]);
            }];
            
            
                
           
        } else {
            NSLog(@"Gyroscope or accelerometer not available");
        }
    }
}


  



@end


@implementation NodeWrapper
- (NSComparisonResult)compare:(NodeWrapper *)otherObject {
    return [@(self.time) compare:@(otherObject.time)]; // @ converts double to NSNumber
}
@end


NSURL *getFileURL(NSString *filename) {
    NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *documentsURL = [paths lastObject];
    return [documentsURL URLByAppendingPathComponent:filename isDirectory:NO];
}

NSURL *createOutputFolderURL(void) {
    NSDate *now = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy_MM_dd_HH_mm_ss_SS"];
    NSString *dateTimeString = [dateFormatter stringFromDate:now];
    
    NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *documentsURL = [paths lastObject];
    NSURL *outputFolderURL = [documentsURL URLByAppendingPathComponent:dateTimeString isDirectory:YES];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:outputFolderURL
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:&error];
    if (error != nil) {
        NSLog(@"Error creating directory: %@", error);
        outputFolderURL = nil;
    }
    return outputFolderURL;
}
