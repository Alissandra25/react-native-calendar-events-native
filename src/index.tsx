import { PermissionsAndroid, Platform } from 'react-native';
import CalendarEventsNative from './NativeCalendarEventsNativeSpec';

export interface CalendarEvent {
  id?: string;
  title: string;
  startDate: string | Date;
  endDate: string | Date;
  location?: string;
  notes?: string;
  url?: string;
  alarms?: CalendarAlarm[];
  recurrence?: RecurrenceRule;
  availability?: 'busy' | 'free' | 'tentative' | 'unavailable';
  allDay?: boolean;
  calendar?: string;
}

export interface CalendarAlarm {
  date?: string | Date;
  structuredLocation?: {
    title?: string;
    proximity?: 'enter' | 'leave' | 'none';
    radius?: number;
    coords?: {
      latitude: number;
      longitude: number;
    };
  };
  minutes?: number;
}

export interface RecurrenceRule {
  frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
  interval?: number;
  endDate?: string | Date;
  occurrence?: number;
  daysOfWeek?: Array<{
    dayOfWeek: number;
    weekNumber?: number;
  }>;
  daysOfMonth?: number[];
  monthsOfYear?: number[];
  daysOfYear?: number[];
}

export interface Calendar {
  id: string;
  title: string;
  type: string;
  source: string;
  isPrimary?: boolean;
  allowsModifications?: boolean;
  color?: string;
  allowedAvailabilities?: string[];
}

export type AuthorizationStatus =
  | 'authorized'
  | 'denied'
  | 'restricted'
  | 'undetermined';

export type PermissionStatus =
  | 'granted'
  | 'denied'
  | 'never_ask_again'
  | 'unavailable';

export type AllPermissionStatus = AuthorizationStatus | PermissionStatus;

class CalendarEvents {
  private readonly native: any;

  constructor() {
    this.native = CalendarEventsNative as any;
  }

  private requireNativeModule() {
    if (!this.native) {
      throw new Error(
        'react-native-calendar-events-native is unavailable in the current binary. Rebuild the native app and reinstall it.',
      );
    }
    return this.native;
  }

  /**
   * Debug method to check available methods
   */
  async debugModuleMethods(): Promise<string> {
    return this.requireNativeModule().debugModuleMethods();
  }

  /**
   * Request calendar permissions
   */
  async requestPermissions(writeOnly: boolean = false): Promise<AllPermissionStatus> {
    if (Platform.OS === 'ios') {
      return this.requireNativeModule().requestPermissions(writeOnly) as Promise<AuthorizationStatus>;
    } else if (Platform.OS === 'android') {
      const permissions = writeOnly
        ? [PermissionsAndroid.PERMISSIONS.WRITE_CALENDAR]
        : [
            PermissionsAndroid.PERMISSIONS.READ_CALENDAR,
            PermissionsAndroid.PERMISSIONS.WRITE_CALENDAR
          ];

      const validPermissions = permissions.filter(p => p !== undefined);
      const results = await PermissionsAndroid.requestMultiple(validPermissions as any);

      if (validPermissions.every(p => p && (results as any)[p as string] === PermissionsAndroid.RESULTS.GRANTED)) {
        return 'granted';
      } else if (validPermissions.some(p => p && (results as any)[p as string] === PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN)) {
        return 'never_ask_again';
      } else {
        return 'denied';
      }
    }
    return 'unavailable';
  }

  /**
   * Check current calendar permissions
   */
  async checkPermissions(writeOnly: boolean = false): Promise<AllPermissionStatus> {
    if (Platform.OS === 'ios') {
      return this.requireNativeModule().checkPermissions(writeOnly) as Promise<AuthorizationStatus>;
    } else if (Platform.OS === 'android') {
      const permissions = writeOnly
        ? [PermissionsAndroid.PERMISSIONS.WRITE_CALENDAR]
        : [
            PermissionsAndroid.PERMISSIONS.READ_CALENDAR,
            PermissionsAndroid.PERMISSIONS.WRITE_CALENDAR
          ];

      const validPermissions = permissions.filter(p => p !== undefined);
      const results = await Promise.all(
        validPermissions.map(p => PermissionsAndroid.check(p as any))
      );

      if (results.every(r => r === true)) {
        return 'granted';
      } else {
        return 'denied';
      }
    }
    return 'unavailable';
  }

  /**
   * Fetch all calendars
   */
  async fetchAllCalendars(): Promise<Calendar[]> {
    return this.requireNativeModule().fetchAllCalendars();
  }

  /**
   * Find or create a calendar
   */
  async findOrCreateCalendar(calendar: Partial<Calendar>): Promise<Calendar> {
    return this.requireNativeModule().findOrCreateCalendar(
      calendar.title || 'Calendar',
      calendar.color,
      undefined, // entityType
      calendar.source
    );
  }

  /**
   * Remove a calendar
   */
  async removeCalendar(calendarId: string): Promise<boolean> {
    return this.requireNativeModule().removeCalendar(calendarId);
  }

  /**
   * Fetch all events
   */
  async fetchAllEvents(
    startDate: string | Date,
    endDate: string | Date,
    calendarIds?: string[]
  ): Promise<CalendarEvent[]> {
    const start = typeof startDate === 'string' ? startDate : startDate.toISOString();
    const end = typeof endDate === 'string' ? endDate : endDate.toISOString();
    const events = await this.requireNativeModule().fetchAllEvents(start, end, calendarIds || []);
    return events as CalendarEvent[];
  }

  /**
   * Find event by ID
   */
  async findEventById(id: string): Promise<CalendarEvent | null> {
    const event = await this.requireNativeModule().findEventById(id);
    return event as CalendarEvent | null;
  }

  /**
   * Save an event
   */
  async saveEvent(event: CalendarEvent): Promise<string> {
    const startDate = typeof event.startDate === 'string'
      ? event.startDate
      : event.startDate.toISOString();
    const endDate = typeof event.endDate === 'string'
      ? event.endDate
      : event.endDate.toISOString();

    return this.requireNativeModule().saveEvent(
      event.title,
      startDate,
      endDate,
      event.location || '',
      event.notes || '',
      event.calendar || ''
    );
  }

  /**
   * Update an event
   */
  async updateEvent(eventId: string, event: Partial<CalendarEvent>): Promise<string> {
    const startDate = event.startDate
      ? (typeof event.startDate === 'string' ? event.startDate : event.startDate.toISOString())
      : '';
    const endDate = event.endDate
      ? (typeof event.endDate === 'string' ? event.endDate : event.endDate.toISOString())
      : '';

    return this.requireNativeModule().updateEvent(
      eventId,
      event.title || '',
      startDate,
      endDate,
      event.location || '',
      event.notes || '',
      event.calendar || ''
    );
  }

  /**
   * Remove an event
   */
  async removeEvent(eventId: string): Promise<boolean> {
    return this.requireNativeModule().removeEvent(eventId);
  }

  /**
   * Open event in calendar app
   */
  async openEventInCalendar(eventId: string): Promise<void> {
    const nativeModule = this.requireNativeModule();
    if (Platform.OS === 'ios' && nativeModule.openEventInCalendar) {
      return nativeModule.openEventInCalendar(eventId);
    } else {
      throw new Error('Opening events in calendar app is only supported on iOS');
    }
  }
}

export default new CalendarEvents();
