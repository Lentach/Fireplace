import { Message } from './message.entity';

/**
 * Safe read of the `messages.reactions` TEXT column, which stores a JSON string
 * `{ emoji: [userId] }` — NOT a JSON/JSONB column, so nothing at the DB level
 * guarantees it parses. Every emit path maps through here (history, new message,
 * edit, reaction update), so a single corrupt row must degrade to "no reactions"
 * for that one message rather than throwing and taking out an entire response.
 */
export function parseReactions(
  raw: Message['reactions'],
): Record<string, number[]> {
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === 'object'
      ? (parsed as Record<string, number[]>)
      : {};
  } catch {
    // Corrupt reactions JSON must not 500 the reaction handler.
    return {};
  }
}
