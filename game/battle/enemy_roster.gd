class_name EnemyRoster
extends RefCounted
## Who the player fights: a name and a portrait for each encounter. A puzzle gets one of three
## monsters, chosen from its id so the same encounter always shows the same one. A theory
## encounter is always the Opening Scholar and a strong encounter the Gatekeeper Rook. The art is
## from the Ninja Adventure pack (see CREDITS.md).

const _ART := "res://assets/ninja_adventure/"

## `tr()` is an instance method, so the static function below calls it on this object.
static var _translator := RefCounted.new()


## The enemy of the encounter `id` of `kind` ("puzzle", "theory" or "strong"; anything else is
## drawn like a puzzle): `{name: String, sprite: String}`, where `sprite` is the `res://` path of
## its portrait.
static func for_encounter(kind: String, id: String) -> Dictionary:
	match kind:
		"theory":
			return {"name": _translator.tr("Opening Scholar"), "sprite": _ART + "characters/old_man_3.png"}
		"strong":
			return {"name": _translator.tr("Gatekeeper Rook"), "sprite": _ART + "bosses/demon_cyclop.png"}
	match id.hash() % 3:
		0: return {"name": _translator.tr("Greedy Pawn"), "sprite": _ART + "monsters/gold_racoon.png"}
		1: return {"name": _translator.tr("Sneaky Bishop"), "sprite": _ART + "monsters/kappa_green.png"}
		_: return {"name": _translator.tr("Knight of the Centre"), "sprite": _ART + "monsters/bear.png"}
