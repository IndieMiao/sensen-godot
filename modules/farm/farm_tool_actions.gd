class_name FarmToolActions
extends RefCounted
## 玩家能选的六种劳作动作。单独成表，是为了让动画守卫测试有个**唯一的引用源**：
## 新增工具必须同时出现在这里和 anim_placeholders.json，漏一边就红。

const CLEAR := "clear"
const TILL := "till"
const SOW := "sow"
const CARE := "care"
const HARVEST := "harvest"

## `care` 在运行时按田况展开成 water / drain / shelter，登记表里那三条单独登记。
const ALL := [CLEAR, TILL, SOW, HARVEST, "water", "drain", "shelter"]
