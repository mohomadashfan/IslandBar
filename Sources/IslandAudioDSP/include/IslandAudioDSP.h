#ifndef ISLAND_AUDIO_DSP_H
#define ISLAND_AUDIO_DSP_H

// Real-time mixer for IslandBar's per-app volume and equaliser.
//
// The render path (ib_mixer_render / ib_mixer_ioproc) runs on Core Audio's real-time I/O thread:
// it never allocates, locks, logs or calls into Objective-C or Swift. Parameters are published
// from the main thread with a sequence lock, so the audio thread always sees a consistent set.

#include <CoreAudio/CoreAudio.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Maximum number of process taps mixed at once.
#define IB_MAX_TAPS 32
/// Number of equaliser bands.
#define IB_EQ_BANDS 6
/// Coefficients per biquad: b0, b1, b2, a1, a2 (normalised so a0 == 1).
#define IB_BIQUAD_COEFFICIENTS 5

typedef struct ib_mixer ib_mixer;

CF_ASSUME_NONNULL_BEGIN

/// Allocates a mixer with unity gains and the equaliser off. Returns NULL on allocation failure.
ib_mixer *_Nullable ib_mixer_create(void);
void ib_mixer_destroy(ib_mixer *mixer);

/// Describes the aggregate device's input buffers: taps start after `input_offset` buffers that
/// belong to the output device itself. Call only while the I/O proc is stopped.
void ib_mixer_set_layout(ib_mixer *mixer, int input_offset, int tap_count);

/// Per-tap linear gains (0 = silent, 1 = unchanged). Safe to call while running.
void ib_mixer_set_gains(ib_mixer *mixer, const float *_Nullable gains, int count);

/// Equaliser settings. `coefficients` holds IB_EQ_BANDS * IB_BIQUAD_COEFFICIENTS values.
/// `preamp` is a linear gain applied before the filters. Safe to call while running.
void ib_mixer_set_eq(ib_mixer *mixer, int enabled, const float *_Nullable coefficients, float preamp);

/// Clears filter history, e.g. after the device changes. Call only while stopped.
void ib_mixer_reset_state(ib_mixer *mixer);

/// Mixes tap input into the output buffers. Exposed for testing.
void ib_mixer_render(ib_mixer *mixer, const AudioBufferList *_Nullable input, AudioBufferList *output);

/// AudioDeviceIOProc that forwards to ib_mixer_render. Pass the mixer as the client data.
OSStatus ib_mixer_ioproc(AudioObjectID device,
                         const AudioTimeStamp *now,
                         const AudioBufferList *input,
                         const AudioTimeStamp *input_time,
                         AudioBufferList *output,
                         const AudioTimeStamp *output_time,
                         void *_Nullable client_data);

CF_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

#endif
