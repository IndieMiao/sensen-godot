extends "res://tools/dev/dynamic_farm/book_loop_qa.gd"
## Emulator QA entry for moving and storing buildings (C-229): the blueprint book's entry (book_loop_qa.gd: one's own
## parcel, its core obstacles cleared on first start) with the cottage, coop, sheep pen and well blueprints, the pen's
## 15 Timber and 15 Stone, and carrots and Wild Herbs to feed with, so that a recording places a few in any order, feeds
## the coop (an egg two minutes later), opens the book's Arrange, sees Store wait with `Ready in …` for the egg on its
## way, moves the coop (its hens and eggs with it), stores the well and places it again. Staged only by
## gather_qa_apk.sh with GATHER_QA_ENTRY=arrange; never the main scene of a delivered package.
const ARRANGE_BAG := {"hoe_starter": 1, "pail": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_coop": 1, "blueprint_well": 1,
	"blueprint_sheep_pen": 1, "wood": 15, "stone": 15, "crop_carrot": 6, "wild_herb": 6}

func start_save(farm: Dictionary) -> Dictionary:
	var save := super(farm)
	save.bag = ARRANGE_BAG.duplicate()
	save.level = 3
	return save
