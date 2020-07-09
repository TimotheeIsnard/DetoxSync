//
//  DTXDispatchQueueSyncResource.m
//  DetoxSync
//
//  Created by Leo Natan (Wix) on 7/29/19.
//  Copyright © 2019 wix. All rights reserved.
//

#import "DTXDispatchQueueSyncResource-Private.h"
#import "DTXSyncManager-Private.h"
#import "_DTXObjectDeallocHelper.h"

@import ObjectiveC;

@implementation DTXDispatchBlockProxy
{
	NSString* _debugDescription;
	NSString* _operation;
}

+ (instancetype)proxyWithBlock:(dispatch_block_t)block operation:(NSString*)operation
{
	return [self proxyWithBlock:block operation:operation moreInfo:nil];
}

+ (instancetype)proxyWithBlock:(dispatch_block_t)block operation:(NSString*)operation moreInfo:(NSString*)moreInfo
{
	DTXDispatchBlockProxy* rv = [DTXDispatchBlockProxy new];
	
	if(rv)
	{
		rv->_operation = operation;
		
		rv->_debugDescription = [NSString stringWithFormat:@"%@%@ with %@", moreInfo == nil ? @"" : [NSString stringWithFormat:@"(%@)", moreInfo], operation, [block debugDescription]];
	}
	
	return rv;
}

- (NSString *)description
{
	return _debugDescription;
}

- (NSString *)debugDescription
{
	return _debugDescription;
}

@end

static const void* DTXQueueDeallocHelperKey = &DTXQueueDeallocHelperKey;

@implementation DTXDispatchQueueSyncResource
{
	NSUInteger _busyCount;
	NSMutableArray* _busyBlocks;
	__weak dispatch_queue_t _queue;
}

+ (void)__superload
{
	@autoreleasepool
	{
		DTXDispatchQueueSyncResource* mainQueueSync = [DTXDispatchQueueSyncResource dispatchQueueSyncResourceWithQueue:dispatch_get_main_queue()];
		[DTXSyncManager registerSyncResource:mainQueueSync];
	}
}

+ (instancetype)dispatchQueueSyncResourceWithQueue:(dispatch_queue_t)queue
{
	DTXDispatchQueueSyncResource* rv = [self _existingSyncResourceWithQueue:queue];
	
	if(rv != nil)
	{
		return rv;
	}
	
	rv = [DTXDispatchQueueSyncResource new];
	rv->_queue = queue;
	_DTXObjectDeallocHelper* dh = [[_DTXObjectDeallocHelper alloc] initWithSyncResource:rv];
	objc_setAssociatedObject(queue, DTXQueueDeallocHelperKey, dh, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	
	return rv;
}

+ (instancetype)_existingSyncResourceWithQueue:(dispatch_queue_t)queue
{
	return (id)[((_DTXObjectDeallocHelper*)objc_getAssociatedObject(queue, DTXQueueDeallocHelperKey)) syncResource];
}

- (instancetype)init
{
	self = [super init];
	if(self)
	{
		_busyBlocks = [NSMutableArray new];
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@: %p queue: %@ work blocks: %@>", self.class, self, _queue, _busyBlocks];
}

- (NSString*)syncResourceDescription
{
	return [NSString stringWithFormat:@"%lu work blocks on dispatch queue “%@”", (unsigned long)_busyCount, _queue];
}

- (NSString*)syncResourceGenericDescription
{
	return @"Dispatch Queue";
}

- (void)addWorkBlockProxy:(DTXDispatchBlockProxy*)blockProxy operation:(NSString*)operation
{
	[self performUpdateBlock:^NSUInteger{
		_busyCount += 1;
#if DEBUG
		NSAssert([_busyBlocks containsObject:blockProxy] == NO, @"Tried to add a duplicate block proxy");
#endif
		[_busyBlocks addObject:blockProxy];
		return _busyCount;
	} eventIdentifier:[NSString stringWithFormat:@"%p", blockProxy] eventDescription:self.syncResourceGenericDescription objectDescription:[self _descriptionForOperation:operation block:blockProxy] additionalDescription:nil];
}

- (void)removeWorkBlockProxy:(DTXDispatchBlockProxy*)blockProxy operation:(NSString*)operation
{
	[self performUpdateBlock:^NSUInteger{
		_busyCount -= 1;
#if DEBUG
		NSAssert([_busyBlocks containsObject:blockProxy], @"Tried to remove a block proxy that doesn't exist");
#endif
		[_busyBlocks removeObject:blockProxy];
		return _busyCount;
	} eventIdentifier:[NSString stringWithFormat:@"%p", blockProxy] eventDescription:self.syncResourceGenericDescription objectDescription:[self _descriptionForOperation:operation block:blockProxy] additionalDescription:nil];
}

- (NSString*)_descriptionForOperation:(NSString*)op block:(id)block
{
	return [NSString stringWithFormat:@"%@ on “%@”", op, _queue];
}

- (void)dealloc
{
	if(_queue == nil)
	{
		return;
	}
	
	objc_setAssociatedObject(_queue, DTXQueueDeallocHelperKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
