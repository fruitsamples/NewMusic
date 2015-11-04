/*

File: ITMSWatcher.m

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


#import "ITMSWatcher.h"
#import "Album.h"
#import "Cover.h"
#import "Artist.h"
#import "Genre.h"
#import "Logging.h"
#import <PubSub/PubSub.h>

/* To find iTunes Music Store feed URLs, use this tool:
    http://phobos.apple.com/WebObjects/MZSearch.woa/wa/MRSS/rssGenerator
*/


#define kITMSNamespace @"http://phobos.apple.com/rss/1.0/modules/itms/"


@implementation ITMSWatcher


static NSArray* kElemNames;

+ (void) initialize
{
    // Maps iTMS tag names to Album property names:
    kElemNames = [[NSArray alloc] initWithObjects:
                        @"artist",
                        @"artistLink",
                        @"album",
                        @"albumLink",
                        @"coverArt",
                        nil];
}


+ (BOOL) handlesFeedURL: (NSURL*)url
{
    return [[[url host] lowercaseString] rangeOfString: @"phobos.apple.com"].length > 0;
}


static UInt32 iTMSIDFromURL( NSString* urlStr )
{
    NSURL *url = [NSURL URLWithString: urlStr];
    if( ! url ) {
        Log(@"ITMSWatcher: Couldn't parse URL <%@>",urlStr);
        return 0;
    }
    NSString *query = [url query];
    for( NSString *param in [query componentsSeparatedByString: @"&"] ) {
        if( [param hasPrefix: @"id="] )
            return [[param substringFromIndex: 3] intValue];
    }
    return 0;
}


- (BOOL) updateAlbum: (Album*)album fromEntry: (PSEntry*)entry
{
    NSString *artistName=nil, *albumTitle=nil, *genreName=nil;
    UInt64 artistID=0, albumID=0, genreID=0;
    NSURL *coverURL=nil;
    int maxHeight = 0;
    
    // Scan the list of 'itms:' tags:
    for( NSXMLElement *elem in [entry extensionXMLElementsUsingNamespace: kITMSNamespace] ) {
        NSString *content = [elem stringValue];
        switch( [kElemNames indexOfObject: [elem localName]] ) {
            case 0:
                artistName = content;
                break;
            case 1:
                artistID = iTMSIDFromURL(content);
                break;
            case 2:
                albumTitle = content;
                break;
            case 3:
                albumID = iTMSIDFromURL(content);
                break;
            case 4: {
                int height = [[[elem attributeForName: @"height"] stringValue] intValue];
                if( height > maxHeight ) {
                    maxHeight = height;
                    coverURL = [NSURL URLWithString: content];
                }
                break;
            }
            default:
                break;
        }
    }
    
    // Get the category (by hand, because PubSub doesn't extract it yet):
    NSXMLElement *category = [[[entry XMLRepresentation] elementsForName: @"category"] lastObject];
    if( category ) {
        genreName = [category stringValue];
        genreID = iTMSIDFromURL( [[category attributeForName: @"domain"] stringValue] );
    }
    
    Log(@"    Artist = '%@' (%qu), Album = '%@' (%qu)",artistName,artistID, albumTitle,albumID);
    Log(@"    Genre  = '%@' (%qu)",genreName,genreID);
    Log(@"    Cover  = <%@> (%i px)",coverURL, maxHeight);
    
    if( ! albumTitle || ! albumID ) {
        Warn(@"iTMS album missing title or ID in %@",entry);
        return NO;
    }
        
    // Check or assign the album ID:
    if( album.iTMSID ) {
        if( album.iTMSID != albumID ) {
            Warn(@"iTMS album ID conflict for %@ [already had %qu]",entry,album.iTMSID);
            return NO;
        }
    } else {
        album.iTMSID = albumID;
    }
    
    album.name = albumTitle;
    
    // Assign the artist:
    album.artist = [Artist createInstanceWithITMSID: artistID named: artistName];

    // Assign the genre:
    Genre *genre = [Genre createInstanceWithITMSID: genreID named: genreName];
    if( genre )
        [album.genres addObject: genre];
    
    // Assign the cover URL:
    if( coverURL )
        album.coverURL = coverURL;
    else
        Warn(@"No cover image for %@",album);
    
    return YES;
}


@end




/* Sample item:
 <item>
 <title>Silent Shout - The Knife</title>
 <link>http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewAlbum?id=171544048&amp;s=143441</link>
 <description>Silent Shout by The Knife</description>
 <pubDate>Tue 25 Jul 2006 11:28:37 -800</pubDate>
 <content:encoded><![CDATA[<TABLE BORDER=0 WIDTH="100%"><TR><TD><table border="0" width="100%" cellspacing="0" cellpadding="0">
 <tr valign="top" align="left">
 <td ALIGN=CENTER WIDTH=166 VALIGN=TOP><a href="http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewAlbum?id=171544048&s=143441"><img border="0" src="http://a1.phobos.apple.com/r10/Music/ee/91/95/mzi.uiphjmje.100x100-99.jpg"></a></td>
 <td width="10"><img alt="" width="10" height="1" src="/images/spacer.gif"></td>
 <td width="95%"><B><a href="http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewAlbum?id=171544048&s=143441">Silent Shout</a></B><br>
 <a href="http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewArtist?id=26090355">The Knife</a><br><br>
 <font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Release Date:</B>
 July 25, 2006<br>
 </font><font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Total Songs:</B>
 11</font><br>
 <font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Genre:</B>
 <a href="http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewGenre?id=7">Electronic</a></font><br>
 <font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Price:</B>
 $9.90</font><br>
 <font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Copyright</B>
 2006 The copyright in this sound recording is owned by Rabid Records under exclusive licence to Brille Records Ltd</font></td>
 </tr>
 </table></TD></TR>
 </TABLE>
 ]]></content:encoded>
 <category domain="http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewGenre?id=7">Electronic</category>
 <itms:artist>The Knife</itms:artist>
 <itms:artistLink>http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewArtist?id=26090355</itms:artistLink>
 <itms:album>Silent Shout</itms:album>
 <itms:albumLink>http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewAlbum?id=171544048&amp;s=143441</itms:albumLink>
 <itms:albumPrice>$9.90</itms:albumPrice>
 
 <itms:coverArt height="53" width="53">http://a1.phobos.apple.com/r10/Music/ee/91/95/mzi.uiphjmje.53x53-75.jpg</itms:coverArt>
 <itms:coverArt height="60" width="60">http://a1.phobos.apple.com/r10/Music/ee/91/95/mzi.uiphjmje.60x60-75.jpg</itms:coverArt>
 <itms:coverArt height="100" width="100">http://a1.phobos.apple.com/r10/Music/ee/91/95/mzi.uiphjmje.100x100-99.jpg</itms:coverArt>
 
 
 <itms:rights>2006 The copyright in this sound recording is owned by Rabid Records under exclusive licence to Brille Records Ltd</itms:rights>
 
 <itms:releasedate>July 25, 2006</itms:releasedate>
 </item>
 */
