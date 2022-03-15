require daslib/media

require tiles
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code
require fio
require json
require daslib/json_boost
// tweakable settings
var night_percent = 0.0
var rain_percent = 0.0
var wheat_grow_timer = 0.0
var wheat_grow_period = 5.0
var draw_grid = false
var map_size = int2(20,20)
var npcCount = 10
var hunger_per_hour = 600.0
var health_loss_from_hunger_per_hour = 0.0
var health_gain_from_no_hunger_per_hour = 600.0

var seconds_per_hour = 3600.0
var hours_per_second = 1.0 / seconds_per_hour
var pieces : ImageHandle
var tiles : ImageHandle

var grid_ground = new Grid()
var grid_ground_decals = new Grid()
var grid_items = new Grid()
var player = new Player()

var tileSizeY = 28.0
var tileSizeX = 18.0

var tileFloorSizeX = 18.0
var tileFloorSizeY = 14.0
var tileFloorHeightZ = 9.0
var tileZToY = tileFloorHeightZ / tileFloorSizeY
var topDownYToY = tileFloorSizeX / tileFloorSizeY

var characters : array<Character?>
var aiCharacters : array<AiCharacter?>

var map_size_f = float2(float(map_size.x),float(map_size.y))
var seed : int4

var time_scale = 1.0

let dbg_pathfinding = false

struct SavedGrid
    height : int
    width : int
    tiles : array<TileKind>

struct SavedCharacter
    position : float2
    kind : TileKind
    carry_item : TileKind

def save_character(c : Character?) : JsonValue?
    var ch : SavedCharacter
    ch.position = c.position
    ch.kind = c.kind
    ch.carry_item = c.carry_item
    return JV(ch)

def load_character(var json : JsonValue?;var g : Character?)
    var posX = ((json as _object)["position"] as _object)["x"] as _number
    var posY = ((json as _object)["position"] as _object)["y"] as _number
    g.position.x = float(posX)
    g.position.y = float(posY)

    var str = (json as _object)["kind"] as _string
    g.kind = str_to_tile_kind[str]
    str = (json as _object)["carry_item"] as _string
    g.carry_item = str_to_tile_kind[str]
    pass


def generate_default_ground_grid(width : int; height : int) : Grid?
    var grid = new Grid()
    grid.width = width
    grid.height = height

    for x in range(0, width)
        for y in range(0, height)
            var tile = Tile()
            tile.position = int2(x,y)
            tile.kind = TileKind SOIL  
            tile.z = float(random_int(seed) % int(tileFloorHeightZ) / 3) / tileFloorHeightZ
            var tint = lerp(random_float(seed), 1.0, 0.8)
            tile.color = make_color(tint)

            push_clone(grid.tiles, tile)

    return grid

def generate_default_grid(width : int; height : int; var ground_grid : Grid?) : Grid?
    var grid = new Grid()
    grid.width = width
    grid.height = height
    for x in range(0, width)
        for y in range(0, height)
            var tile = Tile()
            tile.position = int2(x,y)
            tile.kind = TileKind NONE  
            tile.z = ground_grid->getTileInt(tile.position).z
            push_clone(grid.tiles, tile)
    return grid

def save_grid(g : Grid?) : JsonValue?
    var grid : SavedGrid
    grid.height = g.height
    grid.width = g.width
    for k in g.tiles
        if k.anim.kind == AnimKind PICK
            push(grid.tiles, TileKind NONE)
        else
            push(grid.tiles, k.kind)
    return JV(grid)

var str_to_tile_kind : table<string; TileKind>
def load_grid(var json : JsonValue?; is_ground : bool) : Grid?
    var grid : SavedGrid
    //var h : Grid?
    var heightF <- (json as _object)["height"] as _number
    grid.height = roundi(heightF)
    var widthF <- (json as _object)["width"] as _number
    grid.width = roundi(widthF)
    
    var tilesJson <- (json as _object)["tiles"] as _array
    for t in tilesJson
        var s <- t as _string
        push(grid.tiles, str_to_tile_kind[s])
    
    var g : Grid?
    if is_ground
        g = generate_default_ground_grid(grid.height, grid.width)
        map_size.x = g.width
        map_size.y = g.height
        map_size_f = float2(float(map_size.x),float(map_size.y))
    else
        g = generate_default_grid(grid.height, grid.width, grid_ground)
    
    for idx in range(length(grid.tiles))
        g.tiles[idx].kind = grid.tiles[idx]

    return g

def save()
    var file = fopen("save.sav", "w")
    if file == null
        return

    var json : JsonValue?
    var grid : SavedGrid
    grid.height = grid_ground.height
    grid.width = grid_ground.width

    for k in grid_ground.tiles
        push(grid.tiles, k.kind)
    
    var t : table<string; JsonValue?>
    json = JV(t)
    (json as _object)["ground"] = save_grid(grid_ground)
    (json as _object)["items"] = save_grid(grid_items)
    (json as _object)["decals"] = save_grid(grid_ground_decals)
    var arr : array<JsonValue?>
    (json as _object)["characters"] = JV(arr)   
    for character in characters
        push((json as _object)["characters"] as _array, save_character(character))

    (json as _object)["day_float"] = JV(day_float)   

    fwrite(file, "{write_json(json)}")

    fclose(file)
    log("game saved")

var dbg_msg : array<string>

def log(str : string)
    push(dbg_msg, str)
    if length(dbg_msg) > 10
        erase(dbg_msg, 0)


def load()
    //TODO player items if they still exist
    var file = fopen("save.sav", "r")
    if file == null
        return

    seed = int4(0,0,0,0)

    clear(str_to_tile_kind)
    for e in each_enum(type<TileKind>)
        str_to_tile_kind["{e}"] =  e
        pass
    
    var strJson : string
    var c : __context
    while !feof(file)
        strJson += fgets(file) 
    var errorStr : string
    var json = read_json(strJson, errorStr)

    grid_ground = load_grid((json as _object)["ground"], true)
    grid_items = load_grid((json as _object)["items"], false)
    grid_ground_decals = load_grid((json as _object)["decals"], false)

    var isFirst = true
    clear(characters)
    clear(aiCharacters)
    for js in (json as _object)["characters"] as _array
        var character : Character?
        if isFirst
            player = new Player()
            push(characters, player)
            character = player
            isFirst = false
            load_character(js, character)
        else
            var aiChar = new AiCharacter()
            push(characters, aiChar)
            push(aiCharacters, aiChar)
            character = aiChar
            load_character(js, character)
            
            aiChar.target_position = aiChar.position
    
    day_float = float((json as _object)["day_float"] as _number)

    fclose(file)
    log("game loaded")

def color_to_float4_fix(c: uint): float4
    let b = c & 0xFF
    let g = (c >> 8u) & 0xFF
    let r = (c >> 16u) & 0xFF
    let a = (c >> 24u) & 0xFF
    return float4(r, g, b, a) / 255.0

def color_to_float3_fix(c: uint): float3
    let b = c & 0xFF
    let g = (c >> 8u) & 0xFF
    let r = (c >> 16u) & 0xFF
    return float3(r, g, b) / 255.0

def lerp_colors_fix(a, b: uint; t: float): uint
    let f1 = color_to_float4_fix(a)
    let f2 = color_to_float4_fix(b)
    return make_color(lerp(f1, f2, t))

class Character
    position : float2
    velocity : float2
    z : float
    speed : float
    kind : TileKind
    health : float = 0.5
    hunger : float = 0.5
    isRunning : bool = false
    mirrorX : bool
    items : table<TileKind; int> 
    on_leash : bool = false
    follow_player_on_leash : bool = false
    color : uint = 0xFFFFFFFF
    anim : Anim
    carry_item : TileKind = TileKind NONE


def GetPreferedSpeed(character : Character?) : float
    if character.kind == TileKind SHEEP
        return 0.2
    elif character.kind == TileKind HORSE
        return 2.0
    else
        return GetMaxSpeed(character) / 2.0

def GetMaxSpeed(character : Character?) : float
    if character.kind == TileKind HORSE || character.kind == TileKind HUMAN_ON_HORSE
        return 4.0
    elif character.kind == TileKind SHEEP
        return 2.0
    else
        return 2.0

class Player : Character
    speed2 : float

class AiCharacter : Character
    target_position : float2

def die(var character : Character?)
    if character.anim.kind == AnimKind DEATH
        return
    character.anim.kind = AnimKind DEATH
    character.anim.t = 0.0
    character.anim.stopT = 0.5


// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize
    set_window_title("wasisdasbox")
    set_resolution(1080,720)
    pieces <- create_managed_image("piece.png") 
    pieces |> set_image_smooth(true)
    pieces |> set_image_use_mipmap()

    tiles <- create_managed_image("tiles.png") 
    camera.scale = 3.0

    grid_ground = generate_default_ground_grid(map_size.x, map_size.y)
    grid_items = generate_default_grid(map_size.x, map_size.y, grid_ground)
    grid_ground_decals = generate_default_grid(map_size.x, map_size.y, grid_ground)

    for x in range(0, map_size.x)
        for y in range(0, map_size.y)
            var idx = grid_ground->getIdxInt(int2(x,y))

            var tile = grid_ground.tiles[idx]
            tile.kind = random_float(seed) > 0.1 ? TileKind GRASS : TileKind SOIL    
            grid_ground.tiles[idx] = tile

            var item_tile = grid_items.tiles[idx]
            if tile.kind == TileKind GRASS
                if random_float(seed) > 0.8
                    var r = random_float(seed)
                    if r > 0.5
                        item_tile.kind = TileKind TREE_GREEN
                    elif r > 0.125/2.0
                        item_tile.kind = TileKind TREE_YELLOW
                    else
                        item_tile.kind = TileKind TREE_RED
            else
                if random_float(seed) > 0.9
                    //item_tile.z -= 6.0 / tileFloorHeightZ
                    item_tile.kind = TileKind CHEST_IRON
                elif random_float(seed) > 0.8
                    item_tile.kind = TileKind WHEAT_FULL
                elif random_float(seed) > 0.6
                    item_tile.kind = TileKind FLINT_STONE
            grid_items.tiles[idx] = item_tile

            var decalTile = grid_ground_decals.tiles[idx] 
            if random_float(seed) > 0.95
                if random_float(seed) > 0.2
                    decalTile.kind = TileKind DECAL_SMALL
                else
                    decalTile.kind = TileKind DECAL_BIG
            grid_ground_decals.tiles[idx] = decalTile

    player.position = float2(float(grid_ground.width), float(grid_ground.height )) / 2.0
    player.kind = TileKind HUMAN
    camera.position = player.position - float2(3.0,3.0)

    push(characters, player)

    for i in range(0, npcCount)
        var npc = new AiCharacter()
        npc.position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
        npc.target_position = npc.position
        var r = random_float(seed)
        if r > 0.7
            npc.kind = TileKind HORSE
        elif r > 0.4
            npc.kind = TileKind SHEEP
        elif r > 0.3
            npc.kind = TileKind CHILD_A
        elif r > 0.2
            npc.kind = TileKind CHILD_B
        else
            npc.kind = TileKind HUMAN

        push(characters, npc)
        push(aiCharacters, npc)

    var itemsList : array<TileKind>
    push(itemsList, TileKind FLINT_STONE)
    push(itemsList, TileKind CAMPFIRE)
    push(itemsList, TileKind WOOD)
    push(itemsList, TileKind WHEAT_FULL)
    push(itemsList, TileKind BUCKET_EMPTY)
    push(itemsList, TileKind BUCKET_WITH_WATER)
    push(itemsList, TileKind WHEAT_COLLECTED_1)
    push(itemsList, TileKind WHEAT_COLLECTED_2)
    push(itemsList, TileKind WHEAT_COLLECTED_3)
    push(itemsList, TileKind WHEAT_COLLECTED_4)
    push(itemsList, TileKind WHEAT_COLLECTED_5)
    push(itemsList, TileKind WHEAT_COLLECTED_6)
    push(itemsList, TileKind COAL)
    push(itemsList, TileKind FENCE)
    push(itemsList, TileKind FENCE)
    push(itemsList, TileKind BUSH)
    push(itemsList, TileKind BUSH_WITH_BERRIES)

    for i in range(length(itemsList))
        var tile = grid_items->getTileInt(int2(i - length(itemsList) / 2 + grid_ground.width / 2, 1 + grid_ground.height / 2))
        tile.kind = itemsList[i]
        grid_items->setTile(tile)

        
    var groundTilesList : array<TileKind>
    push(groundTilesList, TileKind GRASS)
    push(groundTilesList, TileKind SOIL)
    push(groundTilesList, TileKind WATER)
    push(groundTilesList, TileKind WATER)
    push(groundTilesList, TileKind WATER)
    push(groundTilesList, TileKind WATER)
    
    for i in range(length(groundTilesList))
        var tile = grid_ground->getTileInt(int2(i - length(groundTilesList) / 2 + grid_ground.width / 2, 4 + grid_ground.height / 2))
        tile.kind = groundTilesList[i]
        grid_ground->setTile(tile)


class Camera
    position : float2
    scale : float

    offset : float2

    def pixelToScreen(pos : float2) : float2
        var result = pos * camera.scale + camera.offset
        result.y = -result.y
        return result

    def worldToScreen(pos : float2) : float2
        return pixelToScreen(pos * float2(tileFloorSizeX, tileFloorSizeY)) 

    def updateOffsetAndScale()
        var width = get_screen_width()
        var height = get_screen_height()
        offset = -position
        offset.x *= tileFloorSizeX * scale
        offset.y *= tileFloorSizeY * scale
        offset.x +=  float(width) / 2.0
        offset.y -=  float(height) / 2.0

var camera = new Camera()

def clampLength(vec : float2; maxLength : float) : float2
    var len = length(vec)
    if len <= maxLength
        return vec
    return vec / len * maxLength

def is_ground_prepared1(pos : int2) : bool
    var groundTile = grid_ground->getTileInt(pos)
    return groundTile.kind == TileKind SOIL

def is_ground_prepared2(pos : int2) : bool
    var decalsTile = grid_ground_decals->getTileInt(pos)
    return decalsTile.kind == TileKind DECAL_PREPARED_SOIL

def can_prepare_ground_for_seeds1(pos : int2) : bool
    var groundTile = grid_ground->getTileInt(pos)
    return groundTile.kind == TileKind GRASS

def prepare_ground_for_seeds1(pos : int2)
    var groundTile = grid_ground->getTileInt(pos)
    groundTile.kind = TileKind SOIL
    grid_ground->setTile(groundTile)

    var decalsTile = grid_ground_decals->getTileInt(pos)
    decalsTile.kind = TileKind NONE
    decalsTile.color = groundTile.color
    grid_ground_decals->setTile(decalsTile)

def prepare_ground_for_seeds2(pos : int2)
    var groundTile = grid_ground->getTileInt(pos)
    
    var decalsTile = grid_ground_decals->getTileInt(pos)
    decalsTile.kind = TileKind DECAL_PREPARED_SOIL
    decalsTile.color = groundTile.color
    grid_ground_decals->setTile(decalsTile)

def unprepare_ground_for_seeds2(pos : int2)
    var groundTile = grid_ground->getTileInt(pos)
    
    var decalsTile = grid_ground_decals->getTileInt(pos)
    decalsTile.kind = TileKind NONE
    decalsTile.color = groundTile.color
    grid_ground_decals->setTile(decalsTile)

def plant_seeds(pos : int2)
    if is_collected_wheat(player.carry_item)
        player.carry_item = get_wheat_from_count(get_wheat_count(player.carry_item) - 1)
    else
        assert(false)

    var tile = grid_items->getTileInt(pos)
    tile.kind = TileKind PLANTED_SEEDS
    grid_items->setTile(tile)

def open_chest(var chest : Tile)
    if random_float(seed) > 0.5
        player.health = min(player.health + 0.1, 1.0)
        chest.kind = TileKind HEART_FULL
        pick(chest)
    else
        player.hunger = max(player.hunger - 0.5, 0.0)
        chest.kind = TileKind HUNGER_FULL
        pick(chest)

    grid_items->setTile(chest)
    player.items[TileKind GOLD] += 1

def cut_tree(var tree : Tile)
    if tree.anim.kind != AnimKind NONE
        return

    var isFinalHit = tree.info >= 3
    if isFinalHit
        tree.anim.kind = AnimKind TREE_FALL
        tree.anim.t = 0.0
        tree.anim.stopT = 1.0
        grid_items->setTile(tree)
    else
        tree.info += 1
        tree.anim.kind = AnimKind SQUASH_AND_STRETCH
        tree.anim.t = 0.0
        tree.anim.stopT = 0.2
        grid_items->setTile(tree)

def drop(kind : TileKind; pos : int2)
    player.carry_item = TileKind NONE

    var tile = grid_items->getTileInt(pos)
    tile.anim.kind = AnimKind NONE
    tile.kind = kind
    grid_items->setTile(tile)

def item_count_per_tile(kind : TileKind) : int
    if kind == TileKind WHEAT_FULL
        return 2
    return 1

def get_wheat_count(a: TileKind) : int
    return int(a) - int(TileKind WHEAT_COLLECTED_1) + 1

def get_wheat_from_count(a: int) : TileKind
    if a == 0
        return TileKind NONE
    if a == 1
        return TileKind WHEAT_COLLECTED_1
    if a == 2
        return TileKind WHEAT_COLLECTED_2
    if a == 3
        return TileKind WHEAT_COLLECTED_3
    if a == 4
        return TileKind WHEAT_COLLECTED_4
    if a == 5
        return TileKind WHEAT_COLLECTED_5
    if a == 6
        return TileKind WHEAT_COLLECTED_6
    assert(false)
    return TileKind NONE

def add_wheat(a : TileKind; b : TileKind) : TileKind
    var s = get_wheat_count(a) + get_wheat_count(b)
    return get_wheat_from_count(min(s, 6))

def add_wheat_reminder(a : TileKind; b : TileKind) : TileKind
    var s = get_wheat_count(a) + get_wheat_count(b)
    return get_wheat_from_count(s - min(s, 6))

def is_collected_wheat(kind : TileKind) : bool
    return int(kind) >= int(TileKind WHEAT_COLLECTED_1) && int(kind) <= int(TileKind WHEAT_COLLECTED_6)

def pick(var tile : Tile)
    if tile.anim.kind != AnimKind NONE
        return
    var kind = tile.kind


    if tile.kind == TileKind WHEAT_FULL
        unprepare_ground_for_seeds2(tile.position)
    
    if is_big_item(tile.kind)
        if player.carry_item != TileKind NONE
            if is_collected_wheat(kind) && is_collected_wheat(player.carry_item)
                player.carry_item = add_wheat(kind, player.carry_item)
                tile.kind = add_wheat_reminder(kind, player.carry_item)
            else
                drop(player.carry_item, tile.position)
                player.carry_item = kind
                tile.kind = TileKind NONE
        else
            player.carry_item = kind
            tile.kind = TileKind NONE
    else
        player.items[tile.kind] += item_count_per_tile(tile.kind)
        tile.anim.kind = AnimKind PICK
        tile.anim.t = 0.0
        tile.anim.stopT = 0.5

    grid_items->setTile(tile)

def is_big_item(kind : TileKind) : bool
    return kind == TileKind WOOD || kind == TileKind FLINT_STONE || kind == TileKind BUCKET_WITH_WATER || kind == TileKind BUCKET_EMPTY || is_collected_wheat(kind) || kind == TileKind COAL

def is_pickable(kind : TileKind) : bool
    return kind == TileKind WOOD || kind == TileKind FLINT_STONE || kind == TileKind BUCKET_WITH_WATER || kind == TileKind BUCKET_EMPTY || is_collected_wheat(kind) || kind == TileKind COAL

var prev_horse : AiCharacter?
var prev_leashed : AiCharacter?

def is_on_horse(character : Character?):bool
    return character.kind == TileKind HUMAN_ON_HORSE

def mount_horse(var horse : AiCharacter?)
    if prev_horse != null
        unleash(prev_horse)
        prev_horse = null
        
    player.kind = TileKind HUMAN_ON_HORSE
    player.mirrorX = horse.mirrorX

    var idx = find_index(characters, horse)
    erase(characters, idx)

    idx = find_index(aiCharacters, horse)
    erase(aiCharacters, idx)
    

def unmount_horse()
    var npc = new AiCharacter()
    npc.position = player.position
    npc.position.y += 0.1
    npc.target_position = npc.position
    npc.kind = TileKind HORSE
    npc.z = player.z
    npc.mirrorX = player.mirrorX
    npc.on_leash = true
    npc.follow_player_on_leash = false
    prev_horse = npc
    
    player.kind = TileKind HUMAN

    push(characters, npc)
    push(aiCharacters, npc)

def unleash(var npc : AiCharacter?)
    npc.on_leash = false

def leash_to_player(var npc : AiCharacter?)
    if prev_leashed != null
        unleash(prev_leashed)
        prev_leashed = null
    
    npc.on_leash = true
    npc.follow_player_on_leash = true
    prev_leashed = npc

def get_nearest_npc(pos : float2) : AiCharacter?
    var nearestDist = 0.5
    var nearestNpc : AiCharacter?
    for npc in aiCharacters
        var dist = length(npc.position - pos)
        if dist < nearestDist
            nearestDist = dist
            nearestNpc = npc

    return nearestNpc

def _craft(var character : Character?; itemTile : Tile; exec : bool) : bool
    var kind = itemTile.kind 
    var result = false
    var groundTile = grid_ground->getTileInt(itemTile.position)
    var groundKind = groundTile.kind 

    if kind == TileKind WOOD && character.carry_item == TileKind FLINT_STONE
        if exec
            kind = TileKind CAMPFIRE
            //character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind CAMPFIRE && character.carry_item == TileKind BUCKET_WITH_WATER
        if exec
            kind = TileKind COAL
            character.carry_item = TileKind BUCKET_EMPTY
        result = true
    elif groundKind == TileKind WATER && character.carry_item == TileKind BUCKET_EMPTY
        if exec
            character.carry_item = TileKind BUCKET_WITH_WATER
        result = true
    elif kind == TileKind NONE && groundKind == TileKind WATER && character.carry_item == TileKind WOOD
        if exec
            character.carry_item = TileKind NONE
            groundKind = TileKind WOODEN_PLANE
            kind = TileKind NONE
        result = true
    elif is_collected_wheat(kind) && is_collected_wheat(character.carry_item)
        var sum = add_wheat(kind, character.carry_item)
        var reminder = add_wheat_reminder(kind, character.carry_item)
        if sum == character.carry_item
            result = false
        else
            result = true
            if exec
                character.carry_item = sum
                kind = reminder
    elif is_collected_wheat(character.carry_item) && is_ground_prepared1(itemTile.position) && is_ground_prepared2(itemTile.position) && itemTile.kind == TileKind NONE
        if exec
            character.carry_item = get_wheat_from_count(get_wheat_count(character.carry_item) - 1)
            kind = TileKind PLANTED_SEEDS
        result = true
    elif kind == TileKind WHEAT_FULL && character.carry_item == TileKind NONE
        if exec
            kind = TileKind WHEAT_COLLECTED_2
            unprepare_ground_for_seeds2(itemTile.position)
        result = true
    elif kind == TileKind WOOD && character.carry_item == TileKind WOOD
        if exec
            kind = TileKind FENCE
            character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind BUSH_WITH_BERRIES && character.carry_item == TileKind NONE
        if exec
            kind = TileKind BUSH
            character.hunger = max(0.0, character.hunger - 1.0)
        result = true
    elif kind == TileKind BUSH && character.carry_item == TileKind NONE
        if exec
            kind = TileKind NONE
        result = true
    elif kind == TileKind FENCE && character.carry_item == TileKind NONE
        if exec
            kind = TileKind NONE
            character.carry_item = TileKind FENCE
        result = true
    if result
        var tile = itemTile
        tile.kind = kind
        grid_items->setTile(tile)

        if groundTile.kind != groundKind
            groundTile.kind = groundKind
            grid_ground->setTile(groundTile)
    
    return result

def can_craft(var character : Character?; itemTile : Tile) : bool
    return _craft(character, itemTile, false)

def craft(var character : Character?; itemTile : Tile)
    _craft(character, itemTile, true)

def do_alt_action()
    _alt_action(true)

def can_do_alt_action() : bool
    let result = _alt_action(false)
    return result.is_valid

let invalidTilePos = int2(-9999,-9999)

def clear_alt_action_highlight()
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, false)
        highlightedAltActionNpc = null

    if highlightedAltActionTilePos != invalidTilePos
        set_highlighted(highlightedAltActionTilePos, false)
        highlightedAltActionTilePos = invalidTilePos

def draw_alt_action_highlight()
    let result = _alt_action(false)
    if !result.is_valid
        return

    if result.has_target_item_pos
        draw_tile_highlight(grid_ground->getTile(player.position))
        
    highlightedAltActionNpc = result.target_char
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, true)

def highlight_alt_action()
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, false)
        highlightedAltActionNpc = null

    if highlightedAltActionTilePos != invalidTilePos
        set_highlighted(highlightedAltActionTilePos, false)
        highlightedAltActionTilePos = invalidTilePos

    var result = _alt_action(false)
    highlightedAltActionNpc = result.target_char
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, true)

    if result.has_target_item_pos
        highlightedAltActionTilePos = result.target_item_pos
        set_highlighted(result.target_item_pos, true)

var highlightedAltActionTilePos : int2
def set_highlighted(tilePos : int2; is_highlighted : bool)
    var tile = grid_items->getTileInt(tilePos)
    if is_highlighted
        if tile.color == 0xffffff80
            return
        tile.color = 0xffffff80
    else
        if tile.color == 0xffffffff
            return
        tile.color = 0xffffffff
    grid_items->setTile(tile)

var highlightedAltActionNpc : Character?
def set_highlighted(var character : Character?; is_highlighted : bool)
    if is_highlighted
        character.color = 0xffffff80
    else
        character.color = 0xffffffff

struct AltActionResult
    is_valid : bool
    target_char : AiCharacter?
    has_target_item_pos : bool
    target_item_pos : int2

def _alt_action(exec : bool) : AltActionResult
    var result : AltActionResult
    if is_dead(player)
        return result
    if is_on_horse(player)
        result.is_valid = true
        if exec
            unmount_horse()
        return result
    
    if prev_leashed != null
        result.is_valid = true
        if exec
            unleash(prev_leashed)
            prev_leashed = null
        return result

    
    var npc = get_nearest_npc(player.position)

    if npc != null
        if npc.kind == TileKind HORSE
            result.is_valid = true
            result.target_char = npc
            if exec
                mount_horse(npc)
            return result
        elif npc.kind == TileKind SHEEP
            result.target_char = npc
            result.is_valid = true
            if exec
                leash_to_player(npc)
            return result

    var item = grid_items->getTile(player.position)
    if can_craft(player, item)
        result.is_valid = true
        result.target_item_pos = item.position
        result.has_target_item_pos = true
        if exec
            craft(player, item)
        return result
    
    return result

def do_action()
    _do_action(true)

def can_do_action() : bool
    return _do_action(false)

var day_percent = 0.0
var day_float = 0.3
var gamedays_per_hour = 300.0
def update_env(dt : float)
    day_float += dt * gamedays_per_hour / seconds_per_hour
    day_percent = day_float - float(trunci(day_float))

    var day_percent_radians = day_percent * PI * 2.0

    night_percent = 0.5 + sin(day_percent_radians) * 0.5

    var is_rainy = sin(day_float) > 0.7
    rain_percent = lerp(rain_percent, is_rainy ? 1.0 : 0.0, dt)

def _do_action(exec : bool) : bool
    if is_on_horse(player) || is_dead(player)
        return false
    var item = grid_items->getTile(player.position)
    var groundTile = grid_ground->getTile(player.position)

    if player.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE && groundTile.kind != TileKind WATER
        if !on_empty_tile
            return false
        if exec
            drop(player.carry_item, grid_items->getTile(player.position).position)
        return true

    if is_pickable(item.kind)
        if exec
            pick(item)
        return true
    elif player.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE
        if !on_empty_tile
            return false
        if exec
            drop(player.carry_item, grid_items->getTile(player.position).position)
        return true
    if item.kind == TileKind CHEST_IRON
        if exec
            open_chest(item)
        return true
    elif item.kind == TileKind NONE
        if is_ground_prepared1(item.position) && is_ground_prepared2(item.position)
            if is_collected_wheat(player.carry_item)
                if exec
                    plant_seeds(item.position)
                return true
        else
            if is_ground_prepared1(item.position)
                if exec
                    prepare_ground_for_seeds2(item.position)
                return true
            elif can_prepare_ground_for_seeds1(item.position)
                if exec
                    prepare_ground_for_seeds1(item.position)
                return true
    elif int(item.kind) >= int(TileKind TREE_GREEN) && int(item.kind) <= int(TileKind TREE_RED)
        if exec
            cut_tree(item)
        return true
    return false

def handle_anim_finished(var ch : Character?)
    if ch.anim.kind == AnimKind DEATH
        ch.anim.t = ch.anim.stopT//hacky
        pass
    pass

def handle_anim_finished(var tile : Tile&)
    if tile.anim.kind == AnimKind TREE_FALL
        tile.kind = TileKind WOOD
    elif tile.anim.kind == AnimKind PICK
        tile.kind = TileKind NONE
    tile.anim.kind = AnimKind NONE

def get_nearest_walkable(pos : float2) : int2
    var minDist = 10.0
    var posInt = grid_ground->getIntPos(pos)
    var bestPos = posInt
    for dx in range(-1, 2)
        for dy in range(-1, 2)
            if is_walkable_for_a_star(posInt + int2(dx,dy))
                var dist = length(pos - float2(posInt + int2(dx,dy)))
                if dist < minDist
                    bestPos = posInt + int2(dx,dy)
                    minDist = dist
    return bestPos

[export]
def act(_dt: float)
    let dt = _dt * time_scale
    set_window_title("wasisdasbox {int(1.0/_dt)}")
    if get_key(VK_ESCAPE)
        schedule_quit_game()

    update_env(dt)

    player.velocity = float2(0.0)
    if get_key(VK_W)
        player.velocity.y += 1.0
    if get_key(VK_S)
        player.velocity.y -= 1.0
    if get_key(VK_D)
        player.velocity.x += 1.0
    if get_key(VK_A)
        player.velocity.x -= 1.0

    if get_key_down(VK_SPACE)
        if can_do_alt_action()
            do_alt_action()
        else
            do_action()

    if get_key_down(VK_F6)
        save()
    if get_key_down(VK_F7)
        load()

    player.velocity = clampLength(player.velocity, 1.0) * GetMaxSpeed(player)
    if get_key(VK_LSHIFT)
        //todo less running on horse + some penalty
        player.velocity *= 2.5
        player.isRunning = true
    else
        player.isRunning = false

    for ch in characters
        if ch.health == 0.0
            die(ch)
            continue

        var hunger_speed = hunger_per_hour * hours_per_second
        if ch.isRunning && !is_on_horse(ch)
            hunger_speed *= 2.0
        ch.hunger = min(1.0, ch.hunger + dt * hunger_speed)

        if ch.hunger == 1.0
            ch.health = max(0.0, ch.health - dt * health_loss_from_hunger_per_hour * hours_per_second)
        else
            ch.health = min(1.0, ch.health + dt * health_gain_from_no_hunger_per_hour * hours_per_second)


        ch.position += ch.velocity * dt
        ch.speed = lerp(ch.speed, length(ch.velocity), dt*5.0)
        ch.z = lerp(ch.z, grid_ground->getHeight(ch.position), dt * 8.0)

        if ch.velocity.x < -0.1
            ch.mirrorX = false
        elif ch.velocity.x > 0.1
            ch.mirrorX = true

        for x in range(int(ch.position.x), int(ch.position.x+2.0))
            for y in range(int(ch.position.y), int(ch.position.y+2.0))
                var tileToCollide = grid_items->getTile(float2(float(x), float(y)))
                var tileToCollide2 = grid_ground->getTile(float2(float(x), float(y)))
                ch.position.x = clamp(ch.position.x, -0.5,map_size_f.x - 0.6)
                ch.position.y = clamp(ch.position.y, -0.5,map_size_f.y - 0.6)
                processCollision(ch.position, tileToCollide)
                processCollision(ch.position, tileToCollide2)

    for ch in aiCharacters
        if length(ch.target_position - ch.position) < 1.0
            ch.target_position = float2(random_float(seed) * float(map_size.x-1), random_float(seed) * float(map_size.y-1))
            continue
        while !is_walkable_for_a_star(grid_ground->getIntPos(ch.target_position))
            ch.target_position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
        var preferedSpeed = GetPreferedSpeed(ch)
        if ch.on_leash
            var leash_length = 1.0
            var delta = player.position - ch.position
            if ch.follow_player_on_leash && length(delta) > 1.0
                ch.target_position = ch.position + clampLength(delta, length(delta) - leash_length)
            else
                ch.target_position = ch.position
            preferedSpeed = min(length(delta), GetMaxSpeed(ch))

        var immediateTargetPos : float2
        immediateTargetPos = ch.target_position
        if !is_walkable_for_a_star(grid_ground->getIntPos(ch.position)) && !ch.on_leash
            immediateTargetPos = float2(get_nearest_walkable(ch.position))
        elif length(ch.target_position - ch.position) > 1.0
            var path : array<int2>
            path <- a_star(grid_ground->getIntPos(ch.position), grid_ground->getIntPos(ch.target_position))
            if length(path) > 1
                //TODO relax path to remove zig-zags
                immediateTargetPos = float2(path[1]) + (grid_items->getTileInt(path[1]).kind == TileKind NONE ? float2(0.0) : float2(0.25, 0.25))
            elif !ch.on_leash
                immediateTargetPos = ch.position
        ch.velocity = lerp(ch.velocity, clampLength((immediateTargetPos - ch.position)*2.0, 1.f) * preferedSpeed, 3.0 * dt)


    camera.position = lerp(camera.position, player.position, dt * 3.0) 
    camera->updateOffsetAndScale()

    for ch in characters
        if ch.anim.kind == AnimKind NONE
            continue
        ch.anim.t += dt
        if ch.anim.t >= ch.anim.stopT
            handle_anim_finished(ch)

    //TODO separate array for such things for optimization
    for tile in grid_items.tiles
        if tile.anim.kind == AnimKind NONE
            continue
        tile.anim.t += dt
        if tile.anim.t >= tile.anim.stopT
            handle_anim_finished(tile)
        grid_items->setTile(tile)

    wheat_grow_timer += dt
    if wheat_grow_timer > wheat_grow_period
        wheat_grow_timer -= wheat_grow_period
        //TODO separate array for such things for optimization
        for tile in grid_items.tiles
            if tile.kind == TileKind PLANTED_SEEDS
                tile.kind = TileKind WHEAT_SMALL
            elif tile.kind == TileKind WHEAT_SMALL
                tile.kind = TileKind WHEAT_MEDIUM
            elif tile.kind == TileKind WHEAT_MEDIUM
                tile.kind = TileKind WHEAT_FULL
            else
                continue
            grid_items->setTile(tile)

def get_tile_texture_rect(kind : TileKind) : float4
    var x = 1
    var y = 0 
    if kind == TileKind GRASS
        x = 4
        y = 0
    elif kind == TileKind HUMAN
        x = 19
        y = 2
    elif kind == TileKind CHILD_A
        x = 18
        y = 2
    elif kind == TileKind CHILD_B
        x = 17
        y = 2
    elif kind == TileKind TILE_SELECTION
        x = 1
        y = 5
    elif kind == TileKind NONE
        x = 0
        y = 5
    elif kind == TileKind TREE_GREEN
        x = 9
        y = 4
    elif kind == TileKind TREE_YELLOW
        x = 11
        y = 4
    elif kind == TileKind TREE_RED
        x = 10
        y = 4
    elif kind == TileKind CHEST_IRON
        x = 19
        y = 4
    elif kind == TileKind FENCE_H
        x = 17
        y = 3
    elif kind == TileKind FENCE_V
        x = 13
        y = 6
    elif kind == TileKind FENCE
        x = 15
        y = 6
    elif kind == TileKind DECAL_PREPARED_SOIL
        x = 13
        y = 5
    elif kind == TileKind DECAL_SMALL
        x = 18
        y = 0
    elif kind == TileKind DECAL_BIG
        x = 18
        y = 1
    elif kind == TileKind HEART_EMPTY
        x = 2
        y = 5
    elif kind == TileKind HEART_HALF
        x = 3
        y = 5
    elif kind == TileKind HEART_FULL
        x = 4
        y = 5
    elif kind == TileKind HUNGER_EMPTY
        x = 5
        y = 5
    elif kind == TileKind HUNGER_HALF
        x = 6
        y = 5
    elif kind == TileKind HUNGER_FULL
        x = 7
        y = 5
    elif kind == TileKind PLANTED_SEEDS
        x = 9
        y = 5
    elif kind == TileKind WHEAT_SMALL
        x = 10
        y = 5
    elif kind == TileKind WHEAT_MEDIUM
        x = 11
        y = 5
    elif kind == TileKind WHEAT_FULL
        x = 12
        y = 5
    elif kind == TileKind WOOD
        x = 8
        y = 5
    elif kind == TileKind HORSE
        x = 16
        y = 2
    elif kind == TileKind HUMAN_ON_HORSE
        x = 14
        y = 5
    elif kind == TileKind SHEEP
        x = 15
        y = 5
    elif kind == TileKind UI_BORDER
        x = 0
        y = 6
    elif kind == TileKind UI_NIGHT
        x = 1
        y = 6
    elif kind == TileKind UI_DAY
        x = 2
        y = 6
    elif kind == TileKind UI_RAIN
        x = 3
        y = 6
    elif kind == TileKind CAMPFIRE
        x = 4
        y = 6
    elif kind == TileKind CAMPFIRE_2
        x = 5
        y = 6
    elif kind == TileKind CAMPFIRE_3
        x = 6
        y = 6
    elif kind == TileKind FLINT_STONE
        x = 8
        y = 6
    elif kind == TileKind BUCKET_EMPTY
        x = 16
        y = 4
    elif kind == TileKind BUCKET_WITH_WATER
        x = 15
        y = 4
    elif kind == TileKind WATER
        x = 0
        y = 3
    elif kind == TileKind WATER_2
        x = 1
        y = 3
    elif kind == TileKind WATER_3
        x = 2
        y = 3
    elif kind == TileKind WATER_4
        x = 3
        y = 3
    elif kind == TileKind WOODEN_PLANE
        x = 7
        y = 4
    elif kind == TileKind WHEAT_COLLECTED_1
        x = 9
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_2
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_3
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_4
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_5
        x = 10
        y = 6
    elif kind == TileKind WHEAT_COLLECTED_6
        x = 11
        y = 6
    elif kind == TileKind COAL
        x = 12
        y = 6
    elif kind == TileKind BUSH
        x = 13
        y = 4
    elif kind == TileKind BUSH_WITH_BERRIES
        x = 14
        y = 6

    return float4(float(x)*tileSizeX,float(y)*tileSizeY,tileSizeX,tileSizeY)

def processCollisionCircle(var deltaPos : float2&; radius : float; center : float2)
    deltaPos -= center
    processCollisionCircle(deltaPos, radius)
    deltaPos += center
def processCollisionCircle(var deltaPos : float2&; radius : float)
    var deltaPosIso = float2(deltaPos.x, deltaPos.y * topDownYToY)
    var len = length(deltaPosIso)
    if len < radius
        if len < 0.001
            deltaPos = float2(1.0,0.0)
            len = 1.0
        deltaPosIso = deltaPosIso / len * radius
        deltaPos.x = deltaPosIso.x
        deltaPos.y = deltaPosIso.y / topDownYToY

def processCollisionRect(var deltaPos : float2&; halfSizeX : float; halfSizeY : float)
    var deltaDelta = float2(0.0)
    var changedX = false
    if deltaPos.x > 0.0 && deltaPos.x < halfSizeX
        deltaDelta.x = halfSizeX - deltaPos.x
        changedX = true
    if deltaPos.x < 0.0 && deltaPos.x > -halfSizeX
        deltaDelta.x = -halfSizeX - deltaPos.x
        changedX = true

    if changedX
        if deltaPos.y > 0.0 && deltaPos.y < halfSizeY
            deltaDelta.y = halfSizeY - deltaPos.y
            changedX = false
        if deltaPos.y < 0.0 && deltaPos.y > -halfSizeY
            deltaDelta.y = -halfSizeY - deltaPos.y
            changedX = false

        if !changedX
            deltaDelta *= 1.01
            if abs(deltaDelta.x) > abs(deltaDelta.y)
                deltaPos.y += deltaDelta.y
            else
                deltaPos.x += deltaDelta.x


def processCollision(var charPos : float2&; tile : Tile)
    var deltaPos = charPos - float2(tile.position)
    log("{tile.position}")
    if tile.kind == TileKind TREE_GREEN || tile.kind == TileKind TREE_YELLOW || tile.kind == TileKind TREE_RED
        processCollisionCircle(deltaPos, 0.3)
    elif tile.kind == TileKind CHEST_IRON || tile.kind == TileKind WOOD || tile.kind == TileKind CAMPFIRE
        deltaPos.y -= 0.12
        processCollisionCircle(deltaPos, 0.4)
        deltaPos.y += 0.12
    elif tile.kind == TileKind FENCE
        if grid_items->getTileInt(tile.position + int2(1, 0)).kind == TileKind FENCE
            deltaPos.x -= 0.5
            processCollisionRect(deltaPos, 0.55, 0.15)
            deltaPos.x += 0.5
        if grid_items->getTileInt(tile.position + int2(0, 1)).kind == TileKind FENCE
            deltaPos.y -= 0.5
            processCollisionRect(deltaPos, 0.15, 0.55)
            deltaPos.y += 0.5
    elif tile.kind == TileKind WATER
        let offset = 0.25
        let radius = 0.4
        processCollisionCircle(deltaPos, radius, float2(offset,offset))
        processCollisionCircle(deltaPos, radius, float2(-offset,offset))
        processCollisionCircle(deltaPos, radius, float2(offset,-offset))
        processCollisionCircle(deltaPos, radius, float2(-offset,-offset))
    elif (tile.kind) == (TileKind WHEAT_COLLECTED_6)
        deltaPos.y -= 0.12
        processCollisionCircle(deltaPos, 0.4)
        deltaPos.y += 0.12
    
    charPos = float2(tile.position) + deltaPos

def apply_anim(anim : Anim; var pos : float2&; var size : float2&; var angle : float&)
    if anim.kind == AnimKind NONE
        return
    
    if anim.kind == AnimKind SQUASH_AND_STRETCH
        var t = (anim.t / anim.stopT) * PI * 2.0
        size.x *= 1.0 + sin(t) * 0.1
        size.y /= 1.0 + sin(t) * 0.1
        //angle = sin(t/3.0) * 0.1
    elif anim.kind == AnimKind TREE_FALL
        var t = (anim.t / anim.stopT)

        var tSize = min(t * PI * 2.0 * 4.0, PI*2.0)
        size.x *= 1.0 + sin(tSize) * 0.1
        size.y /= 1.0 + sin(tSize) * 0.1

        var tAngle = t * PI / 2.0
        angle = tAngle * sin(tAngle)*sin(tAngle)

        var percent = 0.7
        var tSize2 = max(0.0, (t - percent) * (1.0 / (1.0 - percent))) * PI/2.0
        pos.y += sin(tSize2)*0.2
    elif anim.kind == AnimKind PICK
        var t = (anim.t / anim.stopT) * PI * 0.5
        pos.y += sin(t)*0.2

        pass
    elif anim.kind == AnimKind DEATH
        var t = (anim.t / anim.stopT)
        var tAngle = t * PI / 2.0
        angle = tAngle * sin(tAngle)*sin(tAngle)

        pass

    pass

def calc_light(pos : float2) : float
    var light = 1.0 - night_percent * 0.4 - rain_percent * 0.2
    var intpos = int2(roundi(pos.x), roundi(pos.y))
    for dx in range(-2, +3)
        for dy in range(-2, +3)
            if grid_items->getTileInt(int2(intpos.x + dx,intpos.y + dy)).kind == TileKind CAMPFIRE
                light += 0.4 / (float(dx*dx + dy*dy) + 1.0) * (0.9 + sin(get_time_after_start()*7.0+float(intpos.x + dx)) * 0.05 + sin(get_time_after_start()*6.0 + float(intpos.y + dy)) * 0.05)
    return min(1.0, light)

def get_pivot(kind : TileKind) : float2
    if kind == TileKind TREE_GREEN || kind == TileKind TREE_YELLOW || kind == TileKind TREE_RED
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN || kind == TileKind CHILD_A || kind == TileKind CHILD_B
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN_ON_HORSE ||  kind == TileKind HORSE || kind == TileKind SHEEP
        return float2(0.7,1.0)
    else
        return float2(0.5,0.5)

struct IntPosWithDist
    pos : int2
    dist : int
    expectedDist : float

def dist(from : int2; to : int2) : float
    return length(float2(from - to))

def insert_sorted(var arr : array<IntPosWithDist>; val : IntPosWithDist)
    var i = length(arr)
    while i > 0
        if arr[i-1].expectedDist > val.expectedDist
            push(arr, val, i)
            break
        i--
    if i == 0
        push(arr, val, 0)

def is_fence(kind : TileKind) : bool
    return kind == TileKind FENCE_H || kind == TileKind FENCE_V || kind == TileKind FENCE

def is_walkable_for_a_star(pos : int2) : bool
    if grid_ground->getTileInt(pos).kind == TileKind WATER
        return false
    var item = grid_items->getTileInt(pos).kind
    if item == TileKind FENCE
        return false
    if grid_items->getTileInt(pos + int2(-1, 0)).kind == TileKind FENCE && grid_items->getTileInt(pos + int2(1, 0)).kind == TileKind FENCE
        return false
    if grid_items->getTileInt(pos + int2(0, -1)).kind == TileKind FENCE && grid_items->getTileInt(pos + int2(0, 1)).kind == TileKind FENCE
        return false

    return true

def a_star(from : int2; to : int2) : array<int2>
    var result : array<int2>
    if from == to
        push(result, to)
        return <- result
    var r : table<int2; int>

    var wip : array<IntPosWithDist>
    var posWithDist : IntPosWithDist
    posWithDist.pos = from
    posWithDist.dist = 0
    posWithDist.expectedDist = dist(from, to)
    push(wip, posWithDist)
    r[from] = 0

    var found_path = false
    var iterations = 0
    let max_iteration = 300
    while !found_path && length(wip) > 0 && iterations < max_iteration
        iterations++
        var current = wip[length(wip)-1]
        pop(wip)
        for dd in range(0, 4)
            let dx = (dd - 1) % 2
            let dy = (dd - 2) % 2
            posWithDist.pos = current.pos + int2(dx,dy)
            posWithDist.dist = current.dist + 1
            posWithDist.expectedDist = float(posWithDist.dist) + dist(posWithDist.pos, to)
            if key_exists(r, posWithDist.pos) && r[posWithDist.pos] <= posWithDist.dist || !is_walkable_for_a_star(posWithDist.pos)
                continue
            r[posWithDist.pos] = posWithDist.dist
            insert_sorted(wip, posWithDist)
            var screenPos = camera->worldToScreen(float2(posWithDist.pos))
            //text_out(screenPos.x,screenPos.y, "{posWithDist.dist}", 0xffffffff)
            //push(result, posWithDist.pos)
            if posWithDist.pos == to
                found_path = true
                break

        //push(result, current.pos)
        //found_path = true
    iterations = 0
    if found_path
        var currentPos = to
        var currentDist = r[to]
        push(result, currentPos)
        while currentPos != from && iterations < max_iteration
            iterations++
            var minPos : int2
            var minDist = 100000.0
            var dx : int
            var dy : int
            for dd in range(0, 4)
                if iterations % 2 == 0
                    dx = dd / 2 * (dd == 3 ? 1 : -1)
                    dy = (dd == 0 ? 1 : -1) * (dd/2 - 1)
                else
                    dy = dd / 2 * (dd == 3 ? 1 : -1)
                    dx = (dd == 0 ? 1 : -1) * (dd/2 - 1)
                let pos = currentPos + int2(dx, dy)
                if key_exists(r, pos) && r[pos] < currentDist
                    currentPos = pos
                    currentDist = r[pos]
                    break
            
            //var screenPos = camera->worldToScreen(float2(currentPos))
            //text_out(screenPos.x,screenPos.y, "{r[currentPos]}", 0xffffffff)
            push(result, currentPos, 0)
        
        pass

    //log("{length(result)}")
    return <- result

def frac(f : float) : float
    return f - float(int(f))

def draw_tile(tile : TileFloat)
    var pos = tile.position
    pos.y += tile.z * tileZToY + tile.offsetY
    var kind = tile.kind
    var color = tile.color
    var pivot = get_pivot(kind)

    var angle = 0.0
    var size = float2(1.0,1.0)
    var mirrorX = tile.mirrorX
    apply_anim(tile.anim, pos, size, angle)

    if kind == TileKind CAMPFIRE
        let mult = 1.5
        let t = (get_time_after_start() + (pos.x*3.156345 + pos.y*4.842756))*mult
        let f = frac(t)
        mirrorX = frac(t*0.5) > 0.5
        if f > 0.333
            kind = TileKind CAMPFIRE_2
        if f > 0.666
            kind = TileKind CAMPFIRE_3
    else
        color = lerp_colors_fix(0xff000000, color, calc_light(tile.position))//TODO smooth tile.pos for character
    
    if kind == TileKind WATER
        pos.y -= tile.z * tileZToY + 0.2
        let mult = 1.0
        let t = (get_time_after_start())*mult
        let f = frac(t)
        if f > 0.75
            kind = TileKind WATER_4
        elif f > 0.5
            kind = TileKind WATER_3
        elif f > 0.25
            kind = TileKind WATER_2



    if mirrorX
        size.x = -size.x
        angle = -angle

    size *= float2(tileSizeX,tileSizeY) * camera.scale
    var texture_rect = get_tile_texture_rect(kind)

    color = lerp_colors_fix(0xff000000, color, calc_light(tile.position))

    if kind == TileKind PLANTED_SEEDS || kind == TileKind WHEAT_SMALL || kind == TileKind WHEAT_MEDIUM || kind == TileKind WHEAT_FULL
        pos.y -= 1.0
    elif kind == TileKind FENCE_H
        pos.x += 0.5

    var offset_from_pivot = float2((0.5 - pivot.x), (0.5 - pivot.y) * tileSizeY / tileFloorSizeY)
    if !mirrorX
        offset_from_pivot.x = -offset_from_pivot.x
    var clip_space_pos = camera->worldToScreen(pos + offset_from_pivot)

    if is_collected_wheat(kind)
        text_out(clip_space_pos.x+20.0,clip_space_pos.y + 20.0, "{get_wheat_count(kind)}", color)

    draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, angle, pivot.x, pivot.y)

struct TileWithPriority
    tile : TileFloat
    priority : int

var drawTilesQueue : array<TileWithPriority>

def add_to_draw_queue(tile : TileFloat; priority : int)
    var t : TileWithPriority
    t.tile = tile
    t.priority = priority
    push(drawTilesQueue, t)

def draw_item_tile(tile : TileFloat)
    var t = tile
    t.offsetY = 1.0
    add_to_draw_queue(t, 0)

def is_dead(character : Character?) : bool
    return character.anim.kind == AnimKind DEATH

def draw_character(character : Character?)
    var tile = TileFloat()
    
    var runningOffset = min(character.speed, 1.0) * 0.1 * abs(sin(10.0 * get_time_after_start() * (character.isRunning ? 2.0 : 1.0)))
    if is_dead(character)
        runningOffset = 0.0
    var picOffsetY = 0.9
    var zOffset = character.z * tileZToY
    var pos = character.position
    var anim : Anim
    tile.mirrorX = character.mirrorX
    tile.position = pos
    tile.offsetY = picOffsetY + runningOffset + zOffset
    tile.kind = character.kind
    tile.color = character.color
    tile.anim = character.anim

    if character.on_leash && character.follow_player_on_leash
        var from_pos = character.position
        from_pos += float2(0.0, 0.4)
        var to_pos = player.position
        to_pos += float2(0.0, 0.2)
        
        from_pos = camera->worldToScreen(from_pos)
        to_pos = camera->worldToScreen(to_pos)
        line(from_pos.x, from_pos.y, to_pos.x, to_pos.y, 0xff333333)
        pass
    
    if character.carry_item != TileKind NONE
        var carryTile = tile
        carryTile.anim.kind = AnimKind NONE
        carryTile.kind = character.carry_item
        carryTile.z += 1.2
        add_to_draw_queue(carryTile, 0)

    add_to_draw_queue(tile, 0)

def draw_tile_highlight(tile : Tile)
    var t = Tile()
    t.position = tile.position
    t.z = tile.z
    t.kind = TileKind TILE_SELECTION
    add_to_draw_queue(to_tile_float(t), 1)

def draw_grid(color : uint)
    var cameraPosX = int(camera.position.x)
    var cameraPosY = int(camera.position.y)
    for x in range(cameraPosX-20,cameraPosX+20)
        for y in range(cameraPosY-20,cameraPosY+20)
            var pos1A = float2(float(x-100), float(y))
            var pos1B = float2(float(x+100), float(y))
            var pos2A = float2(float(x), float(y-100))
            var pos2B = float2(float(x), float(y+100))
            pos1A = camera->worldToScreen(pos1A)
            pos2A = camera->worldToScreen(pos2A)
            pos1B = camera->worldToScreen(pos1B)
            pos2B = camera->worldToScreen(pos2B)
            line(pos1A.x, pos1A.y, pos1B.x, pos1B.y, color)
            line(pos2A.x, pos2A.y, pos2B.x, pos2B.y, color)

var ui_scale = 3.0
var ui_tile_size = float2(tileSizeX,tileSizeY) * ui_scale

def draw_character_stats(character : Character?; _pos : float2; invertX : bool)
    let max_health = 6
    let max_hunger = 6
    var time = get_time_after_start()

    var texture_rect : float4 
    var health = roundi(character.health * float(max_health))
    var hunger = max_hunger - roundi(character.hunger * float(max_hunger))
    var color = 0xffffffff
    var deltaX = 16.0
    var size = ui_tile_size 
    var pos = _pos
    if invertX
        deltaX = -deltaX
        //size.x = -size.x
        pos.x = float(get_screen_width()) / ui_scale - pos.x

    for i in range(0, max_health / 2)
        if health >= i * 2 + 2
            texture_rect = get_tile_texture_rect(TileKind HEART_FULL)
        elif health == i * 2 + 1
            texture_rect = get_tile_texture_rect(TileKind HEART_HALF)
        else
            texture_rect = get_tile_texture_rect(TileKind HEART_EMPTY)
        var clip_space_pos = float2(pos.x + deltaX * float(i),0.0 + pos.y)*ui_scale

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

    //hunger
    for i in range(0, max_hunger / 2)
        var blinkFreq = 2.0
        var isBlinking = player.isRunning && !is_on_horse(player) && ((time * blinkFreq) - float(floori(time * blinkFreq))) > 0.5
        isBlinking = isBlinking && (max(0, hunger - 1) / 2 == i)
        color = isBlinking ?  0x33ffffff : 0xffffffff
        if hunger >= i * 2 + 2
            texture_rect = get_tile_texture_rect(TileKind HUNGER_FULL)
        elif hunger == i * 2 + 1
            texture_rect = get_tile_texture_rect(TileKind HUNGER_HALF)
        else
            texture_rect = get_tile_texture_rect(TileKind HUNGER_EMPTY)
        var clip_space_pos = float2(pos.x - 0.5 + deltaX * float(i),0.0 + 14.0 + pos.y)*ui_scale

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

def draw_ui()
    let max_health = 6
    let max_hunger = 6

    var health = roundi(player.health * float(max_health))
    var hunger = max_hunger - roundi(player.hunger * float(max_hunger))
    var texture_rect : float4 
    var color = 0xffffffff
    var size = float2(tileSizeX,tileSizeY) * ui_scale
    var time = get_time_after_start()

    draw_character_stats(player, float2(10.0,0.0), false)

    var npc = get_nearest_npc(player.position)
    if npc != null
        draw_character_stats(npc, float2(10.0,0.0), true)

    //health
    color = 0xffffffff

    var y = int(30.0 * ui_scale)
    for kind, count in keys(player.items),values(player.items)
        text_out(10,y, "{kind} {count}", 0xffffffff)
        y += 20

    text_out(10,y, "day_percent= {day_percent}", 0xffffffff)
    y += 20
    text_out(10,y, "rain_percent= {rain_percent}", 0xffffffff)
    y += 20

    
    for i in range(length(dbg_msg))
        text_out(10,y, dbg_msg[length(dbg_msg) - i-1], 0xffffffff)
        y += 20

    if true
        var blinkFreq = 2.0
        var isBlinking = player.isRunning && !is_on_horse(player) && ((time * blinkFreq) - float(floori(time * blinkFreq))) > 0.5
        if night_percent > 0.5
            texture_rect = get_tile_texture_rect(TileKind UI_NIGHT)
        else
            texture_rect = get_tile_texture_rect(TileKind UI_DAY)
        var clip_space_pos = float2(float(get_screen_width())/2.0, -ui_scale * 7.0)

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, 0xffffffff, size, 0.0, 0.5f,0.0f)

        if rain_percent > 0.5
            texture_rect = get_tile_texture_rect(TileKind UI_RAIN)
            draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, 0xffffffff, size, 0.0, 0.5f,0.0f)

var camFSizeX = 36.0
var camFSizeY = 30.0

def get_min_culled() : int2
    var p = int2(floori(camera.position.x - camFSizeX / camera.scale), floori(camera.position.y - camFSizeY / camera.scale))
    p.x = clamp(p.x, 0, grid_ground.width)
    p.y = clamp(p.y, 0, grid_ground.height)
    return p

def get_max_culled() : int2
    var p = int2(ceili(camera.position.x + camFSizeX / camera.scale), ceili(camera.position.y + camFSizeY / camera.scale))
    p.x = clamp(p.x, 0, grid_ground.width)
    p.y = clamp(p.y, 0, grid_ground.height)
    return p

def is_culled(pos : float2) : bool
    return abs(camera.position.x - pos.x) * camera.scale > camFSizeX || abs(camera.position.y - pos.y) * camera.scale > camFSizeY

def is_culled(pos : int2) : bool
    return abs(camera.position.x - float(pos.x)) * camera.scale > camFSizeX || abs(camera.position.y - float(pos.y)) * camera.scale > camFSizeY

def draw_item_fence(tile : Tile)
    var u = grid_items->getTileInt(tile.position + int2(0,1))
    var d = grid_items->getTileInt(tile.position + int2(0,-1))
    var l = grid_items->getTileInt(tile.position + int2(-1,0))
    var r = grid_items->getTileInt(tile.position + int2(1,0))

    var t = to_tile_float(tile)
    if r.kind == TileKind FENCE
        t.kind = TileKind FENCE_H
        draw_item_tile(t)

    if u.kind == TileKind FENCE
        t.kind = TileKind FENCE_V
        draw_item_tile(t)

    if u.kind != TileKind FENCE && d.kind != TileKind FENCE && l.kind != TileKind FENCE && r.kind != TileKind FENCE
        draw_item_tile(t)

[export]
def draw
    clear(drawTilesQueue)
    enable_alpha_blend()
    fill_rect(0, 0, get_screen_width(), get_screen_height(), 0xff204020)
    if draw_grid
        draw_grid(0xffffffff)

    var time = get_time_after_start()

    var min_culled = get_min_culled()
    var max_culled = get_max_culled()
    
    for ix in range(min_culled.x, max_culled.x + 1)
        var iy = max_culled.y
        while iy >= min_culled.y
            draw_tile(to_tile_float(grid_ground->getTileInt(int2(ix, iy))))
            draw_tile(to_tile_float(grid_ground_decals->getTileInt(int2(ix, iy))))
            iy -= 1

    for ix in range(min_culled.x, max_culled.x)
        var iy = max_culled.y
        while iy >= min_culled.y
            var tile = grid_items->getTileInt(int2(ix, iy))
            if tile.kind == TileKind FENCE
                draw_item_fence(tile)
            elif tile.kind != TileKind NONE
                draw_item_tile(to_tile_float(tile))
            iy -= 1
            
    for ch in characters
        if is_culled(ch.position)
            continue
        draw_character(ch)

    if dbg_pathfinding
        for ch in aiCharacters
            if length(ch.target_position - ch.position) > 1.0
                var path : array<int2>
                path <- a_star(grid_ground->getIntPos(ch.position), grid_ground->getIntPos(ch.target_position))
        var path <- a_star(grid_ground->getTile(player.position).position, int2(grid_ground.width / 2, grid_ground.height / 2+5))
        for pos in path
            draw_tile_highlight(grid_ground->getTileInt(pos))
    clear_alt_action_highlight()
    if can_do_alt_action()
        draw_alt_action_highlight()
    else
        if can_do_action()
            draw_tile_highlight(grid_ground->getTile(player.position))
        
    



    sort(drawTilesQueue, $(a,b)=>a.priority==b.priority && a.tile.position.y>b.tile.position.y || a.priority>b.priority)

    for tile in drawTilesQueue
        draw_tile(tile.tile)

    if draw_grid
        draw_grid(0x08ffffff)

    draw_ui()
