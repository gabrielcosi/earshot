#ifndef EARSHOT_ECHO_CANCELLER_H
#define EARSHOT_ECHO_CANCELLER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// WebRTC's AEC3 over 16 kHz mono PCM16: high-pass filter on, no gain control, no noise
/// suppression. Not thread-safe; the caller serializes every call on one instance.
typedef struct earshot_aec earshot_aec;

/// Samples per call: AEC3 processes 10 ms blocks, 160 samples at 16 kHz.
#define EARSHOT_AEC_BLOCK_SAMPLES 160

earshot_aec *earshot_aec_create(void);
void earshot_aec_destroy(earshot_aec *aec);

/// Forgets the echo path, for when the audio the far end describes moves to another device.
void earshot_aec_reset(earshot_aec *aec);

/// One block of what the speakers play (the far end). It must arrive before the microphone
/// audio that carries its echo: AEC3 searches for the echo behind the reference, never ahead.
void earshot_aec_far_end(earshot_aec *aec, const int16_t *block);

/// Removes the far end's echo from one block of microphone audio, in place.
void earshot_aec_near_end(earshot_aec *aec, int16_t *block);

#ifdef __cplusplus
}
#endif

#endif
