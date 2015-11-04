/*

File: Watchers.m

Abstract: Use the PubSub framework to create a music new release browser.

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Computer, Inc. ("Apple") in consideration of your agreement to the
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
Neither the name, trademarks, service marks or logos of Apple Computer,
Inc. may be used to endorse or promote products derived from the Apple
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

Copyright © 2006 Apple Computer, Inc., All Rights Reserved

*/


#import "Watchers.h"
#import "Watcher.h"
#import "Album.h"
#import <PubSub/PubSub.h>


@implementation Watchers


- (id) init {
    self = [super init];
    if (self != nil) {
        _watchers = [[NSMutableDictionary alloc] init];
        _albums = [[NSMutableSet alloc] init];
    }
    return self;
}


- (id) initWithCoder: (NSCoder*)decoder
{
    self = [super init];
    if( self ) {
        if( [decoder decodeIntForKey: @"version"] < kSchemaVersion ) {
            NSLog(@"Saved data is out-of-date: not using it");
            [self release];
            return nil;
        }
        _watchers = [[decoder decodeObjectForKey: @"watchers"] mutableCopy];
        _albums = [[NSMutableSet alloc] init];
        for( Watcher *watcher in [_watchers allValues] ) {
            [watcher setOwner: self];
            [self _addAlbums: [NSSet setWithArray: [watcher albums]]];
        }
        NSDate *lastUpdated = [decoder decodeObjectForKey: @"lastUpdated"];
        if( lastUpdated )
            [self performSelector: @selector(_getUpdates:) withObject: lastUpdated];
    }
    return self;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
    NSDate *lastUpdated = [[PSClient applicationClient] dateLastUpdated];
    [coder encodeInt: kSchemaVersion forKey: @"version"];
    [coder encodeObject: _watchers forKey: @"watchers"];
    [coder encodeObject: lastUpdated forKey: @"lastUpdated"];
}


- (void) _getUpdates: (NSDate*)lastUpdated
{
    NSLog(@"Watchers: Getting updates since %@",lastUpdated);
    [[PSClient applicationClient] setDelegate: self];   // should not be necessary, but currently is
    [[PSClient applicationClient] sendChangesSinceDate: lastUpdated];
}


- (Watcher*) addWatcherWithFeedURL: (NSURL*)feedURL
{
    Watcher *w = [_watchers objectForKey: feedURL];
    if( ! w ) {
        w = [Watcher watcherWithFeedURL: feedURL];
        if( w ) {
            [_watchers setObject: w forKey: feedURL];
            [w setOwner: self];
            _changed = YES;
        }
    }
    return w;
}


- (NSSet*) albums
{
    NSLog(@"albums = (%u)", [_albums count]);
    return _albums;
}


- (void) _addAlbums: (NSSet*)albums
{
    [self willChangeValueForKey: @"albums"
                withSetMutation: NSKeyValueUnionSetMutation
                   usingObjects: albums];
    [_albums unionSet: albums];
    [self didChangeValueForKey: @"albums"
               withSetMutation: NSKeyValueUnionSetMutation
                  usingObjects: albums];
}


- (void) watcher: (Watcher*)w updatedAlbum: (Album*)album
{
    _changed = YES;
}

- (void) watcher: (Watcher*)w addedAlbum: (Album*)album
{
    _changed = YES;
    [self _addAlbums: [NSSet setWithObject: album]];
}

- (BOOL) isChanged
{
    return _changed;
}


// PSClient delegate methods
- (void) feedDidBeginUpdate:(PSFeed *)feed  {NSLog(@"Watchers: %@ is updating",feed);}
- (void) feedDidEndUpdate:(PSFeed *)feed    {NSLog(@"Watchers: %@ ended update",feed);}
- (void) feedDidFailUpdate:(PSFeed *)feed
                 withError:(NSError *)error {NSLog(@"Watchers: %@ failed update (%@)",feed,error);}

- (void) feed:(PSFeed *)feed didAddEntries:(NSArray *)entries { }
- (void) feed:(PSFeed *)feed didRemoveEntriesWithIdentifiers:(NSArray *)identifiers { }
- (void) feed:(PSFeed *)feed didUpdateEntries:(NSArray *)entries { }
- (void) feed:(PSFeed *)feed didFlagEntries:(NSArray *)entries { }


@end
