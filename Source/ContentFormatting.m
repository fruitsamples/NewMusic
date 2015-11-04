/*

File: ContentFormatting.m

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


#import "ContentFormatting.h"
#import "Album.h"
#import <PubSub/PubSub.h>


/* Look up a localized string by its key */
static NSString* LOC( NSString *key )
{
    return [[NSBundle mainBundle] localizedStringForKey: key value:@"" table:nil];
}


/* Return a short string for a date/time.
   Today will shown as "Today", yesterday as "Yesterday".
   Dates in the past week will show only the weekday.
   Dates in the same year, or the last six months, will show only the month and day.
   Otherwise the year, month and day are shown. */
NSString* ShortDateTimeString( NSDate* date )
{
    if( ! date )
        return nil;
        
    // Convert to NSCalendarDate:
    NSCalendarDate *calDate = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate: [date timeIntervalSinceReferenceDate]];
    NSCalendarDate *today = [NSCalendarDate date];
    
    // Figure out which format string to use:
    int days = [today dayOfCommonEra] - [calDate dayOfCommonEra];
    NSString *fmtName;
    if( days == 0 )
        fmtName = @"TodayFmt";
    else if( days == 1 )
        fmtName = @"YesterdayFmt";
    else if( days > 1 && days < 7 )
        fmtName = @"ThisWeekFmt";                  // weekday only
    else if( days < 365/2 || [calDate yearOfCommonEra] == [today yearOfCommonEra] )
        fmtName = @"ThisYearFmt";
    else
        fmtName = @"PastYearFmt";
    NSString *format = LOC(fmtName);
    
    // Add the time format:
    format = [NSString stringWithFormat: @"%@%@%@",
                format, LOC(@"DateTimeSep"), LOC(@"TimeFmt")];
    
    // Apply the format:
    return [calDate descriptionWithCalendarFormat: format
                                           locale: [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
}


void RegisterValueTransformers( void )
{
    [ShortDateTimeTransformer class];
    [AlbumFlagsToImageTransformer class];
    [SampleURLToStringTransformer class];
}


/* A value-transformer that formats NSDates according to ShortDateTimeString */
@implementation ShortDateTimeTransformer

+ (void) initialize
{
    [NSValueTransformer setValueTransformer: [[self alloc] init] 
                                    forName: @"ShortDateTimeTransformer"];
}

- (id)transformedValue:(id)value
{
    return ShortDateTimeString(value);
}

@end



/* A value-transformer that converts NSErrors to their localized descriptions */
@implementation ErrorTransformer

+ (void) initialize
{
    [NSValueTransformer setValueTransformer: [[self alloc] init] 
                                    forName: @"ErrorTransformer"];
}

- (id)transformedValue:(NSError*)value
{
    return [value localizedDescription];
}

@end



/* A value-transformer that formats an array by comma-separating its items' descriptions */
@implementation ArrayTransformer

+ (void) initialize
{
    [NSValueTransformer setValueTransformer: [[self alloc] init] 
                                    forName: @"ArrayTransformer"];
}

- (id)transformedValue:(NSArray*)array
{
    if( ! array )
        return nil;
    NSMutableArray *descs = [NSMutableArray array];
    for( id obj in array )
        [descs addObject: [obj description]];
    return [descs componentsJoinedByString: @", "];
}

@end



/* A value-transformer that formats a PSContent */
@implementation PSContentTransformer

+ (void) initialize
{
    [NSValueTransformer setValueTransformer: [[self alloc] init] 
                                    forName: @"PSContentTransformer"];
}

- (id)transformedValue:(PSContent*)content
{
    if( ! content )
        return nil;
    NSString *type = [[content MIMEType] lowercaseString];
    if( [type hasPrefix: @"text/html"] || [type hasPrefix: @"application/xhtml+xml"] )
        return [content HTMLString];
    else if( [type hasPrefix: @"text/"] )
        return [content plainTextString];
    else
        return [NSString stringWithFormat: @"{%@}",type];
}

@end



@implementation AlbumFlagsToImageTransformer

+ (void) initialize
{
    [NSValueTransformer setValueTransformer: [[self alloc] init] 
    forName: @"AlbumFlagsToImageTransformer"];
}

- (id)transformedValue:(Album*)album
{
    if( ! album.read )
        return [NSImage imageNamed: @"unread.tiff"];
    else if( album.flagged )
        return [NSImage imageNamed: @"flagged.tiff"];
    else
        return nil;
}

@end



@implementation SampleURLToStringTransformer

+ (void) initialize
{
    [NSValueTransformer setValueTransformer: [[self alloc] init] 
    forName: @"SampleURLToStringTransformer"];
}

- (id)transformedValue:(NSArray*)sampleTitles
{
    NSMutableArray *names = [NSMutableArray array];
    unsigned n = [sampleTitles count];
    if( n > 0 ) {
        [names addObject: [NSString stringWithFormat: @"%u tracks available...", n]];
        unsigned i=1;
        for( NSString *title in sampleTitles )
            [names addObject: [NSString stringWithFormat: @"%2u. %@",i++,title]];
    } else {
        [names addObject: @"No samples available"];
    }
    return names;
}

@end
