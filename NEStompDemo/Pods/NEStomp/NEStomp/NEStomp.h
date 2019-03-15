//
//  SRStompKit.h
//  SocketDemo
//
//  Created by JimmyOu on 2018/6/1.
//  Copyright © 2018年 JimmyOu. All rights reserved.
// 参考：https://g.hz.netease.com/hzjiangou/Document/blob/master/webSocket.md

#import <Foundation/Foundation.h>

#pragma mark Frame headers

#define kNEHeaderAck           @"ack"
#define kNEHeaderID            @"id"
#define kNEHeaderReceipt       @"receipt"
#define kNEHeaderReceiptID     @"receipt-id"
#define kNEHeaderTransaction   @"transaction"
#define kNEHeaderDestination   @"destination"
#define kNEHeaderMessageID     @"message-id"

#pragma mark Ack Header Values

#define kNEAckAuto             @"auto"
#define kNEAckClient           @"client"
#define kNEAckClientIndividual @"client-individual"

@class NEStompFrame;
@class NEStompMessage;

typedef void (^NEStompReceiptFrameHandler)(NEStompFrame *_Nonnull frame);
typedef void (^NEStompMessageHandler)(NEStompMessage * _Nonnull message);
typedef void (^NEStompErrorFrameHandler)(NEStompMessage * _Nonnull error);

#pragma mark STOMP Frame

@interface NEStompFrame : NSObject

/**
 帧类型
 */
@property (nonatomic, copy, readonly, nullable) NSString *command;
/**
 帧头部
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary *headers;
/**
 帧消息体
 */
@property (nonatomic, copy, readonly, nullable) NSString *body;
- (NSString *)toString;

@end

#pragma mark STOMP Message

@interface NEStompMessage : NEStompFrame

- (void)ack;

/**
 发送ack消息，代表消息被客户端消费
 @param theHeaders 自定义头部
 */
- (void)ack:(nullable NSDictionary *)theHeaders;

- (void)nack;
/**
 发送nack消息，代表消息被客户端抛弃
 @param theHeaders 自定义头部
 */
- (void)nack:(nullable NSDictionary *)theHeaders;

@end

#pragma mark STOMP Transaction

@interface NEStompTransaction : NSObject

@property (nonatomic, copy, readonly, nonnull) NSString *identifier;

/**
 在过程中提交事务
 */
- (void)commit;

/**
 在过程中回滚事务
 */
- (void)abort;

@end

@protocol NEStompClientDelegate<NSObject>

@optional
/**
 webSocket被断开（用户取消，服务端关闭，网络断开等）
 */
- (void) websocketDidDisconnect: (nonnull NSError *)error;
/**
 收到未能识别的Frame
 */
- (void) websocketDidRecieveUnRecognizedFrameError: (nonnull NSError *)error;

@end


@interface NEStompClient : NSObject
/**
 收到 ReceiptFrame的回调
 block execute on mainThread
 */
@property (nonatomic, copy, nullable) NEStompReceiptFrameHandler receiptFrameHandler;
/**
 收到 ErrorFrame的回调
 block execute on mainThread
 */
@property (nonatomic, copy, nullable) NEStompErrorFrameHandler errorFrameHandler;
/**
 socket是否链接
 */
@property (nonatomic, assign, readonly) BOOL connected;

@property (nonatomic, weak) id<NEStompClientDelegate> delegate;

/**
 初始化
 
 @param theUrl url
 @param headers connected的头部信息
 */
- (instancetype)initWithURL:(NSURL *)theUrl webSocketHeaders:(NSDictionary *)headers;

/**
 以自定义头的形式connected
 
 @param headers customs headers
 @param completionHandler completionHandler execute on mainThread
 */
- (void)connectWithHeaders:(nullable NSDictionary *)headers
         completionHandler:(void (^)(NEStompFrame *_Nullable connectedFrame, NSError *_Nullable error))completionHandler;

/**
 给某个destination发送message
 @param destination destination
 @param body messageBody
 */
- (void)sendTo:(nonnull NSString *)destination
          body:(nonnull NSString *)body;

/**
 给某个destination发送message
 
 @param destination destination
 @param headers custom headers
 @param body messageBody
 */
- (void)sendTo:(nonnull NSString *)destination
       headers:(nullable NSDictionary *)headers
          body:(nonnull NSString *)body;

/**
 订阅某个 destination 的 message
 
 @param destination destination
 @param identifier 目的地的唯一标识符
 @param handler 收到该目的地的消息
 */
- (void)subscribeTo:(nonnull NSString *)destination
         identifier:(nonnull NSString *)identifier
     messageHandler:(nonnull NEStompMessageHandler)handler;
/**
 订阅某个 destination 的 message
 
 @param destination destination
 @param identifier 目的地的唯一标识符
 @param headers 自定义header
 @param handler 收到该目的地的消息
 */
- (void)subscribeTo:(nonnull NSString *)destination
         identifier:(nonnull NSString *)identifier
            headers:(nullable NSDictionary *)headers
     messageHandler:(nonnull NEStompMessageHandler)handler;

/**
 取消某个订阅
 @param identifier 订阅ID
 */
- (void)unsubscribe:(nonnull NSString *)identifier;

/**
 开始一个事务
 @return 事务对象 transcation commmit进行事务提交
 */
- (nonnull NEStompTransaction *)begin;

/**
 开始一个事务
 @param identifier 事务ID
 @return 事务对象，commmit事务提交，abort中止事务
 */
- (nonnull NEStompTransaction *)begin:(nonnull NSString *)identifier;

/**
 手动断开链接
 */
- (void)disconnect;
- (void)disconnect:(void (^)(NSError *_Nonnull error))completionHandler;

@end


