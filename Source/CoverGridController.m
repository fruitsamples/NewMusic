/*

File: CoverGridController.m

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


#import "CoverGridController.h"
#import "Album.h"
#import "Cover.h"
#import "Artist.h"
#import "WatcherApp.h"
#import "mk.h"
#import "Logging.h"

#import <Quartz/Quartz.h>   // For IKImageBrowserView.h


#define kTitleFont @"Arial Narrow"


// Implements the IKImageBrowserItem informal protocol
@interface CoverGridItem : NSObject
{
    Album *_album;
    NSUInteger _index;
}
- (id) initWithAlbum: (Album*)album index: (NSUInteger)i;
- (NSString *)  imageUID; 
- (NSString *) imageRepresentationType;
- (id) imageRepresentation;
- (NSString *) imageTitle;
- (NSString *) imageSubtitle;
@end



@implementation CoverGridController


- (void) _setFontNamed: (NSString*)name size: (float)size style: (NSFontTraitMask)style
                 white: (float)white 
                forKey: (NSString*)key
{
    int weight = (style & NSBoldFontMask) ?10 :5;
    NSFont *font = [[NSFontManager sharedFontManager] fontWithFamily: name traits: style weight: weight size: size];
    if( font ) {
        NSMutableDictionary *attrs = [[_browser valueForKey: key] mutableCopy];
        
        [attrs setObject: font forKey: NSFontAttributeName];
        
        NSColor *color = [NSColor colorWithCalibratedRed: white green: white blue: white alpha: 1.0];
        [attrs setObject: color forKey: NSForegroundColorAttributeName];
        
        [_browser setValue: attrs forKey: key];
        [attrs release];
    }
}


- (void) awakeFromNib
{
    [_browser setCellsStyleMask: (IKCellsStyleOutlined | IKCellsStyleShadowed 
                                  | IKCellsStyleTitled | IKCellsStyleSubtitled)];
    [_browser setAnimates: NO];
    
    // Customize browser fonts:
    [self _setFontNamed: kTitleFont size:14 style: NSBoldFontMask   white: 0.0  forKey: IKImageBrowserCellsTitleAttributesKey];
    [self _setFontNamed: kTitleFont size:14 style: NSBoldFontMask   white: 0.0  forKey: IKImageBrowserCellsHighlightedTitleAttributesKey];
    [self _setFontNamed: kTitleFont size:13 style: NSItalicFontMask white: 0.25 forKey: IKImageBrowserCellsSubtitleAttributesKey];
        
    // Restore the cover image size:
    [_browser setConstrainsToOriginalSize: NO];
    id sizeObj = [[NSUserDefaults standardUserDefaults] objectForKey: @"GridCellSize"];
    float size = sizeObj ?[sizeObj floatValue] :128.0;
    [_browser setCellSize: NSMakeSize(size,size)];
    [_zoomSlider setFloatValue: [_browser zoomValue]];
    
    // Register for notifications:
    [_albumsController addObserver: self forKeyPath: @"arrangedObjects"
                                            options: 0
                                            context: @selector(_controllerContentsChanged:)];
    [_albumsController addObserver: self forKeyPath: @"selectionIndexes"
                                            options: 0
                                            context: @selector(_controllerSelectionChanged:)];
    /*
    [_albumsController addObserver: self forKeyPath: @"arrangedObjects.read"
                                            options: 0
                                            context: @selector(_albumFlagsChanged:)];
    [_albumsController addObserver: self forKeyPath: @"arrangedObjects.flagged"
                                            options: 0
                                            context: @selector(_albumFlagsChanged:)];
     */
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object 
                        change:(NSDictionary *)change 
                       context:(void *)context
{
    [self performSelector: (SEL)context withObject: change];
}


#pragma mark -
#pragma mark Data Model:


- (NSArray*) albums
{
    return [_albumsController arrangedObjects];
}


- (void) _clearGroups
{
    [_groups release];
    _groups = [[NSMutableArray alloc] init];
}


/* Adds a new group, starting at the given index. */
- (void) _addGroupAt: (NSUInteger)i style: (int)style color: (NSColor*)bgColor title: (NSString*)title
{
    NSMutableDictionary *group;
    group = [_groups lastObject];
    if( group ) {
        // Truncate previous group's range:
        NSRange r = [[group objectForKey: IKImageBrowserGroupRangeKey] rangeValue];
        r.length = i - r.location;
        [group setObject: [NSValue valueWithRange: r]
                  forKey: IKImageBrowserGroupRangeKey];
    }
    // Add new group:
    group = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                  [NSValue valueWithRange: NSMakeRange(i,[[self albums] count]-i)], IKImageBrowserGroupRangeKey,
                  [NSNumber numberWithInt: style], IKImageBrowserGroupStyleKey,
                  nil];
    if( bgColor )
        [group setObject: bgColor forKey: IKImageBrowserGroupBackgroundColorKey];
    if( title )
        [group setObject: title forKey: IKImageBrowserGroupTitleKey];
    [_groups addObject: group];
}


/* Group items together by 'isRead' flag value (to give them a bg color). */
- (void) _groupByFlags
{
    static NSColor *sUnreadColor,*sFlaggedColor, *sPlainColor;
    if( ! sUnreadColor ) {
        sUnreadColor = [[[NSColor blueColor] colorWithAlphaComponent: 0.3] retain];
        sFlaggedColor= [[[NSColor  redColor] colorWithAlphaComponent: 0.3] retain];
        sPlainColor  = [[NSColor clearColor] retain];
    }

    [self _clearGroups];    
    int i=0, prevRead=-1;
    for( Album *album in [self albums] ) {
        int isRead = album.read;
        if( isRead != prevRead ) {
            // Start a new group:
            prevRead = isRead;
            NSColor *bg = isRead ?sPlainColor :sUnreadColor;
            [self _addGroupAt: i style: IKGroupBezelStyle color: bg title: nil];
        }
        i++;
    }
}


/* Group items by first letter of artist name. */
- (void) _groupByArtist
{
    [self _clearGroups];    
    int i=0;
    NSString* prevFirst = nil;
    for( Album *album in [self albums] ) {
        NSString *first = [album.artist.nameForSorting substringToIndex: 1];
        if( [first characterAtIndex: 0] < 'A' )
            first = @"0...9";
        if( ! [prevFirst isEqualToString: first] ) {
            // Start a new group:
            prevFirst = first;
            [self _addGroupAt: i style: IKGroupDisclosureStyle color: nil title: first];
        }
        i++;
    }
}


#pragma mark -
#pragma mark Notifications & Updating:


/* Make the browser's selection match the array controller's selection */
- (void) _matchControllerSelection
{
    NSIndexSet *newSel = [_albumsController selectionIndexes];
    if( ! [newSel isEqual: [_browser selectionIndexes]] ) {
        Log(@"CoverGridController: Updating selection (#%u)", [_albumsController selectionIndex]);
        [_browser setSelectionIndexes: newSel byExtendingSelection: NO];
    }
    if( [newSel count] ) {
        Log(@"CoverGridController: Scrolling #%u to visible",[newSel firstIndex]);
        [_browser scrollIndexToVisible: [newSel firstIndex]];
    }
}


/* Reload the data of the browser, from the array controller */
- (void) reload
{
    Log(@"CoverGridController: reloading...");
    if( [[[[_albumsController sortDescriptors] objectAtIndex: 0] key] isEqualToString: @"artist.nameForSorting"] )
        _groupSel = @selector(_groupByArtist);
    else
        _groupSel = @selector(_groupByFlags);
    [self performSelector: _groupSel];
    
    _reloading = YES;
    @try{
        [_browser reloadData];
        [self _matchControllerSelection];
    }@finally{
        _reloading = NO;
    }
}    


- (void) _controllerSelectionChanged: (NSDictionary*)change
{
    [self _matchControllerSelection];
}


- (void) _controllerContentsChanged: (NSDictionary*)change
{
    [self reload];
}


- (IBAction) changeZoom: (id)sender
{
    float zoom = [sender floatValue];
    [_browser setZoomValue: zoom];
    [[NSUserDefaults standardUserDefaults] setFloat: [_browser cellSize].width forKey: @"GridCellSize"];
}


#pragma mark -
#pragma mark IKImageBrowserView data source:


- (NSUInteger) numberOfItemsInImageBrowser:(IKImageBrowserView *) aBrowser
{
    NSUInteger count = [[_albumsController arrangedObjects] count];
    return count;
}

- (id /*IKImageBrowserItem*/) imageBrowser:(IKImageBrowserView *) aBrowser itemAtIndex:(NSUInteger)i
{
    Album *album = [[_albumsController arrangedObjects] objectAtIndex: i];
    return [[[CoverGridItem alloc] initWithAlbum: album index: i] autorelease];
}


- (NSUInteger) numberOfGroupsInImageBrowser:(IKImageBrowserView *) aBrowser
{
    return [_groups count];
}

- (NSDictionary *) imageBrowser:(IKImageBrowserView *) aBrowser groupAtIndex:(NSUInteger) i
{
    return [_groups objectAtIndex: i];
}



#pragma mark -
#pragma mark IKImageBrowserView delegate:


- (void) imageBrowserSelectionDidChange:(IKImageBrowserView *) aBrowser
{
    if( ! _reloading ) {
        //  Propagate selection change to array-controller:
        NSIndexSet *indexes = [_browser selectionIndexes];
        Log(@"CoverGridController: Browser selection changed to %u",[indexes firstIndex]);
        if( [indexes count] == 0 )
            [_albumsController setSelectedObjects: nil];
        else {
            NSUInteger i = [indexes firstIndex];
            [_albumsController setSelectionIndex: i];
            //[[[self albums] objectAtIndex: i] setRead: YES];
        }
    }
}


- (void) imageBrowser:(IKImageBrowserView *) aBrowser cellWasDoubleClickedAtIndex:(NSUInteger) i;
{
    [[WatcherApp sharedInstance] openInBrowser: self];
}

@end




@implementation CoverGridItem
- (id) initWithAlbum: (Album*)album index: (NSUInteger)i
{
    self = [super init];
    if( self ) {
        _album = [album retain];
        _index = i;
    }
    return self;
}

- (void) dealloc
{
    [_album release];
    [super dealloc];
}

- (NSString *)  imageUID
{
    // This gets called on every single item in the browser, so it should not do anything that causes
    // its Album to load its data.
    return [[[_album objectID] URIRepresentation] absoluteString];
}

- (NSString *) imageRepresentationType  {return IKImageBrowserNSDataRepresentationType;}

- (id) imageRepresentation              {return _album.coverDataSync;}

- (NSString *) imageTitle               {return _album.artist.name;}

- (NSString *) imageSubtitle            {return [NSString stringWithFormat: @"\"%@\"",_album.name];}


@end
