/*

File: WatcherApp.m

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


#import "WatcherApp.h"
#import "Watcher.h"
#import "Client.h"
#import "Album.h"
#import "Storage.h"
#import "SubscriptionsController.h"
#import "mk.h"
#import "ContentFormatting.h"
#import "Logging.h"


@implementation WatcherApp


@synthesize storage=_storage;
@synthesize trackURLs=_trackURLs;


+ (void) initialize
{
    RegisterValueTransformers();
}


+ (WatcherApp*) sharedInstance
{
    return [NSApp delegate];
}


- (void) awakeFromNib
{
    [self setSortMode: 0];

    [_table setDelegate: self];
    [_table setDoubleAction: @selector(playSample:)];
    
    NSSortDescriptor *sort = [[_filterTable tableColumnWithIdentifier: @"name"] sortDescriptorPrototype];
    [_filterTable setSortDescriptors: mkarray(sort)];
    
    [_playButton setKeyEquivalent: @" "]; // somehow can't do this in IB
    
    Log(@"WatcherApp awakeFromNib! Showing busy sheet...");
    [_mainWindow makeKeyAndOrderFront: self];
    [self showBusySheet: @"Loading Database..." progress: -1];

    // Need to set this, else the controllers complain during setup
    [_albumsController setManagedObjectContext: [_storage managedObjectContext]];
    [_filterController setManagedObjectContext: [_storage managedObjectContext]];
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    Log(@"WatcherApp appDidFinishLaunching");
    // Wake up model by getting the shared Client object.
    NSArray *watchers = [Client sharedInstance].watchers;
    if( watchers.count == 0 ) {
        // If there are no Watchers (subscriptions), open the subscriptions sheet:
        [_subscriptionsController changeSubscriptions: self];
    } else if( [[Client sharedInstance] isInserted] ) {
        // Database was lost, so re-scan:
        Log(@"Re-scanning feeds...");
        for( Watcher *watcher in watchers )
            [watcher rescan];
    }
}


/**
 Returns the NSUndoManager for the application.  In this case, the manager
 returned is that of the managed object context for the application.
 */

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return [_storage undoManager];
}


/**
 Performs the save action for the application, which is to send the save:
 message to the application's managed object context.  Any encountered errors
 are presented to the user.
 */

- (IBAction) saveAction:(id)sender {
    
    [_storage save];
}


/**
 Implementation of the applicationShouldTerminate: method, used here to
 handle the saving of changes in the application managed object context
 before the application terminates.
 */

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    return [_storage applicationShouldTerminate];
}


- (void) showBusySheet: (NSString*)message progress: (float)progress
{
    if( ! [_mainWindow attachedSheet] ) {
        Log(@"WatcherApp: showBusySheet");
        [NSApp beginSheet: _busySheet modalForWindow: _mainWindow
            modalDelegate: self didEndSelector: NULL contextInfo: NULL];
        [_busyIndicator setUsesThreadedAnimation: YES];
        [_busyIndicator startAnimation: self];
        _busyMessageLastShown = 0;
        // Take the sheet down when the runloop is unblocked again:
        [self performSelector: @selector(endBusySheet) withObject: nil afterDelay: 0.0];
        
        // Disconnect the NSArrayControllers while the model is busy.
        // Otherwise they'll rebuild themselves every time an object is added to
        // the store, which is incredibly expensive.
        [_albumsController setManagedObjectContext: nil];
        [_filterController setManagedObjectContext: nil];
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if( now-_busyMessageLastShown > 0.15 || progress>=1.0 ) {
        [_busyIndicator setIndeterminate: (progress<0)];
        [_busyIndicator setDoubleValue: progress];
        [_busyMessage setStringValue: (message ?: @"Updating Database...")];
        [_busySheet displayIfNeeded];
        _busyMessageLastShown = now;
    }
}

- (void) endBusySheet
{
    Log(@"WatcherApp: endBusySheet");
    [_busyMessage setStringValue: @"Updating Display..."];
    [_busySheet displayIfNeeded];

    // Reconnect the NSArrayControllers now that the operation is over.
    [_albumsController setManagedObjectContext: [_storage managedObjectContext]];
    [_filterController setManagedObjectContext: [_storage managedObjectContext]];

    // Make them reload the changed data immediately. This can be slow, so we
    // want it to happen while the sheet is still up.
    [_albumsController prepareContent];
    [_filterController prepareContent];
    
    // Redraw the window (this can be slow too)
    [_mainWindow displayIfNeeded];
    
    // Then once everything's finished, take down the sheet.
    [NSApp endSheet: _busySheet];
    [_busySheet orderOut: self];
    [_busyIndicator stopAnimation: self];
    Log(@"WatcherApp: ...done with endBusySheet");
}


#pragma mark -
#pragma mark SELECTION / SORT:


- (Album*) selectedAlbum
{
    NSArray *sel = [_albumsController selectedObjects];
    if( [sel count] > 0 )
        return [sel objectAtIndex: 0];
    else
        return nil;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self stopSample];
    [_qtView setHidden: YES];
    [_qtView setMovie: nil];
}


- (void) setSortMode: (int)sortMode
{
    static NSString *const kSortKeysByMode[2] = {@"read,dateAdded", @"artist.nameForSorting"};
    NSArray *keys = [kSortKeysByMode[sortMode] componentsSeparatedByString: @","];
    NSMutableArray *sorts = [NSMutableArray array];
    for( NSString *key in keys  ) {
        BOOL ascending = ! [key isEqualToString: @"dateAdded"];     // dateAdded is descending
        NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey: key
                                                             ascending: ascending];
        [sorts addObject: sort];
        [sort release];
    }
    [_albumsController setSortDescriptors: sorts];
}


#pragma mark -
#pragma mark DRAWER:


- (void) _setFilterSelectionToShowAlbum: (Album*)album
{
    Log(@"SetFilterSelectionToShowAlbum: %@",album);
    id sel = nil;
    if( album ) {
        switch( [_filterSelector selectedSegment] ) {
            case 0: sel = [album artist]; break;
            case 1: sel = [[album genres] allObjects]; break;
            case 2: sel = [album label]; break;
        }
    }
    
    if( sel &&  ![sel isKindOfClass: [NSArray class]] )
        sel = mkarray(sel);
    Log(@"    -selecting %@",[sel description]);
    [_filterController setSelectedObjects: sel];
    Log(@"    -now selection (of %u items) = %@",
        [[_filterController arrangedObjects] count],[[_filterController selectedObjects] description]);
}


- (void) _forceUpdateController: (NSArrayController*)controller
{
    // Force the array controller to reload immediately, so _setFilterSelectionToShowAlbum will work.
    // (normally, it only reloads after a delay)
    NSError *error = nil;
    [controller fetchWithRequest: nil merge: NO error: &error];
    if( error ) {Log(@"fetchWithRequest failed: %@",error);}
    [controller prepareContent];
}


- (void) _setFilterEntity: (NSString*)entity
{
    Log(@"SetFilterEntity: %@",entity);
    [_filterController setEntityName: entity];
    
    // Force the array controller to reload immediately, so _setFilterSelectionToShowAlbum will work.
    // (normally, it only reloads after a delay)
    [self _forceUpdateController: _filterController];
}


- (void)drawerWillOpen:(NSNotification *)notification
{
    Log(@"Filtering albums now");
    [self _setFilterSelectionToShowAlbum: self.selectedAlbum]; 
    [_albumsController bind: @"contentArray"
                   toObject: _filterController
                withKeyPath: @"selectedObjects.@distinctUnionOfSets.albums"
                    options: nil];
}


- (void)drawerDidClose:(NSNotification *)notification
{
    Log(@"Not filtering albums anymore");
    [_albumsController unbind: @"contentArray"];
    [_albumsController prepareContent];
}


// invoked by the segmented control
- (IBAction) selectFilter: (id)sender
{
    static NSString* kEntities[3] = {@"Artist", @"Genre", @"Label"};

    Album *selectedAlbum = self.selectedAlbum;
    [self _setFilterEntity: kEntities[ [_filterSelector selectedSegment] ] ];
    [self _setFilterSelectionToShowAlbum: selectedAlbum]; 
    [_albumsController prepareContent];
    //[self _forceUpdateController: _albumsController];
    if( selectedAlbum )
        [_albumsController setSelectedObjects: mkarray(selectedAlbum)];
    Log(@"Finally filter selection = %@",[[_filterController selectedObjects] description]);
    Log(@"Finally albums selection = %@\n",[[_albumsController selectedObjects] description]);
}


#pragma mark -
#pragma mark ACTIONS:


- (IBAction) toggleAlbumState: (id)sender
{
    Album *album = self.selectedAlbum;
    if( album ) {
        album.read = ! album.read;
        [_albumsController rearrangeObjects];
    }
}

- (IBAction) toggleAlbumFlag: (id)sender
{
    Album *album = self.selectedAlbum;
    if( album ) {
        album.flagged = ! album.flagged;
        [_albumsController rearrangeObjects];
    }
}


- (IBAction) markAllRead: (id)sender
{
    for( Album *album in [_albumsController arrangedObjects] )
        if( ! album.read )
            album.read = YES;
    [_albumsController rearrangeObjects];
}


- (IBAction) changeSort: (id)sender
{
    [self setSortMode: [sender tag]];
}


- (IBAction) openInBrowser: (id)sender
{
    NSURL *url = self.selectedAlbum.webURL;
    Log(@"Opening album URL <%@>",url);
    [[NSWorkspace sharedWorkspace] openURL: url];
}


- (void) stopSample
{
    [_qtView pause: self];
    [_playButton setState: 0];
    [_playButton setTitle: @"Listen"];
}


- (void) playSample: (id)sender
{
    QTMovie *movie = [_qtView movie];
    if( movie && [movie rate] > 0 ) {
        // If a sample is playing, stop it
        [self stopSample];
    } else {
        if( ! movie ) {
            // If a sample's not already loaded, get one:
            self.trackURLs = self.selectedAlbum.trackSampleURLs;
            if( ! [self.trackURLs count] ) {
                NSBeep();
                return;
            }
            NSURL *url = [self.trackURLs objectAtIndex: 0];
            
            Log(@"Playing MP3 sample from <%@>",url);
            NSError *error = nil;
            movie = [QTMovie movieWithURL: url error: &error];
            if( ! movie ) {
                Log(@"Error: Couldn't create QTMovie: %@",error);
                NSBeep();
                return;
            }
            [_qtView setMovie: movie];
            [_qtView gotoBeginning: self];
        }
        // Play the sample:
        [_qtView setHidden: NO];
        [movie autoplay];
        [_playButton setTitle: @"Pause"];
    }
}


- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
    SEL action = [anItem action];
    if( action == @selector(playSample:) )
        return self.selectedAlbum.trackSampleURLs != nil;
    else if( action == @selector(openInBrowser:) )
        return self.selectedAlbum.webURL != nil;
    else if( action == @selector(toggleAlbumState:) || action == @selector(toggleAlbumFlag:) )
        return self.selectedAlbum != nil;
    else
        return YES;
}


@end
