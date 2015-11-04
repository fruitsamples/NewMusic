/*

File: Watcher.m

Abstract: Use the PubSub framework to create a music new release browser.

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
Apple Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.  If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software. 
Neither the name, trademarks, service marks or logos of Apple Inc. 
may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.  Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright © 2006-2007 Apple Inc. All Rights Reserved.

*/

#import "Watcher.h"
#import "Client.h"
#import "Album.h"
#import "ITMSWatcher.h"
#import "EMusicWatcher.h"
#import "Storage.h"
#import "Logging.h"
#import <PubSub/PubSub.h>


@implementation Watcher


+ (BOOL) handlesFeedURL: (NSURL*)url;
{
    // subclass must override
    return NO;
}

+ (BOOL) updateAlbum: (Album*)album fromEntry: (PSEntry*)entry;
{
    // subclass must override
    return NO;
}


+ (Watcher*) allocForFeedURL: (NSURL*)feedURL
{
    if( [ITMSWatcher handlesFeedURL: feedURL] )
        return [ITMSWatcher alloc];
    else if( [EMusicWatcher handlesFeedURL: feedURL] )
        return [EMusicWatcher alloc];
    else {
        Log(@"ERROR: Don't know how to watch <%@>",feedURL);
        return nil;
    }
}


- (id) initWithFeed: (PSFeed*)feed
{
    self = [super init];
    if( self ) {
        _feed = [feed retain];
        Log(@"Instantiated %@ <%@>",[self class],feed.URL);
    }
    return self;
}


- (void) dealloc
{
    [_feed release];
    [super dealloc];
}


+ (Watcher*) watcherWithFeed: (PSFeed*)feed
{
    NSURL *url = feed.URL;
    if( [ITMSWatcher handlesFeedURL: url] )
        return [[ITMSWatcher alloc] initWithFeed: feed];
    else if( [EMusicWatcher handlesFeedURL: url] )
        return [[EMusicWatcher alloc] initWithFeed: feed];
    else {
        Log(@"ERROR: Don't know how to watch <%@>",url);
        return nil;
    }
}


@synthesize feed=_feed;


- (void) rescan
{
    [[Client sharedInstance] feed: _feed didAddEntries: [_feed entries]];
}


- (BOOL) updateAlbum: (Album*)album fromEntry: (PSEntry*)entry
{
    NSAssert1(NO,@"%@ forgot to implement -updateAlbum:fromEntry:",[self class]);
    return NO;
}


- (void) unsubscribe
{
    Log(@"%@: unsubscribing from %@",[self class],_feed);
    
    // Remove Albums:
    for( PSEntry *entry in _feed.entries ) {
        Album *album = [Album albumWithEntryID: entry.identifier];
        if( album ) {
            Log(@"    Removing %@",album);
            [[album managedObjectContext] deleteObject: album];
        }
    }
    [[Storage sharedInstance] saveSoon];
    
    // Unsubscribe from the feed:
    [[PSClient applicationClient] removeFeed: _feed];
    [_feed release];
    _feed = nil;
}


@end
