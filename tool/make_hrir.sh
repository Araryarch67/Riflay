#!/usr/bin/env bash
# Makes the head-related impulse responses behind Virtual speakers, from the
# diffuse-field equalized HRTF measurements of MIT's KEMAR dummy head:
#
#   assets/audio/hrir_kemar_48k.wav     two loudspeakers at ±30° (the stereo
#                                       triangle), for stereo songs
#   assets/audio/hrir_kemar_71_48k.wav  a 7.1 room (ITU-R BS.775): front ±30°,
#                                       centre 0°, sides ±90°, backs ±135°,
#                                       for 5.1 / 7.1 songs (Dolby Atmos beds)
#                                       and stereo upmixed to surround
#
#   tool/make_hrir.sh
#
# Two channels a speaker, in FFmpeg `headphone=hrir=multich` order: the speaker
# to the left ear, then to the right ear; speakers in FFmpeg's 7.1 order (FL FR
# FC LFE BL BR SL SR; the LFE is heard from the front, as a sub is). 48 kHz,
# 32-bit float.
#
# Gain: every IR is scaled by one factor, the one that keeps the front pair from
# making any frequency louder than it went in, whatever the two channels hold
# (max over f of |ipsi| + |contra| is 0 dB), as the equalizer's headroom does.
# So a stereo song sounds as loud in either room. Resampling an IR keeps its
# sample values, so its gain also grows by the rate ratio; that is taken back out.
#
# Data: Bill Gardner and Keith Martin, "HRTF Measurements of a KEMAR
# Dummy-Head Microphone", MIT Media Lab, 1994. Free to use provided the authors
# are cited (assets/audio/HRIR-NOTICE.txt). Needs curl, bsdtar, ffmpeg with
# soxr, python3 with numpy. RIFLAY_KEMAR_ZIP=path uses a diffuse.zip already here.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

url=https://sound.media.mit.edu/resources/KEMAR/diffuse.zip
sum=a48e73137390626ef1e45d1de6a4d98530c6aa570e71b40f7c4442241ed5fa22
if [[ -n ${RIFLAY_KEMAR_ZIP:-} ]]; then cp "$RIFLAY_KEMAR_ZIP" "$work/diffuse.zip"; else curl -fsSL -o "$work/diffuse.zip" "$url"; fi
echo "$sum  $work/diffuse.zip" | sha256sum -c --quiet
mkdir "$work/d" && bsdtar -xf "$work/diffuse.zip" -C "$work/d"

# A source at each azimuth to the right: channel 1 is the far (left) ear, channel 2 the near one.
for az in 000 030 090 135; do
  ffmpeg -hide_banner -loglevel error -i "$work/d/elev0/H0e${az}a.wav" \
    -af "aresample=48000:resampler=soxr:precision=28" -f f32le -c:a pcm_f32le "$work/r$az.raw"
done

python3 - "$work" <<'EOF'
import sys
import numpy as np

work = sys.argv[1]
def load(az):
    x = np.fromfile(f'{work}/r{az}.raw', dtype='<f4').reshape(-1, 2).astype(np.float64)
    return x * 44100 / 48000
ir = {az: load(az) for az in ('000', '030', '090', '135')}
n, rate = 1 << 14, 48000
f = np.fft.rfftfreq(n, 1 / rate)
band = (f >= 20) & (f <= 20000)
front = ir['030']
worst = (np.abs(np.fft.rfft(front[:, 1], n)) + np.abs(np.fft.rfft(front[:, 0], n)))[band].max()
for x in ir.values():
    x /= worst
# The head is taken as symmetric: a speaker on the left is its right twin mirrored.
def right(az): return [ir[az][:, 0], ir[az][:, 1]]       # to the left ear, to the right ear
def left(az): return [ir[az][:, 1], ir[az][:, 0]]
def save(name, cols):
    np.stack(cols, axis=1).astype('<f4').tofile(f'{work}/{name}.raw')
save('stereo', left('030') + right('030'))
centre = right('000')  # straight ahead: the two ears hear it alike
save('71', left('030') + right('030') + centre + centre + left('135') + right('135') + left('090') + right('090'))
print(f'{len(front)} taps, {20 * np.log10(1 / worst):.2f} dB')
EOF

mkdir -p "$project/assets/audio"
ffmpeg -hide_banner -loglevel error -y -f f32le -ar 48000 -ac 4 -i "$work/stereo.raw" -c:a pcm_f32le \
  -map_metadata -1 -fflags +bitexact "$project/assets/audio/hrir_kemar_48k.wav"
ffmpeg -hide_banner -loglevel error -y -f f32le -ar 48000 -ac 16 -i "$work/71.raw" -c:a pcm_f32le \
  -map_metadata -1 -fflags +bitexact "$project/assets/audio/hrir_kemar_71_48k.wav"
echo "Made $project/assets/audio/hrir_kemar_48k.wav and hrir_kemar_71_48k.wav"
