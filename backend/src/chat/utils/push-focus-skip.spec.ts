import { shouldSuppressPushForFocusedState } from './push-focus-skip';

describe('shouldSuppressPushForFocusedState', () => {
  const NOW = 1_000_000;
  const FRESH = 35_000;

  it('suppresses when visible, this conversation active, and fresh', () => {
    expect(
      shouldSuppressPushForFocusedState(
        { clientVisible: true, activeConversationId: 7, updatedAt: NOW - 5_000 },
        7,
        NOW,
        FRESH,
      ),
    ).toBe(true);
  });

  it('does NOT suppress when the foreground claim is stale (missed Android background event)', () => {
    expect(
      shouldSuppressPushForFocusedState(
        { clientVisible: true, activeConversationId: 7, updatedAt: NOW - 40_000 },
        7,
        NOW,
        FRESH,
      ),
    ).toBe(false);
  });

  it('does NOT suppress when updatedAt is missing (legacy/unstamped state)', () => {
    expect(
      shouldSuppressPushForFocusedState(
        { clientVisible: true, activeConversationId: 7 },
        7,
        NOW,
        FRESH,
      ),
    ).toBe(false);
  });

  it('does NOT suppress when not visible', () => {
    expect(
      shouldSuppressPushForFocusedState(
        { clientVisible: false, activeConversationId: 7, updatedAt: NOW },
        7,
        NOW,
        FRESH,
      ),
    ).toBe(false);
  });

  it('does NOT suppress when a different conversation is active', () => {
    expect(
      shouldSuppressPushForFocusedState(
        { clientVisible: true, activeConversationId: 9, updatedAt: NOW },
        7,
        NOW,
        FRESH,
      ),
    ).toBe(false);
  });

  it('does NOT suppress when no state exists', () => {
    expect(shouldSuppressPushForFocusedState(undefined, 7, NOW, FRESH)).toBe(
      false,
    );
  });

  it('treats exactly-at-the-window as fresh (boundary)', () => {
    expect(
      shouldSuppressPushForFocusedState(
        { clientVisible: true, activeConversationId: 7, updatedAt: NOW - FRESH },
        7,
        NOW,
        FRESH,
      ),
    ).toBe(true);
  });
});
