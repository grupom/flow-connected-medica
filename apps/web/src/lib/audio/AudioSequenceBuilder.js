export class AudioSequenceBuilder {
  /**
   * Converts a ticket code and destination into a sequence of audio manifest keys.
   * @param {string} ticketCode - e.g. "C20", "E105"
   * @param {string} destination - e.g. "Consultorio 2", "Laboratorio"
   * @returns {string[]} Array of keys corresponding to AudioManifest
   */
  static buildSequence(ticketCode, destination) {
    const sequence = [];

    // 1. Phrase "Turno"
    sequence.push('phrase_turno');

    // 2. Ticket Code
    if (ticketCode) {
      const code = ticketCode.toString().trim().toUpperCase();
      for (const char of code) {
        if (char >= 'A' && char <= 'Z') {
          sequence.push(`letter_${char.toLowerCase()}`);
        } else if (char >= '0' && char <= '9') {
          sequence.push(`digit_${char}`);
        }
      }
    }

    // 3. Phrase "Favor dirigirse a"
    if (destination) {
      sequence.push('phrase_favor_dirigirse_a');

      // 4. Destination
      const destString = destination.toString().trim();
      
      // Known base locations
      const knownLocations = ['consultorio', 'laboratorio', 'emergencia', 'odontologia'];
      
      const parts = destString.split(/\s+/);
      for (let part of parts) {
        // Normalize: remove accents to match 'odontologia' when 'odontología' is passed
        const normalized = part.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        
        if (knownLocations.includes(normalized)) {
           sequence.push(`location_${normalized}`);
        } else if (/^\d+$/.test(normalized)) {
           // Parse digits
           for (const char of normalized) {
               sequence.push(`digit_${char}`);
           }
        } else {
           // Unknown location modifier / specific name
           sequence.push(`raw_word_${part}`); 
        }
      }
    }

    return sequence;
  }
}
