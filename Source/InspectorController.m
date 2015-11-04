/*

File: InspectorController.m

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


#import "InspectorController.h"
#import "Album.h"
#import "mk.h"
#import "Logging.h"
#import <QTKit/QTKit.h>


@implementation InspectorController


- (void) awakeFromNib
{
    [_albumsController addObserver: self forKeyPath: @"selectedObjects"
                                            options: 0
                                            context: NULL];
    [[_ratingControl cell] setEditable: YES];
    //[_ratingControl setContinuous: YES];
}


- (void)observeValueForKeyPath:(NSString *)keyPath
                    ofObject:(id)object 
                    change:(NSDictionary *)change 
                    context:(void *)context
{
    // Selection changed:
    [_qtView pause: self];
    [_samplePopUp selectItemAtIndex: 0];
    [self loadSelectedSampleAndPlay: NO];
}


- (Album*) selectedAlbum
{
    NSArray *sel = [_albumsController selectedObjects];
    if( [sel count] > 0 )
        return [sel objectAtIndex: 0];
    else
        return nil;
}


- (void) loadSampleAtURL: (NSURL*)url andPlay: (BOOL)play
{
    Log(@"%@ MP3 sample from <%@>",(play ?@"Playing" :@"Loading"), url);
    [_qtView pause: self];
    NSError *error = nil;
    QTMovie *movie = [QTMovie movieWithURL: url error: &error];
    if( ! movie ) {
        Log(@"Error: Couldn't create QTMovie: %@",error);
        NSBeep();
        return;
    }
    
    [_qtView setMovie: movie];
    [_qtView gotoBeginning: self];
    [_qtView setHidden: NO];
    if( play )
        [movie autoplay];
}


// The pop-up menu in the Inspector sends this
- (void) loadSelectedSampleAndPlay: (BOOL)play
{
    NSArray *samples = [[self selectedAlbum] trackSampleURLs];
    unsigned i = [_samplePopUp indexOfSelectedItem];
    if( i==0 || i > [samples count] ) {
        [_qtView setHidden: YES];
        return;
    }
    [[_samplePopUp itemAtIndex: 0] setTitle: [[_samplePopUp itemAtIndex: i] title]];
    [self loadSampleAtURL: [samples objectAtIndex: i-1] andPlay: play];
}


// The pop-up menu in the Inspector sends this
- (IBAction) sampleSelected: (id)sender
{
    [self loadSelectedSampleAndPlay: YES];
}

@end
