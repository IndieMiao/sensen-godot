extends RefCounted
const Art=preload("res://modules/farm/farm_art.gd")
const Old=preload("res://scenes/p0/zz_spot_art_old.gd")
static func build(spot:String,at:Vector3)->Node3D:
	if spot=="spot_reed_bank":return Art.instance("reed_bank",at)
	if spot=="spot_clay_bank":return Art.instance("clay_pit",at)
	return Old.build(spot,at)
