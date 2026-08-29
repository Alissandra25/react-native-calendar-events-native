const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

const indexPath = require.resolve('../lib/commonjs/index.js');
const specPath = require.resolve('../lib/commonjs/NativeCalendarEventsNativeSpec.js');

// Loads the real wrapper with only the React Native boundary replaced
function loadCalendar(nativeModule, platform = 'android') {
  const originalLoad = Module._load;
  delete require.cache[indexPath];
  delete require.cache[specPath];

  Module._load = function load(request, parent, isMain) {
    if (request === 'react-native') {
      return {
        NativeModules: {},
        PermissionsAndroid: { PERMISSIONS: {}, RESULTS: {} },
        Platform: { OS: platform },
        TurboModuleRegistry: { get: () => nativeModule },
      };
    }

    return originalLoad.call(this, request, parent, isMain);
  };

  try {
    return require(indexPath).default;
  } finally {
    Module._load = originalLoad;
  }
}

test('openEventEditor normalizes common and Android-only editor options', async () => {
  let receivedArguments;
  const calendar = loadCalendar({
    openEventEditor(...args) {
      receivedArguments = args;
      return Promise.resolve();
    },
  });

  await calendar.openEventEditor({
    title: 'Project Planning Meeting',
    startDate: new Date('2026-08-28T18:00:00.000Z'),
    endDate: '2026-08-28T20:00:00.000Z',
    location: 'Conference Room',
    notes: 'Discuss project milestones',
    allDay: false,
    calendar: '42',
    availability: 'tentative',
    recurrence: {
      frequency: 'weekly',
      interval: 2,
      endDate: new Date('2026-12-31T20:00:00.000Z'),
    },
    android: {
      attendees: ['one@example.com', 'two@example.com'],
    },
    ios: {
      url: 'https://example.com/meeting',
      alarms: [{ minutes: 15 }],
      availability: 'unavailable',
    },
  });

  assert.deepEqual(receivedArguments, [{
    title: 'Project Planning Meeting',
    startDate: '2026-08-28T18:00:00.000Z',
    endDate: '2026-08-28T20:00:00.000Z',
    location: 'Conference Room',
    notes: 'Discuss project milestones',
    allDay: false,
    calendar: '42',
    availability: 'tentative',
    recurrence: {
      frequency: 'weekly',
      interval: 2,
      endDate: '2026-12-31T20:00:00.000Z',
    },
    android: {
      attendees: ['one@example.com', 'two@example.com'],
    },
  }]);
});

test('openEventEditor forwards only iOS-specific options on iOS', async () => {
  let receivedEvent;
  const calendar = loadCalendar({
    openEventEditor(event) {
      receivedEvent = event;
      return Promise.resolve();
    },
  }, 'ios');

  await calendar.openEventEditor({
    title: 'Project Planning Meeting',
    startDate: '2026-08-28T18:00:00.000Z',
    endDate: '2026-08-28T20:00:00.000Z',
    ios: {
      url: 'https://example.com/meeting',
      alarms: [
        { date: new Date('2026-08-28T17:30:00.000Z') },
        { minutes: 15 },
      ],
      availability: 'unavailable',
    },
    android: {
      attendees: ['one@example.com'],
    },
  });

  assert.deepEqual(receivedEvent, {
    title: 'Project Planning Meeting',
    startDate: '2026-08-28T18:00:00.000Z',
    endDate: '2026-08-28T20:00:00.000Z',
    ios: {
      url: 'https://example.com/meeting',
      alarms: [
        { date: '2026-08-28T17:30:00.000Z' },
        { minutes: 15 },
      ],
      availability: 'unavailable',
    },
  });
});
