require daslib/media

require tiles
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

// tweakable settings
var night_percent = 0.0
var rain_percent = 0.0
var wheat_grow_timer = 0.0
var wheat_grow_period = 5.0
var draw_grid = false
var map_size = int2(20,20)
var npcCount = 10
var hunger_per_hour = 60.0
var health_loss_from_hunger_per_hour = 0.0

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

def is_big_item(kind : TileKind) : bool
    return kind == TileKind WOOD

def GetPreferedSpeed(character : Character?) : float
    if character.kind == TileKind SHEEP
        return 0.5
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

    grid_ground.width = map_size.x
    grid_ground.height = map_size.y

    grid_ground_decals.width = map_size.x
    grid_ground_decals.height = map_size.y

    grid_items.width = map_size.x
    grid_items.height = map_size.y

    for x in range(0, map_size.x)
        for y in range(0, map_size.y)
            var tile = Tile()
            tile.position = int2(x,y)
            if random_float(seed) > 0.5
                tile.z = 1.0
            else
                tile.z = 0.0
            tile.kind = random_float(seed) > 0.1 ? TileKind GRASS : TileKind SOIL    
            tile.z = float(random_int(seed) % int(tileFloorHeightZ) / 3) / tileFloorHeightZ
            var tint = lerp(random_float(seed), 1.0, 0.8)
            tile.color = make_color(tint)

            push_clone(grid_ground.tiles, tile)

            var item_tile = Tile()
            item_tile.position = int2(x,y)
            item_tile.z = tile.z
            item_tile.kind = TileKind NONE
            tint = 1.0
            item_tile.color = make_color(tint)
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
                if random_float(seed) > 0.8
                    //item_tile.z -= 6.0 / tileFloorHeightZ
                    item_tile.kind = TileKind CHEST_IRON
                elif random_float(seed) > 0.95
                    item_tile.kind = TileKind WHEAT_FULL

            push_clone(grid_items.tiles, item_tile)

            var decalTile = Tile()
            decalTile.position = int2(x,y)
            decalTile.z = tile.z

            if random_float(seed) > 0.95
                if random_float(seed) > 0.2
                    decalTile.kind = TileKind DECAL_SMALL
                else
                    decalTile.kind = TileKind DECAL_BIG
            push_clone(grid_ground_decals.tiles, decalTile)

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
    var tile = grid_items->getTileInt(pos)
    tile.kind = TileKind PLANTED_SEEDS
    grid_items->setTile(tile)
    player.items[TileKind WHEAT_FULL] -= 1

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

def pick(var tile : Tile)
    if tile.anim.kind != AnimKind NONE
        return
    var kind = tile.kind


    if tile.kind == TileKind WHEAT_FULL
        unprepare_ground_for_seeds2(tile.position)
    
    if is_big_item(tile.kind)
        if player.carry_item != TileKind NONE
            drop(player.carry_item, tile.position)
        player.carry_item = tile.kind
        tile.kind = TileKind NONE
    else
        player.items[tile.kind] += item_count_per_tile(tile.kind)
        tile.anim.kind = AnimKind PICK
        tile.anim.t = 0.0
        tile.anim.stopT = 0.5

    grid_items->setTile(tile)

def is_pickable(tile : TileKind) : bool
    return tile == TileKind WOOD || tile == TileKind WHEAT_FULL

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
    var nearestDist = 100.0
    var nearestNpc : AiCharacter?
    for npc in aiCharacters
        var dist = length(npc.position - pos)
        if dist < nearestDist
            nearestDist = dist
            nearestNpc = npc

    return nearestNpc



def do_alt_action()
    _alt_action(true)
    pass

def highlight_alt_action()
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, false)
        highlightedAltActionNpc = null

    highlightedAltActionNpc = _alt_action(false)
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, true)

    pass

var highlightedAltActionNpc : Character?
def set_highlighted(var character : Character?; is_highlighted : bool)
    if is_highlighted
        character.color = 0xffffff80
    else
        character.color = 0xffffffff

def _alt_action(exec : bool) : AiCharacter?
    if is_on_horse(player)
        if exec
            unmount_horse()
        return null
    
    if prev_leashed != null
        if exec
            unleash(prev_leashed)
            prev_leashed = null
        return null

    
    var npc = get_nearest_npc(player.position)
    if npc != null
        var pp = player.position
        var np = npc.position
        var l = length(np - pp)
        if l > 1.0
            npc = null

    if npc != null
        if npc.kind == TileKind HORSE
            if exec
                mount_horse(npc)
            return npc
        elif npc.kind == TileKind SHEEP
            if exec
                leash_to_player(npc)
            return npc
    return null

def do_action()
    _do_action(true)

def can_do_action() : bool
    return _do_action(false)

var day_percent = 0.0
var day_float = 0.5
var gamedays_per_hour = 60.0
def update_env(dt : float)
    day_float += dt * gamedays_per_hour / seconds_per_hour
    day_percent = day_float - float(trunci(day_float))

    var day_percent_radians = day_percent * PI * 2.0

    night_percent = 0.5 + sin(day_percent_radians) * 0.5

    var is_rainy = sin(day_float) > 0.7
    rain_percent = lerp(rain_percent, is_rainy ? 1.0 : 0.0, dt)

def _do_action(exec : bool) : bool
    if is_on_horse(player)
        return false
    var item = grid_items->getTile(player.position)

    if player.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE
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
            if player.items[TileKind WHEAT_FULL] > 0
                if exec
                    plant_seeds(item.position)
                return true
        else
            if exec
                if is_ground_prepared1(item.position)
                    prepare_ground_for_seeds2(item.position)
                else
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

[export]
def act(dt: float)
    set_window_title("wasisdasbox {int(1.0/dt)}")
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

    highlight_alt_action()
    if get_key_down(VK_SPACE)
        do_action()
    if get_key_down(VK_F)
        do_alt_action()

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
                ch.position.x = clamp(ch.position.x, -0.5,map_size_f.x - 0.6)
                ch.position.y = clamp(ch.position.y, -0.5,map_size_f.y - 0.6)
                processCollision(ch.position, tileToCollide)

    for ch in aiCharacters
        if length(ch.target_position - ch.position) < 1.0
            ch.target_position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
            continue
        var preferedSpeed = GetPreferedSpeed(ch)
        if ch.on_leash
            var leash_length = 1.0
            var delta = player.position - ch.position
            if ch.follow_player_on_leash && length(delta) > 1.0
                ch.target_position = ch.position + clampLength(delta, length(delta) - leash_length)
            else
                ch.target_position = ch.position
            preferedSpeed = min(length(delta), GetMaxSpeed(ch))
        ch.velocity = lerp(ch.velocity, clampLength(ch.target_position - ch.position, 1.f) * preferedSpeed, 3.0 * dt)


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
        x = 14
        y = 3
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

    return float4(float(x)*tileSizeX,float(y)*tileSizeY,tileSizeX,tileSizeY)

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

    if tile.kind == TileKind TREE_GREEN || tile.kind == TileKind TREE_YELLOW || tile.kind == TileKind TREE_RED
        processCollisionCircle(deltaPos, 0.3)
    elif tile.kind == TileKind CHEST_IRON || tile.kind == TileKind WOOD
        deltaPos.y -= 0.12
        processCollisionCircle(deltaPos, 0.4)
        deltaPos.y += 0.12
    elif tile.kind == TileKind FENCE_H
        deltaPos.y -= 0.08
        processCollisionRect(deltaPos, 0.6, 0.2)
        deltaPos.y += 0.08
    elif tile.kind == TileKind FENCE_V
        //deltaPos.y -= 0.08
        processCollisionRect(deltaPos, 0.2, 0.6)
        //deltaPos.y += 0.08
    
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
    return 1.0 - night_percent * 0.5 - rain_percent * 0.2

def get_pivot(kind : TileKind) : float2
    if kind == TileKind TREE_GREEN || kind == TileKind TREE_YELLOW || kind == TileKind TREE_RED
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN || kind == TileKind CHILD_A || kind == TileKind CHILD_B
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN_ON_HORSE ||  kind == TileKind HORSE || kind == TileKind SHEEP
        return float2(0.7,1.0)
    else
        return float2(0.5,0.5)

def draw_tile(tile : TileFloat)
    var pos = tile.position
    pos.y += tile.z * tileZToY
    var kind = tile.kind
    var color = tile.color
    var pivot = get_pivot(kind)

    var angle = 0.0
    var size = float2(1.0,1.0)
    apply_anim(tile.anim, pos, size, angle)

    if tile.mirrorX
        size.x = -size.x
        angle = -angle

    size *= float2(tileSizeX,tileSizeY) * camera.scale
    var texture_rect = get_tile_texture_rect(kind)

    color = lerp_colors_fix(0xff000000, color, calc_light(pos))

    if kind == TileKind PLANTED_SEEDS || kind == TileKind WHEAT_SMALL || kind == TileKind WHEAT_MEDIUM || kind == TileKind WHEAT_FULL
        pos.y -= 1.0

    var offset_from_pivot = float2((0.5 - pivot.x), (0.5 - pivot.y) * tileSizeY / tileFloorSizeY)
    if !tile.mirrorX
        offset_from_pivot.x = -offset_from_pivot.x
    var clip_space_pos = camera->worldToScreen(pos + offset_from_pivot)

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
    var picOffset = float2(0.0,1.0)
    var t = tile
    t.position += picOffset
    add_to_draw_queue(t, 0)

def is_dead(character : Character?) : bool
    return character.anim.kind == AnimKind DEATH

def draw_character(character : Character?)
    var tile = TileFloat()
    
    var runningOffset = min(character.speed, 1.0) * 0.1 * abs(sin(10.0 * get_time_after_start() * (character.isRunning ? 2.0 : 1.0)))
    if is_dead(character)
        runningOffset = 0.0
    var picOffset = float2(0.0,0.9)
    var zOffset = float2(0.0,character.z * tileZToY)
    var pos = character.position
    var anim : Anim
    tile.mirrorX = character.mirrorX
    tile.position = pos + picOffset + float2(0.0, runningOffset) + zOffset
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



def draw_ui()
    let max_health = 6
    let max_hunger = 6

    var health = roundi(player.health * float(max_health))
    var hunger = max_hunger - roundi(player.hunger * float(max_hunger))
    var texture_rect : float4 
    var color = 0xffffffff
    var ui_scale = 3.0
    var size = float2(tileSizeX,tileSizeY) * ui_scale
    var time = get_time_after_start()

    //health
    color = 0xffffffff
    for i in range(0, max_health / 2)
        if health >= i * 2 + 2
            texture_rect = get_tile_texture_rect(TileKind HEART_FULL)
        elif health == i * 2 + 1
            texture_rect = get_tile_texture_rect(TileKind HEART_HALF)
        else
            texture_rect = get_tile_texture_rect(TileKind HEART_EMPTY)
        var clip_space_pos = float2(10.0 + 16.0 * float(i),0.0)*ui_scale

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
        var clip_space_pos = float2(9.5 + 16.0 * float(i),0.0 + 14.0)*ui_scale

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

    var y = int(30.0 * ui_scale)
    for kind, count in keys(player.items),values(player.items)
        text_out(10,y, "{kind} {count}", 0xffffffff)
        y += 20

    text_out(10,y, "day_percent= {day_percent}", 0xffffffff)
    y += 20
    text_out(10,y, "rain_percent= {rain_percent}", 0xffffffff)
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
            if tile.kind != TileKind NONE
                draw_item_tile(to_tile_float(tile))
            iy -= 1
            
    for ch in characters
        if is_culled(ch.position)
            continue
        draw_character(ch)
    
    if can_do_action()
        draw_tile_highlight(grid_ground->getTile(player.position))

    sort(drawTilesQueue, $(a,b)=>a.priority==b.priority && a.tile.position.y>b.tile.position.y || a.priority>b.priority)

    for tile in drawTilesQueue
        draw_tile(tile.tile)

    if draw_grid
        draw_grid(0x08ffffff)

    draw_ui()
