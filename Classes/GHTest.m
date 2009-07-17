//
//  GHTest.m
//  GHKit
//
//  Created by Gabriel Handford on 1/18/09.
//  Copyright 2009. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

//
// Portions of this file fall under the following license, marked with:
// GTM_BEGIN : GTM_END
//
//  Copyright 2008 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not
//  use this file except in compliance with the License.  You may obtain a copy
//  of the License at
// 
//  http://www.apache.org/licenses/LICENSE-2.0
// 
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
//  License for the specific language governing permissions and limitations under
//  the License.

#import "GHTest.h"

#import "GHTesting.h"

NSString* NSStringFromGHTestStatus(GHTestStatus status) {
	switch(status) {
		case GHTestStatusNone: return NSLocalizedString(@"Waiting", nil);
		case GHTestStatusRunning: return NSLocalizedString(@"Running", nil);
		case GHTestStatusCancelling: return NSLocalizedString(@"Cancelling", nil);
		case GHTestStatusSucceeded: return NSLocalizedString(@"Succeeded", nil); 
		case GHTestStatusErrored: return NSLocalizedString(@"Errored", nil);
		case GHTestStatusCancelled: return NSLocalizedString(@"Cancelled", nil);
		case GHTestStatusDisabled: return NSLocalizedString(@"Disabled", nil);
			
		default: return NSLocalizedString(@"Unknown", nil);
	}
}

GHTestStats GHTestStatsMake(NSInteger succeedCount, NSInteger failureCount, NSInteger disabledCount, NSInteger cancelCount, NSInteger testCount) {
	GHTestStats stats;
	stats.succeedCount = succeedCount;
	stats.failureCount = failureCount; 
	stats.disabledCount = disabledCount;
	stats.cancelCount = cancelCount;	
	stats.testCount = testCount;
	return stats;
}

const GHTestStats GHTestStatsEmpty = {0, 0, 0, 0, 0};

NSString *NSStringFromGHTestStats(GHTestStats stats) {
	return [NSString stringWithFormat:@"%d/%d/%d/%d/%d", stats.succeedCount, stats.failureCount, 
					stats.disabledCount, stats.cancelCount, stats.testCount]; 
}


BOOL GHTestStatusIsRunning(GHTestStatus status) {
	return (status == GHTestStatusRunning || status == GHTestStatusCancelling);
}

BOOL GHTestStatusEnded(GHTestStatus status) {
	return (status == GHTestStatusSucceeded 
					|| status == GHTestStatusErrored
					|| status == GHTestStatusCancelled
					|| status == GHTestStatusDisabled);
}

@implementation GHTest

@synthesize delegate=delegate_, target=target_, selector=selector_, name=name_, interval=interval_, 
exception=exception_, status=status_, log=log_, identifier=identifier_;

- (id)initWithTarget:(id)target selector:(SEL)selector {
	if ((self = [super init])) {
		target_ = [target retain];
		selector_ = selector;
		interval_ = -1;
		name_ = [NSStringFromSelector(selector_) copy];
		status_ = GHTestStatusNone;
		identifier_ = [[NSString stringWithFormat:@"%@/%@", NSStringFromClass([target_ class]), NSStringFromSelector(selector_)] copy];
	}
	return self;	
}

+ (id)testWithTarget:(id)target selector:(SEL)selector {
	return [[[self alloc] initWithTarget:target selector:selector] autorelease];
}

- (void)dealloc {
	[name_ release];
	[target_ release];
	[exception_ release];
	[log_ release];
	[identifier_ release];
	[super dealloc];
}

- (BOOL)isEqual:(id)test {
	return ((test == self) || 
					([test conformsToProtocol:@protocol(GHTest)] && 
					 [self.identifier isEqual:[test identifier]]));
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ %@", self.identifier, [super description]];
}

- (void)setLogWriter:(id<GHTestCaseLogWriter>)logWriter {
	if ([target_ respondsToSelector:@selector(setLogWriter:)])
		[target_ setLogWriter:logWriter];
}	

- (GHTestStats)stats {
	switch(status_) {
		case GHTestStatusSucceeded: return GHTestStatsMake(1, 0, 0, 0, 1);
		case GHTestStatusErrored: return GHTestStatsMake(0, 1, 0, 0, 1);
		case GHTestStatusDisabled: return GHTestStatsMake(0, 0, 1, 0, 1);
		case GHTestStatusCancelled: return GHTestStatsMake(0, 0, 0, 1, 1);
		default:
			return GHTestStatsMake(0, 0, 0, 0, 1);
	}
}

- (void)reset {
	status_ = GHTestStatusNone;
	[delegate_ testDidUpdate:self source:self];
}

- (void)cancel {
	if (status_ == GHTestStatusRunning) {
		status_ = GHTestStatusCancelling;
		// TODO(gabe): Call cancel on target if available?		
	} else {
		status_ = GHTestStatusCancelled;
	}
	[delegate_ testDidUpdate:self source:self];
}

- (void)disable {
	status_ = GHTestStatusDisabled;
	[delegate_ testDidUpdate:self source:self];
}

- (void)setException:(NSException *)exception {
	[exception retain];
	[exception_ release];
	exception_ = exception;
	status_ = GHTestStatusErrored;
	[delegate_ testDidUpdate:self source:self];
}

- (void)run {
	if (status_ == GHTestStatusDisabled) return;
	
	status_ = GHTestStatusRunning;
	
	[delegate_ testDidStart:self source:self];
	
	[self setLogWriter:self];

	[GHTesting runTest:target_ selector:selector_ withObject:nil exception:&exception_ interval:&interval_];
	
	[self setLogWriter:nil];

	if (exception_) {
		status_ = GHTestStatusErrored;
	}

	if (status_== GHTestStatusCancelling) {
		status_ = GHTestStatusCancelled;
	} else if (status_ == GHTestStatusRunning) {
		status_ = GHTestStatusSucceeded;
	}
	[delegate_ testDidEnd:self source:self];
}

- (void)log:(NSString *)message testCase:(id)testCase {
	if (!log_) log_ = [[NSMutableArray array] retain];
	[log_ addObject:message];
	[delegate_ test:self didLog:message source:self];
}

@end
