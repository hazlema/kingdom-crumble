class_name Hud
extends CanvasLayer

func set_shots(n: int) -> void:
	$Shots.text = "Stones: %d" % n

func set_power(ratio: float) -> void:
	$PowerBack.visible = ratio > 0.0
	$PowerBack/PowerFill.size.x = 300.0 * clampf(ratio, 0.0, 1.0)

func banner(title: String, sub: String) -> void:
	$Banner.text = title
	$BannerSub.text = sub
	$Banner.visible = true
	$BannerSub.visible = true

func clear_banner() -> void:
	$Banner.visible = false
	$BannerSub.visible = false
