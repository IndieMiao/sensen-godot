class_name FarmToolActions
extends RefCounted
## 四步生命周期的劳作动作，外加铲平。单独成表，是为了让动画守卫测试有个**唯一的引用源**：
## 新增动作必须同时出现在这里和动画登记表，漏一边就红。

const TILL := "till"
const SOW := "sow"
const WATER := "water"
const HARVEST := "harvest"
const CLEAR := "clear"

const ALL := [TILL, SOW, WATER, HARVEST, CLEAR]
## 访客表情：本机动画，不产生命令。也走同一张登记表。
const EMOTES := ["wave"]
