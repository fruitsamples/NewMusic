/*

File: SubscriptionsController.m

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

#import "SubscriptionsController.h"
#import "Client.h"
#import <PubSub/PubSub.h>


@implementation SubscriptionsController


- (void)awakeFromNib
{
        [self performSelector: @selector(wakeUp) withObject: nil afterDelay: 0];
}


- (void) wakeUp
{
    // If there are no subscriptions yet, open the sheet:
    if( [[[PSClient applicationClient] feeds] count] == 0 )
        [self changeSubscriptions: self];
}


- (void) setUp
{
    NSString *path = [[NSBundle bundleForClass: [self class]] pathForResource: @"MusicFeeds" ofType: @"plist"];
    NSAssert(path,@"Missing MusicFeeds.plist");
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile: path];
    NSAssert(plist,@"Couldn't read MusicFeeds.plist");
    NSArray *names = [[plist allKeys] sortedArrayUsingSelector: @selector(localizedCaseInsensitiveCompare:)];
    
    // Set each checkbox in the matrix, according to whether the corresponding feed is subscribed:
    [_matrix renewRows: 0 columns: 1];
    int i = 0;
    for( NSString *name in names ) {
        NSURL *url = [NSURL URLWithString: [plist objectForKey: name]];
        Watcher *watcher = [[Client sharedInstance] watcherWithFeedURL: url];
        
        [_matrix addRow];
        NSButtonCell *cell = [_matrix cellAtRow: i++ column: 0];
        [cell setTitle: name];
        [cell setRepresentedObject: url];           // tag the cell with the feed URL
        [cell setState: (watcher!=nil)];
    }
    [_matrix sizeToFit];
}


- (IBAction) changeSubscriptions: (id)sender;
{
    [self setUp];
    
    [NSApp beginSheet: _panel modalForWindow: _parentWindow
        modalDelegate: self didEndSelector: @selector(_didEnd:returnCode:contextInfo:)
          contextInfo: NULL];
}


- (IBAction) dismissSheet: (id)sender
{
    [NSApp endSheet: _panel returnCode: [sender tag]];
}


- (void)_didEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [_panel orderOut: self];
    if( returnCode == NSOKButton ) {
        // Process changes: Subscribe/unsubscribe each feed according to the state of its checkbox:
        for( NSButtonCell *cell in [_matrix cells] ) {
            NSURL *url = [cell representedObject];
            if( [cell state] ) {
                [[Client sharedInstance] addWatcherWithFeedURL: url];
            } else {
                [[Client sharedInstance] removeWatcherWithFeedURL: url];
            }
        }
    }
}

@end
