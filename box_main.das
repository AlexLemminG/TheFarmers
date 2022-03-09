require daslib/media
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

require tiles

var pieces : ImageHandle
var tiles : ImageHandle


var proj : float4x4
var proj_view : float4x4
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

var rain_percent = 1.0
var wheat_grow_timer = 0.0
var wheat_grow_period = 5.0

class Character
    position : float2
    velocity : float2
    z : float
    speed : float
    kind : TileKind
    health : int = 3
    hunger : int = 3
    isRunning : bool = false
    items : table<TileKind; int> 

class Player : Character
    speed2 : float

class AiCharacter : Character
    target_position : float2

var map_size = int2(100,100)
var map_size_f = float2(float(map_size.x),float(map_size.y))
var seed : int4

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
    player.kind = TileKind HUMAN
    camera.position = player.position - float2(3.0,3.0)

    push(characters, player)

    var npcCount = 10
    for i in range(0, npcCount)
        var npc = new AiCharacter()
        npc.position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
        npc.target_position = npc.position
        npc.kind = TileKind HUMAN
        if random_float(seed) > 0.33
            if random_float(seed) > 0.5
                npc.kind = TileKind CHILD_A
            else
                npc.kind = TileKind CHILD_B


        push(characters, npc)
        push(aiCharacters, npc)

    return

var x = 3

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

def do_action()
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

    var maxPlayerSpeed = 2.0

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

    player.velocity = clampLength(player.velocity, 1.0) * maxPlayerSpeed
    if get_key(VK_LSHIFT)
        player.velocity *= 2.5
        player.isRunning = true
    else
        player.isRunning = false

    for ch in characters
        ch.position += ch.velocity * dt
        ch.speed = lerp(ch.speed, length(ch.velocity), dt*5.0)
        ch.z = lerp(ch.z, grid_ground->getHeight(ch.position), dt * 8.0)

        for x in range(int(ch.position.x), int(ch.position.x+2.0))
            for y in range(int(ch.position.y), int(ch.position.y+2.0))
                var tileToCollide = grid_items->getTile(float2(float(x), float(y)))
                ch.position.x = clamp(ch.position.x, -0.5,map_size_f.x - 0.6)
                ch.position.y = clamp(ch.position.y, -0.5,map_size_f.y - 0.6)
                processCollision(ch.position, tileToCollide)

    for ch in aiCharacters
        if length(ch.target_position - ch.position) < 1.0
            ch.target_position = float2(random_float(seed) * float(map_size.x), random_float(seed) * float(map_size.y))
            pass
        ch.velocity = lerp(ch.velocity, clampLength(ch.target_position - ch.position, 1.f) * maxPlayerSpeed, 3.0 * dt)


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


    return

def world_to_clip(pos : float3) : float4
    var pos4 = float4(pos.x,pos.y,pos.z,1f)
    var clip_space_pos = proj_view * pos4
    clip_space_pos.w = 1f
    clip_space_pos = clip_space_pos / clip_space_pos.z
    return clip_space_pos

def draw_king(pos : float4)
    var texture_rect = float4(0,0,240,240)
    var color = 0xffffffff
    var size = float2(12f,12f)
    var pi = 3.1415

    var clip_space_pos = pos

    size = size * clip_space_pos.w * -20f

    draw_image_transformed(pieces, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, 0f, 0.5f,0.5f)

    pass

def sphere(count : int; var arr : array<float4>)
    var phi = PI * (1.0 - sqrt(5.0))
    var radius = 10f
    for i in range(0, count+1)
        var t = float(i) / float(count)
        
        var y = 1.0 - t * 2.0
        var r = sqrt(1.0 - y*y)
        var theta = phi * float(i)
        var x = r * sin(theta)
        var z = r * cos(theta)

        push_clone(arr, world_to_clip(float3(x,y,z) * radius))
    pass

def cube(count : int; var arr : array<float4>)
    var radius = 4f / sqrt(3f)
    var halfSize = ceili(sqrt(float(count) / 6f)) / 2
    for x in range(-halfSize, halfSize+1)
        for y in range(-halfSize, halfSize+1)
            for z in range(-halfSize, halfSize+1)
                if abs(x) == halfSize || abs(y) == halfSize || abs(z) == halfSize
                    push_clone(arr, world_to_clip(float3(x,y,z) * radius / float(halfSize)))
        pass



// var cameraScale : float
// var cameraOffset : float2

def get_tile_texture_rect(kind : TileKind) : float4
    var tileSizeX = 18
    var tileSizeY = 28
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

    return float4(x*tileSizeX,y*tileSizeY,tileSizeX,tileSizeY)

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

                //deltaPos.x += sign(deltaDelta.x) * max(0.05, abs(deltaDelta.x)) * 0.1
            else
                deltaPos.x += deltaDelta.x

                //deltaPos.y += sign(deltaDelta.y) * max(0.05, abs(deltaDelta.y)) * 0.1


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

def draw_tile(pos : float2; anim : Anim; kind : TileKind; color : uint = 0xffffffff)
    var p = pos
    var angle = 0.0
    var size = float2(1.0,1.0)
    apply_anim(anim, p, size, angle)

    size *= float2(tileSizeX,tileSizeY) * camera.scale
    var texture_rect = get_tile_texture_rect(kind)

    var pivot = float2(0.5,0.5)
    //TODO separate func
    if kind == TileKind TREE_GREEN || kind == TileKind TREE_YELLOW || kind == TileKind TREE_RED
        pivot = float2(0.5,1.0)
    if kind == TileKind PLANTED_SEEDS || kind == TileKind WHEAT_SMALL || kind == TileKind WHEAT_MEDIUM || kind == TileKind WHEAT_FULL
        p.y -= 1.0

    
    var clip_space_pos = camera->worldToScreen(p + (float2(0.5,0.5) - pivot) * tileSizeY / tileFloorSizeY)

    draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, angle, pivot.x, pivot.y)

    pass

struct TileWithPos
    pos : float2
    kind : TileKind
    anim : Anim
    color : uint
    priority : int

var drawTilesQueue : array<TileWithPos>

def draw_tile(tile : Tile)
    draw_tile(float2(float(tile.position.x), float(tile.position.y) + tile.z * tileZToY), tile.anim, tile.kind, tile.color)

def add_to_draw_queue(pos : float2; kind : TileKind; anim : Anim; priority : int = 0; color : uint = 0xffffffff)
    var t : TileWithPos
    t.pos = pos
    t.kind = kind
    t.color = color
    t.priority = priority
    t.anim = anim
    push(drawTilesQueue, t)

def draw_item_tile(tile : Tile)
    var picOffset = float2(0.0,1.0)
    add_to_draw_queue(float2(float(tile.position.x), float(tile.position.y) + tile.z * tileZToY) + picOffset, tile.kind, tile.anim, 0, tile.color)

def draw_character(player : Character?)
    var runningOffset = min(player.speed, 1.0) * 0.1 * abs(sin(10.0 * get_time_after_start() * (player.isRunning ? 2.0 : 1.0)))
    var picOffset = float2(0.0,0.9)
    var zOffset = float2(0.0,player.z * tileZToY)
    var pos = player.position
    var anim : Anim
    add_to_draw_queue(pos + picOffset + float2(0.0, runningOffset) + zOffset, player.kind, anim)

def draw_tile_highlight(tile : Tile)
    var anim : Anim
    add_to_draw_queue(float2(float(tile.position.x), float(tile.position.y) + tile.z * tileZToY), TileKind TILE_SELECTION, anim, 1)
    pass

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
    var size = float2(18.0,28.0) * 3.0
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
    var draw_grid = false

    proj = persp_forward(300f, 300f, 0.5, 100f)
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
        draw_tile(tile)

    idx = length(grid_ground_decals.tiles)-1
    while idx >= 0
        let tile = grid_ground_decals.tiles[idx] 
        idx -= 1
        if is_culled(tile.position)
            continue
        draw_tile(tile)
        

    for tile in grid_items.tiles
        if is_culled(tile.position)
            continue
        if tile.kind != TileKind NONE
            draw_item_tile(tile)
            
    for ch in characters
        if is_culled(ch.position)
            continue
        draw_character(ch)
    
    draw_tile_highlight(grid_ground->getTile(player.position))

    sort(drawTilesQueue, $(a,b)=>a.priority==b.priority && a.pos.y>b.pos.y || a.priority>b.priority)

    for tile in drawTilesQueue
        draw_tile(tile.pos, tile.anim, tile.kind, tile.color)

    if draw_grid
        draw_grid(0x08ffffff)

    draw_ui()
    // var rotationSpeed = 1f
    // var lookRotation = un_quat_from_unit_vec_ang(float3(0f,1f,0f), rotationSpeed * time)
    // var distanceFromCenter = 20f
    // var view = compose(float4(quat_mul_vec(lookRotation, float3(0f,0f,distanceFromCenter)),1f), lookRotation, float4(1,1,1,1)) 
    // view = inverse(view)

    // var width = get_screen_width()
    // var height = get_screen_height()
    // var proj_to_screen = compose(float4(float(width)/2f, float(height)/2f, 0f,1f), float4(0f,0f,0f,1f), float4(1f,1f,1f,1f))
    // identity(proj_to_screen)
    // proj_to_screen[3][0]=float(get_screen_width())/2f
    // proj_to_screen[3][1]=float(get_screen_height())/2f
    // proj_view = proj_to_screen * proj * view

    // enable_alpha_blend()
    // get_time_after_start()

    // var screenSpacePoints : array<float4>

    // sphere(500, screenSpacePoints)
    // cube(200, screenSpacePoints)

    // sort(screenSpacePoints, $(a,b)=>a.w>b.w)
    // for pos in screenSpacePoints
    //     draw_king(pos)

        
    return
