require math

options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

enum TileKind
    NONE
    GRASS
    SOIL
    HUMAN
    CHILD_A
    CHILD_B
    TREE_GREEN
    TREE_YELLOW
    TREE_RED
    CHEST_IRON
    TILE_SELECTION
    FENCE_H
    FENCE_V
    DECAL_SMALL
    DECAL_BIG
    HEART_FULL
    HEART_HALF
    HEART_EMPTY
    HUNGER_FULL
    HUNGER_HALF
    HUNGER_EMPTY
    PLANTED_SEEDS

struct Tile
    position: int2
    z : float
    color : uint = 0xffffffff
    kind : TileKind

class Grid
    width : int
    height : int
    tiles : array<Tile>

    def getIdx_int(pos : int2) : int
        var idx = pos.x * height + pos.y
        if idx >= length(self.tiles) || idx < 0
            return -1
        return idx

    def getIdx(pos : float2) : int
        return getIdx_int(int2(roundi(pos.x), roundi(pos.y)))


    def setTile(tile : Tile)
        var idx = getIdx_int(tile.position)
        if idx != -1
            self.tiles[idx] = tile

    def getTile(pos : float2) : Tile
        var idx = getIdx(pos)
        if idx == -1
            var fakeTile : Tile
            fakeTile.position.x = roundi(pos.x)
            fakeTile.position.y = roundi(pos.y)
            return fakeTile
        else
            return self.tiles[idx]

    def getHeight(pos : float2) : float
        var idx = getIdx(pos)
        if idx != -1
            return self.tiles[idx].z
        else
            return 0.0
