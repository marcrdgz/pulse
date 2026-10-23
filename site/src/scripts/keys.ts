const modifiers = '⌘⌃⌥⇧';

// Splits a shortcut like "⌘⇧T" into the keys printed on a Mac keyboard: ["⌘", "⇧", "T"].
export function splitCombo(combo: string): string[] {
  const keys = [...combo];
  const firstKey = keys.findIndex((key) => !modifiers.includes(key));
  if (firstKey === -1) return keys;
  return [...keys.slice(0, firstKey), keys.slice(firstKey).join('')];
}
