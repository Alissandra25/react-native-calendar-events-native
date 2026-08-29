#import "CalendarEventsNative.h"
#import <EventKit/EventKit.h>
#import <EventKitUI/EventKitUI.h>
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>
#import <math.h>
#import <stdint.h>

#ifdef RCT_NEW_ARCH_ENABLED
// JSI headers are included automatically by the framework
#endif

// Accept expected Foundation types only across the unsafe bridge
static BOOL HasValue(id value) {
    return value != nil && value != [NSNull null];
}

static NSString *StringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSDictionary *DictOrNil(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *ArrayOrNil(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSNumber *NumberOrNil(id value) {
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

// Accept finite integer numbers but not bridged booleans
static NSNumber *IntegerNumberOrNil(id value) {
    NSNumber *number = NumberOrNil(value);
    if (!number || CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) return nil;
    double doubleValue = number.doubleValue;
    if (!isfinite(doubleValue) || floor(doubleValue) != doubleValue
        || doubleValue < INT32_MIN || doubleValue > INT32_MAX) return nil;
    return number;
}

@interface CalendarEventsNative () <EKEventEditViewDelegate>
@property (nonatomic, strong) EKEventStore *eventStore;
@property (nonatomic, copy) RCTPromiseResolveBlock editEventResolver;
@property (nonatomic, copy) RCTPromiseRejectBlock editEventRejecter;
@end


@implementation CalendarEventsNative

RCT_EXPORT_MODULE(RNCalendarEventsNativeSpec)

- (instancetype)init {
    if (self = [super init]) {
        self.eventStore = [[EKEventStore alloc] init];
        
        // Log that native module was initialized
        NSLog(@"🚀 CalendarEventsNative: Native module initialized!");
        NSLog(@"📱 Module registered as: %@", NSStringFromClass([self class]));
        NSLog(@"🔍 Module export name should be: RNCalendarEventsNativeSpec");
        NSLog(@"🔧 TurboModule support: %@", @"Enabled");
        NSLog(@"✅ Ready to receive method calls from JavaScript");
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

RCT_EXPORT_METHOD(debugModuleMethods:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSLog(@"🔍 CalendarEventsNative: Module methods available!");
    NSLog(@"🔍 Available methods: requestPermissions, checkPermissions, fetchAllCalendars, findOrCreateCalendar, removeCalendar, fetchAllEvents, findEventById, saveEvent, openEventEditor, updateEvent, removeEvent, openEventInCalendar");
    resolve(@"Methods logged to console");
}

#pragma mark - Permission Methods

RCT_EXPORT_METHOD(requestPermissions:(BOOL)writeOnly
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (@available(iOS 17.0, *)) {
        [self.eventStore requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError *error) {
            if (error) {
                reject(@"permission_error", error.localizedDescription, error);
            } else {
                resolve(granted ? @"authorized" : @"denied");
            }
        }];
    } else {
        [self.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
            if (error) {
                reject(@"permission_error", error.localizedDescription, error);
            } else {
                resolve(granted ? @"authorized" : @"denied");
            }
        }];
    }
}

RCT_EXPORT_METHOD(checkPermissions:(BOOL)writeOnly
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    
    NSString *statusString;
    switch (status) {
        case EKAuthorizationStatusAuthorized:
            statusString = @"authorized";
            break;
        case EKAuthorizationStatusDenied:
            statusString = @"denied";
            break;
        case EKAuthorizationStatusRestricted:
            statusString = @"restricted";
            break;
        case EKAuthorizationStatusNotDetermined:
            statusString = @"undetermined";
            break;
        default:
            statusString = @"undetermined";
            break;
    }
    
    resolve(statusString);
}

#pragma mark - Calendar Methods

// Helper method to convert EKCalendar to NSDictionary
- (NSDictionary *)calendarToDict:(EKCalendar *)calendar {
    NSMutableDictionary *calDict = [NSMutableDictionary dictionary];
    calDict[@"id"] = calendar.calendarIdentifier;
    calDict[@"title"] = calendar.title;
    calDict[@"type"] = @(calendar.type);
    calDict[@"source"] = calendar.source.title ?: @"";
    calDict[@"isPrimary"] = @(calendar.type == EKCalendarTypeLocal);
    calDict[@"allowsModifications"] = @(calendar.allowsContentModifications);
    calDict[@"color"] = [self hexStringFromColor:calendar.CGColor];
    
    NSMutableArray *availabilities = [NSMutableArray array];
    if (calendar.supportedEventAvailabilities & EKCalendarEventAvailabilityBusy) {
        [availabilities addObject:@"busy"];
    }
    if (calendar.supportedEventAvailabilities & EKCalendarEventAvailabilityFree) {
        [availabilities addObject:@"free"];
    }
    if (calendar.supportedEventAvailabilities & EKCalendarEventAvailabilityTentative) {
        [availabilities addObject:@"tentative"];
    }
    if (calendar.supportedEventAvailabilities & EKCalendarEventAvailabilityUnavailable) {
        [availabilities addObject:@"unavailable"];
    }
    calDict[@"allowedAvailabilities"] = availabilities;
    
    return calDict;
}

RCT_EXPORT_METHOD(fetchAllCalendars:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSArray<EKCalendar *> *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
    NSMutableArray *calendarData = [NSMutableArray array];
    
    for (EKCalendar *calendar in calendars) {
        [calendarData addObject:[self calendarToDict:calendar]];
    }
    
    resolve(calendarData);
}

RCT_EXPORT_METHOD(findOrCreateCalendar:(NSString *)title
                  color:(NSString *)colorHex
                  entityType:(NSString *)entityType
                  source:(NSString *)sourceName
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        NSString *calendarTitle = title ?: @"Calendar";
        
        // First, try to find existing calendar
        NSArray<EKCalendar *> *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
        for (EKCalendar *existingCal in calendars) {
            if ([existingCal.title isEqualToString:calendarTitle]) {
                // Return full calendar object
                NSDictionary *calDict = [self calendarToDict:existingCal];
                resolve(calDict);
                return;
            }
        }
        
        // Create new calendar
        EKCalendar *calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:self.eventStore];
        if (!calendar) {
            reject(@"calendar_creation_failed", @"Failed to create calendar object", nil);
            return;
        }
        
        calendar.title = calendarTitle;
        
        // Find the default source
        EKSource *localSource = nil;
        EKSource *iCloudSource = nil;
        
        for (EKSource *source in self.eventStore.sources) {
            if (source.sourceType == EKSourceTypeLocal) {
                localSource = source;
            } else if (source.sourceType == EKSourceTypeCalDAV && 
                       [source.title containsString:@"iCloud"]) {
                iCloudSource = source;
            }
        }
        
        calendar.source = iCloudSource ?: localSource ?: self.eventStore.defaultCalendarForNewEvents.source;
        
        // Set color if provided
        if (colorHex && colorHex.length > 0) {
            calendar.CGColor = [self colorFromHexString:colorHex];
        }
        
        NSError *error;
        BOOL success = [self.eventStore saveCalendar:calendar commit:YES error:&error];
        
        if (success) {
            // Return full calendar object
            NSDictionary *calDict = [self calendarToDict:calendar];
            resolve(calDict);
        } else {
            reject(@"calendar_creation_failed", error.localizedDescription ?: @"Unknown error", error);
        }
    });
}

RCT_EXPORT_METHOD(removeCalendar:(NSString *)calendarId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];
        
        if (!calendar) {
            resolve(@NO);
            return;
        }
        
        NSError *error;
        BOOL success = [self.eventStore removeCalendar:calendar commit:YES error:&error];
        
        if (success) {
            resolve(@YES);
        } else {
            reject(@"calendar_removal_failed", error.localizedDescription ?: @"Unknown error", error);
        }
    });
}

#pragma mark - Event Methods

RCT_EXPORT_METHOD(fetchAllEvents:(NSString *)startDate
                  endDate:(NSString *)endDate
                  calendarIds:(NSArray<NSString *> *)calendarIds
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        NSDate *start = [self dateFromISO8601String:startDate];
        NSDate *end = [self dateFromISO8601String:endDate];
        
        NSPredicate *predicate;
        if (calendarIds.count > 0) {
            NSMutableArray<EKCalendar *> *calendars = [NSMutableArray array];
            for (NSString *calendarId in calendarIds) {
                EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];
                if (calendar) {
                    [calendars addObject:calendar];
                }
            }
            predicate = [self.eventStore predicateForEventsWithStartDate:start endDate:end calendars:calendars];
        } else {
            predicate = [self.eventStore predicateForEventsWithStartDate:start endDate:end calendars:nil];
        }
        
        NSArray<EKEvent *> *events = [self.eventStore eventsMatchingPredicate:predicate];
        NSMutableArray *eventData = [NSMutableArray array];
        
        for (EKEvent *event in events) {
            [eventData addObject:[self serializeEvent:event]];
        }
        
        resolve(eventData);
    });
}

RCT_EXPORT_METHOD(findEventById:(NSString *)eventId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        EKEvent *event = [self.eventStore eventWithIdentifier:eventId];
        
        if (event) {
            resolve([self serializeEvent:event]);
        } else {
            resolve([NSNull null]);
        }
    });
}

RCT_EXPORT_METHOD(saveEvent:(NSString *)title
                  startDate:(NSString *)startDate
                  endDate:(NSString *)endDate
                  location:(NSString *)location
                  notes:(NSString *)notes
                  calendarId:(NSString *)calendarId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        EKEvent *event = [EKEvent eventWithEventStore:self.eventStore];
        if (!event) {
            reject(@"event_creation_failed", @"Failed to create event object", nil);
            return;
        }
        
        // Simple property setting - no complex C++ structs!
        event.title = title ?: @"Untitled Event";
        event.startDate = [self dateFromISO8601String:startDate];
        event.endDate = [self dateFromISO8601String:endDate];
        
        if (location && location.length > 0) {
            event.location = location;
        }
        
        if (notes && notes.length > 0) {
            event.notes = notes;
        }
        
        if (calendarId && calendarId.length > 0) {
            EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];
            if (calendar) {
                event.calendar = calendar;
            }
        } else {
            event.calendar = self.eventStore.defaultCalendarForNewEvents;
        }
        
        NSError *error;
        BOOL success = [self.eventStore saveEvent:event span:EKSpanThisEvent commit:YES error:&error];
        
        if (success) {
            resolve(event.eventIdentifier);
        } else {
            reject(@"event_save_failed", error.localizedDescription ?: @"Unknown error", error);
        }
    });
}

RCT_EXPORT_METHOD(updateEvent:(NSString *)eventId
                  title:(NSString *)title
                  startDate:(NSString *)startDate
                  endDate:(NSString *)endDate
                  location:(NSString *)location
                  notes:(NSString *)notes
                  calendarId:(NSString *)calendarId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        EKEvent *event = [self.eventStore eventWithIdentifier:eventId];
        
        if (!event) {
            reject(@"event_not_found", @"Event not found", nil);
            return;
        }
        
        // Update event properties directly
        if (title && title.length > 0) {
            event.title = title;
        }
        if (startDate && startDate.length > 0) {
            event.startDate = [self dateFromISO8601String:startDate];
        }
        if (endDate && endDate.length > 0) {
            event.endDate = [self dateFromISO8601String:endDate];
        }
        if (location && location.length > 0) {
            event.location = location;
        }
        if (notes && notes.length > 0) {
            event.notes = notes;
        }
        if (calendarId && calendarId.length > 0) {
            EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];
            if (calendar) {
                event.calendar = calendar;
            }
        }
        
        NSError *error;
        BOOL success = [self.eventStore saveEvent:event span:EKSpanThisEvent commit:YES error:&error];
        
        if (success) {
            resolve(event.eventIdentifier);
        } else {
            reject(@"event_update_failed", error.localizedDescription ?: @"Unknown error", error);
        }
    });
}

RCT_EXPORT_METHOD(removeEvent:(NSString *)eventId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.eventStore) {
            reject(@"event_store_unavailable", @"Event store not available", nil);
            return;
        }
        
        EKEvent *event = [self.eventStore eventWithIdentifier:eventId];
        
        if (!event) {
            resolve(@NO);
            return;
        }
        
        NSError *error;
        BOOL success = [self.eventStore removeEvent:event span:EKSpanThisEvent commit:YES error:&error];
        
        if (success) {
            resolve(@YES);
        } else {
            reject(@"event_removal_failed", error.localizedDescription ?: @"Unknown error", error);
        }
    });
}

RCT_EXPORT_METHOD(openEventInCalendar:(NSString *)eventId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        EKEvent *event = [self.eventStore eventWithIdentifier:eventId];
        
        if (!event) {
            reject(@"event_not_found", @"Event not found", nil);
            return;
        }
        
        EKEventEditViewController *controller = [[EKEventEditViewController alloc] init];
        controller.event = event;
        controller.eventStore = self.eventStore;
        controller.editViewDelegate = self;
        
        self.editEventResolver = resolve;
        self.editEventRejecter = reject;
        
        UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
        [rootViewController presentViewController:controller animated:YES completion:nil];
    });
}

// Opens EventKitUI with an unsaved event owned by the system editor
RCT_EXPORT_METHOD(openEventEditor:(NSDictionary *)eventOptions
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![eventOptions isKindOfClass:[NSDictionary class]]) {
            reject(@"invalid_event_options", @"Event options must be an object", nil);
            return;
        }

        NSString *title = StringOrNil(eventOptions[@"title"]);
        NSString *startDate = StringOrNil(eventOptions[@"startDate"]);
        NSString *endDate = StringOrNil(eventOptions[@"endDate"]);
        NSString *location = StringOrNil(eventOptions[@"location"]);
        NSString *notes = StringOrNil(eventOptions[@"notes"]);
        NSString *calendarId = StringOrNil(eventOptions[@"calendar"]);
        NSNumber *allDay = NumberOrNil(eventOptions[@"allDay"]);
        if (!title) {
            reject(@"invalid_event_options", @"Event title must be a string", nil);
            return;
        }
        if (HasValue(eventOptions[@"location"]) && !location) {
            reject(@"invalid_event_options", @"Event location must be a string", nil);
            return;
        }
        if (HasValue(eventOptions[@"notes"]) && !notes) {
            reject(@"invalid_event_options", @"Event notes must be a string", nil);
            return;
        }
        if (HasValue(eventOptions[@"calendar"]) && !calendarId) {
            reject(@"invalid_event_options", @"Calendar ID must be a string", nil);
            return;
        }
        if (HasValue(eventOptions[@"allDay"]) && !allDay) {
            reject(@"invalid_event_options", @"Event allDay must be a boolean", nil);
            return;
        }

        NSDate *parsedStartDate = [self dateFromISO8601String:startDate];
        NSDate *parsedEndDate = [self dateFromISO8601String:endDate];
        if (!parsedStartDate || !parsedEndDate) {
            reject(@"invalid_event_dates", @"Event dates must use ISO 8601 format", nil);
            return;
        }
        if ([parsedEndDate compare:parsedStartDate] == NSOrderedAscending) {
            reject(@"invalid_event_dates", @"Event end date must not be before its start date", nil);
            return;
        }

        void (^presentEditor)(void) = ^{
            UIViewController *presenter = RCTPresentedViewController();
            if (!presenter) {
                reject(@"event_editor_unavailable", @"No view controller can present the calendar editor", nil);
                return;
            }
            if ([presenter isKindOfClass:[EKEventEditViewController class]]) {
                reject(@"event_editor_busy", @"A calendar editor is already open", nil);
                return;
            }

            EKEvent *event = [EKEvent eventWithEventStore:self.eventStore];
            event.title = title;
            event.startDate = parsedStartDate;
            event.endDate = parsedEndDate;
            event.location = location;
            event.notes = notes;
            event.allDay = allDay.boolValue;

            NSString *optionsError = [self applyEditorOptions:eventOptions toEvent:event];
            if (optionsError) {
                reject(@"invalid_event_options", optionsError, nil);
                return;
            }

            EKEventEditViewController *controller = [[EKEventEditViewController alloc] init];
            controller.event = event;
            controller.eventStore = self.eventStore;
            controller.editViewDelegate = self;

            [presenter presentViewController:controller animated:YES completion:^{
                resolve(nil);
            }];
        };

        if (@available(iOS 17.0, *)) {
            if (calendarId.length > 0) {
                [self.eventStore requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) {
                            reject(@"permission_error", error.localizedDescription, error);
                        } else if (!granted) {
                            reject(@"calendar_permission_denied", @"Full calendar access is required to preselect a calendar", nil);
                        } else {
                            presentEditor();
                        }
                    });
                }];
                return;
            }
            presentEditor();
            return;
        }

        EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
        if (status == EKAuthorizationStatusAuthorized) {
            presentEditor();
            return;
        }
        if (status != EKAuthorizationStatusNotDetermined) {
            reject(@"calendar_permission_denied", @"Calendar access is required to open the event editor on iOS 16 and earlier", nil);
            return;
        }

        [self.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    reject(@"permission_error", error.localizedDescription, error);
                } else if (!granted) {
                    reject(@"calendar_permission_denied", @"Calendar access is required to open the event editor on iOS 16 and earlier", nil);
                } else {
                    presentEditor();
                }
            });
        }];
    });
}

#pragma mark - Helper Methods

// Applies shared and iOS-only values before presenting EventKitUI
- (NSString *)applyEditorOptions:(NSDictionary *)options toEvent:(EKEvent *)event {
    NSString *calendarId = StringOrNil(options[@"calendar"]);
    if (calendarId.length > 0) {
        EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];
        if (!calendar) return @"The selected calendar was not found";
        event.calendar = calendar;
    } else {
        event.calendar = self.eventStore.defaultCalendarForNewEvents;
    }

    NSString *availabilityError = [self applyAvailability:options[@"availability"] toEvent:event allowUnavailable:NO];
    if (availabilityError) return availabilityError;

    id recurrenceValue = options[@"recurrence"];
    NSDictionary *recurrence = DictOrNil(recurrenceValue);
    if (HasValue(recurrenceValue) && !recurrence) return @"Recurrence must be an object";
    if (recurrence) {
        NSString *recurrenceError = [self applyRecurrence:recurrence toEvent:event];
        if (recurrenceError) return recurrenceError;
    }

    id iosValue = options[@"ios"];
    NSDictionary *iosOptions = DictOrNil(iosValue);
    if (HasValue(iosValue) && !iosOptions) return @"iOS options must be an object";
    if (!iosOptions) return nil;

    id urlValue = iosOptions[@"url"];
    NSString *url = StringOrNil(urlValue);
    if (HasValue(urlValue) && !url) return @"iOS event URL must be a string";
    if (url.length > 0) {
        NSURL *eventURL = [NSURL URLWithString:url];
        if (!eventURL.scheme) return @"iOS event URLs must include a valid scheme";
        event.URL = eventURL;
    }

    NSString *iosAvailabilityError = [self applyAvailability:iosOptions[@"availability"] toEvent:event allowUnavailable:YES];
    if (iosAvailabilityError) return iosAvailabilityError;

    id alarmsValue = iosOptions[@"alarms"];
    NSArray *alarms = ArrayOrNil(alarmsValue);
    if (HasValue(alarmsValue) && !alarms) return @"iOS alarms must be an array";
    if (alarms) {
        NSMutableArray<EKAlarm *> *eventAlarms = [NSMutableArray array];
        for (id alarmValue in alarms) {
            NSDictionary *alarmOptions = DictOrNil(alarmValue);
            if (!alarmOptions) return @"Each iOS alarm must be an object";

            EKAlarm *alarm = nil;
            id dateValue = alarmOptions[@"date"];
            id minutesValue = alarmOptions[@"minutes"];
            NSString *date = StringOrNil(dateValue);
            NSNumber *minutes = NumberOrNil(minutesValue);
            if (HasValue(dateValue) && !date) return @"iOS alarm date must be a string";
            if (HasValue(minutesValue) && !minutes) return @"iOS alarm minutes must be a number";
            if (HasValue(dateValue) && HasValue(minutesValue)) return @"Each iOS alarm must provide either date or minutes";
            if (date) {
                NSDate *parsedDate = [self dateFromISO8601String:date];
                if (!parsedDate) return @"iOS alarm dates must use ISO 8601 format";
                alarm = [EKAlarm alarmWithAbsoluteDate:parsedDate];
            } else if (minutes) {
                if (minutes.doubleValue < 0) return @"iOS alarm minutes must not be negative";
                alarm = [EKAlarm alarmWithRelativeOffset:-(minutes.doubleValue * 60)];
            } else {
                return @"Each iOS alarm must provide date or minutes";
            }
            [eventAlarms addObject:alarm];
        }
        event.alarms = eventAlarms;
    }

    return nil;
}

// Validates availability values supported by the selected platform scope
- (NSString *)applyAvailability:(id)availabilityValue
                         toEvent:(EKEvent *)event
                allowUnavailable:(BOOL)allowUnavailable {
    if (!HasValue(availabilityValue)) return nil;
    NSString *availability = StringOrNil(availabilityValue);
    if (!availability) return @"Availability must be a string";
    if ([availability isEqualToString:@"busy"]) {
        event.availability = EKEventAvailabilityBusy;
    } else if ([availability isEqualToString:@"free"]) {
        event.availability = EKEventAvailabilityFree;
    } else if ([availability isEqualToString:@"tentative"]) {
        event.availability = EKEventAvailabilityTentative;
    } else if (allowUnavailable && [availability isEqualToString:@"unavailable"]) {
        event.availability = EKEventAvailabilityUnavailable;
    } else {
        return allowUnavailable
            ? @"iOS availability must be unavailable"
            : @"Availability must be busy, free, or tentative";
    }
    return nil;
}

// Builds an EventKit recurrence rule from the shared recurrence shape
- (NSString *)applyRecurrence:(NSDictionary *)recurrence toEvent:(EKEvent *)event {
    NSDictionary<NSString *, NSNumber *> *frequencies = @{
        @"daily": @(EKRecurrenceFrequencyDaily),
        @"weekly": @(EKRecurrenceFrequencyWeekly),
        @"monthly": @(EKRecurrenceFrequencyMonthly),
        @"yearly": @(EKRecurrenceFrequencyYearly),
    };
    NSString *frequency = StringOrNil(recurrence[@"frequency"]);
    NSNumber *frequencyValue = frequency ? frequencies[frequency] : nil;
    if (!frequencyValue) return @"Recurrence frequency must be daily, weekly, monthly, or yearly";

    id intervalValue = recurrence[@"interval"];
    NSNumber *intervalNumber = IntegerNumberOrNil(intervalValue);
    if (HasValue(intervalValue) && !intervalNumber) return @"Recurrence interval must be an integer";
    NSInteger interval = intervalNumber ? intervalNumber.integerValue : 1;
    if (interval < 1) return @"Recurrence interval must be greater than zero";

    EKRecurrenceEnd *recurrenceEnd = nil;
    id endDateValue = recurrence[@"endDate"];
    id occurrenceValue = recurrence[@"occurrence"];
    NSString *endDateString = StringOrNil(endDateValue);
    NSNumber *occurrenceNumber = IntegerNumberOrNil(occurrenceValue);
    if (HasValue(endDateValue) && !endDateString) return @"Recurrence end date must be a string";
    if (HasValue(occurrenceValue) && !occurrenceNumber) return @"Recurrence occurrence must be an integer";
    if (endDateString) {
        NSDate *endDate = [self dateFromISO8601String:endDateString];
        if (!endDate) return @"Recurrence end date must use ISO 8601 format";
        recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:endDate];
    } else if (occurrenceNumber) {
        NSInteger occurrence = occurrenceNumber.integerValue;
        if (occurrence < 1) return @"Recurrence occurrence must be greater than zero";
        recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:occurrence];
    }

    NSMutableArray<EKRecurrenceDayOfWeek *> *daysOfWeek = nil;
    id dayOptionsValue = recurrence[@"daysOfWeek"];
    NSArray *dayOptions = ArrayOrNil(dayOptionsValue);
    if (HasValue(dayOptionsValue) && !dayOptions) return @"Recurrence daysOfWeek must be an array";
    if (dayOptions) {
        daysOfWeek = [NSMutableArray array];
        for (id dayValue in dayOptions) {
            NSDictionary *dayOption = DictOrNil(dayValue);
            if (!dayOption) return @"Each recurrence dayOfWeek must be an object";
            NSNumber *dayNumber = IntegerNumberOrNil(dayOption[@"dayOfWeek"]);
            if (!dayNumber) return @"Recurrence dayOfWeek must be an integer";
            NSInteger day = dayNumber.integerValue;
            if (day < 1 || day > 7) return @"Recurrence dayOfWeek must be between 1 and 7";
            id weekNumberValue = dayOption[@"weekNumber"];
            NSNumber *weekNumberObject = IntegerNumberOrNil(weekNumberValue);
            if (HasValue(weekNumberValue) && !weekNumberObject) return @"Recurrence weekNumber must be an integer";
            NSInteger weekNumber = weekNumberObject.integerValue;
            if (weekNumberObject && (weekNumber == 0 || weekNumber < -53 || weekNumber > 53)) {
                return @"Recurrence weekNumber must be between -53 and 53 and cannot be zero";
            }
            EKRecurrenceDayOfWeek *recurrenceDay = weekNumberObject
                ? [EKRecurrenceDayOfWeek dayOfWeek:(EKWeekday)day weekNumber:weekNumber]
                : [EKRecurrenceDayOfWeek dayOfWeek:(EKWeekday)day];
            [daysOfWeek addObject:recurrenceDay];
        }
    }

    id daysOfMonthValue = recurrence[@"daysOfMonth"];
    id monthsOfYearValue = recurrence[@"monthsOfYear"];
    id daysOfYearValue = recurrence[@"daysOfYear"];
    NSString *rangeError = [self validateRecurrenceValues:daysOfMonthValue minimum:-31 maximum:31 disallowZero:YES name:@"daysOfMonth"];
    if (rangeError) return rangeError;
    rangeError = [self validateRecurrenceValues:monthsOfYearValue minimum:1 maximum:12 disallowZero:NO name:@"monthsOfYear"];
    if (rangeError) return rangeError;
    rangeError = [self validateRecurrenceValues:daysOfYearValue minimum:-366 maximum:366 disallowZero:YES name:@"daysOfYear"];
    if (rangeError) return rangeError;

    EKRecurrenceRule *rule = [[EKRecurrenceRule alloc]
        initRecurrenceWithFrequency:(EKRecurrenceFrequency)frequencyValue.integerValue
        interval:interval
        daysOfTheWeek:daysOfWeek
        daysOfTheMonth:ArrayOrNil(daysOfMonthValue)
        monthsOfTheYear:ArrayOrNil(monthsOfYearValue)
        weeksOfTheYear:nil
        daysOfTheYear:ArrayOrNil(daysOfYearValue)
        setPositions:nil
        end:recurrenceEnd];
    event.recurrenceRules = @[rule];
    return nil;
}

// Guards EventKit against invalid recurrence ranges from plain JavaScript
- (NSString *)validateRecurrenceValues:(id)valuesValue
                                minimum:(NSInteger)minimum
                                maximum:(NSInteger)maximum
                           disallowZero:(BOOL)disallowZero
                                   name:(NSString *)name {
    if (!HasValue(valuesValue)) return nil;
    NSArray *values = ArrayOrNil(valuesValue);
    if (!values) return [NSString stringWithFormat:@"Recurrence %@ must be an array", name];
    for (id numberValue in values) {
        NSNumber *number = IntegerNumberOrNil(numberValue);
        if (!number) return [NSString stringWithFormat:@"Recurrence %@ values must be integers", name];
        NSInteger value = number.integerValue;
        if (value < minimum || value > maximum || (disallowZero && value == 0)) {
            return [NSString stringWithFormat:@"Invalid recurrence value for %@", name];
        }
    }
    return nil;
}

- (void)applyEventProperties:(NSDictionary *)eventDict toEvent:(EKEvent *)event {
    event.title = eventDict[@"title"];
    event.startDate = [self dateFromISO8601String:eventDict[@"startDate"]];
    event.endDate = [self dateFromISO8601String:eventDict[@"endDate"]];
    event.location = eventDict[@"location"];
    event.notes = eventDict[@"notes"];
    event.URL = eventDict[@"url"] ? [NSURL URLWithString:eventDict[@"url"]] : nil;
    event.allDay = [eventDict[@"allDay"] boolValue];
    
    // Set calendar
    if (eventDict[@"calendar"]) {
        EKCalendar *calendar = [self.eventStore calendarWithIdentifier:eventDict[@"calendar"]];
        if (calendar) {
            event.calendar = calendar;
        }
    } else {
        event.calendar = self.eventStore.defaultCalendarForNewEvents;
    }
    
    // Set availability
    NSString *availability = eventDict[@"availability"];
    if ([availability isEqualToString:@"busy"]) {
        event.availability = EKEventAvailabilityBusy;
    } else if ([availability isEqualToString:@"free"]) {
        event.availability = EKEventAvailabilityFree;
    } else if ([availability isEqualToString:@"tentative"]) {
        event.availability = EKEventAvailabilityTentative;
    } else if ([availability isEqualToString:@"unavailable"]) {
        event.availability = EKEventAvailabilityUnavailable;
    }
    
    // Set alarms
    NSArray *alarms = eventDict[@"alarms"];
    if (alarms && alarms.count > 0) {
        NSMutableArray<EKAlarm *> *ekAlarms = [NSMutableArray array];
        for (NSDictionary *alarmDict in alarms) {
            EKAlarm *alarm;
            if (alarmDict[@"date"]) {
                NSDate *alarmDate = [self dateFromISO8601String:alarmDict[@"date"]];
                alarm = [EKAlarm alarmWithAbsoluteDate:alarmDate];
            } else if (alarmDict[@"minutes"]) {
                NSTimeInterval offset = -[alarmDict[@"minutes"] doubleValue] * 60;
                alarm = [EKAlarm alarmWithRelativeOffset:offset];
            }
            if (alarm) {
                [ekAlarms addObject:alarm];
            }
        }
        event.alarms = ekAlarms;
    }
    
    // Set recurrence
    NSDictionary *recurrence = eventDict[@"recurrence"];
    if (recurrence) {
        EKRecurrenceFrequency frequency;
        NSString *freq = recurrence[@"frequency"];
        if ([freq isEqualToString:@"daily"]) {
            frequency = EKRecurrenceFrequencyDaily;
        } else if ([freq isEqualToString:@"weekly"]) {
            frequency = EKRecurrenceFrequencyWeekly;
        } else if ([freq isEqualToString:@"monthly"]) {
            frequency = EKRecurrenceFrequencyMonthly;
        } else if ([freq isEqualToString:@"yearly"]) {
            frequency = EKRecurrenceFrequencyYearly;
        } else {
            frequency = EKRecurrenceFrequencyDaily;
        }
        
        NSInteger interval = [recurrence[@"interval"] integerValue] ?: 1;
        
        EKRecurrenceEnd *recurrenceEnd = nil;
        if (recurrence[@"endDate"]) {
            NSDate *endDate = [self dateFromISO8601String:recurrence[@"endDate"]];
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:endDate];
        } else if (recurrence[@"occurrence"]) {
            NSInteger occurrenceCount = [recurrence[@"occurrence"] integerValue];
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:occurrenceCount];
        }
        
        EKRecurrenceRule *rule = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:frequency
                                                                               interval:interval
                                                                                    end:recurrenceEnd];
        event.recurrenceRules = @[rule];
    }
}

- (NSDictionary *)serializeEvent:(EKEvent *)event {
    NSMutableDictionary *eventDict = [NSMutableDictionary dictionary];
    
    eventDict[@"id"] = event.eventIdentifier ?: @"";
    eventDict[@"title"] = event.title ?: @"";
    eventDict[@"startDate"] = [self ISO8601StringFromDate:event.startDate];
    eventDict[@"endDate"] = [self ISO8601StringFromDate:event.endDate];
    eventDict[@"location"] = event.location ?: @"";
    eventDict[@"notes"] = event.notes ?: @"";
    eventDict[@"url"] = event.URL.absoluteString ?: @"";
    eventDict[@"allDay"] = @(event.allDay);
    eventDict[@"calendar"] = event.calendar.calendarIdentifier ?: @"";
    
    // Serialize availability
    switch (event.availability) {
        case EKEventAvailabilityBusy:
            eventDict[@"availability"] = @"busy";
            break;
        case EKEventAvailabilityFree:
            eventDict[@"availability"] = @"free";
            break;
        case EKEventAvailabilityTentative:
            eventDict[@"availability"] = @"tentative";
            break;
        case EKEventAvailabilityUnavailable:
            eventDict[@"availability"] = @"unavailable";
            break;
        default:
            eventDict[@"availability"] = @"busy";
            break;
    }
    
    // Serialize alarms
    if (event.alarms && event.alarms.count > 0) {
        NSMutableArray *alarms = [NSMutableArray array];
        for (EKAlarm *alarm in event.alarms) {
            NSMutableDictionary *alarmDict = [NSMutableDictionary dictionary];
            if (alarm.absoluteDate) {
                alarmDict[@"date"] = [self ISO8601StringFromDate:alarm.absoluteDate];
            } else {
                alarmDict[@"minutes"] = @(-alarm.relativeOffset / 60);
            }
            [alarms addObject:alarmDict];
        }
        eventDict[@"alarms"] = alarms;
    }
    
    // Serialize recurrence
    if (event.recurrenceRules && event.recurrenceRules.count > 0) {
        EKRecurrenceRule *rule = event.recurrenceRules.firstObject;
        NSMutableDictionary *recurrence = [NSMutableDictionary dictionary];
        
        switch (rule.frequency) {
            case EKRecurrenceFrequencyDaily:
                recurrence[@"frequency"] = @"daily";
                break;
            case EKRecurrenceFrequencyWeekly:
                recurrence[@"frequency"] = @"weekly";
                break;
            case EKRecurrenceFrequencyMonthly:
                recurrence[@"frequency"] = @"monthly";
                break;
            case EKRecurrenceFrequencyYearly:
                recurrence[@"frequency"] = @"yearly";
                break;
        }
        
        recurrence[@"interval"] = @(rule.interval);
        
        if (rule.recurrenceEnd) {
            if (rule.recurrenceEnd.endDate) {
                recurrence[@"endDate"] = [self ISO8601StringFromDate:rule.recurrenceEnd.endDate];
            } else if (rule.recurrenceEnd.occurrenceCount > 0) {
                recurrence[@"occurrence"] = @(rule.recurrenceEnd.occurrenceCount);
            }
        }
        
        eventDict[@"recurrence"] = recurrence;
    }
    
    return eventDict;
}

#pragma mark - EKEventEditViewDelegate

- (void)eventEditViewController:(EKEventEditViewController *)controller
          didCompleteWithAction:(EKEventEditViewAction)action {
    [controller dismissViewControllerAnimated:YES completion:^{
        if (self.editEventResolver) {
            self.editEventResolver(nil);
            self.editEventResolver = nil;
            self.editEventRejecter = nil;
        }
    }];
}

#pragma mark - Date Helpers

- (NSDate *)dateFromISO8601String:(NSString *)dateString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone localTimeZone];
    return [formatter dateFromString:dateString];
}

- (NSString *)ISO8601StringFromDate:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone localTimeZone];
    return [formatter stringFromDate:date];
}

#pragma mark - Color Helpers

- (NSString *)hexStringFromColor:(CGColorRef)color {
    const CGFloat *components = CGColorGetComponents(color);
    CGFloat r = components[0];
    CGFloat g = components[1];
    CGFloat b = components[2];
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            lroundf(r * 255),
            lroundf(g * 255),
            lroundf(b * 255)];
}

- (CGColorRef)colorFromHexString:(NSString *)hexString {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    
    CGFloat red = ((rgbValue & 0xFF0000) >> 16) / 255.0;
    CGFloat green = ((rgbValue & 0x00FF00) >> 8) / 255.0;
    CGFloat blue = (rgbValue & 0x0000FF) / 255.0;
    
    return CGColorCreateGenericRGB(red, green, blue, 1.0);
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeCalendarEventsNativeSpecSpecJSI>(params);
    
}
#endif

@end
