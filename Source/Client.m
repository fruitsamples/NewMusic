/*

File: Client.m

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


#import "Client.h"
#import "Storage.h"
#import "WatcherApp.h"
#import "Album.h"
#import "Watcher.h"
#import "CoreDataUtils.h"
#import "mk.h"
#import "Logging.h"
#import <PubSub/PubSub.h>


static const CFTimeInterval kRefreshInterval = 6 * 60*60;        // Every 6 hours


@interface Client ()
@property (copy) NSDate *dateLastUpdated;
@end


@implementation Client


@dynamic dateLastUpdated;


+ (Client*) sharedInstance
{
    static Client* sInstance;
    if( ! sInstance ) {
        Log(@"Client: Fetching Client from db");
        NSManagedObjectContext *context = [[Storage sharedInstance] managedObjectContext];
        sInstance = (Client*) [context fetchUniqueObjectOfEntity: @"Client"];
        if( ! sInstance ) {
            Log(@"Client: Creating singleton instance");
            sInstance = [NSEntityDescription insertNewObjectForEntityForName: @"Client"
                                                      inManagedObjectContext:context];
        }
        [sInstance retain];
        [sInstance _getChanges];
    }
    return sInstance;
}


- (void) _setup
{
    _psClient = [[PSClient applicationClient] retain];
    _psClient.delegate = self;
    
    // Make sure default refresh interval is 6 hours:
    PSFeedSettings *settings = _psClient.settings;
    settings.refreshInterval = kRefreshInterval;
    _psClient.settings = settings;
    
    _watchers = [[NSMutableDictionary alloc] init];
    for( PSFeed *feed in _psClient.feeds ) {
        Watcher *watcher = [Watcher watcherWithFeed: feed];
        if( watcher )
            [_watchers setObject: watcher forKey: feed.URL];
    }
}

- (void)awakeFromFetch      {[self _setup];}
- (void)awakeFromInsert     {[self _setup];}

- (void)didTurnIntoFault
{
    [_watchers release];
    _watchers = nil;
    [_psClient release];
    _psClient = nil;
}


- (void) _getChanges
{
    if( self.dateLastUpdated ) {
        Log(@"Client: Checking for feed changes...");
        [_psClient sendChangesSinceDate: self.dateLastUpdated];
        Log(@"Client: ... Done checking for feed changes");
        
        self.dateLastUpdated = _psClient.dateLastUpdated;
    }
}


- (void) willSave
{
    // Before saving, make sure my dateLastUpdated is, er, up to date:
    NSDate *date = _psClient.dateLastUpdated;
    if( ! [date isEqual: self.dateLastUpdated] )
        self.dateLastUpdated = date;
    Log(@"Client: -willSave called (dateLastUpdate=%@)",date);
    
    [super willSave];
}


#pragma mark -
#pragma mark WATCHERS:


- (NSArray*) watchers
{
    return [_watchers allValues];
}

- (Watcher*) watcherWithFeedURL: (NSURL*)url
{
    return [_watchers objectForKey: url];
}

- (Watcher*) watcherWithFeed: (PSFeed*)feed
{
    return [_watchers objectForKey: feed.URL];
}


- (Watcher*) addWatcherWithFeedURL: (NSURL*)feedURL
{
    // Check whether it already exists:
    Watcher *watcher = [self watcherWithFeedURL: feedURL];
    if( ! watcher ) {
        // Get the PSFeed, subscribing if necessary:
        PSFeed *feed = [_psClient addFeedWithURL: feedURL];
        if( ! feed ) {
            [self release];
            return nil;
        }
        // Set refresh interval to 6 hours:
        PSFeedSettings *settings = feed.settings;
        settings.refreshInterval = kRefreshInterval;
        feed.settings = settings;
        
        // Instantiate Watcher:
        watcher = [Watcher watcherWithFeed: feed];
        if( watcher ) {
            [_watchers setObject: watcher forKey: feedURL];
            // Immediately process any existing entries:
            [self feed: feed didAddEntries: [feed entries]];
        }
    }
    return watcher;
}


- (void) removeWatcherWithFeedURL: (NSURL*)feedURL
{
    // Remove the Watcher object:
    Watcher *watcher = [self watcherWithFeedURL: feedURL];
    if( watcher ) {
        [watcher unsubscribe];
        [_watchers removeObjectForKey: feedURL];
    } else {
        // Just in case there was mistakenly no Watcher, explicitly unsubscribe from the feed:
        PSFeed *feed = [_psClient feedWithURL: feedURL];
        if( feed ) {
            Log(@"Client: Unsubscribing from <%@>",feedURL);
            [_psClient removeFeed: feed];
        }
    }
}


#pragma mark -
#pragma mark PSCLIENT DELEGATE:


//- (void) feedDidBeginRefresh:(PSFeed *)feed {Log(@"Client: %@ is updating",feed);}

//- (void) feedDidEndRefresh:(PSFeed *)feed   {Log(@"Client: %@ ended update",feed);}


- (void) feed:(PSFeed *)feed didAddEntries:(NSArray *)entries
{ 
    Watcher *watcher = [self watcherWithFeed: feed];
    if( ! watcher ) return;
    
    DisableLogs();
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    float i=0, n=entries.count;
    for( PSEntry *entry in entries ) {
        Log(@"=====Client: Creating Album for new %@",entry);
        [[WatcherApp sharedInstance] showBusySheet: [NSString stringWithFormat: @"Adding: %@",entry.title]
                                          progress: ++i/n];
        NSString *entryID = [entry identifier];
        Album *album = [Album albumWithEntryID: entryID];
        if( album )
            Warn(@"Already have Album for new PSEntry %@",entry);
        else {
            album = [Album createAlbumFromEntry: entry];
            if( ! [watcher updateAlbum: album fromEntry: entry] ) {
                Warn(@"Failed to create Album for %@",entry);
                [[[Storage sharedInstance] managedObjectContext] deleteObject: album];
            }
        }
    }
    EnableLogs();
    Log(@"Client: Added %u entries in %.3f sec", entries.count, CFAbsoluteTimeGetCurrent()-start);
    
    self.dateLastUpdated = nil; // force a change
    [[Storage sharedInstance] saveSoon];
}


- (void) feed:(PSFeed *)feed didUpdateEntries:(NSArray *)entries
{ 
    Watcher *watcher = [self watcherWithFeed: feed];
    if( ! watcher ) return;
    
    DisableLogs();
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    
    float i=0, n=entries.count;
    for( PSEntry *entry in entries ) {
        Album *album = [Album albumWithEntryID: [entry identifier]];
        if( album ) {
            Log(@"=====Client: Updating Album for %@",entry);
            [[WatcherApp sharedInstance] showBusySheet: [NSString stringWithFormat: @"Updating: %@",entry.title]
                                              progress: ++i/n];
            [watcher updateAlbum: album fromEntry: entry];
        } else
            Warn(@"Couldn't find Album for updated PSEntry %@",entry);
    }
    EnableLogs();
    Log(@"Client: Added %u entries in %.3f sec", entries.count, CFAbsoluteTimeGetCurrent()-start);
    
    self.dateLastUpdated = nil; // force a change
    [[Storage sharedInstance] saveSoon];
}

- (void) feed:(PSFeed *)feed didChangeFlagsInEntries:(NSArray *)entries
{ 
    for( PSEntry *entry in entries ) {
        Album *album = [Album albumWithEntryID: [entry identifier]];
        if( album ) {
            Log(@"Client: Updating Album flags for %@",entry);
            album.read = [entry isRead];
            album.flagged = [entry isFlagged];
        } else
            Log(@"WARNING: Couldn't find Album for updated PSEntry %@",entry);
    }
    
    self.dateLastUpdated = nil; // force a change
    [[Storage sharedInstance] saveSoon];
}
    
- (void) feed:(PSFeed *)feed didRemoveEntriesWithIdentifiers:(NSArray *)identifiers
{ 
    [[WatcherApp sharedInstance] showBusySheet: [NSString stringWithFormat: @"Removing old albums from %@",feed.title]
                                      progress: -1];
    for( NSString *entryID in identifiers ) {
        Album *album = [Album albumWithEntryID: entryID];
        if( album ) {
            // Leave the Album in the database; just disassociate it from the entry
            Log(@"Client: PSEntry %@ removed",entryID);
            album.entryID = nil;
        } else
            Log(@"WARNING: Couldn't find Album for removed PSEntry with ID %@",entryID);
    }
    
    self.dateLastUpdated = nil; // force a change
    [[Storage sharedInstance] saveSoon];
}


@end
