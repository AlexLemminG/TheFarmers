require daslib/media

require tiles
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

// tweakable settings
var rain_percent = 0.0
var wheat_grow_timer = 0.0
var wheat_grow_period = 5.0
var draw_grid = false
var map_size = int2(20,20)
var npcCount = 10


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
let max_health = 6
let max_hunger = 6

var map_size_f = float2(float(map_size.x),float(map_size.y))
var seed : int4

class Character
    position : float2
    velocity : float2
    z : float
    speed : float
    kind : TileKind
    health : int = 3
    hunger : int = 3
    isRunning : bool = false
    mirrorX : bool
    items : table<TileKind; int> 
    on_leash : bool = false
    follow_player_on_leash : bool = false

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
            var tint = clamp(lerp(random_float(seed), 1.0, 0.8) - rain_percent * 0.2, 0.0, 1.0)
            tile.color = make_color(tint)

            push_clone(grid_ground.tiles, tile)

            var item_tile = Tile()
            item_tile.position = int2(x,y)
            item_tile.z = tile.z
            item_tile.kind = TileKind NONE
            tint = 1.0 - rain_percent * 0.1
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
    player.kind = TileKind HUMAN_ON_HORSE
    camera.position = player.position - float2(3.0,3.0)

    push(characters, player)

    for i in range(0, npcCount)
        var npc = new AiCharacter()
        npc.position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
        npc.target_position = npc.position
        npc.kind = TileKind HUMAN
        if random_float(seed) > 0.33
            if random_float(seed) > 0.5
                npc.kind = TileKind HORSE
            elif random_float(seed) > 0.5
                npc.kind = TileKind SHEEP
            else
                npc.kind = TileKind SHEEP


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
        player.health = min(player.health + 1, max_health)
        chest.kind = TileKind HEART_FULL
        pick(chest)
    else
        player.hunger = min(player.hunger + 1, max_hunger)
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

def pick(var tile : Tile)
    if tile.anim.kind != AnimKind NONE
        return
    
    player.items[tile.kind] += 1
    tile.anim.kind = AnimKind PICK
    tile.anim.t = 0.0
    tile.anim.stopT = 0.5
    grid_items->setTile(tile)

    if tile.kind == TileKind WHEAT_FULL
        player.items[tile.kind] += 1
        unprepare_ground_for_seeds2(tile.position)

def is_pickable(tile : TileKind) : bool
    return tile == TileKind WOOD || tile == TileKind WHEAT_FULL

var prev_horse : AiCharacter?
var prev_leashed : AiCharacter?

def is_on_horse():bool
    return player.kind == TileKind HUMAN_ON_HORSE

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
    if is_on_horse()
        unmount_horse()
        return
    
    if prev_leashed != null
        unleash(prev_leashed)
        prev_leashed = null
        return

    
    var npc = get_nearest_npc(player.position)
    if npc != null
        var pp = player.position
        var np = npc.position
        var l = length(np - pp)
        if l > 1.0
            npc = null

    if npc != null
        if npc.kind == TileKind HORSE
            mount_horse(npc)
        elif npc.kind == TileKind SHEEP
            leash_to_player(npc)

def do_action()
    if is_on_horse()
        return 
    var item = grid_items->getTile(player.position)
    if item.kind == TileKind CHEST_IRON
        open_chest(item)
    elif item.kind == TileKind NONE
        if is_ground_prepared1(item.position) && is_ground_prepared2(item.position)
            if player.items[TileKind WHEAT_FULL] > 0
                plant_seeds(item.position)
        else
            if is_ground_prepared1(item.position)
                prepare_ground_for_seeds2(item.position)
            else
                prepare_ground_for_seeds1(item.position)
    elif int(item.kind) >= int(TileKind TREE_GREEN) && int(item.kind) <= int(TileKind TREE_RED)
        cut_tree(item)
    elif is_pickable(item.kind)
        pick(item)

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

    var playerSpeed = 0.0
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
        do_action()
    if get_key_down(VK_F)
        do_alt_action()

    player.velocity = clampLength(player.velocity, 1.0) * GetMaxSpeed(player)
    if get_key(VK_LSHIFT)
        player.velocity *= 2.5
        player.isRunning = true
    else
        player.isRunning = false

    for ch in characters
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
        for tile in grid_items.tiles
            if tile.kind == TileKind PLANTED_SEEDS
                tile.kind = TileKind WHEAT_SMALL
            elif tile.kind == TileKind WHEAT_SMALL
                tile.kind = TileKind WHEAT_MEDIUM
            elif tile.kind == TileKind WHEAT_MEDIUM
                tile.kind = TileKind WHEAT_FULL

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

    pass

def draw_tile(tile : TileFloat)
    var pos = tile.position
    pos.y += tile.z * tileZToY
    var kind = tile.kind
    var color = tile.color

    var angle = 0.0
    var size = float2(1.0,1.0)
    if tile.mirrorX
        size.x = -1.0
    apply_anim(tile.anim, pos, size, angle)

    size *= float2(tileSizeX,tileSizeY) * camera.scale
    var texture_rect = get_tile_texture_rect(kind)

    var pivot = float2(0.5,0.5)
    //TODO separate func
    if kind == TileKind TREE_GREEN || kind == TileKind TREE_YELLOW || kind == TileKind TREE_RED
        pivot = float2(0.5,1.0)
    if kind == TileKind PLANTED_SEEDS || kind == TileKind WHEAT_SMALL || kind == TileKind WHEAT_MEDIUM || kind == TileKind WHEAT_FULL
        pos.y -= 1.0

    
    var clip_space_pos = camera->worldToScreen(pos + (float2(0.5,0.5) - pivot) * tileSizeY / tileFloorSizeY)

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

def draw_character(character : Character?)
    var tile = TileFloat()
    var runningOffset = min(character.speed, 1.0) * 0.1 * abs(sin(10.0 * get_time_after_start() * (character.isRunning ? 2.0 : 1.0)))
    var picOffset = float2(0.0,0.9)
    var zOffset = float2(0.0,character.z * tileZToY)
    var pos = character.position
    var anim : Anim
    tile.mirrorX = character.mirrorX
    tile.position = pos + picOffset + float2(0.0, runningOffset) + zOffset
    tile.kind = character.kind

    if character.on_leash && character.follow_player_on_leash
        var from_pos = character.position
        from_pos += float2(0.0, 0.4)
        var to_pos = player.position
        to_pos += float2(0.0, 0.2)
        
        from_pos = camera->worldToScreen(from_pos)
        to_pos = camera->worldToScreen(to_pos)
        line(from_pos.x, from_pos.y, to_pos.x, to_pos.y, 0xff333333)
        pass
    
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

    var health = player.health
    var hunger = player.hunger
    var texture_rect : float4 
    var color = 0xffffffff
    var size = float2(tileSizeX,tileSizeY) * 3.0
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
        var clip_space_pos = float2(10.0 + 16.0 * float(i),0.0)*3.0

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

    //hunger
    for i in range(0, max_hunger / 2)
        var blinkFreq = 2.0
        var isBlinking = player.isRunning && ((time * blinkFreq) - float(floori(time * blinkFreq))) > 0.5
        isBlinking = isBlinking && (max(0, hunger - 1) / 2 == i)
        color = isBlinking ?  0x33ffffff : 0xffffffff
        if hunger >= i * 2 + 2
            texture_rect = get_tile_texture_rect(TileKind HUNGER_FULL)
        elif hunger == i * 2 + 1
            texture_rect = get_tile_texture_rect(TileKind HUNGER_HALF)
        else
            texture_rect = get_tile_texture_rect(TileKind HUNGER_EMPTY)
        var clip_space_pos = float2(9.5 + 16.0 * float(i),0.0 + 14.0)*3.0

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0.0, 0.5f,0.5f)

    var y = 100
    for kind, count in keys(player.items),values(player.items)
        text_out(10,y, "{kind} {count}", 0xffffffff)
        y += 20
    pass

var camFSizeX = 12.0
var camFSizeY = 10.0

def is_culled(pos : float2) : bool
    return abs(camera.position.x - pos.x) > camFSizeX || abs(camera.position.y - pos.y) > camFSizeY

def is_culled(pos : int2) : bool
    return abs(camera.position.x - float(pos.x)) > camFSizeX || abs(camera.position.y - float(pos.y)) > camFSizeY

[export]
def draw

    clear(drawTilesQueue)
    enable_alpha_blend()
    fill_rect(0, 0, get_screen_width(), get_screen_height(), 0xff204020)
    if draw_grid
        draw_grid(0xffffffff)

    var time = get_time_after_start()
    var idx = 0
    
    idx = length(grid_ground.tiles)-1
    while idx >= 0
        let tile = grid_ground.tiles[idx] 
        idx -= 1
        if is_culled(tile.position)
            continue
        draw_tile(to_tile_float(tile))

    idx = length(grid_ground_decals.tiles)-1
    while idx >= 0
        let tile = grid_ground_decals.tiles[idx] 
        idx -= 1
        if is_culled(tile.position)
            continue
        draw_tile(to_tile_float(tile))
        

    for tile in grid_items.tiles
        if is_culled(tile.position)
            continue
        if tile.kind != TileKind NONE
            draw_item_tile(to_tile_float(tile))
            
    for ch in characters
        if is_culled(ch.position)
            continue
        draw_character(ch)
    
    if !is_on_horse()
        draw_tile_highlight(grid_ground->getTile(player.position))

    sort(drawTilesQueue, $(a,b)=>a.priority==b.priority && a.tile.position.y>b.tile.position.y || a.priority>b.priority)

    for tile in drawTilesQueue
        draw_tile(tile.tile)

    if draw_grid
        draw_grid(0x08ffffff)

    draw_ui()
