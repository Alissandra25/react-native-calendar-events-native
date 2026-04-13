import type { TurboModule } from 'react-native';
import { NativeModules, TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  debugModuleMethods(): Promise<string>;
  requestPermissions(writeOnly: boolean): Promise<string>;
  checkPermissions(writeOnly: boolean): Promise<string>;
  fetchAllCalendars(): Promise<Array<{
    id: string;
    title: string;
    type: string;
    source: string;
    isPrimary?: boolean;
    allowsModifications?: boolean;
    color?: string;
    allowedAvailabilities?: Array<string>;
  }>>;
  findOrCreateCalendar(
    title: string,
    color?: string,
    entityType?: string,
    source?: string
  ): Promise<{
    id: string;
    title: string;
    type: string;
    source: string;
    isPrimary?: boolean;
    allowsModifications?: boolean;
    color?: string;
    allowedAvailabilities?: Array<string>;
  }>;
  removeCalendar(calendarId: string): Promise<boolean>;
  fetchAllEvents(
    startDate: string,
    endDate: string,
    calendarIds: Array<string>
  ): Promise<Array<{
    id?: string;
    title: string;
    startDate: string;
    endDate: string;
    location?: string;
    notes?: string;
    url?: string;
    alarms?: Array<{
      date?: string;
      structuredLocation?: {
        title?: string;
        proximity?: string;
        radius?: number;
        coords?: {
          latitude: number;
          longitude: number;
        };
      };
      minutes?: number;
    }>;
    recurrence?: {
      frequency: string;
      interval?: number;
      endDate?: string;
      occurrence?: number;
      daysOfWeek?: Array<{
        dayOfWeek: number;
        weekNumber?: number;
      }>;
      daysOfMonth?: Array<number>;
      monthsOfYear?: Array<number>;
      daysOfYear?: Array<number>;
    };
    availability?: string;
    allDay?: boolean;
    calendar?: string;
  }>>;
  findEventById(eventId: string): Promise<{
    id?: string;
    title: string;
    startDate: string;
    endDate: string;
    location?: string;
    notes?: string;
    url?: string;
    alarms?: Array<{
      date?: string;
      structuredLocation?: {
        title?: string;
        proximity?: string;
        radius?: number;
        coords?: {
          latitude: number;
          longitude: number;
        };
      };
      minutes?: number;
    }>;
    recurrence?: {
      frequency: string;
      interval?: number;
      endDate?: string;
      occurrence?: number;
      daysOfWeek?: Array<{
        dayOfWeek: number;
        weekNumber?: number;
      }>;
      daysOfMonth?: Array<number>;
      monthsOfYear?: Array<number>;
      daysOfYear?: Array<number>;
    };
    availability?: string;
    allDay?: boolean;
    calendar?: string;
  } | null>;
  saveEvent(
    title: string,
    startDate: string,
    endDate: string,
    location: string,
    notes: string,
    calendarId: string
  ): Promise<string>;
  updateEvent(
    eventId: string,
    title: string,
    startDate: string,
    endDate: string,
    location: string,
    notes: string,
    calendarId: string
  ): Promise<string>;
  removeEvent(eventId: string): Promise<boolean>;
  openEventInCalendar?(eventId: string): Promise<void>;
}

const turboModule = TurboModuleRegistry.get<Spec>('RNCalendarEventsNativeSpec');

// Fallback keeps app booting if TurboModule registration is missing in the current binary.
const bridgedModule =
  (NativeModules.RNCalendarEventsNativeSpec as Spec | undefined) ??
  (NativeModules.CalendarEventsNative as Spec | undefined);

export default turboModule ?? bridgedModule ?? null;
