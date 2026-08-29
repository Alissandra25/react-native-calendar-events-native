package com.calendarevents;

import java.time.Instant;
import java.util.TimeZone;

public final class CalendarEventDateUtilsTest {
    public static void main(String[] args) {
        TimeZone originalTimeZone = TimeZone.getDefault();
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Riyadh"));
            assertEquals(
                "2026-08-28T00:00:00Z",
                CalendarEventDateUtils.toUtcMidnight(
                    Instant.parse("2026-08-27T21:00:00Z").toEpochMilli()
                )
            );
            long startUtcMidnight = CalendarEventDateUtils.toUtcMidnight(
                Instant.parse("2026-08-28T06:00:00Z").toEpochMilli()
            );
            assertEquals(
                "2026-08-29T00:00:00Z",
                CalendarEventDateUtils.toExclusiveUtcMidnightEnd(
                    startUtcMidnight,
                    Instant.parse("2026-08-28T14:00:00Z").toEpochMilli()
                )
            );

            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"));
            assertEquals(
                "2026-08-28T00:00:00Z",
                CalendarEventDateUtils.toUtcMidnight(
                    Instant.parse("2026-08-28T04:00:00Z").toEpochMilli()
                )
            );
        } finally {
            TimeZone.setDefault(originalTimeZone);
        }
    }

    private static void assertEquals(String expected, long actualMillis) {
        String actual = Instant.ofEpochMilli(actualMillis).toString();
        if (!expected.equals(actual)) {
            throw new AssertionError("Expected " + expected + " but received " + actual);
        }
    }
}
