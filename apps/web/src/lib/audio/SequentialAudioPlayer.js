export class SequentialAudioPlayer {
  /**
   * Plays a single MP3 clip by its URL.
   * Resolves when the clip ends playing.
   * Rejects if the clip cannot be loaded or played.
   * @param {string} url - The URL of the MP3 file
   * @returns {Promise<void>}
   */
  static playClip(url, rate = 1.0) {
    return new Promise((resolve, reject) => {
      if (typeof window === 'undefined') return resolve();
      
      const audio = new Audio(url);
      audio.playbackRate = rate;
      
      // Cleanup to prevent memory leaks
      const cleanup = () => {
        audio.removeEventListener('ended', onEnded);
        audio.removeEventListener('error', onError);
      };

      const onEnded = () => {
         cleanup();
         resolve();
      };
      
      const onError = (e) => {
         cleanup();
         reject(new Error(`Failed to play audio: ${url}`));
      };

      audio.addEventListener('ended', onEnded);
      audio.addEventListener('error', onError);
      
      audio.play().catch(onError);
    });
  }
}
