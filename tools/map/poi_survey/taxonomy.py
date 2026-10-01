import re
# 只用瓦片 poi_label 字段综合判断（2026-09-28 定案）：不接 Search Box、不按店名关键词推断、无名 POI 不上图。
# 优先级：hide > brand > 细分 maki > type > 通用 maki > class
BRAND = {  # 品牌 -> 语义子类（只取品类，不画 logo）
 "Starbucks":"drink.coffee","星巴克":"drink.coffee","瑞幸咖啡":"drink.coffee","Manner Coffee":"drink.coffee","Costa咖啡":"drink.coffee",
 "Peet's Coffee":"drink.coffee","Philz Coffee":"drink.coffee","Blue Bottle Coffee":"drink.coffee","Dunkin'":"drink.donut",
 "蜜雪冰城":"drink.milk_tea","喜茶":"drink.milk_tea","奈雪的茶":"drink.milk_tea","CoCo都可":"drink.milk_tea",
 "麦当劳":"food.burger","McDonald's":"food.burger","肯德基":"food.fried_chicken","KFC":"food.fried_chicken","Burger King":"food.burger","汉堡王":"food.burger",
 "必胜客":"food.pizza","Pizza Hut":"food.pizza","赛百味":"food.sandwich","Subway":"food.sandwich","Chipotle":"food.mexican","Pret A Manger":"food.sandwich",
 "庆丰包子铺":"food.dumpling","全聚德":"food.roast_duck","便宜坊":"food.roast_duck","海底捞":"food.hotpot","Wagas":"food.western","Outback Steakhouse":"food.steak","Morton's The Steakhouse":"food.steak","王品牛排":"food.steak","Le Pain Quotidien":"drink.bakery",
 "全家":"grocery.convenience","罗森":"grocery.convenience","7-Eleven":"grocery.convenience",
 "Walgreens":"health.pharmacy","CVS Pharmacy":"health.pharmacy","Duane Reade":"health.pharmacy",
}
MAKI_SPECIFIC = {"restaurant-pizza":"food.pizza","restaurant-noodle":"food.noodle","restaurant-seafood":"food.seafood","restaurant-sushi":"food.sushi","restaurant-bbq":"food.bbq",
 "bakery":"drink.bakery","confectionery":"drink.dessert","ice-cream":"drink.ice_cream","teahouse":"drink.tea","beer":"drink.pub","alcohol-shop":"grocery.alcohol",
 "clothing-store":"shop.clothing","shoe":"shop.shoes","jewelry-store":"shop.jewelry","watch":"shop.jewelry","mobile-phone":"shop.electronics","furniture":"shop.furniture",
 "hardware":"shop.hardware","optician":"shop.optician","florist":"shop.florist","gift":"shop.gift","department-store":"shop.mall",
 "pharmacy":"health.pharmacy","hospital":"health.hospital","doctor":"health.clinic","dentist":"health.dentist","veterinary":"health.vet",
 "religious-christian":"religion.christian","religious-buddhist":"religion.buddhist","religious-jewish":"religion.jewish","religious-muslim":"religion.muslim","place-of-worship":"religion.generic",
 "museum":"culture.museum","art-gallery":"culture.gallery","theatre":"culture.theatre","cinema":"culture.cinema","music":"culture.music","monument":"culture.monument","castle":"culture.palace","casino":"leisure.casino",
 "attraction":"culture.attraction","viewpoint":"culture.viewpoint","zoo":"leisure.zoo","aquarium":"leisure.zoo","amusement-park":"leisure.amusement",
 "park":"leisure.park","garden":"leisure.park","dog-park":"leisure.dog_park","playground":"leisure.playground","fitness-centre":"leisure.fitness","swimming":"leisure.swimming",
 "basketball":"leisure.basketball","tennis":"leisure.tennis","table-tennis":"leisure.table_tennis","volleyball":"leisure.volleyball","american-football":"leisure.american_football","soccer":"leisure.soccer","baseball":"leisure.baseball","skateboard":"leisure.skate","pitch":"leisure.pitch","stadium":"leisure.stadium","golf":"leisure.golf","bowling-alley":"leisure.bowling",
 "school":"edu.school","college":"edu.college","library":"edu.library",
 "bank":"service.bank","post":"service.post","laundry":"service.laundry","suitcase":"service.travel","car-repair":"service.car_repair","fuel":"service.fuel","charging-station":"service.charging",
 "car-rental":"service.car","car":"service.car","town-hall":"civic.town_hall","police":"civic.police","fire-station":"civic.fire","harbor":"transport.harbor",
 "lodging":"lodging.hotel","cafe":"drink.coffee","bar":"drink.bar","fast-food":"food.fast_food","convenience":"grocery.convenience","grocery":"grocery.supermarket","restaurant":"food.restaurant"}
TYPE = {  # OSM 原始类型：补 maki 分不出来的细类（对 shop / marker / grocery / lodging / school 等泛 maki 生效）
 "Books":"shop.books","Florist":"shop.florist","Cosmetics":"shop.cosmetics","Chemist":"shop.cosmetics","Mall":"shop.mall","Department Store":"shop.mall","Pet":"shop.pet",
 "Electronics":"shop.electronics","Computer":"shop.electronics","Camera":"shop.electronics","Stationery":"shop.stationery","Sports":"shop.sports","Outdoor":"shop.sports","Toys":"shop.toys",
 "Gift":"shop.gift","Antiques":"shop.antique","Second Hand":"shop.antique","Garden Centre":"shop.florist","Boutique":"shop.clothing","Fabric":"shop.clothing","Tailor":"shop.clothing",
 "Hairdresser":"service.hair","Beauty":"service.beauty","Massage":"service.beauty","Tattoo":"service.beauty","Dry Cleaning":"service.laundry","Copyshop":"service.post",
 "Tobacco":"shop.tobacco","Bicycle":"shop.bicycle","Watches":"shop.jewelry","Art":"shop.art","Chocolate":"drink.dessert","Pastry":"drink.bakery","Butcher":"grocery.butcher",
 "Tea":"drink.tea","Houseware":"shop.furniture","Interior Decoration":"shop.furniture","Kitchen":"shop.furniture","Ticket":"service.travel","Pet Grooming":"shop.pet",
 "Greengrocer":"grocery.greengrocer","Deli":"grocery.deli","Marketplace":"grocery.market","Seafood":"grocery.market",
 "Hostel":"lodging.hostel","Kindergarten":"edu.kindergarten","Nightclub":"drink.nightclub","Food Court":"food.food_court","Sports Centre":"leisure.sports_centre","Sports Hall":"leisure.sports_centre","Fitness Centre":"leisure.fitness","Ice Rink":"leisure.ice_rink","Dojo":"leisure.martial_arts","Dance":"leisure.dance","Batting Cage":"leisure.baseball","Escape Game":"leisure.amusement","Arcade Machine":"leisure.amusement","Karaoke":"leisure.karaoke",
 "University":"edu.college","Hospital":"health.hospital","City Gate":"culture.monument","Tower":"culture.tower","Parklet":"leisure.pocket_park","Casino":"leisure.casino","Pier":"transport.harbor","Amusement Arcade":"leisure.amusement","Events Venue":"culture.theatre",
 "Community Centre":"civic.town_hall","Courthouse":"civic.town_hall","Palace":"culture.palace","Brewery":"drink.pub","Wine":"grocery.alcohol"}
CLASS = {"food_and_drink":"food.restaurant","food_and_drink_stores":"grocery.supermarket","store_like":"shop.retail","park_like":"leisure.park","lodging":"lodging.hotel",
 "education":"edu.school","medical":"health.clinic","religion":"religion.generic","arts_and_entertainment":"culture.attraction","sport_and_leisure":"leisure.fitness",
 "historic":"culture.monument","landmark":"culture.attraction","commercial_services":"service.generic","public_facilities":"civic.town_hall","visitor_amenities":None,
 "motorist":None,"building":None,"place_like":None,"general":None,"industrial":None}
HIDE_MAKI = {"parking","parking-garage","bridge","toilet","drinking-water","bicycle","information","slipway","prison","cemetery","communications-tower"}
GENERIC_MAKI = {"marker","shop","restaurant","cafe","bar","fast-food","lodging","grocery","convenience","school"}

PARK_TYPE = {"Nature Reserve":"leisure.nature","Forest":"leisure.nature","Wood":"leisure.nature","Protected Area":"leisure.nature","National Park":"leisure.nature",
 "Allotments":"leisure.community_garden","Recreation Ground":"leisure.lawn","Picnic Site":"leisure.picnic"}
def refine_park(p):
    typ = p.get("type","")
    if typ in PARK_TYPE: return PARK_TYPE[typ], "type"
    if typ == "Garden": return ("leisure.classical_garden" if p.get("iso_3166_1") in ("CN","HK","TW","JP") else "leisure.garden"), "type"
    return "leisure.park", "maki"

def resolve(p, use_name=None):  # use_name 仅为兼容旧调用，已不使用
    if not (p.get("name") or "").strip(): return None, "hide"  # 无名 POI 不上图（与 CityMapData.normalize 一致）
    k, s = _resolve(p)
    if k == "leisure.park" or (p.get("maki") == "picnic-site" and p.get("type") == "Picnic Site"): return refine_park(p)
    return k, s

def _resolve(p):
    maki, typ, brand = p.get("maki",""), p.get("type",""), p.get("brand") or ""
    if maki == "picnic-site" and typ != "Picnic Site": return None, "hide"  # 野餐桌不上图
    if maki in HIDE_MAKI or (p.get("maki_beta") in ("taxi","parking-paid")): return None, "hide"
    # 广播发射塔（KJAZ-FM、WNYE-TV 这类呼号）不是景观塔
    if typ == "Tower" and re.fullmatch(r"[KW][A-Z]{2,4}-(FM|AM|TV)", p.get("name") or ""): return None, "hide"
    if brand in BRAND: return BRAND[brand], "brand"
    if maki in MAKI_SPECIFIC and maki not in GENERIC_MAKI: return MAKI_SPECIFIC[maki], "maki"
    if typ in TYPE: return TYPE[typ], "type"
    if maki in MAKI_SPECIFIC: return MAKI_SPECIFIC[maki], "maki_generic"
    k = CLASS.get(p.get("class"))
    return (k,"class") if k else (None,"hide")
