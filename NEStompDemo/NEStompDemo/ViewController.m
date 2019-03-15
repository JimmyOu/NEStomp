//
//  ViewController.m
//  NEStompDemo
//
//  Created by JimmyOu on 2018/7/3.
//  Copyright © 2018年 JimmyOu. All rights reserved.
//

#import "ViewController.h"
#import <NEStomp/NEStomp.h>
#import "Reachability.h"
#import "UIColor+Extension.h"
@interface ViewController ()<NEStompClientDelegate>

@property (weak, nonatomic) IBOutlet UITextField *urlText;
@property (weak, nonatomic) IBOutlet UITextView *messageTextView;
@property (weak, nonatomic) IBOutlet UITextView *sendView;
@property (weak, nonatomic) IBOutlet UIButton *connectBtn;
@property (weak, nonatomic) IBOutlet UIButton *disconnctBtn;
@property (weak, nonatomic) IBOutlet UIButton *sendBtn;


/*是否用户点击了关闭*/
@property (assign, nonatomic) BOOL closeByUser;

- (IBAction)connect:(UIButton *)sender;
- (IBAction)disconnect:(UIButton *)sender;
- (IBAction)clearHistory:(UIButton *)sender;

- (IBAction)sendMessage:(UIButton *)sender;


/* Socket模块 */
@property (strong, nonatomic) NEStompClient *stompClient;

/* 网络检测模块，可以选择自己app里面的检测模块 */
@property (strong, nonatomic)  Reachability *reachability;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.closeByUser = NO;
    //监听网络，或者进入后台等消息。链接socket
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkDidChanged:) name:kReachabilityChangedNotification object:nil];
    
    self.messageTextView.layer.borderWidth = 1;
    self.messageTextView.layer.borderColor = [UIColor redColor].CGColor;
    
    [self configureUI];
}


- (void)dealloc {
    [self.reachability stopNotifier];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - notification
- (void)networkDidChanged:(NSNotification *)notification {
    if (self.reachability) {
        switch (self.reachability.currentReachabilityStatus) {
            case NotReachable: { ////有网->无网
            }
                break;
                
            default: {//无网/其他网络->有网
                if (!self.closeByUser) {
                    [self connectSocket];
                }
            }
                break;
        }
    }
}

- (void)connectSocket {
    self.closeByUser = NO;
    if (self.stompClient.connected) {
        return;
    }
    //初始化
    NSString *socketUrl = self.urlText.text;
    self.stompClient = [[NEStompClient alloc] initWithURL:[NSURL URLWithString:socketUrl]
                                         webSocketHeaders:nil];//socket链接的header,这里一般可以传App认证信息
    
    //链接,内部会发起socket链接 + 发送 CONNECTED 帧
    __weak typeof(self) weakSelf = self;
    [self.stompClient connectWithHeaders:nil
                       completionHandler:^(NEStompFrame * _Nullable connectedFrame, NSError * _Nullable error) {
                           [self configureUI];
                           if (error) { //链接失败
                               [weakSelf writeErrorToTextView:error];
                           } else { //链接成功
                               [weakSelf writeFrameToTextView:connectedFrame];
                               //订阅你需要的消息
                               /*订阅服务，这和服务端商量，和业务相关*/
                               NSString *subScribeStr = @"shareRead/123445";
                               /*订阅ID，这和服务端商量，和业务相关*/
                               NSString *subScribeId = subScribeStr;
                               /*
                                headers:
                                1.指定监听的消息id
                                2.消息由客户端确认消费
                                */
                               [weakSelf.stompClient subscribeTo:subScribeStr
                                                      identifier:subScribeId
                                                         headers:@{kNEHeaderAck:kNEAckClient} //客户端消费发送ack
                                                  messageHandler:^(NEStompMessage * _Nonnull message) {
                                                      //回复ACK表示消费
                                                      [message ack];
                                                      [weakSelf didReciveMessage:message];
                               }];
                           }
    }];
    self.stompClient.delegate = self;
    self.stompClient.errorFrameHandler = ^(NEStompMessage * _Nonnull frame) {
        [weakSelf writeFrameToTextView:frame];
    };
    self.stompClient.receiptFrameHandler = ^(NEStompFrame * _Nonnull frame) {
        [weakSelf writeFrameToTextView:frame];
    };
    
}
#pragma mark NEStompClientDelegate
- (void) websocketDidDisconnect: (nonnull NSError *)error {
    [self writeErrorToTextView:error];
    [self configureUI];
    [self reconnectIfNeeded];
}
- (void)websocketDidRecieveUnRecognizedFrameError:(NSError *)error {
    [self writeErrorToTextView:error];
}
- (void)didReciveMessage:(NEStompMessage *)message {
    [self writeFrameToTextView:message];
}
- (void)writeErrorToTextView:(NSError *)error {
    NSString *frameStr = [error localizedDescription];
    NSMutableAttributedString *mult = [self.messageTextView.attributedText mutableCopy];
    if (!mult) {
        mult = [[NSMutableAttributedString alloc] init];
    }
    NSAttributedString *attributeStr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@",frameStr]
                                                                       attributes:@{
                                                                                    NSForegroundColorAttributeName:[UIColor randomColor],
                                                                                    NSFontAttributeName:[UIFont systemFontOfSize:14],
                                                                                    }];
    [mult appendAttributedString:attributeStr];
    self.messageTextView.attributedText = mult;
}
- (void)writeFrameToTextView:(__kindof NEStompFrame *)frame {
    NSString *frameStr = [frame toString];
    NSMutableAttributedString *mult = [self.messageTextView.attributedText mutableCopy];
    if (!mult) {
        mult = [[NSMutableAttributedString alloc] init];
    }
    NSAttributedString *attributeStr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@",frameStr]
                                                                       attributes:@{
                                                                                    NSForegroundColorAttributeName:[UIColor randomColor],
                                                                                    NSFontAttributeName:[UIFont systemFontOfSize:14],
                                                                                    }];
    [mult appendAttributedString:attributeStr];
    self.messageTextView.attributedText = mult;
}

- (void)reconnectIfNeeded {
    if (self.closeByUser) {
        return ;
    }
    [self.stompClient disconnect];
    //隔个5s重连
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.closeByUser) {
            [self connectSocket];
        }
    });
}

- (void)close {
    self.closeByUser = YES;
    [self.stompClient disconnect];
}


- (IBAction)connect:(UIButton *)sender {
    [self connectSocket];
}

- (IBAction)disconnect:(UIButton *)sender {
    [self close];
}

- (IBAction)clearHistory:(UIButton *)sender {
    self.messageTextView.attributedText = nil;
}

- (IBAction)sendMessage:(UIButton *)sender {
    [self.view endEditing:YES];
    NEStompFrame *frame = [[NEStompFrame alloc] init];
    [frame setValue:@"SEND" forKey:@"command"];
    [frame setValue:self.sendView.text forKey:@"body"];
    [self writeFrameToTextView:frame];
    NSString *subScribeStr = @"shareRead/123445";
    [self.stompClient sendTo:subScribeStr body:self.sendView.text];
}

- (void)configureUI {
    self.connectBtn.enabled = !self.stompClient.connected;
    self.disconnctBtn.enabled = self.stompClient.connected;
    self.sendBtn.enabled = self.stompClient.connected;
    
}


@end
