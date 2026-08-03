// Map module prefixes to colors for UI aesthetics.
// Supports both single-letter (C, L, E…) and multi-letter (PD, RX…) prefixes.
// Full prefix is checked first; falls back to first letter, then default.
export const moduleColors = {
  'C':  '#0083C3', // Consultorio  -> Médica Blue
  'L':  '#a855f7', // Laboratorio  -> Purple
  'E':  '#ef4444', // Emergencia   -> Red
  'O':  '#10b981', // Odontología  -> Green
  'P':  '#f59e0b', // Psicología   -> Amber
  'PD': '#0083C3', // Pediatría    -> Médica Blue
  'default': '#0083C3' // Médica Blue
};

export function getModuleColor(prefix) {
  if (!prefix) return moduleColors.default;
  const upper = prefix.toUpperCase();
  // 1. Exact match (handles multi-letter prefixes like PD)
  if (moduleColors[upper]) return moduleColors[upper];
  // 2. Fallback to first letter
  const firstLetter = upper.charAt(0);
  return moduleColors[firstLetter] || moduleColors.default;
}
