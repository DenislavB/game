extends Node
## SFX — procedurally synthesized sound effects. No audio assets: every
## sound is generated as 16-bit PCM at startup-on-demand and cached.
## play(name) for UI/self sounds; play_at(name, pos) for positional ones.

const RATE := 22050
var _cache: Dictionary = {}
var _players: Array = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 12345
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	Events.player_level_up.connect(func(_lvl): play("levelup"))
	Events.quest_completed.connect(func(_q): play("quest_done"))
	Events.quest_accepted.connect(func(_q): play("click"))
	Events.player_died.connect(func(): play("death"))


func play(sound: String, volume_db: float = 0.0) -> void:
	var stream := _build_stream(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = -8.0 + volume_db
	p.play()


func play_at(sound: String, pos: Vector3, parent: Node = null) -> void:
	var stream := _build_stream(sound)
	if stream == null:
		return
	if parent == null or not is_instance_valid(parent):
		play(sound)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = -4.0
	p.max_distance = 40.0
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


# ---------------------------------------------------------------- synthesis

func _build_stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var samples: PackedFloat32Array
	match sound:
		"swing":
			samples = _noise(0.14, 12.0, 900.0)
		"hit":
			samples = _mix(_tone(85.0, 0.16, 16.0), _noise(0.03, 60.0, 3000.0))
		"hit_crit":
			samples = _mix(_tone(65.0, 0.24, 10.0), _noise(0.05, 40.0, 2500.0))
		"hurt":
			samples = _tone(120.0, 0.12, 22.0)
		"bow":
			samples = _mix(_tone(220.0, 0.1, 30.0), _noise(0.12, 14.0, 1200.0))
		"spell_fire":
			samples = _mix(_noise(0.2, 9.0, 700.0), _tone(140.0, 0.18, 12.0))
		"spell_frost":
			samples = _chirp(1200.0, 700.0, 0.18, 12.0)
		"spell_arcane":
			samples = _chirp(500.0, 1000.0, 0.16, 10.0)
		"spell_shadow":
			samples = _mix(_tone(150.0, 0.25, 8.0), _tone(157.0, 0.25, 8.0))
		"spell_nature":
			samples = _chirp(800.0, 500.0, 0.16, 10.0)
		"spell_holy":
			samples = _mix(_tone(523.0, 0.25, 7.0), _tone(784.0, 0.25, 7.0))
		"heal":
			samples = _seq([[523.0, 0.12], [659.0, 0.18]], 9.0)
		"levelup":
			samples = _seq([[523.0, 0.1], [659.0, 0.1], [784.0, 0.1], [1046.0, 0.28]], 5.0)
		"quest_done":
			samples = _seq([[659.0, 0.12], [880.0, 0.24]], 6.0)
		"click":
			samples = _noise(0.02, 90.0, 4000.0)
		"death":
			samples = _chirp(300.0, 80.0, 0.6, 4.0)
		"loot":
			samples = _seq([[880.0, 0.05], [1174.0, 0.08]], 20.0)
		_:
			return null
	var stream := _to_wav(samples)
	_cache[sound] = stream
	return stream


func _tone(freq: float, dur: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * freq / RATE
		out[i] = sin(phase) * exp(-decay * t) * 0.8
	return out


func _chirp(f0: float, f1: float, dur: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		phase += TAU * f / RATE
		out[i] = sin(phase) * exp(-decay * t) * 0.7
	return out


func _noise(dur: float, decay: float, cutoff: float) -> PackedFloat32Array:
	## One-pole low-passed white noise burst (whooshes, thuds, ticks).
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var alpha := clampf(cutoff / RATE * TAU, 0.01, 1.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += alpha * (_rng.randf_range(-1.0, 1.0) - lp)
		out[i] = lp * exp(-decay * t) * 1.6
	return out


func _seq(notes: Array, decay: float) -> PackedFloat32Array:
	## Consecutive tones: [[freq, duration], ...]
	var out := PackedFloat32Array()
	for note in notes:
		out.append_array(_tone(float(note[0]), float(note[1]), decay))
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i < b.size():
			v += b[i]
		out[i] = clampf(v, -1.0, 1.0)
	return out


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
