//
//  MDWampMessage.m
//  iOS_WAMP_Test
//
//  Created by pronk on 13/09/12.
//  Copyright (c) 2012 mogui. All rights reserved.
//


#import "MDWampMessage.h"
#import "MDJSONBridge.h"
@implementation MDWampMessage
@synthesize type;



/*
 * return the first element from the messageStack and removes it from the stack
 * it retain the object!!!
 */
- (id) shiftStack
{
	__autoreleasing id object = [messageStack objectAtIndex:0];
	[messageStack removeObjectAtIndex:0];
	return object;
}

- (int) shiftStackAsInt
{
	return [[self shiftStack] intValue];
}

- (NSString*) shiftStackAsString
{
	return (NSString*)[self shiftStack];
}

- (NSArray*) getRemainingArgs
{
	return [NSArray arrayWithArray:messageStack];
}

- (id) initWithResponseArray:(NSArray*)responseArray
{
	self = [super init];
	if (self) {
		messageStack = [[NSMutableArray alloc] initWithArray: responseArray];
		type = [[self shiftStack] intValue];
	}
	return self;
}

- (id) initWithResponse:(NSString*)response
{
	NSArray *responseArray = (NSArray*)[MDJSONBridge objectFromJSONString:response];
	return [self initWithResponseArray:responseArray];
}


@end
