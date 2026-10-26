extends Node2D
## Wires a scene's dialogue graph to the presentation layer.
##
## This is the only place that knows both the runtime and the UI exist. The runtime emits "a line
## should be shown"; this decides *how*. Keeping that seam clean is what lets the same content run
## headless in the validator.

@export var episode: int = 1
@export var scene_id: String = "s01_the_tremor"

var stage: Stage
var runtime: DialogueRuntime

var _dialogue: DialogueBox
var _choices: ChoicePanel
var _qte: QteWidget
var _deduction: DeductionBoard
var _ui_layer: CanvasLayer

var _palette := "CRYPT"


func _ready() -> void:
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	_ui_layer.layer = 10
	add_child(_ui_layer)

	_dialogue = DialogueBox.new()
	_dialogue.name = "DialogueBox"
	_ui_layer.add_child(_dialogue)
	_dialogue.advance_requested.connect(_on_advance)

	_choices = ChoicePanel.new()
	_choices.name = "ChoicePanel"
	_ui_layer.add_child(_choices)
	_choices.chosen.connect(_on_choice)
	_choices.timed_out.connect(_on_choice_timeout)

	_qte = QteWidget.new()
	_qte.name = "Qte"
	_ui_layer.add_child(_qte)
	_qte.resolved.connect(_on_qte)

	_deduction = DeductionBoard.new()
	_deduction.name = "Deduction"
	_ui_layer.add_child(_deduction)
	_deduction.committed.connect(_on_deduction)

	runtime = DialogueRuntime.new()
	runtime.name = "Runtime"
	add_child(runtime)
	runtime.line_shown.connect(_on_line)
	runtime.choices_offered.connect(_on_choices_offered)
	runtime.qte_requested.connect(_on_qte_requested)
	runtime.deduction_requested.connect(_on_deduction_requested)
	runtime.stage_directive.connect(_on_stage_directive)
	runtime.shot_requested.connect(_on_shot)
	runtime.finished.connect(_on_finished)

	var path := SceneDirector.data_path(episode, scene_id)
	if not runtime.load_graph(path):
		push_error("PlayScene: could not load %s — returning to menu." % path)
		await SceneDirector.go_to_menu()
		return

	runtime.start()


# --- runtime -> presentation ------------------------------------------------------------------

func _on_stage_directive(d: Dictionary) -> void:
	stage.apply_directive(d)
	if stage.palette_id != _palette:
		_palette = stage.palette_id
		_dialogue.set_palette(_palette)
		_choices.set_palette(_palette)
		_qte.set_palette(_palette)
		_deduction.set_palette(_palette)


func _on_shot(shot: Dictionary) -> void:
	stage.apply_shot(shot)


func _on_line(node: Dictionary) -> void:
	# Defensive: clear every other surface. The runtime can be resolved from outside the UI (the
	# autoplay and capture harnesses do exactly that), and a board left on screen would silently
	# cover the rest of the scene.
	_choices.dismiss()
	if _deduction.visible:
		_deduction.hide()
	if _qte.visible:
		_qte.hide()
	_dialogue.set_input_enabled(true)
	_dialogue.show_line(node)


func _on_advance() -> void:
	runtime.advance()


func _on_choices_offered(node: Dictionary, options: Array) -> void:
	# The prompt line stays visible above the options so the player keeps the context they're
	# answering, but taps must not advance dialogue while a choice is live.
	_dialogue.complete_reveal()
	_dialogue.set_input_enabled(false)
	_dialogue.dismiss()
	_choices.present(node, options)


func _on_choice(index: int) -> void:
	runtime.pick_choice(index)


func _on_choice_timeout() -> void:
	runtime.timeout_choice()


func _on_qte_requested(node: Dictionary) -> void:
	_dialogue.set_input_enabled(false)
	_dialogue.dismiss()
	_qte.begin(node)


func _on_qte(success: bool) -> void:
	runtime.resolve_qte(success)


func _on_deduction_requested(node: Dictionary) -> void:
	_dialogue.set_input_enabled(false)
	_dialogue.dismiss()
	_deduction.present(node)


func _on_deduction(index: int) -> void:
	runtime.resolve_deduction(index)


func _on_finished(finished_scene: String) -> void:
	_dialogue.dismiss()
	_choices.dismiss()
	await SceneDirector.finish_scene(finished_scene)
