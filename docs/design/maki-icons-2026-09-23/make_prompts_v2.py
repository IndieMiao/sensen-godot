"""Additional icons so each maki has ceil(count/10) (min 2) icons. Numbering continues after existing ones."""
from pathlib import Path
import importlib.util
spec = importlib.util.spec_from_file_location("v1", "make_prompts.py")
TEMPLATE = open("make_prompts.py").read().split('TEMPLATE = """')[1].split('"""')[0]
NEW = {
 "park": ("park / green space", 3, [
  "a small stone fountain with a gentle water spray", "a red playground slide", "a wooden swing hanging from a green frame",
  "a colorful kite with a curly tail", "a picnic basket with a red-and-white checkered cloth", "a round flower bed of pink and yellow tulips",
  "a white duck floating on a tiny round pond", "a green pine tree", "a vintage black park lamp post",
  "a red frisbee leaning on a tuft of grass", "a bunch of three colorful balloons", "a cute brown squirrel holding an acorn",
  "a small white gazebo with a green roof", "a watering can with a sprout", "a blue butterfly on a daisy",
  "a potted round topiary bush", "a pair of cherry blossom branches in pink bloom", "a wooden signpost with an arrow and a leaf"]),
 "restaurant": ("restaurant", 3, [
  "a steaming bowl of spaghetti with a fork twirled in it", "a chef's tall white hat", "a roast chicken on a small platter",
  "a bowl of ramen with chopsticks and an egg", "a steak on a wooden board with a sprig of rosemary", "a taco with colorful fillings",
  "a menu board shape with a knife and fork emblem (no text)", "a sushi roll set on a slate plate", "a bowl of green salad",
  "a cooking pot with a lid and steam", "a wine glass next to a folded napkin", "a plate of dumplings with a small dipping bowl"]),
 "school": ("school", 3, [
  "a graduation cap with a gold tassel", "a green chalkboard on a small stand (no writing)", "a yellow pencil and a pink eraser",
  "a small globe on a stand", "a yellow school bus", "a ruler, pencil and triangle set", "a small red school bell",
  "an open notebook with a pencil (no writing)", "a paint palette with a brush", "a microscope"]),
 "fast-food": ("fast food", 3, [
  "a hot dog with a mustard zigzag", "a paper bag of fast food with fries peeking out", "a glazed donut with sprinkles",
  "a fried chicken bucket", "a slice of pizza", "a milkshake with whipped cream and a cherry", "a burrito wrapped in foil", "a soft-serve ice cream cone"]),
 "religious-christian": ("church / place of worship", 3, [
  "a small arched stained-glass window panel with soft colors", "a lit white candle in a brass holder", "a small rounded cream chapel with a tiny bell tower",
  "a pair of white doves", "an open cream book with a ribbon bookmark on a stand (no writing)", "a white lily in bloom", "a small wooden pew bench"]),
 "shop": ("shop / store", 3, ["a pastel pink gift box with a ribbon", "a small clothes hanger with a folded shirt", "a shopping cart-free red store awning", "a pair of sneakers", "a wallet with a card peeking out"]),
 "grocery": ("grocery / supermarket", 3, ["a brown paper grocery bag with vegetables and a bread", "a bunch of bananas beside a red apple"]),
 "fuel": ("gas station", 3, ["a gas nozzle with a drop of fuel", "a green electric car charger plug"]),
 "lodging": ("hotel / lodging", 1 + 2, ["a brass hotel room key with a round tag"]),
 "cafe": ("cafe / coffee", 3, ["a croissant next to a small espresso cup"]),
 "bank": ("bank", 1, ["a gold coin stack", "a pink piggy bank with a coin", "a small classical bank facade icon with columns, simple and chunky"]),
 "convenience": ("convenience store", 1, ["a bottle of water and a snack bag", "a small shopping basket with a milk carton", "a round clock showing 24 hours style open icon without numbers, with a small shopping bag"]),
 "harbor": ("harbor / marina", 1, ["a navy anchor", "a small white sailboat", "a red-and-white life ring"]),
 "fire-station": ("fire station", 1, ["a red fire helmet", "a small red fire truck", "a red fire extinguisher"]),
 "pitch": ("sports field", 1, ["a soccer ball", "a baseball with a wooden bat", "a basketball"]),
 "doctor": ("doctor / clinic", 1, ["a stethoscope", "a white first aid kit with a red cross"]),
 "information": ("tourist information", 1, ["a round blue information sign with a lowercase i symbol (only the i glyph allowed)", "a folded paper map with a location pin"]),
 "restaurant-pizza": ("pizza restaurant", 1, ["a whole pizza with pepperoni", "a pizza slice with melted cheese"]),
 "car-repair": ("car repair", 1, ["a crossed wrench and screwdriver", "a small red toolbox"]),
 "fitness-centre": ("gym / fitness", 1, ["a pair of dumbbells", "a kettlebell"]),
 "museum": ("museum", 1, ["a classical marble bust on a pedestal", "an ornate golden picture frame with a landscape painting"]),
 "theatre": ("theatre", 1, ["a pair of comedy and tragedy masks", "red stage curtains with a small spotlight"]),
 "beer": ("beer / brewery", 1, ["a foamy beer mug", "a wooden beer barrel"]),
 "town-hall": ("town hall", 1, ["a small domed civic building icon with columns, simple and chunky", "a judge-style wooden gavel"]),
 "bar": ("bar", 1, ["a cocktail glass with a lime slice", "a pair of clinking drink glasses"]),
 "library": ("library", 1, ["a tall stack of hardcover books", "an open book with pages fanning"]),
 "car": ("car dealer / cars", 1, ["a small cute red car", "a car key with a fob"]),
}
n = 0
for key, (meaning, start, objs) in NEW.items():
    for i, obj in enumerate(objs):
        Path(f"prompt-{key}_{start + i}.txt").write_text(TEMPLATE.format(obj=obj, meaning=meaning)); n += 1
print("new prompts", n, "total", len(list(Path(".").glob("prompt-*.txt"))))
