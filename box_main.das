require daslib/media

require tiles
require fio
require json
require daslib/json_boost

options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

var dbg_mode : bool = true
// tweakable settings
var night_percent = 0.0
var rain_percent = 0.0
var wheat_grow_timer = 0.0
var wheat_grow_period = 5.0
var draw_grid = false
var map_size = int2(20,20)
var npcCount = 30
var hunger_per_hour = 600.0
var health_loss_from_hunger_per_hour = 0.0
var health_gain_from_no_hunger_per_hour = 600.0
var gamedays_per_hour = 12.0

var gamedays_to_grow_wool = 2.0

var dbg_time_scale = 1.0
var time_scale = 1.0
var player_sleep_time_scale_when_everyone_sleeps = 50.0
var player_sleep_time_scale = 10.0
var seconds_per_hour = 3600.0
var hours_per_second = 1.0 / seconds_per_hour
var pieces : ImageHandle
var tiles : ImageHandle
var seconds_per_gameday = seconds_per_hour / gamedays_per_hour

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

var sounds : table<string; SoundHandle>
var empty_sound : SoundHandle

var all_human_names : array<string>
var initial_day_float = 1.0 + 6.0 / 24.0

struct WorldState
    next_free_human_name : int = 0
    day_float : float = initial_day_float

def get_realtime_since_world_started() : float
    return (world_state.day_float - initial_day_float) * seconds_per_gameday

var world_state = WorldState()

def play_sound(str : string; pos : float2; volumeMult : float = 1.0; pitchMult : float = 1.0)
    var snd = sounds[str]
    if snd.duration == 0.0
        try
            snd <- create_managed_sound("sounds/{str}.wav")
        recover
            pass
        sounds[str] = snd

    let dist_multi = 0.5
    let delta_pos = pos - player.position
    var volume = volumeMult / max(1.0, length_sq(delta_pos * dist_multi))
    var pitch = pitchMult
    var pan = clamp(-delta_pos.x * 0.5, -0.5, 0.5)
    snd |> play_sound(volume, pitch, pan)

def random_float(min : float; max : float) : float
    return random_float(seed) * (max-min) + min

def play_sound(kind : SoundKind; pos : int2)
    play_sound(kind, float2(pos))

def play_sound(kind : SoundKind; pos : float2)
    var str = "{kind}"
    var volume = 1.0
    var pitch = 1.0
    if kind == SoundKind FOOTSTEP
        str = "FOOTSTEP ({(random_int(seed) % 8) + 1})"
        volume = 0.2
    elif kind == SoundKind CHOP
        pitch = random_float(0.9, 1.1)
    elif kind == SoundKind FIRE_PUT_OUT
        volume = 0.3
    elif kind == SoundKind PICK || kind == SoundKind DROP
        volume = 0.3
        pitch = random_float(1.5, 1.6)
    elif kind == SoundKind GENERIC_ACTION
        volume = 0.3
        pitch = random_float(0.7, 0.75)

    play_sound(str, pos, volume, pitch)

def get_pick_sound(kind : TileKind) : SoundKind
    return SoundKind PICK

def get_drop_sound(kind : TileKind) : SoundKind
    return SoundKind DROP



let dbg_pathfinding = false

struct SavedGrid
    height : int
    width : int
    tiles : array<TileKind>

struct SavedCharacter
    position : float2
    kind : TileKind
    carry_item : TileKind
    ai_command : AiCommand
    name : string
    is_name_known : bool
    saved_float : float
    hunger : float
    health : float

def save_character(c : Character?) : JsonValue?
    var ch : SavedCharacter
    ch.position = c.position
    ch.kind = c.kind
    ch.carry_item = c.carry_item
    ch.ai_command = c.command
    ch.name = c.name
    ch.is_name_known = c.is_name_known
    ch.saved_float = c.saved_float
    ch.hunger = c.hunger
    ch.health = c.health
    return JV(ch)

def load_ai_command(var json : JsonValue?;var c : AiCommand)
    var str_kind = (json as _object)["kind"] as _string
    c.kind = str_to_ai_command_kind[str_kind]
    c.a_pos = load_float2((json as _object)["a_pos"])
    c.b_pos = load_float2((json as _object)["b_pos"])
    c.a_tile = str_to_tile_kind[(json as _object)["a_tile"] as _string]
    c.b_tile = str_to_tile_kind[(json as _object)["b_tile"] as _string]

def load_float2(var json : JsonValue?) : float2
    var p : float2
    p.x = float((json as _object)["x"] as _number)
    p.y = float((json as _object)["y"] as _number)
    return p

def load_character(var json : JsonValue?;var g : Character?)
    g.position = load_float2((json as _object)["position"])

    var str = (json as _object)["kind"] as _string
    g.kind = str_to_tile_kind[str]
    str = (json as _object)["carry_item"] as _string
    g.carry_item = str_to_tile_kind[str]
    g.name = (json as _object)["name"] as _string
    g.is_name_known = (json as _object)["is_name_known"] as _bool
    g.saved_float = float((json as _object)["saved_float"] as _number)
    g.hunger = float((json as _object)["hunger"] as _number)
    g.health = float((json as _object)["health"] as _number)
    load_ai_command((json as _object)["ai_command"], g.command)
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
var str_to_ai_command_kind : table<string; AiCommandKind>
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

def load_world_state(var json : JsonValue?) : WorldState
    var state = WorldState()
    state.day_float = float((json as _object)["day_float"] as _number)
    return state

def save_world_state(state : WorldState) : JsonValue?
    return JV(state)

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

    (json as _object)["world_state"] = save_world_state(world_state)

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

    clear(str_to_ai_command_kind)
    for e in each_enum(type<AiCommandKind>)
        str_to_ai_command_kind["{e}"] =  e
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

    world_state = load_world_state((json as _object)["world_state"])

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
    fixed_seed : int4 = int4(random_int(seed), random_int(seed), random_int(seed), random_int(seed))
    command : AiCommand
    saved_float : float
    position : float2
    velocity : float2
    name : string
    is_name_known : bool
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
    next_footstep_time : float


def GetPreferedSpeed(character : Character) : float
    if character.kind == TileKind SHEEP || character.kind == TileKind SHEEP_SHEARED
        return 0.2
    elif character.kind == TileKind HORSE
        return 2.0
    else
        return GetMaxSpeed(character) / 2.0

def GetMaxSpeed(character : Character) : float
    if character.kind == TileKind HORSE || character.kind == TileKind HUMAN_ON_HORSE
        return 4.0
    elif character.kind == TileKind SHEEP || character.kind == TileKind SHEEP_SHEARED
        return 2.0
    else
        return 2.0

class Player : Character
    speed2 : float

enum AiCommandKind
    NONE
    BRING_A_TILE_TO_B_TILE
    DO_DEFAULT_ACTION_ON_A_TILE
    MAKE_WHEAT_STACKS
    PLOW_GROUND
    PICK_A
    PLANT_WHEAT
    STAY_NEAR_A_TILE
    GO_TO_SLEEP


struct AiCommand
    kind : AiCommandKind
    a_tile : TileKind
    b_tile : TileKind
    a_pos : float2
    b_pos : float2

def is_human(kind : TileKind) : bool
    return kind == TileKind HUMAN || kind == TileKind CHILD_A || kind == TileKind CHILD_B

def get_current_hour_float() : float
    var time_float = world_state.day_float - float(trunci(world_state.day_float))
    return time_float * 24.0

def get_current_hour() : int
    return int(get_current_hour_float())

def is_evening_time() : bool
    return get_current_hour_float() >= 18.0 && get_current_hour_float() < 22.0

def is_night_time(hours_offset = 0.0) : bool
    let hours = (get_current_hour_float() + hours_offset) % 24.0
    return hours >= 22.0 || hours < 6.0

def is_morning_time() : bool
    return get_current_hour_float() >= 6.0 && get_current_hour_float() < 10.0

def is_day_time() : bool
    return get_current_hour_float() >= 10.0 && get_current_hour_float() < 18.0

def is_player_must_sleep_time() : bool
    return get_current_hour_float() >= 24.0 || get_current_hour_float() < 6.0

def is_sleep_action_on_bed() : bool
    return is_night_time()

def angle_radius_to_point(angle_rad : float; radius : float)
    return float2(sin(angle_rad), cos(angle_rad)) * radius

class AiCharacter : Character
    target_position : float2
    dbg_str : string
    idle_time_left : float

    def fixed_random_int4() : int4
        return fixed_seed

    def fixed_random_float(idx : int = 0) : float
        var s = fixed_random_int4()
        for i in range(idx)
            random_float(s) 
        return random_float(s) 

    def get_current_command() : AiCommand
        if is_evening_time()
            if is_human(kind)
                var cmd : AiCommand
                cmd.a_tile = TileKind CAMPFIRE
                cmd.kind = AiCommandKind STAY_NEAR_A_TILE
                return cmd
        elif is_night_time(fixed_random_float())
            var cmd : AiCommand
            cmd.kind = AiCommandKind GO_TO_SLEEP
            return cmd
        return command

    def Think(dt : float)
        dbg_str = "" 

        if anim.kind == AnimKind SLEEP || anim.kind == AnimKind SLEEP_IN_BED && !is_night_time(fixed_random_float())
            set_character_animation(self, AnimKind NONE)

        if !process_command(dt, get_current_command())
            if length(target_position - position) < 1.0
                target_position = random_wander_pos(position)
                return
            while !is_walkable_for_a_star(grid_ground->getIntPos(target_position), is_human(kind))
                target_position = random_wander_pos(position)
        var preferedSpeed = GetPreferedSpeed(self)
        if on_leash
            var leash_length = 1.0
            var delta = player.position - position
            if follow_player_on_leash && length(delta) > 1.0
                target_position = position + clampLength(delta, length(delta) - leash_length)
            else
                target_position = position
            preferedSpeed = min(length(delta), GetMaxSpeed(self))

        var immediateTargetPos : float2
        immediateTargetPos = target_position
        if !is_walkable_for_a_star(grid_ground->getIntPos(position), is_human(kind)) && !on_leash
            immediateTargetPos = float2(get_nearest_walkable(position, is_human(kind)))
        elif length(target_position - position) > 1.0
            var path : array<int2>
            path <- a_star(grid_ground->getIntPos(position), grid_ground->getIntPos(target_position), is_human(kind))
            if length(path) > 1
                //TODO relax path to remove zig-zags
                immediateTargetPos = float2(path[1]) + (grid_items->getTileInt(path[1]).kind == TileKind NONE ? float2(0.0) : float2(0.15, 0.35))
                //if world_state.day_float % 1.0 * (100.0 + fixed_random_float()) % 1.0 > 0.99 //hacky hacky hacky ho
                //    immediateTargetPos += float2(-0.05, 0.03)
            elif !on_leash
                immediateTargetPos = position
                if command.kind == AiCommandKind NONE
                    target_position = random_wander_pos(position)
        dbg_ai("moving to {target_position} (immediate {immediateTargetPos})") 
        velocity = lerp(velocity, clampLength((immediateTargetPos - position)*2.0, 1.f) * preferedSpeed, 3.0 * dt)
        
    def process_command(dt : float; cmd : AiCommand) : bool
        if idle_time_left > 0.0
            idle_time_left -= dt
            return true
        if cmd.kind == AiCommandKind MAKE_WHEAT_STACKS
            if item_is(carry_item, TileKind WHEAT_COLLECTED_6)
                var nearest_empty_pos = find_nearest_empty_pos(grid_items->getIntPos(position))
                if nearest_empty_pos == invalid_tile_pos
                    return false
                drop_carry_item(self, nearest_empty_pos)
                return true
            if _process_command(ai_command_pick_a(TileKind WHEAT_COLLECTED_NOT_6))
                return true
            return false
        elif cmd.kind == AiCommandKind PLANT_WHEAT
            if !item_is(carry_item, TileKind WHEAT_COLLECTED_ANY)
                if _process_command(ai_command_pick_a(TileKind WHEAT_COLLECTED_ANY))
                    return true
                return false
            else
                //TODO use pos and do_default command
                return _process_command(cmd)

        var result = _process_command(cmd)
        if !result && cmd.kind == AiCommandKind BRING_A_TILE_TO_B_TILE && is_flag(cmd.b_tile) && cmd.a_tile == TileKind WHEAT_STACK
            result = process_command(dt, ai_command_make_wheat_stacks())
        return result

    def dbg_ai(msg : string)
        dbg_str += "{msg}\n"

    //true if in process of doing command
    //false if cant do it
    def _process_command(cmd : AiCommand) : bool
        dbg_ai("checking {cmd}")
        let intPos = grid_items->getIntPos(position)
        if cmd.kind == AiCommandKind BRING_A_TILE_TO_B_TILE
            var is_drop_command = is_flag(cmd.b_tile)
            var drop_excluding_half_size : int
            var drop_flag_pos : int2

            var nearest_tile_b_pos = find_nearest_item(cmd.b_tile, intPos)
            if nearest_tile_b_pos == invalid_tile_pos
                dbg_ai("no {cmd.b_tile} found")
                return false

            if is_drop_command
                drop_flag_pos = nearest_tile_b_pos
                nearest_tile_b_pos = find_nearest_empty_pos(nearest_tile_b_pos)
                if nearest_tile_b_pos == invalid_tile_pos
                    dbg_ai("no empty tiles near {cmd.b_tile} found")
                    return false
                var delta = abs(nearest_tile_b_pos - drop_flag_pos)
                drop_excluding_half_size = max(delta.x, delta.y)
                
            if !item_is(carry_item, cmd.a_tile)
                var nearest_tile_a_pos :int2 
                if is_drop_command
                    nearest_tile_a_pos = find_nearest_item_excluding_rect(cmd.a_tile, intPos, drop_excluding_half_size, drop_flag_pos)
                else
                    nearest_tile_a_pos = find_nearest_item(cmd.a_tile, intPos)

                if nearest_tile_a_pos == invalid_tile_pos
                    dbg_ai("no {cmd.a_tile} found")
                    return false
                if length(float2(nearest_tile_a_pos - intPos)) > 0.8
                    target_position = float2(nearest_tile_a_pos)
                    return true
                pick(self, grid_items->getTileInt(nearest_tile_a_pos))
                idle_time_left = 0.5
                return true

            if length(float2(nearest_tile_b_pos - intPos)) > 0.8
                target_position = float2(nearest_tile_b_pos)
                return true

            if is_drop_command
                drop_carry_item(self, nearest_tile_b_pos)
            else
                var tile = grid_items->getTileInt(nearest_tile_b_pos)
                if !can_craft(self, tile)
                    assert(false)
                    return false
                craft(self, tile)
                return true
        elif cmd.kind == AiCommandKind PICK_A
            if carry_item != cmd.a_tile || is_collected_wheat(cmd.a_tile)
                let nearest_tile_a_pos = find_nearest_item(cmd.a_tile, intPos)
                if nearest_tile_a_pos == invalid_tile_pos
                    return false
                if length(float2(nearest_tile_a_pos - intPos)) > 0.8
                    target_position = float2(nearest_tile_a_pos)
                    return true
                pick(self, grid_items->getTileInt(nearest_tile_a_pos))
                return true
        elif cmd.kind == AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
            if carry_item != TileKind NONE
                var nearest_empty_pos = find_nearest_empty_pos(grid_items->getIntPos(position))
                if nearest_empty_pos == invalid_tile_pos
                    return false
                drop_carry_item(self, nearest_empty_pos)

            let nearest_tile_a_pos = find_nearest_item(cmd.a_tile, intPos)
            if nearest_tile_a_pos == invalid_tile_pos
                dbg_ai("no {cmd.a_tile} found")
                return false
            if length(float2(nearest_tile_a_pos - intPos)) > 0.8
                target_position = float2(nearest_tile_a_pos)
                dbg_ai("setting target_position to nearest {cmd.a_tile} at {nearest_tile_a_pos}")
                return true
            idle_time_left = 0.5
            var res = do_alt_action(self, nearest_tile_a_pos)
            if res.is_valid
                dbg_ai("doing alt_action with {cmd.a_tile} at {nearest_tile_a_pos}")
            else
                dbg_ai("failed to do alt_action with {cmd.a_tile} at {nearest_tile_a_pos}")
                assert(false)
                return false
            return true
        elif cmd.kind == AiCommandKind PLOW_GROUND
            var nearest_non_plowed = find_nearest_non_plowed_ground(grid_items->getIntPos(position))
            if nearest_non_plowed == invalid_tile_pos
                dbg_ai("no non-plowed soil found")
                return false
            if length(float2(nearest_non_plowed - intPos)) > 0.8
                target_position = float2(nearest_non_plowed)
                dbg_ai("setting target_position to nearest non-plowed soil at {nearest_non_plowed}")
                return true
            idle_time_left = 0.5
            var res = do_alt_action(self, nearest_non_plowed)
        elif cmd.kind == AiCommandKind PLANT_WHEAT
            var nearest_plowed = find_nearest_plowed_ground(grid_items->getIntPos(position))
            if nearest_plowed == invalid_tile_pos
                dbg_ai("no plowed soil found")
                return false
            if length(float2(nearest_plowed - intPos)) > 0.8
                target_position = float2(nearest_plowed)
                dbg_ai("setting target_position to nearest plowed soil at {nearest_plowed}")
                return true
            idle_time_left = 0.5
            var res = do_alt_action(self, nearest_plowed)
        elif cmd.kind == AiCommandKind STAY_NEAR_A_TILE
            var nearest_tile = find_nearest_item(cmd.a_tile, grid_items->getIntPos(position))
            if nearest_tile == invalid_tile_pos
                dbg_ai("no {cmd.a_tile} found")
                return false
            var delta_pos = angle_radius_to_point(fixed_random_float(0) * PI * 2.0, lerp(0.4, 0.6, fixed_random_float(1)))
            var nearest_tile_float = float2(nearest_tile) + delta_pos
            if length(nearest_tile_float - position) > 0.2
                target_position = nearest_tile_float
                dbg_ai("setting target_position to nearest {cmd.a_tile} at {nearest_tile}")
                return true
            return true //continue staying
        elif cmd.kind == AiCommandKind GO_TO_SLEEP
            if anim.kind == AnimKind SLEEP_IN_BED || anim.kind == AnimKind SLEEP
                return true 
            //TODO if human find bed
            //TODO sleep in personal tile
            var is_going_to_bed = false
            if is_human(kind)
                var go_to_bed_result = _process_command(ai_command_do_default_action_on_a(TileKind BED))
                if go_to_bed_result
                    return true
            
            var nearest_sleep_pos = find_nearest_empty_pos(intPos)
            if nearest_sleep_pos == invalid_tile_pos
                dbg_ai("no sleep pos found")
                return false

            var delta_pos = is_going_to_bed ? float2(0.0,0.0) : float2(fixed_random_float(0), fixed_random_float(1)) - float2(0.5, 0.5)
            var nearest_sleep_pos_float = float2(nearest_sleep_pos) + delta_pos
            if length(nearest_sleep_pos_float - position) > 0.5
                target_position = nearest_sleep_pos_float
                dbg_ai("setting target_position to nearest empty pos at {nearest_sleep_pos}")
                return true

            set_character_animation(self, AnimKind SLEEP)
            target_position = position
            velocity = float2(0.0,0.0)
            return true //continue sleeping


        return false

def item_is(item : TileKind; other : TileKind) : bool
    if other == TileKind TREE
        if int(item) >= int(TileKind TREE_GREEN) && int(item) <= int(TileKind TREE_RED)
            return true
    if other == TileKind WHEAT_COLLECTED_NOT_6
        if int(item) >= int(TileKind WHEAT_COLLECTED_1) && int(item) <= int(TileKind WHEAT_COLLECTED_5)
            return true
    if other == TileKind WHEAT_STACK
        if item == TileKind WHEAT_COLLECTED_6
            return true
    if other == TileKind WHEAT_COLLECTED_ANY
        if int(item) >= int(TileKind WHEAT_COLLECTED_1) && int(item) <= int(TileKind WHEAT_COLLECTED_6)
            return true
    if other == TileKind WHEAT
        if item == TileKind WHEAT_FULL
            return true
    return item == other

var dbg_highlighted_tiles : array<int2>
def dbg_highlight(pos : int2)
    push(dbg_highlighted_tiles, pos)

let nearest_search_radius = 20
def find_nearest_item_excluding_rect(kind : TileKind; pos : int2; excluding_half_size : int; excluding_center : int2) : int2
    let radius = nearest_search_radius
    //PERF
    var nearest = invalid_tile_pos
    var nearest_dist = float(radius * radius)
    var checked = 0
    for dx in range(-radius, radius+1)
        for dy in range(-radius, radius+1)
            let item_pos = pos + int2(dx,dy)
            if abs(item_pos.x - excluding_center.x) <= excluding_half_size && abs(item_pos.y - excluding_center.y) <= excluding_half_size
                continue
            checked += 1
            //dbg_highlight(item_pos)
            if item_is(grid_items->getTileInt(item_pos).kind, kind) && length(float2(int2(dx,dy))) < nearest_dist 
                nearest_dist = length(float2(dx,dy))
                nearest = item_pos

    return nearest

def find_nearest_t(pos : int2; predicate:block<(arg:int2):bool>) : int2
    if invoke(predicate, pos)
        return pos

    //PERF try quadtree in emergency situation
    var max_count = (nearest_search_radius * 2 + 1) * (nearest_search_radius * 2 + 1)

    var current_pos = pos
    var current_radius = 1
    var t = 1
    while current_radius <= nearest_search_radius
        for i in range(t)
            current_pos.y -= 1
            if invoke(predicate, current_pos)
                return current_pos
        for i in range(t)
            current_pos.x += 1
            if invoke(predicate, current_pos)
                return current_pos
        t++
        for i in range(t)
            current_pos.y += 1
            if invoke(predicate, current_pos)
                return current_pos
        for i in range(t)
            current_pos.x -= 1
            if invoke(predicate, current_pos)
                return current_pos
        t++
        current_radius++

    return invalid_tile_pos

def find_nearest_item(kind : TileKind; pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>item_is(grid_items->getTileInt(item_pos).kind, kind) )

def find_nearest_plowed_ground(pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>is_ground_prepared2(item_pos) && is_ground_prepared1(item_pos) && grid_items->getTileInt(item_pos).kind == TileKind NONE )

def find_nearest_non_plowed_ground(pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>!is_ground_prepared2(item_pos) && is_ground_prepared1(item_pos) && grid_items->getTileInt(item_pos).kind == TileKind NONE )

def find_nearest_empty_pos(pos : int2) : int2
    return find_nearest_t(pos, $(item_pos)=>grid_items->getTileInt(item_pos).kind == TileKind NONE && is_walkable_for_a_star(item_pos, false))

def die(var character : Character)
    if character.anim.kind == AnimKind DEATH
        return
    set_character_animation(character, AnimKind DEATH)

def ai_command_do_default_action_on_a(a : TileKind) : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
    command.a_tile = a
    return command

def ai_command_make_wheat_stacks() : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind MAKE_WHEAT_STACKS
    return command

def ai_command_plow_ground() : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind PLOW_GROUND
    return command

def ai_command_plant_wheat() : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind PLANT_WHEAT
    return command

def ai_command_pick_a(a : TileKind) : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind PICK_A
    command.a_tile = a
    return command

def ai_command_bring_a_to_b(a : TileKind; b : TileKind) : AiCommand
    var command : AiCommand
    command.kind = AiCommandKind BRING_A_TILE_TO_B_TILE
    command.a_tile = a
    command.b_tile = b
    return command

// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize
    set_window_title("wasisdasbox")
    set_resolution(1080,720)
    pieces <- create_managed_image("piece.png") 
    pieces |> set_image_smooth(true)
    pieces |> set_image_use_mipmap()
    
    var empty_sound_raw : array<float>
    empty_sound = create_managed_sound(44100, empty_sound_raw)

    tiles <- create_managed_image("tiles.png") 
    camera.scale = 3.0

    grid_ground = generate_default_ground_grid(map_size.x, map_size.y)
    grid_items = generate_default_grid(map_size.x, map_size.y, grid_ground)
    grid_ground_decals = generate_default_grid(map_size.x, map_size.y, grid_ground)

    push(all_human_names, "Noël")
    push(all_human_names, "Jérôme")
    push(all_human_names, "Gilles")
    push(all_human_names, "Margot")
    push(all_human_names, "Margaret")
    push(all_human_names, "Renée")
    push(all_human_names, "Émilie")
    push(all_human_names, "Danielle")
    push(all_human_names, "Thierry")
    push(all_human_names, "Guy Morel")
    push(all_human_names, "Isaac")
    push(all_human_names, "Margaux")
    push(all_human_names, "Luc")
    push(all_human_names, "Françoise")
    push(all_human_names, "Odette Lombard")
    push(all_human_names, "Claire Fernandes")
    push(all_human_names, "Roland")
    push(all_human_names, "Zoé")
    push(all_human_names, "Jacques Lecoq")
    push(all_human_names, "Valérie")
    push(all_human_names, "Alain")
    push(all_human_names, "Benoît")
    push(all_human_names, "Anouk")
    push(all_human_names, "Joseph")
    push(all_human_names, "Nathalie")
    push(all_human_names, "Lucas Vidal")
    push(all_human_names, "Christiane")
    push(all_human_names, "Astrid")

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
                elif random_float(seed) > 0.99
                    item_tile.kind = TileKind BUSH_WITH_BERRIES
            else
                if random_float(seed) > 0.9
                    //item_tile.z -= 6.0 / tileFloorHeightZ
                    item_tile.kind = TileKind CHEST_IRON
                elif random_float(seed) > 0.8
                    item_tile.kind = TileKind WHEAT_FULL
                elif random_float(seed) > 0.6
                    item_tile.kind = TileKind STONE //TODO many stones + one flint
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
        if i == 0
            npc.kind = TileKind HUMAN
        else
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

        if is_human(npc.kind)
            npc.name = all_human_names[world_state.next_free_human_name]
            world_state.next_free_human_name = (world_state.next_free_human_name + 1) % length(all_human_names)

        push(characters, npc)
        push(aiCharacters, npc)

    //make_dialog(aiCharacters[0])

    if dbg_mode
        var itemsList : array<TileKind>
        push(itemsList, TileKind STONE)
        push(itemsList, TileKind FLINT_STONE)
        push(itemsList, TileKind CAMPFIRE)
        push(itemsList, TileKind WOOD)
        push(itemsList, TileKind WHEAT_FULL)
        push(itemsList, TileKind BUCKET_EMPTY)
        push(itemsList, TileKind BUCKET_WITH_WATER)
        // push(itemsList, TileKind WHEAT_COLLECTED_1)
        push(itemsList, TileKind WHEAT_COLLECTED_2)
        // push(itemsList, TileKind WHEAT_COLLECTED_3)
        // push(itemsList, TileKind WHEAT_COLLECTED_4)
        push(itemsList, TileKind WHEAT_COLLECTED_5)
        // push(itemsList, TileKind WHEAT_COLLECTED_6)
        push(itemsList, TileKind COAL)
        push(itemsList, TileKind FENCE)
        push(itemsList, TileKind FENCE)
        push(itemsList, TileKind BUSH)
        push(itemsList, TileKind BUSH_WITH_BERRIES)
        push(itemsList, TileKind RED_FLAG)
        push(itemsList, TileKind GREEN_FLAG)
        push(itemsList, TileKind BLUE_FLAG)
        push(itemsList, TileKind BED)
        push(itemsList, TileKind SHEEP_SHEARS)
        push(itemsList, TileKind WOOL)

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
        pick(*player, chest)
    else
        player.hunger = max(player.hunger - 0.5, 0.0)
        chest.kind = TileKind HUNGER_FULL
        pick(*player, chest)

    grid_items->setTile(chest)
    player.items[TileKind GOLD] += 1

def cut_tree(var tree : Tile)
    if tree.anim.kind != AnimKind NONE
        return

    play_sound(SoundKind CHOP, tree.position)
    
    var isFinalHit = tree.info >= 3
    if isFinalHit
        play_sound(SoundKind TREE_FALL, tree.position)
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

def drop_carry_item(var character : Character; pos : int2)
    if character.carry_item != TileKind NONE
        //TODO assert can drop there
        drop(character.carry_item, pos)
        character.carry_item = TileKind NONE

def drop(kind : TileKind; pos : int2)

    var tile = grid_items->getTileInt(pos)
    tile.anim.kind = AnimKind NONE
    tile.kind = kind
    grid_items->setTile(tile)

    play_sound(get_drop_sound(kind), pos)

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

def pick(var character : Character; var tile : Tile)
    if tile.anim.kind != AnimKind NONE
        return
    var kind = tile.kind

    play_sound(get_pick_sound(tile.kind), tile.position)

    if tile.kind == TileKind WHEAT_FULL
        unprepare_ground_for_seeds2(tile.position)
    
    if is_big_item(tile.kind)
        if character.carry_item != TileKind NONE
            if is_collected_wheat(kind) && is_collected_wheat(character.carry_item)
                tile.kind = add_wheat_reminder(kind, character.carry_item)
                character.carry_item = add_wheat(kind, character.carry_item)
            else
                tile.kind = character.carry_item
                drop_carry_item(character, tile.position)
                character.carry_item = kind
        else
            character.carry_item = kind
            tile.kind = TileKind NONE
    else
        character.items[tile.kind] += item_count_per_tile(tile.kind)
        tile.anim.kind = AnimKind PICK
        tile.anim.t = 0.0
        tile.anim.stopT = 0.5


    grid_items->setTile(tile)

def get_bread_count(kind : TileKind) : int
    assert(is_bread(kind))
    return int(kind) - int(TileKind BREAD_1) + 1

def is_bread(kind : TileKind) : bool
    return int(kind) >= int(TileKind BREAD_1) && int(kind) <= int(TileKind BREAD_6)

def is_big_item(kind : TileKind) : bool
    if kind == TileKind WOOD || kind == TileKind FLINT_STONE || kind == TileKind BUCKET_WITH_WATER || kind == TileKind BUCKET_EMPTY || is_collected_wheat(kind) || kind == TileKind COAL || is_flag(kind)
        return true
    if kind == TileKind BED || kind == TileKind SHEEP_SHEARS || kind == TileKind WOOL || kind == TileKind STOVE || kind == TileKind STOVE_WITH_COAL || kind == TileKind STONE || kind == TileKind FLOUR
        return true
    if is_bread(kind)
        return true
    return false

def is_pickable(kind : TileKind) : bool
    if kind == TileKind WOOD || kind == TileKind FLINT_STONE || kind == TileKind BUCKET_WITH_WATER || kind == TileKind BUCKET_EMPTY || is_collected_wheat(kind) || kind == TileKind COAL || is_flag(kind)
        return true
    if kind == TileKind BED || kind == TileKind SHEEP_SHEARS || kind == TileKind WOOL || kind == TileKind STOVE || kind == TileKind STOVE_WITH_COAL || kind == TileKind STONE || kind == TileKind FLOUR
        return true
    if is_bread(kind)
        return true
    return false
var prev_horse : AiCharacter?
var prev_leashed : AiCharacter?

def is_on_horse(character : Character):bool
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
    

def unmount_horse(var character : Character)
    var npc = new AiCharacter()
    npc.position = character.position
    npc.position.y += 0.1
    npc.target_position = npc.position
    npc.kind = TileKind HORSE
    npc.z = character.z
    npc.mirrorX = character.mirrorX
    npc.on_leash = true
    //WARN player only stuff
    npc.follow_player_on_leash = false
    //WARN player only stuff
    prev_horse = npc
    
    character.kind = TileKind HUMAN

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

def _craft(var character : Character; _itemTile : Tile; exec : bool) : bool
    var itemTile = _itemTile
    var kind = itemTile.kind 
    var result = false

    var character_pos = character.position
    var groundTile = grid_ground->getTileInt(itemTile.position)
    var groundKind = groundTile.kind 

    if kind == TileKind WOOD && character.carry_item == TileKind FLINT_STONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind CAMPFIRE
            //character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind WOOD && character.carry_item == TileKind WOOL
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind BED
            character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind STONE && character.carry_item == TileKind STONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind STOVE
            character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind STOVE && (character.carry_item == TileKind COAL || character.carry_item == TileKind WOOD)
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind STOVE_WITH_COAL
            character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind STOVE_WITH_COAL && character.carry_item == TileKind FLINT_STONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind STOVE_WITH_COAL_FIRED
        result = true
    elif kind == TileKind STOVE_WITH_COAL_FIRED && character.carry_item == TileKind FLOUR
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            character.carry_item = TileKind BREAD_6
        result = true
    elif kind == TileKind WHEAT_COLLECTED_6 && character.carry_item == TileKind STONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind FLOUR
        result = true
    elif kind == TileKind CAMPFIRE && character.carry_item == TileKind BUCKET_WITH_WATER
        if exec
            play_sound(SoundKind DROP_WATER, character_pos)
            play_sound(SoundKind FIRE_PUT_OUT, character_pos)
            kind = TileKind COAL
            character.carry_item = TileKind BUCKET_EMPTY
        result = true
    elif kind == TileKind STOVE_WITH_COAL_FIRED && character.carry_item == TileKind BUCKET_WITH_WATER
        if exec
            play_sound(SoundKind DROP_WATER, character_pos)
            play_sound(SoundKind FIRE_PUT_OUT, character_pos)
            kind = TileKind STOVE_WITH_COAL
            character.carry_item = TileKind BUCKET_EMPTY
        result = true
    elif groundKind == TileKind WATER && character.carry_item == TileKind BUCKET_EMPTY
        if exec
            play_sound(SoundKind PICK_WATER, character_pos)
            character.carry_item = TileKind BUCKET_WITH_WATER
        result = true
    elif kind == TileKind NONE && groundKind == TileKind WATER && character.carry_item == TileKind WOOD
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
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
                play_sound(get_pick_sound(kind), character_pos)
                character.carry_item = sum
                kind = reminder
    elif is_collected_wheat(character.carry_item) && is_ground_prepared1(itemTile.position) && is_ground_prepared2(itemTile.position) && itemTile.kind == TileKind NONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            character.carry_item = get_wheat_from_count(get_wheat_count(character.carry_item) - 1)
            kind = TileKind PLANTED_SEEDS
        result = true
    elif kind == TileKind WHEAT_FULL && character.carry_item == TileKind NONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind WHEAT_COLLECTED_2
            unprepare_ground_for_seeds2(itemTile.position)
        result = true
    elif kind == TileKind WOOD && character.carry_item == TileKind WOOD
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind FENCE
            character.carry_item = TileKind NONE
        result = true
    elif kind == TileKind BUSH_WITH_BERRIES && character.carry_item == TileKind NONE
        if exec
            play_sound(SoundKind EAT_APPLE, character_pos)
            kind = TileKind BUSH
            character.hunger = max(0.0, character.hunger - 1.0)
            itemTile.anim.kind = AnimKind GROWING_BERRIES
            itemTile.anim.t = 0.0
            itemTile.anim.stopT = seconds_per_gameday
        result = true
    elif kind == TileKind BUSH && character.carry_item == TileKind NONE
        if exec
            play_sound(SoundKind GENERIC_ACTION, character_pos)
            kind = TileKind NONE
            itemTile.anim.kind = AnimKind NONE
        result = true
    elif kind == TileKind FENCE && character.carry_item == TileKind NONE
        if exec
            play_sound(get_pick_sound(TileKind FENCE), character_pos)
            kind = TileKind NONE
            character.carry_item = TileKind FENCE
        result = true
    if result && exec
        var tile = itemTile
        tile.kind = kind
        grid_items->setTile(tile)

        if groundTile.kind != groundKind
            groundTile.kind = groundKind
        grid_ground->setTile(groundTile)
    
    return result

def can_combine(a : TileKind; b : TileKind) : bool
    unsafe
        var character : Character
        character.carry_item = a
        var tile : Tile
        tile.kind = b
        return can_craft(character, tile)

def can_craft(var character : Character; itemTile : Tile) : bool
    return _craft(character, itemTile, false)

def craft(var character : Character; itemTile : Tile)
    _craft(character, itemTile, true)

def do_alt_action(var character : Character; at_pos : int2) : AltActionResult
    return _alt_action(character, at_pos, true)

def can_do_alt_action(var character : Character; at_pos : int2) : bool
    let result = _alt_action(character, at_pos, false)
    return result.is_valid

let invalid_tile_pos = int2(-9999,-9999)

def clear_alt_action_highlight()
    if highlightedAltActionNpc != null
        set_highlighted(highlightedAltActionNpc, false)
        highlightedAltActionNpc = null

    if highlightedAltActionTilePos != invalid_tile_pos
        set_highlighted(highlightedAltActionTilePos, false)
        highlightedAltActionTilePos = invalid_tile_pos

def draw_alt_action_highlight()
    let result = _alt_action(*player, invalid_tile_pos, false)
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

    if highlightedAltActionTilePos != invalid_tile_pos
        set_highlighted(highlightedAltActionTilePos, false)
        highlightedAltActionTilePos = invalid_tile_pos

    var result = _alt_action(*player, invalid_tile_pos ,false)
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

def can_make_dialog(character : AiCharacter?) : bool
    return is_human(character.kind)

def make_dialog(character : AiCharacter?)
    if current_dialog != null
        assert(false)
        return

    current_dialog = new DialogState()
    current_dialog.character = character
    current_dialog.character.on_leash = true

def get_bread_from_count(count : int) : TileKind
    if count == 0
        return TileKind NONE
    if count == 1
        return TileKind BREAD_1
    if count == 2
        return TileKind BREAD_2
    if count == 3
        return TileKind BREAD_3
    if count == 4
        return TileKind BREAD_4
    if count == 5
        return TileKind BREAD_5
    if count == 6
        return TileKind BREAD_6
    assert(false)
    return TileKind NONE

def _alt_action(var character : Character; _at_pos : int2; exec : bool) : AltActionResult
    var at_pos = _at_pos
    var pos_only = at_pos != invalid_tile_pos
    if at_pos == invalid_tile_pos
        at_pos = grid_items->getIntPos(character.position)

    var result : AltActionResult
    if is_dead(character)
        return result
    if is_on_horse(character)
        result.is_valid = true
        if exec
            unmount_horse(character)
        return result
    
    //WARN changing player only static vars 
    if !pos_only && prev_leashed != null
        result.is_valid = true
        if exec
            unleash(prev_leashed)
            prev_leashed = null
        return result

    
    var npc = get_nearest_npc(character.position)

    //WARN doing player only stuff 
    if !pos_only && npc != null
        if npc.kind == TileKind HORSE
            result.is_valid = true
            result.target_char = npc
            if exec
                mount_horse(npc)
            return result
        elif npc.kind == TileKind SHEEP || npc.kind == TileKind SHEEP_SHEARED
            result.target_char = npc
            result.is_valid = true

            var is_shearing = character.carry_item == TileKind SHEEP_SHEARS && npc.kind == TileKind SHEEP
            var shearing_wool_pos = invalid_tile_pos
            if is_shearing
                shearing_wool_pos = find_nearest_empty_pos(get_int_pos(character.position))
                result.is_valid = shearing_wool_pos != invalid_tile_pos

            if exec && result.is_valid
                if is_shearing
                    play_sound(SoundKind GENERIC_ACTION, npc.position)//TODO something else
                    npc.kind = TileKind SHEEP_SHEARED
                    var tile = grid_items->getTileInt(shearing_wool_pos)
                    assert(tile.kind == TileKind NONE)
                    tile.kind = TileKind WOOL
                    npc.saved_float = world_state.day_float
                    grid_items->setTile(tile)
                else
                    leash_to_player(npc)
            return result
        elif can_make_dialog(npc)
            result.target_char = npc
            result.is_valid = true
            if exec
                make_dialog(npc)
            return result


    var item = grid_items->getTile(character.position)
    if can_craft(character, item)
        result.is_valid = true
        result.target_item_pos = item.position
        result.has_target_item_pos = true
        if exec
            craft(character, item)
        return result


    //old action begin
    if is_on_horse(character) || is_dead(character)
        return result
    var groundTile = grid_ground->getTile(character.position)
    result.has_target_item_pos = true
    result.target_item_pos = groundTile.position

    if character.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE && groundTile.kind != TileKind WATER
        if !on_empty_tile
            return result
        if exec
            drop_carry_item(character, groundTile.position)
        result.is_valid = true
        return result

    if item.kind == TileKind BED && is_sleep_action_on_bed()
        if exec
            item.kind = TileKind BED_OCCUPIED
            set_character_animation(character, AnimKind SLEEP_IN_BED)
            character.position = float2(item.position) - float2(0.0, 0.001)
            grid_items->setTile(item)
        result.is_valid = true
        return result
    elif is_bread(item.kind) && character.hunger > 1.0 / 3.0
        if exec
            item.kind = get_bread_from_count(get_bread_count(item.kind)-1)
            play_sound(SoundKind EAT_APPLE, character.position)//TODO different sound
            grid_items->setTile(item)
            character.hunger -= 1.0 / 3.0
        result.is_valid = true
        return result

    if is_pickable(item.kind)
        if exec
            pick(character, item)
        result.is_valid = true
        return result
    elif character.carry_item != TileKind NONE
        var on_empty_tile = item.kind == TileKind NONE
        if !on_empty_tile
            return result
        if exec
            drop_carry_item(character, grid_items->getTile(character.position).position)
        result.is_valid = true
        return result
    if item.kind == TileKind CHEST_IRON
        if exec
            open_chest(item)
        result.is_valid = true
        return result
    elif item.kind == TileKind NONE
        if is_ground_prepared1(item.position) && is_ground_prepared2(item.position)
            if is_collected_wheat(character.carry_item)
                if exec
                    play_sound(SoundKind GENERIC_ACTION, item.position)
                    plant_seeds(item.position)
                result.is_valid = true
                return result
        else
            if is_ground_prepared1(item.position)
                if exec
                    play_sound(SoundKind GENERIC_ACTION, item.position)
                    prepare_ground_for_seeds2(item.position)
                result.is_valid = true
                return result
            elif can_prepare_ground_for_seeds1(item.position)
                if exec
                    play_sound(SoundKind GENERIC_ACTION, item.position)
                    prepare_ground_for_seeds1(item.position)
                result.is_valid = true
                return result
    elif int(item.kind) >= int(TileKind TREE_GREEN) && int(item.kind) <= int(TileKind TREE_RED)
        if exec
            cut_tree(item)
        result.is_valid = true
        return result
    //old action end

    return result

def update_env(dt : float)
    world_state.day_float += dt * gamedays_per_hour / seconds_per_hour
    var day_percent = get_current_hour_float() / 24.0

    var day_percent_radians = (day_percent + 4.0 / 24.0) * PI * 2.0

    night_percent = 0.4 + sin(day_percent_radians) * 0.6

    var is_rainy = sin(world_state.day_float) > 0.7
    rain_percent = lerp(rain_percent, is_rainy ? 1.0 : 0.0, dt)

def set_character_animation(var ch : Character; anim : AnimKind)
    if ch.anim.kind != anim
        handle_anim_finished(ch)
    ch.anim.kind = anim
    ch.anim.t = 0.0
    ch.anim.stopT = 0.5

def handle_anim_finished(var ch : Character)
    if ch.anim.kind == AnimKind DEATH
        ch.anim.t = ch.anim.stopT//hacky
        return
    if ch.anim.kind == AnimKind SLEEP_IN_BED
        var item = grid_items->getTile(ch.position)
        if item.kind == TileKind BED_OCCUPIED
            item.kind = TileKind BED
        else
            assert(false)
        grid_items->setTile(item)
        ch.position = float2(item.position) + float2(0.0, -0.3)
        
    ch.anim.kind = AnimKind NONE

def handle_anim_finished(var tile : Tile&)
    if tile.anim.kind == AnimKind TREE_FALL
        tile.kind = TileKind WOOD
        play_sound(SoundKind TREE_FALL_END, tile.position)
    elif tile.anim.kind == AnimKind PICK
        tile.kind = TileKind NONE
    elif tile.anim.kind == AnimKind GROWING_BERRIES
        if tile.kind == TileKind BUSH
            tile.kind = TileKind BUSH_WITH_BERRIES
        else
            assert(false)
    tile.anim.kind = AnimKind NONE


def get_nearest_walkable(pos : float2; is_human : bool) : int2
    var minDist = 10.0
    var posInt = grid_ground->getIntPos(pos)
    var bestPos = posInt
    for dx in range(-1, 2)
        for dy in range(-1, 2)
            if is_walkable_for_a_star(posInt + int2(dx,dy), is_human)
                var dist = length(pos - float2(posInt + int2(dx,dy)))
                if dist < minDist
                    bestPos = posInt + int2(dx,dy)
                    minDist = dist
    return bestPos

def random_wander_pos(char_pos : float2) : float2
    let diameter = 10.0
    return float2(clamp((random_float(seed) - 0.5) * diameter + char_pos.x, 0.0, float(map_size.x-1)), clamp((random_float(seed) - 0.5) * diameter + char_pos.y, 0.0, float(map_size.y-1)))

def get_int_pos(pos : float2) : int2
    return grid_items->getIntPos(pos)

[export]
def act(_dt: float)
    var is_rapid_timescale = false
    if player.anim.kind == AnimKind SLEEP || player.anim.kind == AnimKind SLEEP_IN_BED
        var is_anyone_awake = false
        for ch in characters
            if ch.anim.kind != AnimKind SLEEP && ch.anim.kind != AnimKind SLEEP_IN_BED && ch.anim.kind != AnimKind DEATH
                is_anyone_awake = true
                break

        if is_anyone_awake
            time_scale = max(dbg_time_scale, player_sleep_time_scale)
        else
            time_scale = max(dbg_time_scale, player_sleep_time_scale_when_everyone_sleeps)
            is_rapid_timescale = true
    else
        time_scale = dbg_time_scale


    var dt = min(_dt, 0.03333333) * time_scale
    if !is_rapid_timescale
        dt = min(dt, 0.15)
    if dbg_mode
        set_window_title("wasisdasbox {int(1.0/_dt)}fps, dt={dt}")
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    //log("time_scale={time_scale}; dt = {dt}")

    update_env(dt)

    var player_can_move = true

    player.velocity = float2(0.0)
    if current_dialog != null
        if update_dialog(current_dialog)
            if current_dialog.finished
                var command = ai_command_from_dialog(*current_dialog)
                current_dialog.character.command = command
            current_dialog.character.on_leash = false

            current_dialog = null
        player_can_move = false

    if !is_dead(*player)
        if player_can_move && is_player_must_sleep_time() || (player.anim.kind == AnimKind SLEEP || player.anim.kind == AnimKind SLEEP_IN_BED) && is_sleep_action_on_bed()
            //TODO some message
            player_can_move = false
            if player.anim.kind == AnimKind SLEEP_IN_BED
                set_character_animation(*player, AnimKind SLEEP_IN_BED)
            else
                set_character_animation(*player, AnimKind SLEEP)
            player.velocity = float2(0.0,0.0)
        else
            set_character_animation(*player, AnimKind NONE)

        

    if player_can_move
        if get_key(VK_W)
            player.velocity.y += 1.0
        if get_key(VK_S)
            player.velocity.y -= 1.0
        if get_key(VK_D)
            player.velocity.x += 1.0
        if get_key(VK_A)
            player.velocity.x -= 1.0

        if get_key_down(VK_SPACE)
            if can_do_alt_action(*player, invalid_tile_pos)
                do_alt_action(*player, invalid_tile_pos)

                
    //TODO if dbg
    if dbg_mode
        if get_key_down(VK_HOME)
            dbg_time_scale = min(10.0, dbg_time_scale + 1.0)
            log("dbg_time_scale = {dbg_time_scale}")
        elif get_key_down(VK_END)
            dbg_time_scale = max(1.0, dbg_time_scale - 1.0)
            log("dbg_time_scale = {dbg_time_scale}")

    if get_key_down(VK_F6)
        save()
    if get_key_down(VK_F7)
        load()
    if get_key_down(VK_F8) && dbg_mode
        heap_report()

    player.velocity = clampLength(player.velocity, 1.0) * GetMaxSpeed(*player)
    if get_key(VK_LSHIFT) && dbg_mode
        //todo less running on horse + some penalty
        player.velocity *= 2.5
        player.isRunning = true
    else
        player.isRunning = false

    for ch in characters
        if ch.health == 0.0
            die(*ch)
            continue

        if ch.anim.kind == AnimKind SLEEP || ch.anim.kind == AnimKind SLEEP_IN_BED
            ch.anim.t = 0.0
            ch.speed = 0.0
            ch.velocity = float2(0.0,0.0)
            continue

        if ch.kind == TileKind SHEEP_SHEARED
            if world_state.day_float > ch.saved_float + gamedays_to_grow_wool
                ch.kind = TileKind SHEEP

        if ch.next_footstep_time < 0.0
            play_sound(SoundKind FOOTSTEP, ch.position)
            ch.next_footstep_time = 1.0
        ch.next_footstep_time -= dt * ch.speed * 1.0

        var hunger_speed = hunger_per_hour * hours_per_second
        if ch.isRunning && !is_on_horse(*ch)
            hunger_speed *= 2.0
        ch.hunger = min(1.0, ch.hunger + dt * hunger_speed)

        if ch.hunger == 1.0
            ch.health = max(0.0, ch.health - dt * health_loss_from_hunger_per_hour * hours_per_second)
        else
            ch.health = min(1.0, ch.health + dt * health_gain_from_no_hunger_per_hour * hours_per_second)

        if !is_rapid_timescale
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


    camera.position = lerp(camera.position, player.position, saturate(dt * 3.0)) 
    camera->updateOffsetAndScale()

    for ch in characters
        if ch.anim.kind == AnimKind NONE
            continue
        ch.anim.t += dt
        if ch.anim.t >= ch.anim.stopT && !is_rapid_timescale
            handle_anim_finished(*ch)

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
            
    for ch in aiCharacters
        ch->Think(dt)


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
    elif kind == TileKind STONE
        x = 7
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
    elif is_flag(kind)
        x = 16
        y = 6
    elif kind == TileKind BED || kind == TileKind BED_OCCUPIED
        x = 17
        y = 6
    elif kind == TileKind SHEEP_SHEARS
        x = 18
        y = 6
    elif kind == TileKind SHEEP_SHEARED
        x = 16
        y = 5
    elif kind == TileKind WOOL
        x = 17
        y = 5
    elif kind == TileKind STOVE
        x = 0
        y = 7
    elif kind == TileKind STOVE_WITH_COAL
        x = 1
        y = 7
    elif kind == TileKind STOVE_WITH_COAL_FIRED
        x = 2
        y = 7
    elif kind == TileKind FLOUR
        x = 3
        y = 7
    elif is_bread(kind)
        x = 4
        y = 7

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
        if deltaPos.x == 0.0
            deltaPos.x = 0.01
        if deltaPos.y == 0.0
            deltaPos.y = 0.01

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
    elif tile.kind == TileKind CHEST_IRON || tile.kind == TileKind WOOD || tile.kind == TileKind CAMPFIRE || tile.kind == TileKind WHEAT_COLLECTED_6 || tile.kind == TileKind STOVE || tile.kind == TileKind STOVE_WITH_COAL || tile.kind == TileKind STOVE_WITH_COAL_FIRED || tile.kind == TileKind FLOUR
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
    elif tile.kind == TileKind BED || tile.kind == TileKind BED_OCCUPIED
        processCollisionCircle(deltaPos, 0.45)
    elif tile.kind == TileKind WOOL || is_bread(tile.kind)
        processCollisionCircle(deltaPos, 0.3)
    
    charPos = float2(tile.position) + deltaPos

def apply_anim(anim : Anim; var pos : float2&; var size : float2&; var angle : float&; var mirrorX : bool&)
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
    elif anim.kind == AnimKind SLEEP || anim.kind == AnimKind SLEEP_IN_BED
        angle = PI / 2.0
        var offset = get_realtime_since_world_started() % 1.0
        var z_count = 3
        if anim.kind == AnimKind SLEEP_IN_BED
            pos += float2(0.2, 0.4)
            mirrorX = true
        for i in range(z_count)
            var p = pos + float2(float(i)+offset,(float(i)+offset)*0.5) * 0.2 + float2(0.2, 0.0)
            p.y += sin((float(i)+offset) * 4.0) * 0.03
            if mirrorX
                p.x -= 0.5
            else
                p.x += 0.5
            var clip_space_pos = camera->worldToScreen(p)
            var t = (float(i)+offset) / float(z_count)
            var text_color = lerp_colors_fix(0xffffffff, 0x00ffffff, t)
            text_color = lerp_colors_fix(0x00ffffff, text_color, t*10.0)
            text_out(clip_space_pos.x,clip_space_pos.y, "z", text_color)

def calc_light(pos : float2) : float
    var light = 1.0 - night_percent * 0.4 - rain_percent * 0.2
    var intpos = int2(roundi(pos.x), roundi(pos.y))
    for dx in range(-2, +3)
        for dy in range(-2, +3)
            if grid_items->getTileInt(int2(intpos.x + dx,intpos.y + dy)).kind == TileKind CAMPFIRE
                light += 0.4 / (float(dx*dx + dy*dy) + 1.0) * (0.9 + sin(get_time_after_start()*7.0+float(intpos.x + dx)) * 0.05 + sin(get_time_after_start()*6.0 + float(intpos.y + dy)) * 0.05)
    
    for dx in range(-1, +2)
        for dy in range(0, +2)
            if grid_items->getTileInt(int2(intpos.x + dx,intpos.y + dy)).kind == TileKind STOVE_WITH_COAL_FIRED
                light += 0.2 / (float(dx*dx + dy*dy) + 1.0) * (0.9 + sin(get_time_after_start()*7.0+float(intpos.x + dx)) * 0.05 + sin(get_time_after_start()*6.0 + float(intpos.y + dy)) * 0.05)
     
    return min(1.0, light)

def get_pivot(kind : TileKind) : float2
    if kind == TileKind TREE_GREEN || kind == TileKind TREE_YELLOW || kind == TileKind TREE_RED
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN || kind == TileKind CHILD_A || kind == TileKind CHILD_B
        return float2(0.5,1.0)
    elif kind == TileKind HUMAN_ON_HORSE ||  kind == TileKind HORSE || kind == TileKind SHEEP || kind == TileKind SHEEP_SHEARED
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

def is_walkable_for_a_star(pos : int2; is_human : bool) : bool
    if grid_ground->getTileInt(pos).kind == TileKind WATER
        return false
    var item = grid_items->getTileInt(pos).kind
    if item == TileKind FENCE
        return false
    if !is_human && grid_items->getTileInt(pos + int2(-1, 0)).kind == TileKind FENCE && grid_items->getTileInt(pos + int2(1, 0)).kind == TileKind FENCE
        return false
    if !is_human && grid_items->getTileInt(pos + int2(0, -1)).kind == TileKind FENCE && grid_items->getTileInt(pos + int2(0, 1)).kind == TileKind FENCE
        return false

    return true

def a_star(from : int2; to : int2; is_human : bool) : array<int2>
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
            if key_exists(r, posWithDist.pos) && r[posWithDist.pos] <= posWithDist.dist || !is_walkable_for_a_star(posWithDist.pos, is_human)
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

def is_flag(kind : TileKind) : bool
    return int(kind) >= int(TileKind RED_FLAG) && int(kind) <= int(TileKind BLUE_FLAG)

def draw_tile(tile : TileFloat)
    var pos = tile.position
    pos.y += tile.z * tileZToY + tile.offsetY
    var kind = tile.kind
    var color = tile.color
    var pivot = get_pivot(kind)

    var angle = 0.0
    var size = float2(1.0,1.0)
    var mirrorX = tile.mirrorX
    apply_anim(tile.anim, pos, size, angle, mirrorX)
    
    if is_flag(kind)
        if kind == TileKind RED_FLAG
            color = 0xffff0000
        elif kind == TileKind GREEN_FLAG
            color = 0xff00ff00
        elif kind == TileKind BLUE_FLAG
            color = 0xff0000ff
        else
            assert(false)

    if kind == TileKind CAMPFIRE
        let mult = 1.5
        let t = (get_realtime_since_world_started() + (pos.x*3.156345 + pos.y*4.842756))*mult
        let f = frac(t)
        mirrorX = frac(t*0.5) > 0.5
        if f > 0.333
            kind = TileKind CAMPFIRE_2
        if f > 0.666
            kind = TileKind CAMPFIRE_3
    elif kind == TileKind STOVE_WITH_COAL_FIRED
        let mult = 1.5
        let t = (get_realtime_since_world_started() + (pos.x*3.156345 + pos.y*4.842756))*mult
        let f = frac(t)
        mirrorX = frac(t*0.5) > 0.5
    else
        color = lerp_colors_fix(0xff000000, color, calc_light(tile.position))//TODO smooth tile.pos for character
    
    if kind == TileKind WATER
        pos.y -= tile.z * tileZToY + 0.2
        let mult = 1.0
        let t = (get_realtime_since_world_started())*mult
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
    elif kind == TileKind BED || kind == TileKind BED_OCCUPIED
        pos.y -= 1.0 / 7.0

    var offset_from_pivot = float2((0.5 - pivot.x), (0.5 - pivot.y) * tileSizeY / tileFloorSizeY)
    if !mirrorX
        offset_from_pivot.x = -offset_from_pivot.x

    var clip_space_pos = camera->worldToScreen(pos + offset_from_pivot)
    if is_collected_wheat(kind)
        text_out(clip_space_pos.x+20.0,clip_space_pos.y + 20.0, "{get_wheat_count(kind)}", color)

    draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, color, size, angle, pivot.x, pivot.y)

    if is_bread(kind)
        for i in range(get_bread_count(kind)-1)
            clip_space_pos = camera->worldToScreen(pos + offset_from_pivot + float2(0.0, float(i+1)*2.0 / 7.0))
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

def is_dead(character : Character) : bool
    return character.anim.kind == AnimKind DEATH

def draw_character(character : Character?)
    var tile = TileFloat()
    
    var runningOffset = min(character.speed, 1.0) * 0.1 * abs(sin(10.0 * get_realtime_since_world_started() * (character.isRunning ? 2.0 : 1.0)))
    if is_dead(*character)
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

    if character.is_name_known
        var name_pos = character.position
        name_pos += float2(0.0, 0.0)
        var clip_space_pos = camera->worldToScreen(name_pos)
        var pp = player.position
        var cp = character.position
        var distance_from_player = length(pp - cp)
        var color = lerp_colors_fix(0xffffffff, 0x00ffffff, (distance_from_player - 5.0) / 4.0)
        text_out(clip_space_pos.x,clip_space_pos.y, "{character.name}", color)

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
        var isBlinking = player.isRunning && !is_on_horse(*player) && ((time * blinkFreq) - float(floori(time * blinkFreq))) > 0.5
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
        //clear(dbg_msg)
        //log(npc.dbg_str)

    //health
    color = 0xffffffff

    var y = int(30.0 * ui_scale)
    for kind, count in keys(player.items),values(player.items)
        text_out(10,y, "{kind} {count}", 0xffffffff)
        y += 20

    var hour_float = get_current_hour_float()
    var hour = int(hour_float)
    var minute_delta = 15
    var minute = int((hour_float - float(hour)) * 60.0 / float(minute_delta)) * minute_delta
    var minute_str = "{minute}"
    if minute == 0
        minute_str = "00"
    var day = int(world_state.day_float)
    var time_str : string
    text_out(10,y, "{hour}:{minute_str} day {day}", 0xffffffff)
    y += 20

    var weather_state = ""
    if is_morning_time()
        weather_state = "morning"
    elif is_day_time()
        weather_state = "day"
    elif is_evening_time()
        weather_state = "evening"
    else
        verify(is_night_time())
        weather_state = "night"
    if rain_percent > 0.5
        weather_state += ", rainy"
    text_out(10,y, "{weather_state}", 0xffffffff)
    y += 20

    var population = 0
    for c in characters
        if is_human(c.kind)
            population += 1
    text_out(10,y, "population: {population}", 0xffffffff)
    y += 20

    if dbg_mode
        for i in range(length(dbg_msg))
            text_out(10,y, dbg_msg[length(dbg_msg) - i-1], 0xffffffff)
            y += 20

    if true
        var blinkFreq = 2.0
        var isBlinking = player.isRunning && !is_on_horse(*player) && ((time * blinkFreq) - float(floori(time * blinkFreq))) > 0.5
        if night_percent > 0.5
            texture_rect = get_tile_texture_rect(TileKind UI_NIGHT)
        else
            texture_rect = get_tile_texture_rect(TileKind UI_DAY)
        var clip_space_pos = float2(float(get_screen_width())/2.0, -ui_scale * 7.0)

        draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, 0xffffffff, size, 0.0, 0.5f,0.0f)

        if rain_percent > 0.5
            texture_rect = get_tile_texture_rect(TileKind UI_RAIN)
            draw_image_transformed(tiles, clip_space_pos.x,clip_space_pos.y, texture_rect, 0xffffffff, size, 0.0, 0.5f,0.0f)

    if current_dialog != null
        ui_draw_dialog(*current_dialog)


var current_dialog : DialogState?

enum DialogFirstAction
    NONE
    WHAT_ARE_YOU_DOING
    BRING
    MAKE
    CUT
    PLOW_GROUND
    PLANT

class DialogState
    character : AiCharacter?

    had_greeting : bool

    i_current_option : int = 1
    first_action : DialogFirstAction
    first_action_tile_kind : TileKind
    second_action_tile_kind : TileKind

    to_pressed : bool

    ui_message : string
    ui_options : array<string>
    ui_prev_options_offset : int

    finished : bool

def ai_command_to_str(command : AiCommand)
    //TODO more generic and less manual way
    if command.kind == AiCommandKind NONE
        return "NOTHING SPECIAL"
    elif command.kind == AiCommandKind BRING_A_TILE_TO_B_TILE
        if command.a_tile == TileKind FLINT_STONE && command.b_tile == TileKind WOOD
            return "I MAKE FIRE"
        elif command.a_tile == TileKind WOOD && command.b_tile == TileKind WOOD
            return "I MAKE FENCES"
        else
            return "I BRING {readable_tile_name(command.a_tile)} TO {readable_tile_name(command.b_tile)}"
    elif command.kind == AiCommandKind DO_DEFAULT_ACTION_ON_A_TILE
        if item_is(command.a_tile, TileKind TREE)
            return "I CUT TREES"
        elif item_is(command.a_tile, TileKind WHEAT)
            return "I CUT WHEAT"
        else
            return "I DO {command.a_tile}"
    elif command.kind == AiCommandKind MAKE_WHEAT_STACKS
        return "I MAKE WHEAT STACKS"
    elif command.kind == AiCommandKind PLOW_GROUND
        return "I PLOW GROUND"
    elif command.kind == AiCommandKind PLANT_WHEAT
        return "I PLANT WHEAT"

    assert(false)
    return "SOMETHING IMPORTANT"


def ai_command_from_dialog(dialog : DialogState) : AiCommand
    //TODO more generic and less manual way
    if dialog.first_action == DialogFirstAction BRING
        return ai_command_bring_a_to_b(dialog.first_action_tile_kind, dialog.second_action_tile_kind)
    elif dialog.first_action == DialogFirstAction CUT
        return ai_command_do_default_action_on_a(dialog.first_action_tile_kind)
    elif dialog.first_action == DialogFirstAction MAKE
        if dialog.first_action_tile_kind == TileKind CAMPFIRE
            return ai_command_bring_a_to_b(TileKind FLINT_STONE, TileKind WOOD)
        elif dialog.first_action_tile_kind == TileKind FENCE
            return ai_command_bring_a_to_b(TileKind WOOD, TileKind WOOD)
        elif dialog.first_action_tile_kind == TileKind WHEAT_STACK
            return ai_command_make_wheat_stacks()
    elif dialog.first_action == DialogFirstAction PLOW_GROUND
        return ai_command_plow_ground()
    elif dialog.first_action == DialogFirstAction PLANT
        return ai_command_plant_wheat()
        
            
    assert(false)
    var command : AiCommand
    return command

def readable_tile_name(kind : TileKind) : string
    var str = "{kind}"
    if kind == TileKind WHEAT_COLLECTED_6
        str = "WHEAT STACK"
    str = replace(str, "_", " ")
    return str;

//returns true if dialog finished
def update_dialog(var dialog_state : DialogState?) : bool
    clear(dialog_state.ui_options)
    dialog_state.ui_message = ""
    
    push(dialog_state.ui_options, "<BACK>")

    var bringable_items : array<TileKind>
    push(bringable_items, TileKind WHEAT_STACK)
    for e in each_enum(type<TileKind>)
        if is_big_item(e) && !is_collected_wheat(e) && !is_flag(e)
            push(bringable_items, e)

    var bringtoable_flags : array<TileKind>
    for e in each_enum(type<TileKind>)
        if is_flag(e)
            push(bringtoable_flags, e)
    
    var makeable_items : array<TileKind>
    push(makeable_items, TileKind CAMPFIRE)
    push(makeable_items, TileKind FENCE)
    push(makeable_items, TileKind WHEAT_STACK)

    var cutable_items : array<TileKind>
    push(cutable_items, TileKind TREE)
    push(cutable_items, TileKind WHEAT)

    var plantable_items : array<TileKind>
    push(plantable_items, TileKind WHEAT)

    var has_second = dialog_state.first_action == DialogFirstAction BRING
    var has_first = dialog_state.first_action != DialogFirstAction PLOW_GROUND && dialog_state.first_action != DialogFirstAction WHAT_ARE_YOU_DOING

    var first_tile_source_array : array<TileKind>
    if dialog_state.first_action == DialogFirstAction BRING
        first_tile_source_array <- bringable_items
    elif dialog_state.first_action == DialogFirstAction CUT
        first_tile_source_array <- cutable_items
    elif dialog_state.first_action == DialogFirstAction MAKE
        first_tile_source_array <- makeable_items
    elif dialog_state.first_action == DialogFirstAction PLOW_GROUND
        pass
    elif dialog_state.first_action == DialogFirstAction PLANT
        first_tile_source_array <- plantable_items
    
    if !dialog_state.had_greeting
        push(dialog_state.ui_options, "Hi, {dialog_state.character.name}")
    elif dialog_state.first_action == DialogFirstAction NONE
        for e in each_enum(type<DialogFirstAction>)
            if e == DialogFirstAction NONE
                continue
            push(dialog_state.ui_options, "{e}")
    elif dialog_state.first_action_tile_kind == TileKind NONE && has_first
        for e in first_tile_source_array
            push(dialog_state.ui_options, "{readable_tile_name(e)}")
    elif !dialog_state.to_pressed && has_second && has_first
        push(dialog_state.ui_options, "TO")
    elif dialog_state.second_action_tile_kind == TileKind NONE && has_second && has_first
        for e in each_enum(type<TileKind>)
            if can_combine(dialog_state.first_action_tile_kind, e)
                push(dialog_state.ui_options, "{readable_tile_name(e)}")
        for e in bringtoable_flags
            if e != dialog_state.first_action_tile_kind
                push(dialog_state.ui_options, "{readable_tile_name(e)}")
    else
        push(dialog_state.ui_options, "<DONE>")

    //elif dialog_state.first_action_tile_kind

    if dialog_state.first_action != DialogFirstAction NONE
        dialog_state.ui_message += "{dialog_state.first_action}"
    if dialog_state.first_action_tile_kind != TileKind NONE
        dialog_state.ui_message += " {dialog_state.first_action_tile_kind}"
    if dialog_state.to_pressed
        dialog_state.ui_message += " TO"
    if dialog_state.second_action_tile_kind != TileKind NONE
        dialog_state.ui_message += " {dialog_state.second_action_tile_kind}"

    if dialog_state.first_action == DialogFirstAction WHAT_ARE_YOU_DOING
        dialog_state.ui_message = ai_command_to_str(dialog_state.character.command)


    if dialog_state.ui_message == ""
        dialog_state.ui_message = "???"
    
    if get_key_down(VK_W)
        dialog_state.i_current_option -= 1
    if get_key_down(VK_S)
        dialog_state.i_current_option += 1
    dialog_state.i_current_option = clamp(dialog_state.i_current_option, 0, length(dialog_state.ui_options)-1)


    if get_key_down(VK_SPACE)
        if !dialog_state.had_greeting
            dialog_state.character.is_name_known = true
            if 0 == dialog_state.i_current_option
                return true
            else
                dialog_state.had_greeting = true
        elif dialog_state.first_action == DialogFirstAction NONE
            if 0 == dialog_state.i_current_option
                return true
            else
                var idx = 0
                for e in each_enum(type<DialogFirstAction>)
                    if dialog_state.i_current_option == idx
                        dialog_state.first_action = e
                        break
                    idx++
        elif dialog_state.first_action_tile_kind == TileKind NONE && has_first
            if 0 == dialog_state.i_current_option
                dialog_state.first_action = DialogFirstAction NONE
            else
                for i in range(length(first_tile_source_array))
                    if dialog_state.i_current_option == i + 1
                        dialog_state.first_action_tile_kind = first_tile_source_array[i]
                        break
        elif !dialog_state.to_pressed && has_second
            if 0 == dialog_state.i_current_option
                dialog_state.first_action_tile_kind = TileKind NONE
            else
                dialog_state.to_pressed = true
        elif dialog_state.second_action_tile_kind == TileKind NONE && has_second
            if 0 == dialog_state.i_current_option
                dialog_state.to_pressed = false
            else
                var idx = 1
                for e in each_enum(type<TileKind>)
                    if can_combine(dialog_state.first_action_tile_kind, e)
                        if dialog_state.i_current_option == idx
                            dialog_state.second_action_tile_kind = e
                        idx++
                for e in bringtoable_flags
                    if dialog_state.i_current_option == idx
                        dialog_state.second_action_tile_kind = e
                    idx++
        else
            if 0 == dialog_state.i_current_option
                dialog_state.second_action_tile_kind = TileKind NONE
                if !has_second
                    dialog_state.first_action_tile_kind = TileKind NONE
                if !has_first
                    dialog_state.first_action = DialogFirstAction NONE
            else
                dialog_state.finished = dialog_state.first_action != DialogFirstAction WHAT_ARE_YOU_DOING
                return true

        dialog_state.i_current_option = 1
        dialog_state.ui_prev_options_offset = 1

    return false

def ui_draw_dialog(var dialog_state : DialogState)
    var main_text_pos = int2(get_screen_width() / 2, get_screen_height() - 300)
    main_text_pos.x -= int(get_text_size(dialog_state.ui_message).x / 2.0)
    text_out(main_text_pos.x,main_text_pos.y, dialog_state.ui_message, 0xffffffff)
    
    var options_text_pos = int2(get_screen_width() / 2 - 100, get_screen_height() - 250)
    var max_options_visible = 5
    var y_offset = 30
    var i_first = max(dialog_state.i_current_option - 1, 0)
    var i_last = min(dialog_state.i_current_option + 1, length(dialog_state.ui_options) - 1)

    if i_last == length(dialog_state.ui_options) - 1 || dialog_state.ui_prev_options_offset + max_options_visible <= i_last
        i_first = max(0, i_last - max_options_visible + 1)
    elif i_first == 0 || dialog_state.ui_prev_options_offset >= i_first
        i_last = min(i_first + max_options_visible - 1, length(dialog_state.ui_options) - 1)
    else
        i_first = dialog_state.ui_prev_options_offset
        i_last = min(i_first + max_options_visible - 1, length(dialog_state.ui_options) - 1)

    dialog_state.ui_prev_options_offset = i_first

    for i in range(i_first, i_last + 1)
        var y = options_text_pos.y + y_offset * (i - i_first)
        var option = dialog_state.ui_options[i]
        if dialog_state.i_current_option == i
            option = "[*] " + option
        else
            option = "[ ] " + option
        text_out(options_text_pos.x,y, option, 0xffffffff)
    if i_first > 0
        text_out(options_text_pos.x,options_text_pos.y - y_offset, "    ▲", 0xffffffff)
    if i_last < length(dialog_state.ui_options) - 1
        text_out(options_text_pos.x,options_text_pos.y + y_offset * max_options_visible, "    ▼", 0xffffffff)
        

    pass

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

    if dbg_mode
        if dbg_pathfinding
            for ch in aiCharacters
                if length(ch.target_position - ch.position) > 1.0
                    var path : array<int2>
                    path <- a_star(grid_ground->getIntPos(ch.position), grid_ground->getIntPos(ch.target_position))
            var path <- a_star(get_int_pos(player.position), int2(grid_ground.width / 2, grid_ground.height / 2+5))
            for pos in path
                draw_tile_highlight(grid_ground->getTileInt(pos))

        for pos in dbg_highlighted_tiles
            draw_tile_highlight(grid_ground->getTileInt(pos))
    clear(dbg_highlighted_tiles)

    clear_alt_action_highlight()
    if can_do_alt_action(*player, invalid_tile_pos)
        draw_alt_action_highlight()

    sort(drawTilesQueue, $(a,b)=>a.priority==b.priority && a.tile.position.y>b.tile.position.y || a.priority>b.priority)

    for tile in drawTilesQueue
        draw_tile(tile.tile)

    if draw_grid
        draw_grid(0x08ffffff)

    

    draw_ui()
