extends Node
## SCAFFOLD — torch-free LuxTTS synthesis in GDScript.
##
## Mirrors tools/tts-onnx-poc/infer_onnx.py. The ML lives in three ONNX models
## run by an onnxruntime GDExtension (e.g. joemarshall/godot_onnx_extension);
## everything here is plain arithmetic — the flow-matching sampler loop.
##
## This does NOT run as-is: it needs an ONNX extension that exposes a
## `run(input_names, input_tensors) -> tensors` API and a small ND-tensor
## helper. It documents the exact port so the engine work is mechanical.
##
## Pipeline: text tokens + voice embedding -> text_encoder -> sampler loop over
## fm_decoder -> mel -> vocos -> PackedFloat32Array @ 48kHz -> AudioStreamGenerator.

const FEAT_DIM := 100      # mel bins (from fm_decoder metadata "feat_dim")
const SAMPLE_RATE := 48000

# Assigned at load: ONNX session wrappers from the GDExtension.
var text_encoder            # text_encoder_int8.onnx
var fm_decoder              # fm_decoder_int8.onnx
var vocoder                 # vocos.onnx (see tools/tts-onnx-poc/export_vocos.py)


## Time schedule — direct port of zipvoice get_time_steps().
func get_time_steps(num_step: int, t_shift: float) -> PackedFloat32Array:
	var ts := PackedFloat32Array()
	for i in range(num_step + 1):
		var t := float(i) / float(num_step)
		ts.append(t_shift * t / (1.0 + (t_shift - 1.0) * t))
	return ts


## voice: a loaded character embedding (.npz exported via export_voice.py ->
##        Godot resource): prompt_tokens (int[]), prompt_features (float[1,L,100]),
##        prompt_features_len (int), prompt_rms (float).
## tokens: precomputed token ids for the line (precompute_tokens.py).
func synthesize(tokens: PackedInt64Array, voice: Dictionary, num_steps := 4,
		guidance := 3.0, speed := 1.0, t_shift := 0.5, seed := 0) -> PackedFloat32Array:
	var prompt_len: int = voice.prompt_features_len

	# 1) text encoder -> text_condition (1, num_frames, FEAT_DIM)
	var text_condition = text_encoder.run(
		["tokens", "prompt_tokens", "prompt_features_len", "speed"],
		[tokens, voice.prompt_tokens, prompt_len, float(speed) * 1.3])
	var num_frames: int = text_condition.shape[1]

	# 2) init noise + speech condition (voice mel padded to num_frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var x := _randn(num_frames, FEAT_DIM, rng)                 # (1, num_frames, FEAT_DIM)
	var speech_condition := _pad_frames(voice.prompt_features, num_frames)

	# 3) flow-matching sampler loop — the heart, pure arithmetic
	var ts := get_time_steps(num_steps, t_shift)
	for step in range(num_steps):
		var t_cur := ts[step]
		var t_next := ts[step + 1]
		var vel = fm_decoder.run(
			["t", "x", "text_condition", "speech_condition", "guidance_scale"],
			[t_cur, x, text_condition, speech_condition, float(guidance)])
		# x1 = x + (1-t)·v ; x0 = x - t·v ; advance along the ODE
		var x1 := _axpy(x, vel, 1.0 - t_cur)                   # x + (1-t)*v
		if step == num_steps - 1:
			x = x1                                             # snap to clean data
		else:
			var x0 := _axpy(x, vel, -t_cur)                    # x - t*v
			x = _lerp_nd(x0, x1, t_next)                       # (1-tn)*x0 + tn*x1

	# 4) strip prompt portion, scale, transpose to (1, FEAT_DIM, frames)
	var mel := _strip_and_scale(x, prompt_len, 1.0 / 0.1)

	# 5) vocoder -> waveform; match prompt loudness
	var wav: PackedFloat32Array = vocoder.run(["features"], [mel]).flatten()
	if voice.prompt_rms < 0.1:
		_scale_inplace(wav, voice.prompt_rms / 0.1)
	return wav   # feed into an AudioStreamGenerator playback buffer


# --- ND-tensor helpers (stubs; back with the extension's tensor type or a
#     flat PackedFloat32Array + shape, as godot_onnx_extension expects) ---
func _randn(_frames: int, _dim: int, _rng: RandomNumberGenerator): pass
func _pad_frames(_features, _to_frames): pass
func _axpy(_a, _b, _k: float): pass                 # a + k*b
func _lerp_nd(_a, _b, _k: float): pass              # (1-k)*a + k*b
func _strip_and_scale(_x, _prompt_len: int, _k: float): pass
func _scale_inplace(_w: PackedFloat32Array, _k: float): pass
