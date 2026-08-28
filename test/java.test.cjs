const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const projectRoot = path.resolve(__dirname, '..');
const sourcePath = path.join(
  projectRoot,
  'android/src/main/java/com/calendarevents/CalendarEventDateUtils.java',
);
const testPath = path.join(
  projectRoot,
  'test/java/com/calendarevents/CalendarEventDateUtilsTest.java',
);
const hasJdk = spawnSync('javac', ['-version']).status === 0;

test('Android all-day dates keep their local day and exclusive end', {
  skip: hasJdk ? false : 'JDK not available',
}, () => {
  const outputDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'calendar-event-date-test-'),
  );

  try {
    const compile = spawnSync(
      'javac',
      ['-d', outputDirectory, sourcePath, testPath],
      { encoding: 'utf8' },
    );
    assert.equal(compile.status, 0, compile.stderr || compile.stdout);

    const run = spawnSync(
      'java',
      ['-cp', outputDirectory, 'com.calendarevents.CalendarEventDateUtilsTest'],
      { encoding: 'utf8' },
    );
    assert.equal(run.status, 0, run.stderr || run.stdout);
  } finally {
    fs.rmSync(outputDirectory, { recursive: true, force: true });
  }
});
