//
//  MDWampTests.m
//  MDWamp
//
//  Created by Niko Usai on 11/03/14.
//  Copyright (c) 2014 mogui.it. All rights reserved.
//
#import <XCTest/XCTest.h>
#import "XCTAsyncTestCase.h"
#import "MDWampTestIncludes.h"
#import "MDWamp.h"
#import "NSString+MDString.h"

#define kMDWampTestsFakeSerialization 99

@interface MDWampTests : XCTAsyncTestCase
@property (strong, nonatomic) MDWamp *wamp;
@property (strong, nonatomic) MDWampClientDelegateMock *delegate;
@property (strong, nonatomic) MDWampTransportMock *transport;
@property (strong, nonatomic) MDWampSerializationMock *s;
@property (strong, nonatomic) NSDictionary *dictionaryPayload;
@property (strong, nonatomic) NSArray *arrayPayload;
@end

@implementation MDWampTests

- (void)setUp
{
    [super setUp];
    _delegate = [[MDWampClientDelegateMock alloc] init];
    _transport = [[MDWampTransportMock alloc] initWithServer:[NSURL URLWithString:@"http://fakeserver.com"]];
    _transport.serializationClass = kMDWampTestsFakeSerialization;
    self.wamp = [[MDWamp alloc] initWithTransport:_transport realm:@"Realm1" delegate:_delegate];
    self.wamp.serializationInstanceMap = @{[NSNumber numberWithInt:kMDWampTestsFakeSerialization]: [MDWampSerializationMock class]};
    _s = [[MDWampSerializationMock alloc] init];

    self.dictionaryPayload = @{@"color": @"orange", @"sizes": @[@23, @42, @7]};
    self.arrayPayload = @[@1,@2, @34, @4545];
    [_wamp connect];
    [self prepare];
}

- (void)tearDown
{
    [super tearDown];
}


- (id<MDWampMessage>)msgFromTransportAndCheckIsA:(Class)class
{
    NSArray *arr = [_s unpack:[_transport.sendBuffer lastObject]];
    Class msgC = [MDWampMessageFactory messageClassFromCode:arr[0] forVersion:kMDWampVersion2];

    if ( ![msgC isSubclassOfClass:class]) {
        return nil;
    }
    
    NSMutableArray *tmp = [arr mutableCopy];
    [tmp shift];
    
    id<MDWampMessage> msg = [(id<MDWampMessage>)[msgC alloc] initWithPayload:tmp];
    XCTAssertNotNil(msg, @"An %@ message must be in the transport buffer", NSStringFromClass(class));
    
    return msg;
}

- (void)triggerMsg:(id<MDWampMessage>)msg
{
    NSArray *arr = [msg marshallFor:kMDWampVersion2];
    NSData *d = [_s pack:arr];
    [_transport triggerDidReceiveMessage:d];
}

- (void) testSessionEstablished {

    
    MDWampHello *hello = [self msgFromTransportAndCheckIsA:[MDWampHello class]];
    
    NSDictionary *roles = [[hello details] objectForKey:@"roles"];
    XCTAssert([roles count] > 0, @"At least a role should be sent in hello message");
    
    MDWampWelcome *welcome = [[MDWampWelcome alloc] init];
    welcome.session = [NSNumber numberWithInt:[[NSString stringWithRandomId] intValue]];
    welcome.details = @{};
    
    [self triggerMsg:welcome];
    
    XCTAssertNotNil(_wamp.sessionId , @"Must have session");
}

- (void)testSessionAbort {
    MDWampAbort *abort = [[MDWampAbort alloc] initWithPayload:@[@{@"message": @"The realm does not exist."}, @"wamp.error.no_such_realm"]];

    [self triggerMsg:abort];
    
    XCTAssert(_delegate.onCloseCalled , @"Session is Abortd onClose method must be called");
}

- (void)testGoodbye {
    
    MDWampGoodbye *goodbye = [[MDWampGoodbye alloc] initWithPayload:@[@{}, @"wamp.error.close_realm"]];
    [self triggerMsg:goodbye];
    
    [self msgFromTransportAndCheckIsA:[MDWampGoodbye class]];
    
    XCTAssert(_delegate.onCloseCalled , @"Server sent goodbye onClose method must be called");
}

- (void)testSubscribeUnsubscribe
{
    
    //
    // test fail subscription
    //

    [_wamp subscribe:@"com.topic.x"  onEvent:^(id payload) {
        // nothing to do
    } result:^(NSError *error) {
        XCTAssertEqualObjects(error.localizedDescription, @"wamp.error.not_authorized", @"Must call error");
        [self notify:kXCTUnitWaitStatusSuccess];
    }];
    MDWampSubscribe *sub = [self msgFromTransportAndCheckIsA:[MDWampSubscribe class]];
    MDWampError *error = [[MDWampError alloc] initWithPayload:@[@32, sub.request, @{}, @"wamp.error.not_authorized"]];
    [_transport triggerDidReceiveMessage:[error marshallFor:kMDWampVersion2]];
    
    [self waitForStatus:kXCTUnitWaitStatusSuccess timeout:0.5];
    
    
    //
    // test succed subscription
    //
    [self prepare];
    [_wamp subscribe:@"com.topic.x" onEvent:^(id payload) {
        // nothing to do
    } result:^(NSError *error) {
        XCTAssertNil(error, @"error must be nil");
        [self notify:kXCTUnitWaitStatusSuccess];
    }];
    MDWampSubscribe *sub2 = [self msgFromTransportAndCheckIsA:[MDWampSubscribe class]];
    MDWampSubscribed *subscribed = [[MDWampSubscribed alloc] initWithPayload:@[sub2.request, @12343234]];
    [_transport triggerDidReceiveMessage:[subscribed marshallFor:kMDWampVersion2]];
    
    [self waitForStatus:kXCTUnitWaitStatusSuccess timeout:0.5];
    
    
    //
    // test succed unsubscription
    //
    [self prepare];
    [_wamp unsubscribe:@"com.topic.x" result:^(NSError *error) {
        XCTAssertNil(error, @"Must correctly unsubscribe");
        [self notify:kXCTUnitWaitStatusSuccess];
    }];
    
    MDWampUnsubscribe *un = [self msgFromTransportAndCheckIsA:[MDWampUnsubscribe class]];
    MDWampUnsubscribed *unsubscribed = [[MDWampUnsubscribed alloc] initWithPayload:@[un.request]];
    [_transport triggerDidReceiveMessage:[unsubscribed marshallFor:kMDWampVersion2]];
    
    [self waitForStatus:kXCTUnitWaitStatusSuccess timeout:0.5];
    
    // fail unsubscription for inexistent topic
    [self prepare];
    [_wamp unsubscribe:@"com.topic.y" result:^(NSError *error) {
        XCTAssertNotNil(error, @"Must call error");
        // Should fail instantly
        [self notify:kXCTUnitWaitStatusSuccess];
    }];
    [self waitForStatus:kXCTUnitWaitStatusSuccess timeout:0.5];
    
    
    [self prepare];
    [_wamp subscribe:@"com.asder.x" onEvent:^(id payload) {
        // nothing
    } result:^(NSError *error) {
        
        // triggering an error server side
        [_wamp unsubscribe:@"com.asder.x" result:^(NSError *error) {
            XCTAssertNotNil(error, @"Must call error");
            // Should fail instantly
            [self notify:kXCTUnitWaitStatusSuccess];
        }];
        
        MDWampUnsubscribe *un2 = [self msgFromTransportAndCheckIsA:[MDWampUnsubscribe class]];
        
        MDWampError *error2 = [[MDWampError alloc] initWithPayload:@[@34, un2.request, @{}, @"wamp.error.no_such_subscription"]];
        [_transport triggerDidReceiveMessage:[error2 marshallFor:kMDWampVersion2]];

    } ];
    
    MDWampSubscribe *sub3 = [self msgFromTransportAndCheckIsA:[MDWampSubscribe class]];
    MDWampSubscribed *subscribed2 = [[MDWampSubscribed alloc] initWithPayload:@[sub3.request, @12343234]];
    [_transport triggerDidReceiveMessage:[subscribed2 marshallFor:kMDWampVersion2]];
    
    
    [self waitForStatus:kXCTUnitWaitStatusSuccess timeout:0.5];
}


- (void)testCompletePublish {
    [_wamp publishTo:@"com.myapp.mytopic1"
                args:self.arrayPayload
                  kw:self.dictionaryPayload
             options:@{@"someoption":@"somevalue"}
              result:^(NSError *error) {
                  // check if publishing is OK or not
                  XCTAssertNil(error, @"No error must be triggered");
                  
                  MDWampPublish *msg = [self msgFromTransportAndCheckIsA:[MDWampPublish class]];
                  
                  XCTAssertEqualObjects(msg.argumentsKw, self.dictionaryPayload, @"Publish message sent to transport");
                  XCTAssertEqualObjects(msg.arguments, self.arrayPayload, @"Publish message sent to transport");
                  
                  [self notify:kXCTUnitWaitStatusSuccess];
              }];
    [self waitForStatus:kXCTUnitWaitStatusSuccess timeout:0.5];
}

@end
