package com.calendarevents;

import java.util.Calendar;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

final class CalendarEventDateUtils {
    private static final TimeZone UTC = TimeZone.getTimeZone("UTC");

    private CalendarEventDateUtils() {}

    // Preserve the device-local day at the UTC boundary required for all-day events
    static long toUtcMidnight(long millis) {
        Calendar localDate = Calendar.getInstance();
        localDate.setTimeInMillis(millis);

        Calendar utcDate = Calendar.getInstance(UTC);
        utcDate.clear();
        utcDate.set(
            localDate.get(Calendar.YEAR),
            localDate.get(Calendar.MONTH),
            localDate.get(Calendar.DAY_OF_MONTH),
            0,
            0,
            0
        );
        return utcDate.getTimeInMillis();
    }

    // Keep CalendarContract's all-day end exclusive
    static long toExclusiveUtcMidnightEnd(long startUtcMidnight, long endMillis) {
        long endUtcMidnight = toUtcMidnight(endMillis);
        return endUtcMidnight <= startUtcMidnight
            ? startUtcMidnight + TimeUnit.DAYS.toMillis(1)
            : endUtcMidnight;
    }
}
