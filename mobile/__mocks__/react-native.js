'use strict';
// Minimal react-native mock for AsyncScreen unit tests.
// Uses string host component names which @testing-library/react-native can detect.
module.exports = {
  View: 'View',
  Text: 'Text',
  Pressable: 'Pressable',
  ActivityIndicator: 'ActivityIndicator',
  AppState: {
    addEventListener: jest.fn(() => ({ remove: jest.fn() })),
    currentState: 'active',
  },
  StyleSheet: {
    create: (styles) => styles,
    flatten: (style) => {
      if (!style) return {};
      if (Array.isArray(style)) return Object.assign({}, ...style.map((s) => (s && typeof s === 'object' ? s : {})));
      if (typeof style === 'object') return style;
      return {};
    },
    hairlineWidth: 1,
    absoluteFillObject: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 },
  },
  Platform: {
    OS: 'ios',
    select: (spec) => spec.ios ?? spec.default,
  },
};
