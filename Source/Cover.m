/*

File: Cover.m

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

#import "Cover.h"
#import "Storage.h"
#import "Downloader.h"
#import "Logging.h"


@interface Cover ()
@property (copy) NSString *urlString;
@property (retain) Album *album;
@end


@implementation Cover


@dynamic urlString, album;


- (NSURL*) URL
{
    NSString *urlString = self.urlString;
    return urlString ?[NSURL URLWithString: urlString] :nil;
}

- (void) setURL: (NSURL*)url
{
    self.urlString = [url absoluteString];
}

- (void) _saveImageData: (NSData*)data
{
    [self setValue: (data ?data :[NSData data])     // use 0-byte data as placeholder for missing cover
            forKey: @"imageData"];
    [[Storage sharedInstance] saveSoon];
}


/* Asynchronously loads data, if necessary */
- (NSData*) imageData
{
    [self willAccessValueForKey: @"imageData"];
    NSData *data = [self primitiveValueForKey: @"imageData"];
    [self didAccessValueForKey: @"imageData"];

    if( ! data ) {
        NSURL *url = self.URL;
        if( url && ! _downloadedCover ) {
            _downloadedCover = YES;
            [[Downloader alloc] initWithURL: url 
                                     target: self 
                                     action: @selector(_saveImageData:)];
        }
        return nil;
    } else if( data.length == 0 ) {
        return nil;
    } else {
        return data;
    }
}


/* Asynchronously loads data, if necessary */
- (NSData*) imageDataSync
{
    [self willAccessValueForKey: @"imageData"];
    NSData *data = [self primitiveValueForKey: @"imageData"];
    [self didAccessValueForKey: @"imageData"];
    
    if( ! data ) {
        NSURL *url = self.URL;
        if( url && ! _downloadedCover ) {
            _downloadedCover = YES;
            
            Log(@"Synchronous download of <%@> for %@",url,self.album);
            NSError *error = nil;
            NSURLResponse *response = nil;
            NSURLRequest *request = [NSURLRequest requestWithURL: url];
            data = [NSURLConnection sendSynchronousRequest: request
                                         returningResponse: &response
                                                     error: &error];
            Log(@"    Got %u bytes",data.length);
            [self _saveImageData: data];
        }
    } else if( data.length == 0 ) {
        data = nil;
    }
    return data;
}


- (NSData*) loadData: (BOOL)synchronous
{
    NSData *data = synchronous ?self.imageDataSync :self.imageData;
    // Turn the cover object back into a fault, to unload its image data out of memory.
    if( !self.isUpdated && !self.isInserted )
        [[self managedObjectContext] refreshObject: self mergeChanges: NO];
    return data;
}


- (NSImage*) image
{
    NSData *data = [self loadData: YES];
    if( data ) {
        NSImage *coverImage = [[NSImage alloc] initWithData: data];
        if( coverImage ) {
            // Force 72dpi, else many covers look tiny:
            NSBitmapImageRep *rep = [[coverImage representations] objectAtIndex: 0];
            [coverImage setSize: NSMakeSize([rep pixelsWide],[rep pixelsHigh])];
        } else
            Log(@"Warning: Couldn't create NSImage on data of <%@>",self.urlString);
        return [coverImage autorelease];
    } else {
        return nil;
    }
}


@end
