/**
 * Jest test setup for Swapboard frontend
 */

// Mock localStorage
const localStorageMock = {
  store: {},
  getItem: jest.fn((key) => localStorageMock.store[key] || null),
  setItem: jest.fn((key, value) => {
    localStorageMock.store[key] = String(value);
  }),
  removeItem: jest.fn((key) => {
    delete localStorageMock.store[key];
  }),
  clear: jest.fn(() => {
    localStorageMock.store = {};
  }),
};

Object.defineProperty(window, "localStorage", {
  value: localStorageMock,
});

// Mock matchMedia
Object.defineProperty(window, "matchMedia", {
  writable: true,
  value: jest.fn().mockImplementation((query) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: jest.fn(),
    removeListener: jest.fn(),
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),
    dispatchEvent: jest.fn(),
  })),
});

// Mock Notification API. Rebuilt before each test: several tests swap in their
// own constructor, and one left behind would carry a live 10s close() timer into
// whichever test runs next.
function resetNotification() {
  global.Notification = {
    permission: "default",
    requestPermission: jest.fn().mockResolvedValue("granted"),
  };
}
resetNotification();

// Mock fetch
global.fetch = jest.fn();

// Reset mocks before each test
beforeEach(() => {
  jest.clearAllMocks();
  resetNotification();
  localStorageMock.store = {};
  global.fetch.mockReset();
});

// Export for use in tests
global.localStorageMock = localStorageMock;
