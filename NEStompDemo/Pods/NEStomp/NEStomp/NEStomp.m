//
//  SRStompKit.m
//  SocketDemo
//
//  Created by JimmyOu on 2018/6/1.
//  Copyright © 2018年 JimmyOu. All rights reserved.
//

#import "NEStomp.h"
#import "SRWebSocket.h"

#define kNEDefaultTimeout 5
#define kNEVersion1_2 @"1.2"
#define kNENoHeartBeat @"0,0"

#define WSProtocols @[]//@[@"v10.stomp", @"v11.stomp"]

#pragma mark Logging macros

#ifdef DEBUG // set to 1 to enable logs

#define LogDebug(frmt, ...) NSLog(frmt, ##__VA_ARGS__);

#else

#define LogDebug(frmt, ...) {}

#endif

#define kNEHeaderAcceptVersion @"accept-version"
#define kNEHeaderContentLength @"content-length"
#define kNEHeaderHeartBeat     @"heart-beat"
#define kNEHeaderHost          @"host"
#define kNEHeaderLogin         @"login"
#define kNEHeaderPasscode      @"passcode"
#define kNEHeaderSession       @"session"
#define kNEHeaderSubscription  @"subscription"

#pragma mark Frame commands

#define kNECommandAbort       @"ABORT"
#define kNECommandAck         @"ACK"
#define kNECommandBegin       @"BEGIN"
#define kNECommandCommit      @"COMMIT"
#define kNECommandConnect     @"CONNECT"
#define kNECommandConnected   @"CONNECTED"
#define kNECommandDisconnect  @"DISCONNECT"
#define kNECommandError       @"ERROR"
#define kNECommandMessage     @"MESSAGE"
#define kNECommandNack        @"NACK"
#define kNECommandReceipt     @"RECEIPT"
#define kNECommandSend        @"SEND"
#define kNECommandSubscribe   @"SUBSCRIBE"
#define kNECommandUnsubscribe @"UNSUBSCRIBE"

#pragma mark Control characters

#define    kNELineFeed @"\x0A"
#define    kNENullChar @"\x00"
#define kNEHeaderSeparator @":"


@interface NEStompClient()<SRWebSocketDelegate>
@property (strong, nonatomic) SRWebSocket *socket;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSString *host;
@property (nonatomic) NSString *clientHeartBeat;
@property (nonatomic, weak) NSTimer *pinger;
@property (nonatomic, weak) NSTimer *ponger;
@property (nonatomic, assign) BOOL heartbeat;
@property (nonatomic, assign) BOOL connected;

@property (nonatomic, copy) void (^disconnectedHandler)(NSError *error);
@property (nonatomic, copy) void (^connectionCompletionHandler)(NEStompFrame *connectedFrame, NSError *error);
@property (nonatomic, copy) NSDictionary *connectFrameHeaders;
@property (nonatomic, retain) NSMutableDictionary *subscriptions;

- (void) sendFrameWithCommand:(NSString *)command
                      headers:(NSDictionary *)headers
                         body:(NSString *)body;

@end

#pragma mark STOMP Frame
@interface NEStompFrame()

- (id)initWithCommand:(NSString *)theCommand
              headers:(NSDictionary *)theHeaders
                 body:(NSString *)theBody;

- (NSData *)toData;

@end
@implementation NEStompFrame

@synthesize command, headers, body;

- (id)initWithCommand:(NSString *)theCommand
              headers:(NSDictionary *)theHeaders
                 body:(NSString *)theBody {
    if(self = [super init]) {
        command = theCommand;
        headers = theHeaders;
        body =  theBody;
    }
    return self;
}

- (NSString *)toString {
    NSMutableString *frame = [NSMutableString stringWithString: [self.command stringByAppendingString:kNELineFeed]];
    for (id key in self.headers) {
        [frame appendString:[NSString stringWithFormat:@"%@%@%@%@", key, kNEHeaderSeparator, self.headers[key], kNELineFeed]];
    }
    [frame appendString:kNELineFeed];
    if (self.body) {
        [frame appendString:self.body];
    }
    [frame appendString:kNENullChar];
    return frame;
}

- (NSData *)toData {
    return [[self toString] dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NEStompFrame *)STOMPFrameFromData:(NSData *)data {
    NSData *strData = [data subdataWithRange:NSMakeRange(0, [data length])];
    NSString *msg = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    LogDebug(@"<<< %@", msg);
    NSMutableArray *contents = (NSMutableArray *)[[msg componentsSeparatedByString:kNELineFeed] mutableCopy];
    //to do better
    while ([contents count] > 0 && [contents[0] isEqual:@""]) {
        [contents removeObjectAtIndex:0];
    }
    if (!contents.count) {
        return nil;
    }
    NSString *command = [[contents objectAtIndex:0] copy];
    NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
    NSString *body = nil;
    BOOL hasHeaders = NO;
    [contents removeObjectAtIndex:0];
    for(NSString *line in contents) {
        if(hasHeaders) {
            body = [line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:kNENullChar]];
            
        } else {
            if ([line isEqual:@""]) {
                hasHeaders = YES;
            } else {
                NSMutableArray *parts = [NSMutableArray arrayWithArray:[line componentsSeparatedByString:kNEHeaderSeparator]];
                // key ist the first part
                NSString *key = parts[0];
                [parts removeObjectAtIndex:0];
                headers[key] = [parts componentsJoinedByString:kNEHeaderSeparator];
            }
        }
    }
    return [[NEStompFrame alloc] initWithCommand:command headers:headers body:[body stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}

- (NSString *)description {
    return [self toString];
}

@end

#pragma mark STOMP Message
@interface NEStompMessage()

@property (nonatomic, retain) NEStompClient *client;

+ (NEStompMessage *)STOMPMessageFromFrame:(NEStompFrame *)frame
                                   client:(NEStompClient *)client;

@end

@implementation NEStompMessage

@synthesize client;

- (id)initWithClient:(NEStompClient *)theClient
             headers:(NSDictionary *)theHeaders
                body:(NSString *)theBody {
    if (self = [super initWithCommand:kNECommandMessage
                              headers:theHeaders
                                 body:theBody]) {
        self.client = theClient;
    }
    return self;
}

- (void)ack {
    [self ackWithCommand:kNECommandAck headers:nil];
}

- (void)ack: (NSDictionary *)theHeaders {
    [self ackWithCommand:kNECommandAck headers:theHeaders];
}

- (void)nack {
    [self ackWithCommand:kNECommandNack headers:nil];
}

- (void)nack: (NSDictionary *)theHeaders {
    [self ackWithCommand:kNECommandNack headers:theHeaders];
}

- (void)ackWithCommand: (NSString *)command
               headers: (NSDictionary *)theHeaders {
    NSMutableDictionary *ackHeaders = [[NSMutableDictionary alloc] initWithDictionary:theHeaders];
    ackHeaders[kNEHeaderID] = self.headers[kNEHeaderAck];
    [self.client sendFrameWithCommand:command
                              headers:ackHeaders
                                 body:nil];
}

+ (NEStompMessage *)STOMPMessageFromFrame:(NEStompFrame *)frame
                                   client:(NEStompClient *)client {
    return [[NEStompMessage alloc] initWithClient:client headers:frame.headers body:frame.body];
}

@end


#pragma mark STOMP Transaction

@interface NEStompTransaction()

@property (nonatomic, retain) NEStompClient *client;

- (id)initWithClient:(NEStompClient *)theClient
          identifier:(NSString *)theIdentifier;

@end

@implementation NEStompTransaction

@synthesize identifier;

- (id)initWithClient:(NEStompClient *)theClient
          identifier:(NSString *)theIdentifier {
    if(self = [super init]) {
        self.client = theClient;
        identifier = [theIdentifier copy];
    }
    return self;
}

- (void)commit {
    [self.client sendFrameWithCommand:kNECommandCommit
                              headers:@{kNEHeaderTransaction: self.identifier}
                                 body:nil];
}

- (void)abort {
    [self.client sendFrameWithCommand:kNECommandAbort
                              headers:@{kNEHeaderTransaction: self.identifier}
                                 body:nil];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<STOMPTransaction identifier:%@>", identifier];
}

@end


#pragma mark STOMP Client Implementation

@implementation NEStompClient

@synthesize socket, url, host, heartbeat;
@synthesize connectFrameHeaders;
@synthesize connectionCompletionHandler, disconnectedHandler, receiptFrameHandler;
@synthesize subscriptions;
@synthesize pinger, ponger;
@synthesize delegate;

int idGenerator;
CFAbsoluteTime serverActivity;

#pragma mark Public API
- (instancetype)initWithURL:(NSURL *)theUrl webSocketHeaders:(NSDictionary *)headers {
    if (self = [super init]) {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:theUrl];
        if (headers) {
            request.allHTTPHeaderFields = headers;
        }
        self.socket = [[SRWebSocket alloc] initWithURLRequest:request protocols:WSProtocols];
        self.socket.delegate = self;
        
        self.heartbeat = YES;
        
        self.url = theUrl;
        self.host = theUrl.host;
        idGenerator = 0;
        self.connected = NO;
        self.subscriptions = [[NSMutableDictionary alloc] init];
        self.clientHeartBeat = @"10000,10000";
    }
    return self;
}

- (BOOL) heartbeatActivated {
    return heartbeat;
}
- (void)connectWithLogin:(NSString *)login
                passcode:(NSString *)passcode
       completionHandler:(void (^)(NEStompFrame *connectedFrame, NSError *error))completionHandler {
    [self connectWithHeaders:@{kNEHeaderLogin: login, kNEHeaderPasscode: passcode}
           completionHandler:completionHandler];
}

- (void)connectWithHeaders:(NSDictionary *)headers
         completionHandler:(void (^)(NEStompFrame *connectedFrame, NSError *error))completionHandler {
    self.connectFrameHeaders = headers;
    self.connectionCompletionHandler = completionHandler;
    [self.socket open];
    
}
- (void)sendTo:(NSString *)destination
          body:(NSString *)body {
    [self sendTo:destination
         headers:nil
            body:body];
}

- (void)sendTo:(NSString *)destination
       headers:(NSDictionary *)headers
          body:(NSString *)body {
    NSMutableDictionary *msgHeaders = [NSMutableDictionary dictionaryWithDictionary:headers];
    msgHeaders[kNEHeaderDestination] = destination;
    NSString *bodyEncode = [body stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (bodyEncode) {
        msgHeaders[kNEHeaderContentLength] = [NSNumber numberWithLong:[bodyEncode length]];
    }
    [self sendFrameWithCommand:kNECommandSend
                       headers:msgHeaders
                          body:bodyEncode];
}


- (void)subscribeTo:(nonnull NSString *)destination
         identifier:(nonnull NSString *)identifier
     messageHandler:(nonnull NEStompMessageHandler)handler {
    [self subscribeTo:destination
           identifier:identifier
              headers:nil
       messageHandler:handler];
}

- (void)subscribeTo:(nonnull NSString *)destination
         identifier:(nonnull NSString *)identifier
            headers:(nullable NSDictionary *)headers
     messageHandler:(nonnull NEStompMessageHandler)handler {
    NSMutableDictionary *subHeaders = [[NSMutableDictionary alloc] initWithDictionary:headers];
    subHeaders[kNEHeaderDestination] = destination;
    subHeaders[kNEHeaderID] = identifier;
    self.subscriptions[identifier] = handler;
    [self sendFrameWithCommand:kNECommandSubscribe
                       headers:subHeaders
                          body:nil];
}

- (void)unsubscribe:(NSString *)identifier {
    [self sendFrameWithCommand:kNECommandUnsubscribe
                       headers:@{kNEHeaderID: identifier}
                          body:nil];
    
}
- (NEStompTransaction *)begin {
    NSString *identifier = [NSString stringWithFormat:@"tx-%d", idGenerator++];
    return [self begin:identifier];
}

- (NEStompTransaction *)begin:(NSString *)identifier {
    [self sendFrameWithCommand:kNECommandBegin
                       headers:@{kNEHeaderTransaction: identifier}
                          body:nil];
    return [[NEStompTransaction alloc] initWithClient:self identifier:identifier];
}

- (void)disconnect {
    [self disconnect: nil];
}
- (void)disconnect:(void (^)(NSError *error))completionHandler {
    self.disconnectedHandler = completionHandler;
    [self sendFrameWithCommand:kNECommandDisconnect
                       headers:nil
                          body:nil];
    [self.subscriptions removeAllObjects];
    [self.pinger invalidate];
    [self.ponger invalidate];
    [self.socket close];
}

#pragma mark Private Methods
- (void)sendFrameWithCommand:(NSString *)command
                     headers:(NSDictionary *)headers
                        body:(NSString *)body {
    if (self.socket.readyState != SR_OPEN) {
        return;
    }
    NEStompFrame *frame = [[NEStompFrame alloc] initWithCommand:command headers:headers body:body];
    LogDebug(@">>> %@", frame);
    [self.socket send:[frame toData]];
}
- (void)sendPing:(NSTimer *)timer  {
    if (self.socket.readyState != SR_OPEN) {
        return;
    }
    [self.socket send:[NSData dataWithBytes:"\x0A" length:1]];
    LogDebug(@">>> PING");
}
- (void)checkPong:(NSTimer *)timer  {
    NSDictionary *dict = timer.userInfo;
    NSInteger ttl = [dict[@"ttl"] intValue];
    
    CFAbsoluteTime delta = CFAbsoluteTimeGetCurrent() - serverActivity;
    if (delta > (ttl * 2)) {
        LogDebug(@"did not receive server activity for the last %f seconds", delta);
        [self disconnect:nil];
    }
}

- (void)setupHeartBeatWithClient:(NSString *)clientValues
                          server:(NSString *)serverValues {
    if (!heartbeat) {
        return;
    }
    
    NSInteger cx, cy, sx, sy;
    
    NSScanner *scanner = [NSScanner scannerWithString:clientValues];
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@", "];
    [scanner scanInteger:&cx];
    [scanner scanInteger:&cy];
    
    scanner = [NSScanner scannerWithString:serverValues];
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@", "];
    [scanner scanInteger:&sx];
    [scanner scanInteger:&sy];
    
    NSInteger pingTTL = ceil(MAX(cx, sy) / 1000);
    NSInteger pongTTL = ceil(MAX(sx, cy) / 1000);
    
    LogDebug(@"send heart-beat every %ld seconds", pingTTL);
    LogDebug(@"expect to receive heart-beats every %ld seconds", pongTTL);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pingTTL > 0) {
            self.pinger = [NSTimer scheduledTimerWithTimeInterval: pingTTL
                                                           target: self
                                                         selector: @selector(sendPing:)
                                                         userInfo: nil
                                                          repeats: YES];
        }
        if (pongTTL > 0) {
            self.ponger = [NSTimer scheduledTimerWithTimeInterval: pongTTL
                                                           target: self
                                                         selector: @selector(checkPong:)
                                                         userInfo: @{@"ttl": [NSNumber numberWithInteger:pongTTL]}
                                                          repeats: YES];
        }
    });
    
}
- (void)receivedFrame:(NEStompFrame *)frame {
    // CONNECTED
    if([kNECommandConnected isEqual:frame.command]) {
        self.connected = YES;
        [self setupHeartBeatWithClient:self.clientHeartBeat server:frame.headers[kNEHeaderHeartBeat]];
        if (self.connectionCompletionHandler) {
            self.connectionCompletionHandler(frame, nil);
        }
        // MESSAGE
    } else if([kNECommandMessage isEqual:frame.command]) {
        NEStompMessageHandler handler = self.subscriptions[frame.headers[kNEHeaderSubscription]];
        if (handler) {
            NEStompMessage *message = [NEStompMessage STOMPMessageFromFrame:frame
                                                                     client:self];
            handler(message);
        } else {
            //TODO default handler
        }
        // RECEIPT
    } else if([kNECommandReceipt isEqual:frame.command]) {
        if (self.receiptFrameHandler) {
            self.receiptFrameHandler(frame);
        }
        // ERROR
    } else if([kNECommandError isEqual:frame.command]) {
        NSError *error = [[NSError alloc] initWithDomain:@"StompKit" code:1 userInfo:@{@"frame": frame}];
        // ERROR coming after the CONNECT frame
        if (!self.connected && self.connectionCompletionHandler) {
            self.connectionCompletionHandler(frame, error);
        } else {
            if (self.errorFrameHandler) {
                self.errorFrameHandler(frame);
            }
        }
    } else {
        NSError *error = [[NSError alloc] initWithDomain:@"StompKit"
                                                    code:2
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown frame %@", frame.command],
                                                           @"frame": frame}];
        if (self.delegate && [self.delegate respondsToSelector:@selector(websocketDidRecieveUnRecognizedFrameError:)]) {
            [self.delegate websocketDidRecieveUnRecognizedFrameError:error];
        }
        LogDebug(@"Unhandled ERROR frame: %@", frame);
    }
}

#pragma mark SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSMutableDictionary *connectHeaders = [[NSMutableDictionary alloc] initWithDictionary:connectFrameHeaders];
    connectHeaders[kNEHeaderAcceptVersion] = kNEVersion1_2;
    if (!connectHeaders[kNEHeaderHost]) {
        connectHeaders[kNEHeaderHost] = host;
    }
    if (!connectHeaders[kNEHeaderHeartBeat]) {
        connectHeaders[kNEHeaderHeartBeat] = self.clientHeartBeat;
    } else {
        self.clientHeartBeat = connectHeaders[kNEHeaderHeartBeat];
    }
    [self sendFrameWithCommand:kNECommandConnect
                       headers:connectHeaders
                          body: nil];
}

// message will either be an NSString if the server is using text
// or NSData if the server is using binary.
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    serverActivity = CFAbsoluteTimeGetCurrent();
    NEStompFrame *frame = [NEStompFrame STOMPFrameFromData:message];
    if (frame == nil || frame == NULL) {
        return;
    }
    [self receivedFrame:frame];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    LogDebug(@"socket did disconnect, error: %@", error);
    if (!self.connected && self.connectionCompletionHandler) {
        self.connectionCompletionHandler(nil, error);
    }
    self.connected = NO;
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(websocketDidDisconnect:)]) {
        [self.delegate websocketDidDisconnect:error];
    }
}
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSString *reasonStr = (reason != nil)? reason:@"";
    NSError *error = [NSError errorWithDomain:@"SRStormKit" code:code userInfo:@{NSLocalizedDescriptionKey:reasonStr}];
    LogDebug(@"socket did disconnect, error: %@", error);
    if (!self.connected && self.connectionCompletionHandler) {
        self.connectionCompletionHandler(nil, error);
    } else if (self.connected) {
        if (self.disconnectedHandler) {
            self.disconnectedHandler(error);
        }
    }
    self.connected = NO;
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(websocketDidDisconnect:)]) {
        [self.delegate websocketDidDisconnect:error];
    }
}
// Return YES to convert messages sent as Text to an NSString. Return NO to skip NSData -> NSString conversion for Text messages. Defaults to YES.
- (BOOL)webSocketShouldConvertTextFrameToString:(SRWebSocket *)webSocket {
    return NO;
}

@end
