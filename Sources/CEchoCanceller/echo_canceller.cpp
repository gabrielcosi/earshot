#include "echo_canceller.h"

#include <api/scoped_refptr.h>
#include <modules/audio_processing/include/audio_processing.h>

// The engine's rate, which both captures already resample to.
static const int kSampleRate = 16000;

struct earshot_aec {
    rtc::scoped_refptr<webrtc::AudioProcessing> apm;
    webrtc::StreamConfig stream{kSampleRate, 1};
};

earshot_aec *earshot_aec_create(void) {
    auto apm = webrtc::AudioProcessingBuilder().Create();
    if (!apm) return nullptr;
    // Measured on a room's speakers with the process tap as the far end: AEC3 alone with the
    // high-pass filter took the bleed below the room's noise. Gain control would raise the
    // residual back up between words, and noise suppression is not the engine's job here.
    webrtc::AudioProcessing::Config config;
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = false;
    config.high_pass_filter.enabled = true;
    config.gain_controller1.enabled = false;
    config.gain_controller2.enabled = false;
    config.noise_suppression.enabled = false;
    apm->ApplyConfig(config);
    return new earshot_aec{std::move(apm)};
}

void earshot_aec_destroy(earshot_aec *aec) { delete aec; }

void earshot_aec_reset(earshot_aec *aec) { aec->apm->Initialize(); }

void earshot_aec_far_end(earshot_aec *aec, const int16_t *block) {
    int16_t copy[EARSHOT_AEC_BLOCK_SAMPLES];
    aec->apm->ProcessReverseStream(block, aec->stream, aec->stream, copy);
}

void earshot_aec_near_end(earshot_aec *aec, int16_t *block) {
    aec->apm->ProcessStream(block, aec->stream, aec->stream, block);
}
