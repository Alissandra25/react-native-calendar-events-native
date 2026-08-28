package com.calendarevents;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CalendarContract;
import android.provider.CalendarContract.Calendars;
import android.provider.CalendarContract.Events;
import android.provider.CalendarContract.Reminders;
import android.text.TextUtils;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.ReadableType;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.module.annotations.ReactModule;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

@ReactModule(name = CalendarEventsNativeModule.NAME)
public class CalendarEventsNativeModule extends NativeCalendarEventsNativeSpecSpec {
    public static final String NAME = "RNCalendarEventsNativeSpec";
    private static final SimpleDateFormat ISO_8601_FORMAT = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);

    static {
        ISO_8601_FORMAT.setTimeZone(TimeZone.getTimeZone("UTC"));
    }

    public CalendarEventsNativeModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    @NonNull
    public String getName() {
        return NAME;
    }

    // Debug method required by TurboModule spec
    @ReactMethod
    public void debugModuleMethods(Promise promise) {
        promise.resolve("CalendarEventsNative module methods: debugModuleMethods, requestPermissions, checkPermissions, fetchAllCalendars, findOrCreateCalendar, removeCalendar, fetchAllEvents, findEventById, saveEvent, openEventEditor, updateEvent, removeEvent, openEventInCalendar");
    }

    // Permission methods
    @ReactMethod
    public void requestPermissions(boolean writeOnly, Promise promise) {
        // Permission handling is done in JavaScript side using PermissionsAndroid
        // This is just a placeholder for consistency with iOS
        checkPermissions(writeOnly, promise);
    }

    @ReactMethod
    public void checkPermissions(boolean writeOnly, Promise promise) {
        Context context = getReactApplicationContext();
        boolean hasReadPermission = ContextCompat.checkSelfPermission(context,
            Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED;
        boolean hasWritePermission = ContextCompat.checkSelfPermission(context,
            Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED;

        if (writeOnly) {
            promise.resolve(hasWritePermission ? "granted" : "denied");
        } else {
            promise.resolve(hasReadPermission && hasWritePermission ? "granted" : "denied");
        }
    }

    // Calendar methods
    @ReactMethod
    public void fetchAllCalendars(Promise promise) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();

        String[] projection = new String[] {
            Calendars._ID,
            Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.ACCOUNT_NAME,
            Calendars.ACCOUNT_TYPE,
            Calendars.IS_PRIMARY,
            Calendars.CALENDAR_COLOR,
            Calendars.CALENDAR_ACCESS_LEVEL
        };

        Cursor cursor = cr.query(Calendars.CONTENT_URI, projection, null, null, null);
        WritableArray calendars = Arguments.createArray();

        if (cursor != null) {
            while (cursor.moveToNext()) {
                WritableMap calendar = Arguments.createMap();
                calendar.putString("id", cursor.getString(0));
                calendar.putString("title", cursor.getString(1));
                calendar.putString("source", cursor.getString(2));
                calendar.putString("type", cursor.getString(3));
                calendar.putBoolean("isPrimary", cursor.getInt(4) == 1);
                calendar.putString("color", String.format("#%06X", (0xFFFFFF & cursor.getInt(5))));
                calendar.putBoolean("allowsModifications",
                    cursor.getInt(6) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR);

                WritableArray availabilities = Arguments.createArray();
                availabilities.pushString("busy");
                availabilities.pushString("free");
                calendar.putArray("allowedAvailabilities", availabilities);

                calendars.pushMap(calendar);
            }
            cursor.close();
        }

        promise.resolve(calendars);
    }

    @ReactMethod
    public void findOrCreateCalendar(String title, @Nullable String color, @Nullable String entityType, @Nullable String source, Promise promise) {
        // First, try to find existing calendar
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        String[] projection = new String[] { Calendars._ID, Calendars.CALENDAR_DISPLAY_NAME };
        Cursor cursor = cr.query(Calendars.CONTENT_URI, projection,
            Calendars.CALENDAR_DISPLAY_NAME + " = ?", new String[] { title }, null);

        if (cursor != null && cursor.moveToFirst()) {
            String calendarId = cursor.getString(0);
            String displayName = cursor.getString(1);
            cursor.close();

            WritableMap result = Arguments.createMap();
            result.putString("id", calendarId);
            result.putString("title", displayName);
            result.putString("source", source != null ? source : "local");
            result.putString("type", entityType != null ? entityType : "local");
            result.putBoolean("isPrimary", false);
            result.putBoolean("allowsModifications", true);

            promise.resolve(result);
            return;
        }

        if (cursor != null) {
            cursor.close();
        }

        // Create new calendar
        ContentValues values = new ContentValues();
        values.put(Calendars.ACCOUNT_NAME, "CalendarEventsNative");
        values.put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL);
        values.put(Calendars.NAME, title);
        values.put(Calendars.CALENDAR_DISPLAY_NAME, title);
        values.put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER);
        values.put(Calendars.OWNER_ACCOUNT, "CalendarEventsNative");
        values.put(Calendars.VISIBLE, 1);
        values.put(Calendars.SYNC_EVENTS, 1);

        if (color != null) {
            try {
                int colorInt = (int) Long.parseLong(color.replace("#", ""), 16);
                values.put(Calendars.CALENDAR_COLOR, colorInt);
            } catch (NumberFormatException e) {
                // ignore invalid color
            }
        }

        Uri.Builder builder = Calendars.CONTENT_URI.buildUpon();
        builder.appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true");
        builder.appendQueryParameter(Calendars.ACCOUNT_NAME, "CalendarEventsNative");
        builder.appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL);

        Uri uri = cr.insert(builder.build(), values);
        if (uri != null) {
            String calendarId = uri.getLastPathSegment();

            WritableMap result = Arguments.createMap();
            result.putString("id", calendarId);
            result.putString("title", title);
            result.putString("source", source != null ? source : "local");
            result.putString("type", entityType != null ? entityType : "local");
            result.putBoolean("isPrimary", false);
            result.putBoolean("allowsModifications", true);
            if (color != null) result.putString("color", color);

            promise.resolve(result);
        } else {
            promise.reject("CALENDAR_CREATION_FAILED", "Failed to create calendar");
        }
    }

    @ReactMethod
    public void removeCalendar(String calendarId, Promise promise) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        Uri uri = ContentUris.withAppendedId(Calendars.CONTENT_URI, Long.parseLong(calendarId));
        int rows = cr.delete(uri, null, null);
        promise.resolve(rows > 0);
    }

    // Event methods
    @ReactMethod
    public void fetchAllEvents(String startDate, String endDate, ReadableArray calendarIds, Promise promise) {
        long startMillis = parseDate(startDate);
        long endMillis = parseDate(endDate);

        ContentResolver cr = getReactApplicationContext().getContentResolver();

        String selection = Events.DTSTART + " >= ? AND " + Events.DTSTART + " <= ?";
        String[] selectionArgs = new String[] { String.valueOf(startMillis), String.valueOf(endMillis) };

        if (calendarIds != null && calendarIds.size() > 0) {
            StringBuilder calendarSelection = new StringBuilder(" AND " + Events.CALENDAR_ID + " IN (");
            for (int i = 0; i < calendarIds.size(); i++) {
                if (i > 0) calendarSelection.append(",");
                calendarSelection.append(calendarIds.getString(i));
            }
            calendarSelection.append(")");
            selection += calendarSelection.toString();
        }

        String[] projection = new String[] {
            Events._ID,
            Events.TITLE,
            Events.DESCRIPTION,
            Events.DTSTART,
            Events.DTEND,
            Events.ALL_DAY,
            Events.EVENT_LOCATION,
            Events.CALENDAR_ID,
            Events.AVAILABILITY,
            Events.RRULE,
            Events.CUSTOM_APP_URI
        };

        Cursor cursor = cr.query(Events.CONTENT_URI, projection, selection, selectionArgs, null);
        WritableArray events = Arguments.createArray();

        if (cursor != null) {
            while (cursor.moveToNext()) {
                WritableMap event = serializeEvent(cursor);
                events.pushMap(event);
            }
            cursor.close();
        }

        promise.resolve(events);
    }

    @ReactMethod
    public void findEventById(String eventId, Promise promise) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        Uri uri = ContentUris.withAppendedId(Events.CONTENT_URI, Long.parseLong(eventId));

        String[] projection = new String[] {
            Events._ID,
            Events.TITLE,
            Events.DESCRIPTION,
            Events.DTSTART,
            Events.DTEND,
            Events.ALL_DAY,
            Events.EVENT_LOCATION,
            Events.CALENDAR_ID,
            Events.AVAILABILITY,
            Events.RRULE,
            Events.CUSTOM_APP_URI
        };

        Cursor cursor = cr.query(uri, projection, null, null, null);

        if (cursor != null && cursor.moveToFirst()) {
            WritableMap event = serializeEvent(cursor);
            cursor.close();
            promise.resolve(event);
        } else {
            promise.resolve(null);
        }
    }


    @ReactMethod
    public void removeEvent(String eventId, Promise promise) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        Uri uri = ContentUris.withAppendedId(Events.CONTENT_URI, Long.parseLong(eventId));
        int rows = cr.delete(uri, null, null);
        promise.resolve(rows > 0);
    }

    // Opens the system editor without writing to the calendar provider
    @ReactMethod
    public void openEventEditor(ReadableMap event, Promise promise) {
        try {
            String title = event.getString("title");
            String startDate = event.getString("startDate");
            String endDate = event.getString("endDate");
            boolean allDay = event.hasKey("allDay") && event.getBoolean("allDay");
            long startMillis = ISO_8601_FORMAT.parse(startDate).getTime();
            long endMillis = ISO_8601_FORMAT.parse(endDate).getTime();
            if (endMillis < startMillis) {
                promise.reject("invalid_event_dates", "Event end date must not be before its start date");
                return;
            }
            if (allDay) {
                startMillis = CalendarEventDateUtils.toUtcMidnight(startMillis);
                endMillis = CalendarEventDateUtils.toExclusiveUtcMidnightEnd(startMillis, endMillis);
            }

            Intent intent = new Intent(Intent.ACTION_INSERT, Events.CONTENT_URI);
            intent.putExtra(Events.TITLE, title);
            intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMillis);
            intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis);
            if (event.hasKey("location") && !TextUtils.isEmpty(event.getString("location"))) {
                intent.putExtra(Events.EVENT_LOCATION, event.getString("location"));
            }
            if (event.hasKey("notes") && !TextUtils.isEmpty(event.getString("notes"))) {
                intent.putExtra(Events.DESCRIPTION, event.getString("notes"));
            }
            intent.putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, allDay);

            if (event.hasKey("calendar")) {
                intent.putExtra(Events.CALENDAR_ID, Long.parseLong(event.getString("calendar")));
            }
            if (event.hasKey("availability")) {
                intent.putExtra(Events.AVAILABILITY, parseAvailability(event.getString("availability")));
            }
            if (event.hasKey("recurrence")) {
                intent.putExtra(Events.RRULE, buildRRule(event.getMap("recurrence")));
            }

            if (event.hasKey("android")) {
                ReadableMap androidOptions = event.getMap("android");
                if (androidOptions != null && androidOptions.hasKey("attendees")) {
                    String attendees = joinStrings(androidOptions.getArray("attendees"));
                    if (!TextUtils.isEmpty(attendees)) intent.putExtra(Intent.EXTRA_EMAIL, attendees);
                }
            }

            Activity activity = getReactApplicationContext().getCurrentActivity();
            if (activity != null) {
                activity.startActivity(intent);
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getReactApplicationContext().startActivity(intent);
            }
            promise.resolve(null);
        } catch (ParseException e) {
            promise.reject("invalid_event_dates", "Event dates must use ISO 8601 format", e);
        } catch (NumberFormatException e) {
            promise.reject("invalid_calendar", "Android calendar IDs must be numeric strings", e);
        } catch (IllegalArgumentException e) {
            promise.reject("invalid_event_options", e.getMessage(), e);
        } catch (ActivityNotFoundException e) {
            promise.reject("event_editor_unavailable", "No calendar app can create this event", e);
        } catch (Exception e) {
            promise.reject("open_event_editor_failed", "Failed to open the calendar editor", e);
        }
    }

    @ReactMethod
    public void openEventInCalendar(String eventId, Promise promise) {
        // Android doesn't support opening events directly in the calendar app
        // We can only open the calendar app
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setData(Uri.parse("content://com.android.calendar/time"));
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        try {
            getReactApplicationContext().startActivity(intent);
            promise.resolve(null);
        } catch (Exception e) {
            promise.reject("OPEN_CALENDAR_FAILED", "Failed to open calendar app", e);
        }
    }

    // Helper methods
    private void applyEventProperties(ReadableMap eventMap, ContentValues values) {
        if (eventMap.hasKey("title")) {
            values.put(Events.TITLE, eventMap.getString("title"));
        }

        if (eventMap.hasKey("startDate")) {
            values.put(Events.DTSTART, parseDate(eventMap.getString("startDate")));
        }

        if (eventMap.hasKey("endDate")) {
            values.put(Events.DTEND, parseDate(eventMap.getString("endDate")));
        }

        if (eventMap.hasKey("location")) {
            values.put(Events.EVENT_LOCATION, eventMap.getString("location"));
        }

        if (eventMap.hasKey("notes")) {
            values.put(Events.DESCRIPTION, eventMap.getString("notes"));
        }

        if (eventMap.hasKey("url")) {
            values.put(Events.CUSTOM_APP_URI, eventMap.getString("url"));
        }

        if (eventMap.hasKey("allDay")) {
            values.put(Events.ALL_DAY, eventMap.getBoolean("allDay") ? 1 : 0);
        }

        if (eventMap.hasKey("calendar")) {
            values.put(Events.CALENDAR_ID, Long.parseLong(eventMap.getString("calendar")));
        }

        if (eventMap.hasKey("availability")) {
            String availability = eventMap.getString("availability");
            int availabilityValue = Events.AVAILABILITY_BUSY;
            if ("free".equals(availability)) {
                availabilityValue = Events.AVAILABILITY_FREE;
            } else if ("tentative".equals(availability)) {
                availabilityValue = Events.AVAILABILITY_TENTATIVE;
            }
            values.put(Events.AVAILABILITY, availabilityValue);
        }

        if (eventMap.hasKey("recurrence")) {
            ReadableMap recurrence = eventMap.getMap("recurrence");
            String rrule = buildRRule(recurrence);
            if (!TextUtils.isEmpty(rrule)) {
                values.put(Events.RRULE, rrule);
                values.put(Events.DURATION, "P3600S"); // Default 1 hour duration for recurring events
            }
        }

        values.put(Events.EVENT_TIMEZONE, TimeZone.getDefault().getID());
    }

    private WritableMap serializeEvent(Cursor cursor) {
        WritableMap event = Arguments.createMap();

        event.putString("id", cursor.getString(0));
        event.putString("title", cursor.getString(1));
        event.putString("notes", cursor.getString(2));
        event.putString("startDate", formatDate(cursor.getLong(3)));
        event.putString("endDate", formatDate(cursor.getLong(4)));
        event.putBoolean("allDay", cursor.getInt(5) == 1);
        event.putString("location", cursor.getString(6));
        event.putString("calendar", cursor.getString(7));

        int availability = cursor.getInt(8);
        String availabilityStr = "busy";
        if (availability == Events.AVAILABILITY_FREE) {
            availabilityStr = "free";
        } else if (availability == Events.AVAILABILITY_TENTATIVE) {
            availabilityStr = "tentative";
        }
        event.putString("availability", availabilityStr);

        String rrule = cursor.getString(9);
        if (!TextUtils.isEmpty(rrule)) {
            event.putMap("recurrence", parseRRule(rrule));
        }

        event.putString("url", cursor.getString(10));

        // Get alarms
        WritableArray alarms = getEventReminders(cursor.getString(0));
        if (alarms.size() > 0) {
            event.putArray("alarms", alarms);
        }

        return event;
    }

    private WritableArray getEventReminders(String eventId) {
        WritableArray alarms = Arguments.createArray();
        ContentResolver cr = getReactApplicationContext().getContentResolver();

        Cursor cursor = cr.query(Reminders.CONTENT_URI,
            new String[] { Reminders.MINUTES },
            Reminders.EVENT_ID + " = ?",
            new String[] { eventId },
            null);

        if (cursor != null) {
            while (cursor.moveToNext()) {
                WritableMap alarm = Arguments.createMap();
                alarm.putInt("minutes", cursor.getInt(0));
                alarms.pushMap(alarm);
            }
            cursor.close();
        }

        return alarms;
    }

    private void addReminder(String eventId, ReadableMap alarm) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        ContentValues values = new ContentValues();

        values.put(Reminders.EVENT_ID, Long.parseLong(eventId));
        values.put(Reminders.METHOD, Reminders.METHOD_ALERT);

        if (alarm.hasKey("minutes")) {
            values.put(Reminders.MINUTES, alarm.getInt("minutes"));
        } else {
            values.put(Reminders.MINUTES, 15); // Default 15 minutes
        }

        cr.insert(Reminders.CONTENT_URI, values);
    }

    private String buildRRule(ReadableMap recurrence) {
        StringBuilder rrule = new StringBuilder();

        String frequency = recurrence.hasKey("frequency")
            && recurrence.getType("frequency") == ReadableType.String
                ? recurrence.getString("frequency")
                : null;
        if (!"daily".equals(frequency) && !"weekly".equals(frequency)
            && !"monthly".equals(frequency) && !"yearly".equals(frequency)) {
            throw new IllegalArgumentException("Recurrence frequency must be daily, weekly, monthly, or yearly");
        }
        rrule.append("FREQ=").append(frequency.toUpperCase(Locale.US));

        if (recurrence.hasKey("interval")) {
            int interval = readInteger(recurrence, "interval", "Recurrence interval must be an integer");
            if (interval < 1) throw new IllegalArgumentException("Recurrence interval must be greater than zero");
            rrule.append(";INTERVAL=").append(interval);
        }

        if (recurrence.hasKey("endDate")) {
            long endMillis;
            try {
                endMillis = ISO_8601_FORMAT.parse(recurrence.getString("endDate")).getTime();
            } catch (ParseException e) {
                throw new IllegalArgumentException("Recurrence end date must use ISO 8601 format", e);
            }
            SimpleDateFormat format = new SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US);
            format.setTimeZone(TimeZone.getTimeZone("UTC"));
            rrule.append(";UNTIL=").append(format.format(new Date(endMillis)));
        } else if (recurrence.hasKey("occurrence")) {
            int occurrence = readInteger(recurrence, "occurrence", "Recurrence occurrence must be an integer");
            if (occurrence < 1) throw new IllegalArgumentException("Recurrence occurrence must be greater than zero");
            rrule.append(";COUNT=").append(occurrence);
        }

        appendDaysOfWeek(rrule, recurrence);
        appendIntegerArray(rrule, recurrence, "daysOfMonth", "BYMONTHDAY", -31, 31, true);
        appendIntegerArray(rrule, recurrence, "monthsOfYear", "BYMONTH", 1, 12, false);
        appendIntegerArray(rrule, recurrence, "daysOfYear", "BYYEARDAY", -366, 366, true);

        return rrule.toString();
    }

    // Maps the shared availability values to CalendarContract constants
    private int parseAvailability(String availability) {
        if ("busy".equals(availability)) return Events.AVAILABILITY_BUSY;
        if ("free".equals(availability)) return Events.AVAILABILITY_FREE;
        if ("tentative".equals(availability)) return Events.AVAILABILITY_TENTATIVE;
        throw new IllegalArgumentException("Android availability must be busy, free, or tentative");
    }

    // Formats Android-only attendee emails for the calendar intent
    private String joinStrings(@Nullable ReadableArray values) {
        if (values == null) return "";
        StringBuilder result = new StringBuilder();
        for (int index = 0; index < values.size(); index++) {
            String value = values.getString(index);
            if (TextUtils.isEmpty(value)) continue;
            if (result.length() > 0) result.append(',');
            result.append(value);
        }
        return result.toString();
    }

    // Converts EventKit weekday numbers to RFC 5545 weekday tokens
    private void appendDaysOfWeek(StringBuilder rrule, ReadableMap recurrence) {
        if (!recurrence.hasKey("daysOfWeek")) return;
        ReadableArray days = recurrence.getArray("daysOfWeek");
        if (days == null || days.size() == 0) return;
        String[] tokens = {"SU", "MO", "TU", "WE", "TH", "FR", "SA"};
        rrule.append(";BYDAY=");
        for (int index = 0; index < days.size(); index++) {
            ReadableMap day = days.getMap(index);
            int dayOfWeek = readInteger(day, "dayOfWeek", "Recurrence dayOfWeek must be an integer");
            if (dayOfWeek < 1 || dayOfWeek > 7) {
                throw new IllegalArgumentException("Recurrence dayOfWeek must be between 1 and 7");
            }
            if (index > 0) rrule.append(',');
            if (day.hasKey("weekNumber")) {
                int weekNumber = readInteger(day, "weekNumber", "Recurrence weekNumber must be an integer");
                if (weekNumber == 0 || weekNumber < -53 || weekNumber > 53) {
                    throw new IllegalArgumentException("Recurrence weekNumber must be between -53 and 53 and cannot be zero");
                }
                rrule.append(weekNumber);
            }
            rrule.append(tokens[dayOfWeek - 1]);
        }
    }

    // Appends a validated integer list to an RFC 5545 recurrence rule
    private void appendIntegerArray(StringBuilder rrule, ReadableMap recurrence, String key,
                                    String ruleKey, int minimum, int maximum, boolean disallowZero) {
        if (!recurrence.hasKey(key)) return;
        ReadableArray values = recurrence.getArray(key);
        if (values == null || values.size() == 0) return;
        rrule.append(';').append(ruleKey).append('=');
        for (int index = 0; index < values.size(); index++) {
            int value = readInteger(values, index, "Recurrence " + key + " values must be integers");
            if (value < minimum || value > maximum || (disallowZero && value == 0)) {
                throw new IllegalArgumentException("Invalid recurrence value for " + key);
            }
            if (index > 0) rrule.append(',');
            rrule.append(value);
        }
    }

    // Reads an integer without truncating a JavaScript number
    private int readInteger(ReadableMap values, String key, String errorMessage) {
        if (!values.hasKey(key) || values.getType(key) != ReadableType.Number) {
            throw new IllegalArgumentException(errorMessage);
        }
        return requireInteger(values.getDouble(key), errorMessage);
    }

    // Reads an array integer without truncating a JavaScript number
    private int readInteger(ReadableArray values, int index, String errorMessage) {
        if (values.getType(index) != ReadableType.Number) {
            throw new IllegalArgumentException(errorMessage);
        }
        return requireInteger(values.getDouble(index), errorMessage);
    }

    // Validates integer range after reading a JavaScript number
    private int requireInteger(double value, String errorMessage) {
        if (Double.isNaN(value) || Double.isInfinite(value) || value != Math.rint(value)
            || value < Integer.MIN_VALUE || value > Integer.MAX_VALUE) {
            throw new IllegalArgumentException(errorMessage);
        }
        return (int) value;
    }

    private WritableMap parseRRule(String rrule) {
        WritableMap recurrence = Arguments.createMap();

        String[] parts = rrule.split(";");
        for (String part : parts) {
            String[] keyValue = part.split("=");
            if (keyValue.length == 2) {
                String key = keyValue[0];
                String value = keyValue[1];

                if ("FREQ".equals(key)) {
                    String frequency = "daily";
                    if ("WEEKLY".equals(value)) {
                        frequency = "weekly";
                    } else if ("MONTHLY".equals(value)) {
                        frequency = "monthly";
                    } else if ("YEARLY".equals(value)) {
                        frequency = "yearly";
                    }
                    recurrence.putString("frequency", frequency);
                } else if ("INTERVAL".equals(key)) {
                    recurrence.putInt("interval", Integer.parseInt(value));
                } else if ("COUNT".equals(key)) {
                    recurrence.putInt("occurrence", Integer.parseInt(value));
                }
            }
        }

        return recurrence;
    }

    private long parseDate(String dateString) {
        try {
            return ISO_8601_FORMAT.parse(dateString).getTime();
        } catch (ParseException e) {
            return System.currentTimeMillis();
        }
    }

    private String formatDate(long millis) {
        return ISO_8601_FORMAT.format(new Date(millis));
    }

    private long getDefaultCalendarId() {
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        Cursor cursor = cr.query(Calendars.CONTENT_URI,
            new String[] { Calendars._ID },
            Calendars.IS_PRIMARY + " = 1",
            null, null);

        if (cursor != null && cursor.moveToFirst()) {
            long id = cursor.getLong(0);
            cursor.close();
            return id;
        }

        // If no primary calendar, get the first one
        cursor = cr.query(Calendars.CONTENT_URI,
            new String[] { Calendars._ID },
            null, null, null);

        if (cursor != null && cursor.moveToFirst()) {
            long id = cursor.getLong(0);
            cursor.close();
            return id;
        }

        return 1; // Default fallback
    }

    // saveEvent — matches TurboModule spec (individual String params)
    @ReactMethod
    public void saveEvent(String title, String startDate, String endDate,
                         String location, String notes, String calendarId, Promise promise) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();

        ContentValues values = new ContentValues();
        values.put(Events.TITLE, title);
        values.put(Events.DESCRIPTION, notes);
        values.put(Events.EVENT_LOCATION, location);

        try {
            long startMillis = ISO_8601_FORMAT.parse(startDate).getTime();
            long endMillis = ISO_8601_FORMAT.parse(endDate).getTime();

            values.put(Events.DTSTART, startMillis);
            values.put(Events.DTEND, endMillis);
            values.put(Events.EVENT_TIMEZONE, TimeZone.getDefault().getID());

            long calId = TextUtils.isEmpty(calendarId) ? getDefaultCalendarId() : Long.parseLong(calendarId);
            values.put(Events.CALENDAR_ID, calId);

            Uri uri = cr.insert(Events.CONTENT_URI, values);
            if (uri != null) {
                promise.resolve(uri.getLastPathSegment());
            } else {
                promise.reject("event_save_failed", "Failed to save event");
            }
        } catch (ParseException e) {
            promise.reject("date_parse_error", "Invalid date format", e);
        } catch (Exception e) {
            promise.reject("event_save_failed", "Failed to save event", e);
        }
    }

    // updateEvent — matches TurboModule spec (individual String params)
    @ReactMethod
    public void updateEvent(String eventId, String title, String startDate, String endDate,
                           String location, String notes, String calendarId, Promise promise) {
        ContentResolver cr = getReactApplicationContext().getContentResolver();
        Uri uri = ContentUris.withAppendedId(Events.CONTENT_URI, Long.parseLong(eventId));

        ContentValues values = new ContentValues();
        if (!TextUtils.isEmpty(title)) values.put(Events.TITLE, title);
        if (!TextUtils.isEmpty(notes)) values.put(Events.DESCRIPTION, notes);
        if (!TextUtils.isEmpty(location)) values.put(Events.EVENT_LOCATION, location);

        try {
            if (!TextUtils.isEmpty(startDate)) {
                values.put(Events.DTSTART, ISO_8601_FORMAT.parse(startDate).getTime());
            }
            if (!TextUtils.isEmpty(endDate)) {
                values.put(Events.DTEND, ISO_8601_FORMAT.parse(endDate).getTime());
            }
            if (!TextUtils.isEmpty(calendarId)) {
                values.put(Events.CALENDAR_ID, Long.parseLong(calendarId));
            }

            int rowsUpdated = cr.update(uri, values, null, null);
            if (rowsUpdated > 0) {
                promise.resolve(eventId);
            } else {
                promise.reject("event_update_failed", "No rows updated");
            }
        } catch (Exception e) {
            promise.reject("event_update_failed", "Failed to update event", e);
        }
    }
}
