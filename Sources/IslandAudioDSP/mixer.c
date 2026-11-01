#include "IslandAudioDSP.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    float gains[IB_MAX_TAPS];
    float coefficients[IB_EQ_BANDS][IB_BIQUAD_COEFFICIENTS];
    float preamp;
    int eq_enabled;
} ib_params;

struct ib_mixer {
    // Written by the main thread only, published through `shared` under `sequence`.
    ib_params staging;
    ib_params shared;
    _Atomic unsigned sequence;

    // Owned by the audio thread.
    ib_params current;
    float history[IB_EQ_BANDS][2][2]; // band, channel, z1/z2 (transposed direct form II)

    // Set while stopped.
    int input_offset;
    int tap_count;
};

static void ib_params_default(ib_params *params) {
    memset(params, 0, sizeof(*params));
    for (int i = 0; i < IB_MAX_TAPS; i++) {
        params->gains[i] = 1.0f;
    }
    for (int band = 0; band < IB_EQ_BANDS; band++) {
        params->coefficients[band][0] = 1.0f; // b0: identity filter
    }
    params->preamp = 1.0f;
}

ib_mixer *ib_mixer_create(void) {
    ib_mixer *mixer = calloc(1, sizeof(ib_mixer));
    if (!mixer) {
        return NULL;
    }
    ib_params_default(&mixer->staging);
    mixer->shared = mixer->staging;
    mixer->current = mixer->staging;
    atomic_init(&mixer->sequence, 0);
    return mixer;
}

void ib_mixer_destroy(ib_mixer *mixer) {
    free(mixer);
}

void ib_mixer_set_layout(ib_mixer *mixer, int input_offset, int tap_count) {
    mixer->input_offset = input_offset < 0 ? 0 : input_offset;
    mixer->tap_count = tap_count < 0 ? 0 : (tap_count > IB_MAX_TAPS ? IB_MAX_TAPS : tap_count);
}

/// Sequence-lock writer: odd while writing, even when stable.
static void ib_publish(ib_mixer *mixer) {
    atomic_fetch_add_explicit(&mixer->sequence, 1, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);
    mixer->shared = mixer->staging;
    atomic_fetch_add_explicit(&mixer->sequence, 1, memory_order_release);
}

void ib_mixer_set_gains(ib_mixer *mixer, const float *gains, int count) {
    for (int i = 0; i < IB_MAX_TAPS; i++) {
        mixer->staging.gains[i] = (i < count && gains) ? gains[i] : 1.0f;
    }
    ib_publish(mixer);
}

void ib_mixer_set_eq(ib_mixer *mixer, int enabled, const float *coefficients, float preamp) {
    mixer->staging.eq_enabled = enabled;
    mixer->staging.preamp = preamp;
    if (coefficients) {
        memcpy(mixer->staging.coefficients, coefficients, sizeof(mixer->staging.coefficients));
    }
    ib_publish(mixer);
}

void ib_mixer_reset_state(ib_mixer *mixer) {
    memset(mixer->history, 0, sizeof(mixer->history));
}

/// Sequence-lock reader. Keeps the previous parameters if a write is in progress.
static void ib_refresh_params(ib_mixer *mixer) {
    for (int attempt = 0; attempt < 3; attempt++) {
        unsigned before = atomic_load_explicit(&mixer->sequence, memory_order_acquire);
        if (before & 1u) {
            continue;
        }
        ib_params copy = mixer->shared;
        atomic_thread_fence(memory_order_acquire);
        unsigned after = atomic_load_explicit(&mixer->sequence, memory_order_relaxed);
        if (before == after) {
            mixer->current = copy;
            return;
        }
    }
}

static inline float ib_biquad(const float *c, float *z, float x) {
    float y = c[0] * x + z[0];
    z[0] = c[1] * x - c[3] * y + z[1];
    z[1] = c[2] * x - c[4] * y;
    return y;
}

static inline float ib_clamp(float x) {
    if (x > 1.0f) return 1.0f;
    if (x < -1.0f) return -1.0f;
    return x;
}

void ib_mixer_render(ib_mixer *mixer, const AudioBufferList *input, AudioBufferList *output) {
    if (!output || output->mNumberBuffers == 0) {
        return;
    }
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        if (output->mBuffers[b].mData) {
            memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
        }
    }

    ib_refresh_params(mixer);
    const ib_params *params = &mixer->current;

    const int interleaved = output->mNumberBuffers == 1;
    const UInt32 out_channels = output->mBuffers[0].mNumberChannels ? output->mBuffers[0].mNumberChannels : 1;
    const UInt32 frames = output->mBuffers[0].mDataByteSize / (UInt32)(sizeof(float) * (interleaved ? out_channels : 1));

    for (UInt32 frame = 0; frame < frames; frame++) {
        float left = 0.0f;
        float right = 0.0f;

        for (int tap = 0; tap < mixer->tap_count; tap++) {
            UInt32 index = (UInt32)(mixer->input_offset + tap);
            if (!input || index >= input->mNumberBuffers) {
                break;
            }
            const AudioBuffer *buffer = &input->mBuffers[index];
            const UInt32 channels = buffer->mNumberChannels ? buffer->mNumberChannels : 1;
            const UInt32 available = buffer->mDataByteSize / (UInt32)(sizeof(float) * channels);
            if (!buffer->mData || frame >= available) {
                continue;
            }
            const float *samples = (const float *)buffer->mData;
            const float l = samples[frame * channels];
            const float r = channels > 1 ? samples[frame * channels + 1] : l;
            const float gain = params->gains[tap];
            left += l * gain;
            right += r * gain;
        }

        if (params->eq_enabled) {
            left *= params->preamp;
            right *= params->preamp;
            for (int band = 0; band < IB_EQ_BANDS; band++) {
                left = ib_biquad(params->coefficients[band], mixer->history[band][0], left);
                right = ib_biquad(params->coefficients[band], mixer->history[band][1], right);
            }
        }

        left = ib_clamp(left);
        right = ib_clamp(right);

        if (interleaved) {
            float *out = (float *)output->mBuffers[0].mData;
            if (!out) continue;
            out[frame * out_channels] = left;
            if (out_channels > 1) {
                out[frame * out_channels + 1] = right;
            }
        } else {
            float *out_left = (float *)output->mBuffers[0].mData;
            if (out_left) out_left[frame] = left;
            if (output->mNumberBuffers > 1) {
                float *out_right = (float *)output->mBuffers[1].mData;
                if (out_right) out_right[frame] = right;
            }
        }
    }

    // Guard against denormals and runaway filters producing NaNs.
    for (int band = 0; band < IB_EQ_BANDS; band++) {
        for (int channel = 0; channel < 2; channel++) {
            for (int z = 0; z < 2; z++) {
                float value = mixer->history[band][channel][z];
                if (!isfinite(value) || fabsf(value) < 1e-20f) {
                    mixer->history[band][channel][z] = 0.0f;
                }
            }
        }
    }
}

OSStatus ib_mixer_ioproc(AudioObjectID device,
                         const AudioTimeStamp *now,
                         const AudioBufferList *input,
                         const AudioTimeStamp *input_time,
                         AudioBufferList *output,
                         const AudioTimeStamp *output_time,
                         void *client_data) {
    (void)device;
    (void)now;
    (void)input_time;
    (void)output_time;
    if (client_data) {
        ib_mixer_render((ib_mixer *)client_data, input, output);
    }
    return noErr;
}
