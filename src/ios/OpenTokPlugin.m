//
//  OpentokPlugin.m
//
//  Copyright (c) 2012 TokBox. All rights reserved.
//  Please see the LICENSE included with this distribution for details.
//

#import "OpentokPlugin.h"
#import "UIView+JTViewToImage.h"
// #import "OpenTokPlugin-Swift.h"
#import "MyAudioDevice.h"

@implementation OpenTokPlugin{
    OTSession* _session;
    OTPublisher* _publisher;
    OTSubscriber* _subscriber;
    OTSubscriber* sub;
    NSMutableDictionary *subscriberDictionary;
    NSMutableDictionary *connectionDictionary;
    NSMutableDictionary *streamDictionary;
    NSMutableDictionary *callbackList;
    
    MyAudioDevice* _myAudioDevice;
    
    // videoView stuff
    AVCaptureSession* captureSession;
    AVCaptureVideoPreviewLayer* previewLayer;
    AVCaptureDevice* captureDevice;
    AVCaptureDeviceInput* previousInput;
    BOOL videoPlaying;
    
    dispatch_queue_t myQueue;
}

@synthesize exceptionId;


-(void) startVideo:(CDVInvokedUrlCommand*)command {
    NSLog(@"startVideo()");
    
    videoPlaying = NO;
    
    NSArray* sublayers = [NSArray arrayWithArray:self.webView.layer.sublayers];
    for (CALayer *layer in sublayers) {
        if([layer.name isEqualToString:@"VideoView"]) {
            videoPlaying = YES;
        }
    }
    
    if(videoPlaying == NO) {
    
        NSArray* devices = [AVCaptureDevice devices];

        for (AVCaptureDevice *device in devices) {
            if([device position] == AVCaptureDevicePositionBack) {
                captureDevice = [AVCaptureDevice deviceWithUniqueID:device.uniqueID];
            }
        }
        
        if (captureDevice != nil) {
            
            previousInput = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error: nil];
            
            captureSession = [[AVCaptureSession alloc] init];
            [captureSession addInput:previousInput];
            
            previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
            previewLayer.name = @"VideoView";
            [self.webView.layer insertSublayer:previewLayer atIndex:0];
            previewLayer.frame = self.webView.layer.frame;
            
            CGRect bounds = self.webView.layer.bounds;
            previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            previewLayer.bounds = bounds;
            previewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
            
            [captureSession startRunning];
            
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId]; 
        }
        
    }
    
}

-(void) stopVideo:(CDVInvokedUrlCommand*)command {
    NSLog(@"stopVideo()");
     NSArray* sublayers = [NSArray arrayWithArray:self.webView.layer.sublayers];
     for (CALayer *layer in sublayers) {
         if([layer.name isEqualToString:@"VideoView"]) {
             [layer removeFromSuperlayer];
             [captureSession removeInput:previousInput];
             previousInput = nil;
             captureSession = nil;
             previewLayer = nil;
         }
     }
    
}

-(void) getImgData:(CDVInvokedUrlCommand*)command {
    NSLog(@"getImgData()");
    
    NSString *type = [command.arguments objectAtIndex:0];
    
    UIImage *myImg;
    
    if([type isEqualToString:@"subscriber"]) {
        myImg = [sub.view toImage];
    } else {
        myImg = [_publisher.view toImage];
    }
    
    // create it in a new context, because using it directly eats memory for some reason..
    UIGraphicsBeginImageContext(CGSizeMake(myImg.size.width, myImg.size.height));
    [myImg drawInRect:CGRectMake(0, 0, myImg.size.width, myImg.size.height)];
    UIImage* newImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    dispatch_async(myQueue, ^{
        @autoreleasepool {
            NSData *imageData = UIImagePNGRepresentation(newImg);
//            NSData *imageData = UIImagePNGRepresentation(myImg);
            NSString *encodedString = [imageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        
            dispatch_async(dispatch_get_main_queue(), ^{
                // Return to Javascript
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:encodedString];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            });
        }
    });
    
}


//- (UIImage *)imageFromLayer:(CALayer *)layer {
//    UIGraphicsBeginImageContext([layer frame].size);
//    
//    [layer renderInContext:UIGraphicsGetCurrentContext()];
//    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();
//    
//    UIGraphicsEndImageContext();
//    
//    return outputImage;
//}

// end added by Devin Andrews

#pragma mark -
#pragma mark Cordova Methods
-(void) pluginInitialize{
    callbackList = [[NSMutableDictionary alloc] init];

    [self.webView.superview setOpaque:NO];
    self.webView.backgroundColor = [UIColor clearColor];
    [self.webView setOpaque:NO];

    // init myQueue
    myQueue = dispatch_queue_create("My Queue",NULL);
}
- (void)addEvent:(CDVInvokedUrlCommand*)command{
    NSString* event = [command.arguments objectAtIndex:0];
    [callbackList setObject:command.callbackId forKey: event];
}


#pragma mark -
#pragma mark Cordova JS - iOS bindings
#pragma mark TB Methods
/*** TB Methods
 ****/
// Called by TB.addEventListener('exception', fun...)
-(void)exceptionHandler:(CDVInvokedUrlCommand*)command{
    self.exceptionId = command.callbackId;
}

// Called by TB.initsession()
-(void)initSession:(CDVInvokedUrlCommand*)command{
    
    if(![[OTAudioDeviceManager currentAudioDevice] isKindOfClass:[MyAudioDevice class]]) {
        _myAudioDevice = [[MyAudioDevice alloc] init];
        [OTAudioDeviceManager setAudioDevice:_myAudioDevice];
    }
    
    // Get Parameters
    NSString* apiKey = [command.arguments objectAtIndex:0];
    NSString* sessionId = [command.arguments objectAtIndex:1];
    
    // Create Session
    _session = [[OTSession alloc] initWithApiKey: apiKey sessionId:sessionId delegate:self];
    
    // Initialize Dictionary, contains DOM info for every stream
    subscriberDictionary = [[NSMutableDictionary alloc] init];
    streamDictionary = [[NSMutableDictionary alloc] init];
    connectionDictionary = [[NSMutableDictionary alloc] init];
    
    // Return Result
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by TB.initPublisher()
- (void)initPublisher:(CDVInvokedUrlCommand *)command{
    NSLog(@"iOS creating Publisher");
    BOOL bpubAudio = YES;
    BOOL bpubVideo = YES;
    
    // Get Parameters
    NSString* name = [command.arguments objectAtIndex:0];
    int top = [[command.arguments objectAtIndex:1] intValue];
    int left = [[command.arguments objectAtIndex:2] intValue];
    int width = [[command.arguments objectAtIndex:3] intValue];
    int height = [[command.arguments objectAtIndex:4] intValue];
    int zIndex = [[command.arguments objectAtIndex:5] intValue];
    
    NSString* publishAudio = [command.arguments objectAtIndex:6];
    if ([publishAudio isEqualToString:@"false"]) {
        bpubAudio = NO;
    }
    NSString* publishVideo = [command.arguments objectAtIndex:7];
    if ([publishVideo isEqualToString:@"false"]) {
        bpubVideo = NO;
    }
    
    // Publish and set View
    _publisher = [[OTPublisher alloc] initWithDelegate:self name:name];
    [_publisher setPublishAudio:bpubAudio];
    [_publisher setPublishVideo:bpubVideo];
    
    [_publisher.view setFrame:CGRectMake(left, top, width, height)];
    
//        [self.webView.superview addSubview:_publisher.view];
    [self.webView.superview insertSubview:_publisher.view atIndex:0];
    self.webView.layer.zPosition = 3;
    

    
    if (zIndex>0) {
        _publisher.view.layer.zPosition = zIndex;
    }
    NSString* cameraPosition = [command.arguments objectAtIndex:8];
    if ([cameraPosition isEqualToString:@"back"]) {
        _publisher.cameraPosition = AVCaptureDevicePositionBack;
    }
    
    // Return to Javascript
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
// Helper function to update Views
- (void)updateView:(CDVInvokedUrlCommand*)command{
    NSString* callback = command.callbackId;
    NSString* sid = [command.arguments objectAtIndex:0];
    int top = [[command.arguments objectAtIndex:1] intValue];
    int left = [[command.arguments objectAtIndex:2] intValue];
    int width = [[command.arguments objectAtIndex:3] intValue];
    int height = [[command.arguments objectAtIndex:4] intValue];
    int zIndex = [[command.arguments objectAtIndex:5] intValue];
    
    NSLog(@"updateView() called");
    NSLog(sid);
    
    if ([sid isEqualToString:@"TBPublisher"]) {
        NSLog(@"The Width is: %d", width);
        CGRect frame = self.webView.frame;
        _publisher.view.frame = frame;
        
//        _publisher.view.frame = CGRectMake(left, top, width, height);
//        [_publisher.view setFrame:CGRectMake(left, top, width, height)];
//        _publisher.view.layer.zPosition = zIndex;
    } else {
        CGRect frame = self.webView.frame;
        sub.view.frame = frame;
    }
    
    // Pulls the subscriber object from dictionary to prepare it for update
//    OTSubscriber* streamInfo = [subscriberDictionary objectForKey:sid];
//    
//    if (streamInfo) {
//        // Reposition the video feeds!
//        streamInfo.view.frame = CGRectMake(left, top, width, height);
//        streamInfo.view.layer.zPosition = zIndex;
//    }
    
    CDVPluginResult* callbackResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [callbackResult setKeepCallbackAsBool:YES];
    //[self.commandDelegate sendPluginResult:callbackResult toSuccessCallbackString:command.callbackId];
    [self.commandDelegate sendPluginResult:callbackResult callbackId:command.callbackId];
}

#pragma mark Publisher Methods
- (void)publishAudio:(CDVInvokedUrlCommand*)command{
    NSString* publishAudio = [command.arguments objectAtIndex:0];
    NSLog(@"iOS Altering Audio publishing state, %@", publishAudio);
    BOOL pubAudio = YES;
    if ([publishAudio isEqualToString:@"false"]) {
        pubAudio = NO;
    }
    [_publisher setPublishAudio:pubAudio];
}
- (void)publishVideo:(CDVInvokedUrlCommand*)command{
    NSString* publishVideo = [command.arguments objectAtIndex:0];
    NSLog(@"iOS Altering Video publishing state, %@", publishVideo);
    BOOL pubVideo = YES;
    if ([publishVideo isEqualToString:@"false"]) {
        pubVideo = NO;
    }
    [_publisher setPublishVideo:pubVideo];
}
- (void)setCameraPosition:(CDVInvokedUrlCommand*)command{
    NSString* publishCameraPosition = [command.arguments objectAtIndex:0];
    NSLog(@"iOS Altering Video camera position, %@", publishCameraPosition);
    
    if ([publishCameraPosition isEqualToString:@"back"]) {
        [_publisher setCameraPosition:AVCaptureDevicePositionBack];
    } else if ([publishCameraPosition isEqualToString:@"front"]) {
        [_publisher setCameraPosition:AVCaptureDevicePositionFront];
    }
}
- (void)destroyPublisher:(CDVInvokedUrlCommand *)command{
    NSLog(@"iOS Destroying Publisher");
    // Unpublish publisher
    [_session unpublish:_publisher error:nil];
    
    // Remove publisher view
    if (_publisher) {
        [_publisher.view removeFromSuperview];
    }
    
    // Return to Javascript
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


#pragma mark Session Methods
- (void)connect:(CDVInvokedUrlCommand *)command{
    NSLog(@"iOS Connecting to Session");
    
    // Get Parameters
    NSString* tbToken = [command.arguments objectAtIndex:0];
    [_session connectWithToken:tbToken error:nil];
}

// Called by session.disconnect()
- (void)disconnect:(CDVInvokedUrlCommand*)command{
    [_session disconnect:nil];
}

// Called by session.publish(top, left)
- (void)publish:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS Publish stream to session");
    [_session publish:_publisher error:nil];
    
    // Return to Javascript
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by session.unpublish(...)
- (void)unpublish:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS Unpublishing publisher");
    [_session unpublish:_publisher error:nil];
}

// Called by session.subscribe(streamId, top, left)
- (void)subscribe:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS subscribing to stream");
    
    // Get Parameters
    NSString* sid = [command.arguments objectAtIndex:0];
    
    
    int top = [[command.arguments objectAtIndex:1] intValue];
    int left = [[command.arguments objectAtIndex:2] intValue];
    int width = [[command.arguments objectAtIndex:3] intValue];
    int height = [[command.arguments objectAtIndex:4] intValue];
    int zIndex = [[command.arguments objectAtIndex:5] intValue];
    
    // Acquire Stream, then create a subscriber object and put it into dictionary
    OTStream* myStream = [streamDictionary objectForKey:sid];
//    OTSubscriber* sub = [[OTSubscriber alloc] initWithStream:myStream delegate:self];
    sub = [[OTSubscriber alloc] initWithStream:myStream delegate:self];
    [_session subscribe:sub error:nil];
    
    if ([[command.arguments objectAtIndex:6] isEqualToString:@"false"]) {
        [sub setSubscribeToAudio: NO];
    }
    if ([[command.arguments objectAtIndex:7] isEqualToString:@"false"]) {
        [sub setSubscribeToVideo: NO];
    }
    [subscriberDictionary setObject:sub forKey:myStream.streamId];
    
    [sub.view setFrame:CGRectMake(left, top, width, height)];
    if (zIndex>0) {
        sub.view.layer.zPosition = zIndex;
    }
//    [self.webView.superview addSubview:sub.view];
    [self.webView.superview insertSubview:sub.view atIndex:0];
    self.webView.layer.zPosition = 3;
    
    // Return to JS event handler
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by session.unsubscribe(streamId, top, left)
- (void)unsubscribe:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS unSubscribing to stream");
    //Get Parameters
    NSString* sid = [command.arguments objectAtIndex:0];
    OTSubscriber * subscriber = [subscriberDictionary objectForKey:sid];
    [_session unsubscribe:subscriber error:nil];
    [subscriber.view removeFromSuperview];
    [subscriberDictionary removeObjectForKey:sid];
}

// Called by session.unsubscribe(streamId, top, left)
- (void)signal:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS signaling to connectionId %@", [command.arguments objectAtIndex:2]);
    OTConnection* c = [connectionDictionary objectForKey: [command.arguments objectAtIndex:2]];
    NSLog(@"iOS signaling to connection %@", c);
    [_session signalWithType:[command.arguments objectAtIndex:0] string:[command.arguments objectAtIndex:1] connection:c error:nil];
}


#pragma mark -
#pragma mark Delegates
#pragma mark Subscriber Delegates
/*** Subscriber Methods
 ****/
- (void)subscriberDidConnectToStream:(OTSubscriberKit*)sub{
    NSLog(@"iOS Connected To Stream");
    
    NSLog(@"Stream has audio?");
    NSLog(sub.stream.hasAudio == YES ? @"YES":@"NO");
    
    if(sub.stream.hasAudio == YES) {
        // change audio route to bluetooth,if present, else headset otherwise device
        // speakers
        [_myAudioDevice
         configureAudioSessionWithDesiredAudioRoute:AUDIO_DEVICE_BLUETOOTH];
    }
    
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    NSString* streamId = sub.stream.streamId;
    [eventData setObject:streamId forKey:@"streamId"];
    [self triggerJSEvent: @"sessionEvents" withType: @"subscribedToStream" withData: eventData];
    
}
- (void)subscriber:(OTSubscriber*)subscrib didFailWithError:(OTError*)error{
    NSLog(@"subscriber didFailWithError %@", error);
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    NSString* streamId = subscrib.stream.streamId;
    NSNumber* errorCode = [NSNumber numberWithInt:1600];
    [eventData setObject: errorCode forKey:@"errorCode"];
    [eventData setObject:streamId forKey:@"streamId"];
    [self triggerJSEvent: @"sessionEvents" withType: @"subscribedToStream" withData: eventData];
}


#pragma mark Session Delegates
- (void)sessionDidConnect:(OTSession*)session{
    NSLog(@"iOS Connected to Session");
    
    NSMutableDictionary* sessionDict = [[NSMutableDictionary alloc] init];
    
    // SessionConnectionStatus
    NSString* connectionStatus = @"";
    if (session.sessionConnectionStatus==OTSessionConnectionStatusConnected) {
        connectionStatus = @"OTSessionConnectionStatusConnected";
    }else if (session.sessionConnectionStatus==OTSessionConnectionStatusConnecting) {
        connectionStatus = @"OTSessionConnectionStatusConnecting";
    }else if (session.sessionConnectionStatus==OTSessionConnectionStatusDisconnecting) {
        connectionStatus = @"OTSessionConnectionStatusDisconnected";
    }else{
        connectionStatus = @"OTSessionConnectionStatusFailed";
    }
    [sessionDict setObject:connectionStatus forKey:@"sessionConnectionStatus"];
    
    // SessionId
    [sessionDict setObject:session.sessionId forKey:@"sessionId"];
    
    [connectionDictionary setObject: session.connection forKey: session.connection.connectionId];
    
    
    // After session is successfully connected, the connection property is available
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    [eventData setObject:@"status" forKey:@"connected"];
    NSMutableDictionary* connectionData = [self createDataFromConnection: session.connection];
    [eventData setObject: connectionData forKey: @"connection"];
    
    
    NSLog(@"object for session is %@", sessionDict);
    
    // After session dictionary is constructed, return the result!
    //    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:sessionDict];
    //    NSString* sessionConnectCallback = [callbackList objectForKey:@"sessSessionConnected"];
    //    [self.commandDelegate sendPluginResult:pluginResult callbackId:sessionConnectCallback];
    
    
    [self triggerJSEvent: @"sessionEvents" withType: @"sessionConnected" withData: eventData];
}


- (void)session:(OTSession *)session connectionCreated:(OTConnection *)connection
{
    [connectionDictionary setObject: connection forKey: connection.connectionId];
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* connectionData = [self createDataFromConnection: connection];
    [data setObject: connectionData forKey: @"connection"];
    [self triggerJSEvent: @"sessionEvents" withType: @"connectionCreated" withData: data];
}

- (void)session:(OTSession *)session connectionDestroyed:(OTConnection *)connection
{
    [connectionDictionary removeObjectForKey: connection.connectionId];
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* connectionData = [self createDataFromConnection: connection];
    [data setObject: connectionData forKey: @"connection"];
    [self triggerJSEvent: @"sessionEvents" withType: @"connectionDestroyed" withData: data];
}
- (void)session:(OTSession*)mySession streamCreated:(OTStream*)stream{
    NSLog(@"iOS Received Stream");
    [streamDictionary setObject:stream forKey:stream.streamId];
    [self triggerStreamCreated: stream withEventType: @"sessionEvents"];
}
- (void)session:(OTSession*)session streamDestroyed:(OTStream *)stream{
    NSLog(@"iOS Drop Stream");
    
    OTSubscriber * subscriber = [subscriberDictionary objectForKey:stream.streamId];
    if (subscriber) {
        NSLog(@"subscriber found, unsubscribing");
        [_session unsubscribe:subscriber error:nil];
        [subscriber.view removeFromSuperview];
        [subscriberDictionary removeObjectForKey:stream.streamId];
    }
    [self triggerStreamDestroyed: stream withEventType: @"sessionEvents"];
}
- (void)session:(OTSession*)session didFailWithError:(OTError*)error {
    NSLog(@"Error: Session did not Connect");
    NSLog(@"Error: %@", error);
    NSNumber* code = [NSNumber numberWithInt:[error code]];
    NSMutableDictionary* err = [[NSMutableDictionary alloc] init];
    [err setObject:error.localizedDescription forKey:@"message"];
    [err setObject:code forKey:@"code"];
    
    if (self.exceptionId) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: err];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.exceptionId];
    }
}
- (void)sessionDidDisconnect:(OTSession*)session{
    NSString* alertMessage = [NSString stringWithFormat:@"Session disconnected: (%@)", session.sessionId];
    NSLog(@"sessionDidDisconnect (%@)", alertMessage);
    
    // Setting up event object
    for ( id key in subscriberDictionary ) {
        OTSubscriber* aStream = [subscriberDictionary objectForKey:key];
        [aStream.view removeFromSuperview];
    }
    [subscriberDictionary removeAllObjects];
    if( _publisher ){
        [_publisher.view removeFromSuperview];
    }
    
    // Setting up event object
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    [eventData setObject:@"clientDisconnected" forKey:@"reason"];
    [self triggerJSEvent: @"sessionEvents" withType: @"sessionDisconnected" withData: eventData];
}
-(void) session:(OTSession *)session receivedSignalType:(NSString *)type fromConnection:(OTConnection *)connection withString:(NSString *)string{
    
    NSLog(@"iOS Session Received signal from Connection: %@ with id %@", connection, [connection connectionId]);
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    [data setObject: type forKey: @"type"];
    [data setObject: string forKey: @"data"];
    if (connection.connectionId) {
        [data setObject: connection.connectionId forKey: @"connectionId"];
        [self triggerJSEvent: @"sessionEvents" withType: @"signalReceived" withData: data];
    }
}


#pragma mark Publisher Delegates
- (void)publisher:(OTPublisherKit *)publisher streamCreated:(OTStream *)stream{
    [streamDictionary setObject:stream forKey:stream.streamId];
    [self triggerStreamCreated: stream withEventType: @"publisherEvents"];
}
- (void)publisher:(OTPublisherKit*)publisher streamDestroyed:(OTStream *)stream{
    [self triggerStreamDestroyed: stream withEventType: @"publisherEvents"];
}
- (void)publisher:(OTPublisher*)publisher didFailWithError:(NSError*) error {
    NSLog(@"iOS Publisher didFailWithError");
    NSMutableDictionary* err = [[NSMutableDictionary alloc] init];
    [err setObject:error.localizedDescription forKey:@"message"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: err];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.exceptionId];
}

#pragma mark -
#pragma mark Helper Methods
- (void)triggerStreamCreated: (OTStream*) stream withEventType: (NSString*) eventType{
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* streamData = [self createDataFromStream: stream];
    [data setObject: streamData forKey: @"stream"];
    [self triggerJSEvent: eventType withType: @"streamCreated" withData: data];
}
- (void)triggerStreamDestroyed: (OTStream*) stream withEventType: (NSString*) eventType{
    [streamDictionary removeObjectForKey: stream.streamId];
    
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* streamData = [self createDataFromStream: stream];
    [data setObject: streamData forKey: @"stream"];
    [self triggerJSEvent: eventType withType: @"streamDestroyed" withData: data];
}
- (NSMutableDictionary*)createDataFromConnection:(OTConnection*)connection{
    NSLog(@"iOS creating data from stream: %@", connection);
    NSMutableDictionary* connectionData = [[NSMutableDictionary alloc] init];
    [connectionData setObject: connection.connectionId forKey: @"connectionId" ];
    [connectionData setObject: [NSString stringWithFormat:@"%.0f", [connection.creationTime timeIntervalSince1970]] forKey: @"creationTime" ];
    if (connection.data) {
        [connectionData setObject: connection.data forKey: @"data" ];
    }
    return connectionData;
}
- (NSMutableDictionary*)createDataFromStream:(OTStream*)stream{
    NSMutableDictionary* streamData = [[NSMutableDictionary alloc] init];
    [streamData setObject: stream.connection.connectionId forKey: @"connectionId" ];
    [streamData setObject: [NSString stringWithFormat:@"%.0f", [stream.creationTime timeIntervalSince1970]] forKey: @"creationTime" ];
    [streamData setObject: [NSNumber numberWithInt:-999] forKey: @"fps" ];
    [streamData setObject: [NSNumber numberWithBool: stream.hasAudio] forKey: @"hasAudio" ];
    [streamData setObject: [NSNumber numberWithBool: stream.hasVideo] forKey: @"hasVideo" ];
    [streamData setObject: stream.name forKey: @"name" ];
    [streamData setObject: stream.streamId forKey: @"streamId" ];
    return streamData;
}
- (void)triggerJSEvent:(NSString*)event withType:(NSString*)type withData:(NSMutableDictionary*) data{
    NSMutableDictionary* message = [[NSMutableDictionary alloc] init];
    [message setObject:type forKey:@"eventType"];
    [message setObject:data forKey:@"data"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [pluginResult setKeepCallbackAsBool:YES];
    
    NSString* callbackId = [callbackList objectForKey:event];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}



/***** Notes
 
 
 NSString *stringObtainedFromJavascript = [command.arguments objectAtIndex:0];
 CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: stringObtainedFromJavascript];
 
 if(YES){
 [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackID]];
 }else{
 //Call  the Failure Javascript function
 [self.commandDelegate [pluginResult toErrorCallbackString:self.callbackID]];
 }
 
 ******/


@end

