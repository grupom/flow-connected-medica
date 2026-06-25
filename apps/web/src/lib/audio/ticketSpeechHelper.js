/**
 * Transforms a ticket code (like "C20") into a slowed, separated spoken format.
 * E.g. "Turno C, 2, 0. Pase a Consultorio 1."
 * 
 * @param {string} ticketCode - The raw code, e.g. "C20", "E105"
 * @param {string} moduleName - The destination module, e.g. "Consultorio 1"
 * @returns {string} The full phrase formatted for Speech Synthesis
 */
export function formatTicketAudioSequence(ticketCode, moduleName) {
  if (!ticketCode) return '';
  
  // Example ticketCode: "C20" -> split into characters: "C", "2", "0"
  // We want to force the speech engine to spell each character out.
  // Adding commas between digits forces a tiny pause.
  const spelledOut = ticketCode.split('').join(', ');

  const destination = moduleName ? `Pase a ${moduleName}` : 'Pase a recepción';

  return `Turno ${spelledOut}. ${destination}.`;
}
