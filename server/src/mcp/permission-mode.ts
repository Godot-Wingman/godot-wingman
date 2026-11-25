/**
 * How much the AI may do without asking.
 *
 * - "full":      the AI uses every enabled tool. Editor changes can be undone with Ctrl+Z.
 * - "confirm":   before every change, the Godot editor shows an Allow / Deny dialog.
 * - "read-only": tools that change anything are hidden; the AI can only look.
 */
export const PERMISSION_MODES = ["full", "confirm", "read-only"] as const;

export type PermissionMode = (typeof PERMISSION_MODES)[number];

export function parsePermissionMode(value: string | undefined): PermissionMode {
  if (!value) {
    return "full";
  }
  const normalizedValue = value.trim().toLowerCase().replace("readonly", "read-only");
  if ((PERMISSION_MODES as readonly string[]).includes(normalizedValue)) {
    return normalizedValue as PermissionMode;
  }
  throw new Error(`Unknown permission mode '${value}'. Use one of: ${PERMISSION_MODES.join(", ")}.`);
}

export function describePermissionMode(mode: PermissionMode): string {
  switch (mode) {
    case "full":
      return "full: every enabled tool can be used.";
    case "confirm":
      return "confirm: each change must be approved in an Allow / Deny dialog in the Godot editor.";
    case "read-only":
      return "read-only: tools that change the project are hidden.";
  }
}
