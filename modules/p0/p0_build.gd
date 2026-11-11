class_name P0Build
extends RefCounted
## Which build this is (SGODOT-483, 上架; the user 11-11: in review within one or two weeks). The store build (App Store /
## Google Play: its export preset's custom feature `store`, 蒙恬 11-11 — fixed when exported, no file turns it) hides what
## a store review would not take: Test options (a new test account / back to the main one), the card room and its
## blackjack (simulated gambling; the user D6 「上架版隐藏」), the Voice Profile (recordings sent abroad for an AI reading).
## The OSS test build and every development run show them all. A test sets `store_override`.

static var store_override: Variant = null

static func store() -> bool:
	return bool(store_override) if store_override != null else OS.has_feature("store")
