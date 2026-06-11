Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutDir = Join-Path $Root "artifacts\road_region_previews"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$RegionsDoc = Get-Content (Join-Path $Root "data\road_regions.json") -Raw | ConvertFrom-Json
$TileRows = Import-Csv (Join-Path $Root "data\tile_properties.csv")
$TileById = @{}
foreach ($row in $TileRows) { $TileById[$row.id] = $row }

$Shots = @(
    @{ identity = "dense_city"; region = "capital_port" },
    @{ identity = "dense_city"; region = "stoneshore" },
    @{ identity = "sparse_city"; region = "southlake" },
    @{ identity = "sparse_city"; region = "klade_estuary" },
    @{ identity = "dense_rural"; region = "holyfinger" },
    @{ identity = "dense_rural"; region = "green_flats"; suffix = "proxy" },
    @{ identity = "sparse_rural"; region = "knot_valley" },
    @{ identity = "sparse_rural"; region = "peatsfield" },
    @{ identity = "mountain_range"; region = "blue_mountains" },
    @{ identity = "mountain_range"; region = "shoulderland" }
)

$SavedPaths = @()

$TerrainRoutesPath = Join-Path $OutDir "terrain_routes.json"
$TerrainRoutesByKey = @{}
if (Test-Path $TerrainRoutesPath) {
    $TerrainRoutesDoc = Get-Content $TerrainRoutesPath -Raw | ConvertFrom-Json
    foreach ($routeShot in $TerrainRoutesDoc.shots) {
        $suffix = if ($null -ne $routeShot.suffix) { [string]$routeShot.suffix } else { "" }
        $TerrainRoutesByKey["$($routeShot.identity)|$($routeShot.region)|$suffix"] = $routeShot
    }
}

$TerrainColors = @{
    rural = [System.Drawing.Color]::FromArgb(255, 196, 211, 143)
    urban = [System.Drawing.Color]::FromArgb(255, 198, 155, 113)
    hill = [System.Drawing.Color]::FromArgb(255, 165, 184, 115)
    mountain = [System.Drawing.Color]::FromArgb(255, 145, 119, 94)
    sea = [System.Drawing.Color]::FromArgb(255, 104, 151, 178)
    deep_sea = [System.Drawing.Color]::FromArgb(255, 47, 84, 120)
}
$HighlightColors = @{
    dense_city = [System.Drawing.Color]::FromArgb(72, 236, 91, 44)
    sparse_city = [System.Drawing.Color]::FromArgb(72, 235, 169, 46)
    dense_rural = [System.Drawing.Color]::FromArgb(70, 77, 166, 81)
    sparse_rural = [System.Drawing.Color]::FromArgb(64, 121, 176, 69)
    mountain_range = [System.Drawing.Color]::FromArgb(78, 128, 103, 76)
}

$LakeTiles = @(
    "tile_5_15", "tile_4_16", "tile_3_16",
    "tile_20_13", "tile_20_14", "tile_20_15", "tile_21_16", "tile_21_15", "tile_22_14",
    "tile_25_15", "tile_23_13", "tile_23_12", "tile_21_11",
    "tile_21_6", "tile_21_4", "tile_23_3", "tile_22_2"
)

function Parse-TileId([string]$TileId) {
    $parts = $TileId -split "_"
    [PSCustomObject]@{
        Col = [int]$parts[1]
        Row = [int]$parts[2]
        Q = [int]$parts[1] - 1
        R = [int]$parts[2] - 1
    }
}

$TileByCoord = @{}
foreach ($row in $TileRows) {
    $coord = Parse-TileId $row.id
    $TileByCoord["$($coord.Q),$($coord.R)"] = $row
}

function Center-For([int]$Q, [int]$R) {
    # World space includes HexMap.MAP_PADDING (2,2): real centre = map_to_local(Q+2, R+2).
    # Q+2 keeps Q's parity, so the odd-column shift is unchanged and the padding is a
    # constant (+810, +960). Route points from the preview JSON are in padded world
    # space — without this the roads render offset by exactly two tiles.
    [PSCustomObject]@{
        X = ($Q * 405.0) + 270.0 + 810.0
        Y = ($R * 480.0) + ($(if (($Q % 2) -eq 1) { 240.0 } else { 0.0 })) + 240.0 + 960.0
    }
}

function Point([double]$X, [double]$Y) {
    [PSCustomObject]@{ X = $X; Y = $Y }
}

function Dist2($A, $B) {
    $dx = $A.X - $B.X
    $dy = $A.Y - $B.Y
    ($dx * $dx) + ($dy * $dy)
}

function Get-Hex($Center) {
    @(
        (Point ($Center.X - 135) ($Center.Y - 240)),
        (Point ($Center.X + 135) ($Center.Y - 240)),
        (Point ($Center.X + 270) ($Center.Y)),
        (Point ($Center.X + 135) ($Center.Y + 240)),
        (Point ($Center.X - 135) ($Center.Y + 240)),
        (Point ($Center.X - 270) ($Center.Y))
    )
}

function To-PointF($P, $Bounds, [double]$Scale) {
    [System.Drawing.PointF]::new(
        [single](40 + (($P.X - $Bounds.MinX) * $Scale)),
        [single](78 + (($P.Y - $Bounds.MinY) * $Scale))
    )
}

function Cross($O, $A, $B) {
    (($A.X - $O.X) * ($B.Y - $O.Y)) - (($A.Y - $O.Y) * ($B.X - $O.X))
}

function Convex-Hull($Points) {
    $sorted = @($Points | Sort-Object X, Y)
    if ($sorted.Count -le 1) { return $sorted }
    $lower = New-Object System.Collections.ArrayList
    foreach ($p in $sorted) {
        while ($lower.Count -ge 2 -and (Cross $lower[$lower.Count - 2] $lower[$lower.Count - 1] $p) -le 0) {
            $lower.RemoveAt($lower.Count - 1)
        }
        [void]$lower.Add($p)
    }
    $upper = New-Object System.Collections.ArrayList
    for ($i = $sorted.Count - 1; $i -ge 0; $i--) {
        $p = $sorted[$i]
        while ($upper.Count -ge 2 -and (Cross $upper[$upper.Count - 2] $upper[$upper.Count - 1] $p) -le 0) {
            $upper.RemoveAt($upper.Count - 1)
        }
        [void]$upper.Add($p)
    }
    $lower.RemoveAt($lower.Count - 1)
    $upper.RemoveAt($upper.Count - 1)
    @($lower + $upper)
}

function Centroid($Points) {
    $sx = 0.0; $sy = 0.0
    foreach ($p in $Points) { $sx += $p.X; $sy += $p.Y }
    Point ($sx / [Math]::Max(1, $Points.Count)) ($sy / [Math]::Max(1, $Points.Count))
}

function Nearest($Target, $Points) {
    $best = $Points[0]; $bestD = Dist2 $Target $best
    foreach ($p in $Points) {
        $d = Dist2 $Target $p
        if ($d -lt $bestD) { $best = $p; $bestD = $d }
    }
    $best
}

function Farthest-Pair($Points) {
    $best = @($Points[0], $Points[1]); $bestD = Dist2 $Points[0] $Points[1]
    for ($i = 0; $i -lt $Points.Count; $i++) {
        for ($j = $i + 1; $j -lt $Points.Count; $j++) {
            $d = Dist2 $Points[$i] $Points[$j]
            if ($d -gt $bestD) { $best = @($Points[$i], $Points[$j]); $bestD = $d }
        }
    }
    $best
}

function Curve($A, $B, [double]$Bend, [int]$Salt) {
    $dx = $B.X - $A.X; $dy = $B.Y - $A.Y
    $len = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
    if ($len -lt 1) { return @($A, $B) }
    $sign = $(if (($Salt % 2) -eq 0) { 1.0 } else { -1.0 })
    $nx = -$dy / $len; $ny = $dx / $len
    $mid = Point (($A.X + $B.X) / 2.0 + ($nx * $len * $Bend * $sign)) (($A.Y + $B.Y) / 2.0 + ($ny * $len * $Bend * $sign))
    @($A, $mid, $B)
}

function Project-ToSegment($P, $A, $B) {
    $abx = $B.X - $A.X; $aby = $B.Y - $A.Y
    $den = ($abx * $abx) + ($aby * $aby)
    if ($den -le 0.001) { return $A }
    $t = (($P.X - $A.X) * $abx + ($P.Y - $A.Y) * $aby) / $den
    $t = [Math]::Max(0.0, [Math]::Min(1.0, $t))
    Point ($A.X + $abx * $t) ($A.Y + $aby * $t)
}

function Edge($Path, [string]$Tier, [double]$Width) {
    [PSCustomObject]@{ Path = @($Path); Tier = $Tier; Width = $Width }
}

function Thin-Path($Path, [double]$MinDistance) {
    $pts = @($Path)
    if ($pts.Count -le 2) { return $pts }
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add($pts[0])
    for ($i = 1; $i -lt $pts.Count - 1; $i++) {
        if ([Math]::Sqrt((Dist2 $out[$out.Count - 1] $pts[$i])) -ge $MinDistance) {
            [void]$out.Add($pts[$i])
        }
    }
    if ((Dist2 $out[$out.Count - 1] $pts[$pts.Count - 1]) -gt 1.0) {
        [void]$out.Add($pts[$pts.Count - 1])
    }
    @($out)
}

function Smooth-Path($Path, [int]$Iterations) {
    $current = @($Path)
    for ($iter = 0; $iter -lt $Iterations; $iter++) {
        if ($current.Count -lt 3) { break }
        $next = New-Object System.Collections.ArrayList
        [void]$next.Add($current[0])
        for ($i = 0; $i -lt $current.Count - 1; $i++) {
            $a = $current[$i]
            $b = $current[$i + 1]
            [void]$next.Add((Point ($a.X + (($b.X - $a.X) * 0.25)) ($a.Y + (($b.Y - $a.Y) * 0.25))))
            [void]$next.Add((Point ($a.X + (($b.X - $a.X) * 0.75)) ($a.Y + (($b.Y - $a.Y) * 0.75))))
        }
        [void]$next.Add($current[$current.Count - 1])
        $current = @($next)
    }
    $current
}

function Shot-Key([string]$Identity, [string]$RegionId, [string]$Suffix) {
    "$Identity|$RegionId|$Suffix"
}

function Convert-TerrainEdges($RouteShot) {
    if ($null -eq $RouteShot) { return $null }
    $out = New-Object System.Collections.ArrayList
    foreach ($edge in $RouteShot.edges) {
        $path = New-Object System.Collections.ArrayList
        foreach ($p in $edge.path) {
            [void]$path.Add((Point ([double]$p[0]) ([double]$p[1])))
        }
        if ($path.Count -ge 2) {
            $displayPath = Smooth-Path (Thin-Path @($path) 54.0) 2
            [void]$out.Add((Edge @($displayPath) ([string]$edge.tier) ([double]$edge.width)))
        }
    }
    @($out)
}

function Coord-Key([int]$Q, [int]$R) {
    "$Q,$R"
}

function Is-WaterType([string]$Type) {
    $Type -eq "sea" -or $Type -eq "deep_sea"
}

function Is-WaterTile($Tile) {
    (Is-WaterType $Tile.Type) -or ($LakeTiles -contains $Tile.Id)
}

function Neighbor-Coords([int]$Q, [int]$R) {
    $odd = ($Q % 2) -eq 1
    @(
        [PSCustomObject]@{ Q = $Q; R = $R - 1 },
        [PSCustomObject]@{ Q = $Q + 1; R = $(if ($odd) { $R } else { $R - 1 }) },
        [PSCustomObject]@{ Q = $Q + 1; R = $(if ($odd) { $R + 1 } else { $R }) },
        [PSCustomObject]@{ Q = $Q; R = $R + 1 },
        [PSCustomObject]@{ Q = $Q - 1; R = $(if ($odd) { $R + 1 } else { $R }) },
        [PSCustomObject]@{ Q = $Q - 1; R = $(if ($odd) { $R } else { $R - 1 }) }
    )
}

function Is-CoastalNode($Node) {
    foreach ($n in (Neighbor-Coords $Node.Q $Node.R)) {
        $key = Coord-Key $n.Q $n.R
        if ($TileByCoord.ContainsKey($key) -and (Is-WaterType $TileByCoord[$key].type)) {
            return $true
        }
    }
    $false
}

function Nearest-LandNode($Point, $LandNodes) {
    $best = $LandNodes[0]
    $bestD = Dist2 $Point $best.Center
    foreach ($node in $LandNodes) {
        $d = Dist2 $Point $node.Center
        if ($d -lt $bestD) { $best = $node; $bestD = $d }
    }
    $best
}

function Route-LandPath($A, $B, $LandNodes, $LandByKey) {
    if ($LandNodes.Count -lt 2) { return @($A, $B) }
    $start = Nearest-LandNode $A $LandNodes
    $goal = Nearest-LandNode $B $LandNodes
    $startKey = Coord-Key $start.Q $start.R
    $goalKey = Coord-Key $goal.Q $goal.R
    if ($startKey -eq $goalKey) { return @($start.Center) }

    $dist = @{ $startKey = 0.0 }
    $prev = @{}
    $open = New-Object System.Collections.ArrayList
    [void]$open.Add($startKey)
    $closed = @{}

    while ($open.Count -gt 0) {
        $bestIndex = 0
        $bestScore = [double]::PositiveInfinity
        for ($i = 0; $i -lt $open.Count; $i++) {
            $key = [string]$open[$i]
            $node = $LandByKey[$key]
            $score = [double]$dist[$key] + ([Math]::Sqrt((Dist2 $node.Center $goal.Center)) * 0.35)
            if ($score -lt $bestScore) { $bestScore = $score; $bestIndex = $i }
        }
        $currentKey = [string]$open[$bestIndex]
        $open.RemoveAt($bestIndex)
        if ($closed.ContainsKey($currentKey)) { continue }
        $closed[$currentKey] = $true
        if ($currentKey -eq $goalKey) { break }

        $current = $LandByKey[$currentKey]
        foreach ($n in (Neighbor-Coords $current.Q $current.R)) {
            $neighborKey = Coord-Key $n.Q $n.R
            if (-not $LandByKey.ContainsKey($neighborKey)) { continue }
            if ($closed.ContainsKey($neighborKey)) { continue }
            $neighbor = $LandByKey[$neighborKey]
            $step = [Math]::Sqrt((Dist2 $current.Center $neighbor.Center))
            if ((Is-CoastalNode $current) -or (Is-CoastalNode $neighbor)) {
                $step *= 0.92
            }
            $candidate = [double]$dist[$currentKey] + $step
            if ((-not $dist.ContainsKey($neighborKey)) -or $candidate -lt [double]$dist[$neighborKey]) {
                $dist[$neighborKey] = $candidate
                $prev[$neighborKey] = $currentKey
                [void]$open.Add($neighborKey)
            }
        }
    }

    if (-not $prev.ContainsKey($goalKey)) {
        return @($start.Center, $goal.Center)
    }
    $keys = New-Object System.Collections.ArrayList
    $cursor = $goalKey
    [void]$keys.Add($cursor)
    while ($cursor -ne $startKey -and $prev.ContainsKey($cursor)) {
        $cursor = [string]$prev[$cursor]
        [void]$keys.Add($cursor)
    }
    $keys.Reverse()
    @($keys | ForEach-Object { $LandByKey[[string]$_].Center })
}

function Constrain-EdgesToLand($Edges, $ContextTiles) {
    $landNodes = @($ContextTiles | Where-Object { -not (Is-WaterTile $_) })
    if ($landNodes.Count -lt 2) { return $Edges }
    $landByKey = @{}
    foreach ($node in $landNodes) { $landByKey[(Coord-Key $node.Q $node.R)] = $node }
    $out = New-Object System.Collections.ArrayList
    foreach ($edge in $Edges) {
        $path = @($edge.Path)
        $routed = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $path.Count - 1; $i++) {
            $segment = @(Route-LandPath $path[$i] $path[$i + 1] $landNodes $landByKey)
            foreach ($p in $segment) {
                if ($routed.Count -eq 0 -or (Dist2 $routed[$routed.Count - 1] $p) -gt 1.0) {
                    [void]$routed.Add($p)
                }
            }
        }
        if ($routed.Count -ge 2) {
            [void]$out.Add((Edge @($routed) $edge.Tier $edge.Width))
        }
    }
    @($out)
}

function Generate-Edges($Members, [string]$Identity) {
    $points = @($Members | ForEach-Object { $_.Center })
    $urban = @($Members | Where-Object { $_.Type -eq "urban" } | ForEach-Object { $_.Center })
    $centroid = Centroid $points
    $edges = New-Object System.Collections.ArrayList

    if ($Identity -eq "dense_city") {
        $hexPts = @()
        foreach ($m in $Members) { $hexPts += Get-Hex $m.Center }
        $hull = Convex-Hull $hexPts
        $ring = @()
        foreach ($p in $hull) { $ring += Point ($centroid.X + (($p.X - $centroid.X) * 0.78)) ($centroid.Y + (($p.Y - $centroid.Y) * 0.78)) }
        if ($ring.Count -gt 2) { $ring += $ring[0]; [void]$edges.Add((Edge $ring "trunk" 8.0)) }
        $hubs = if ($urban.Count -ge 2) { $urban } else { @($points | Sort-Object { Dist2 $_ $centroid } | Select-Object -First 2) }
        foreach ($h in $hubs) { [void]$edges.Add((Edge (Curve $h (Nearest $h $ring) 0.08 1) "local" 5.0)) }
        for ($i = 0; $i -lt $hubs.Count; $i++) {
            for ($j = $i + 1; $j -lt $hubs.Count; $j++) {
                if ([Math]::Sqrt((Dist2 $hubs[$i] $hubs[$j])) -le 1050) {
                    [void]$edges.Add((Edge (Curve $hubs[$i] $hubs[$j] 0.05 ($i + $j)) "local" 5.0))
                }
            }
        }
        foreach ($p in $points) {
            $h = Nearest $p $hubs
            if ([Math]::Sqrt((Dist2 $p $h)) -gt 50 -and [Math]::Sqrt((Dist2 $p $h)) -le 850) {
                [void]$edges.Add((Edge (Curve $h $p 0.04 2) "local" 4.0))
            }
        }
    } elseif ($Identity -eq "sparse_city") {
        $hubs = @($urban | Select-Object -First 2)
        if ($hubs.Count -eq 0) { $hubs = @($points | Sort-Object { Dist2 $_ $centroid } | Select-Object -First 1) }
        if ($hubs.Count -eq 2) { [void]$edges.Add((Edge (Curve $hubs[0] $hubs[1] 0.05 3) "local" 5.5)) }
        foreach ($p in $points) {
            $h = Nearest $p $hubs
            if ([Math]::Sqrt((Dist2 $p $h)) -gt 50) { [void]$edges.Add((Edge (Curve $h $p 0.08 4) "local" 4.5)) }
        }
        if ($points.Count -ge 4) {
            $pair = Farthest-Pair $points
            [void]$edges.Add((Edge (Curve $pair[0] $pair[1] 0.16 5) "trunk" 6.5))
        }
    } elseif ($Identity -eq "dense_rural") {
        $hub = if ($urban.Count -gt 0) { Nearest $centroid $urban } else { Nearest $centroid $points }
        foreach ($p in $points) {
            if ([Math]::Sqrt((Dist2 $p $hub)) -gt 50) { [void]$edges.Add((Edge (Curve $hub $p 0.11 6) "local" 4.5)) }
        }
        if ($points.Count -ge 4) {
            $pair = Farthest-Pair $points
            [void]$edges.Add((Edge (Curve $pair[0] $pair[1] 0.10 7) "local" 4.0))
        }
    } elseif ($Identity -eq "mountain_range") {
        $pair = Farthest-Pair $points
        $dx = $pair[1].X - $pair[0].X; $dy = $pair[1].Y - $pair[0].Y
        $len = [Math]::Max(1.0, [Math]::Sqrt(($dx * $dx) + ($dy * $dy)))
        $nx = -$dy / $len; $ny = $dx / $len
        $ordered = @($points | Sort-Object { (($_.X - $pair[0].X) * $dx) + (($_.Y - $pair[0].Y) * $dy) })
        $path = @($pair[0])
        $step = [Math]::Max(1, [int][Math]::Ceiling($ordered.Count / 4.0))
        $side = 1.0
        for ($i = $step; $i -lt $ordered.Count - 1; $i += $step) {
            $p = $ordered[$i]
            $path += Point ($p.X + $nx * 90 * $side) ($p.Y + $ny * 90 * $side)
            $side *= -1.0
        }
        $path += $pair[1]
        [void]$edges.Add((Edge $path "trunk" 5.8))
        if ($points.Count -ge 6) {
            $target = $ordered[[int]($ordered.Count * 0.5)]
            $anchor = Project-ToSegment $target $pair[0] $pair[1]
            [void]$edges.Add((Edge (Curve $anchor $target 0.12 8) "local" 3.8))
        }
    } else {
        $pair = Farthest-Pair $points
        [void]$edges.Add((Edge (Curve $pair[0] $pair[1] 0.14 9) "trunk" 5.8))
        $farms = @($Members | Where-Object { $_.Type -in @("rural", "hill") } | ForEach-Object { $_.Center } | Sort-Object { Dist2 $_ (Project-ToSegment $_ $pair[0] $pair[1]) } | Select-Object -First 2)
        foreach ($f in $farms) {
            $anchor = Project-ToSegment $f $pair[0] $pair[1]
            if ([Math]::Sqrt((Dist2 $anchor $f)) -gt 50) { [void]$edges.Add((Edge (Curve $anchor $f 0.08 10) "local" 3.8)) }
        }
    }
    @($edges)
}

function Draw-LinePath($Graphics, $Transform, $Path, [System.Drawing.Color]$Color, [double]$Width) {
    if ($Path.Count -lt 2) { return }
    $pts = @($Path | ForEach-Object { To-PointF $_ $Transform.Bounds $Transform.Scale })
    $pen = [System.Drawing.Pen]::new($Color, [single]$Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $Graphics.DrawLines($pen, [System.Drawing.PointF[]]$pts)
    $pen.Dispose()
}

foreach ($shot in $Shots) {
    $regionId = $shot.region
    $identity = $shot.identity
    $shotSuffix = if ($shot.ContainsKey("suffix")) { [string]$shot.suffix } else { "" }
    $region = $RegionsDoc.regions.$regionId
    $members = @()
    foreach ($tileId in $region.tiles) {
        if (-not $TileById.ContainsKey($tileId)) { continue }
        $coord = Parse-TileId $tileId
        $center = Center-For $coord.Q $coord.R
        $members += [PSCustomObject]@{
            Id = $tileId; Col = $coord.Col; Row = $coord.Row; Q = $coord.Q; R = $coord.R
            Type = $TileById[$tileId].type
            Center = $center
        }
    }
    $minCol = ($members | Measure-Object Col -Minimum).Minimum - 1
    $maxCol = ($members | Measure-Object Col -Maximum).Maximum + 1
    $minRow = ($members | Measure-Object Row -Minimum).Minimum - 1
    $maxRow = ($members | Measure-Object Row -Maximum).Maximum + 1
    $context = @($TileRows | Where-Object {
        $c = Parse-TileId $_.id
        $c.Col -ge $minCol -and $c.Col -le $maxCol -and $c.Row -ge $minRow -and $c.Row -le $maxRow
    } | ForEach-Object {
        $c = Parse-TileId $_.id
        [PSCustomObject]@{
            Id = $_.id; Col = $c.Col; Row = $c.Row; Q = $c.Q; R = $c.R
            Type = $_.type
            Center = (Center-For $c.Q $c.R)
        }
    })
    $allHexPoints = @()
    foreach ($tile in $context) { $allHexPoints += Get-Hex $tile.Center }
    $minX = ($allHexPoints | Measure-Object X -Minimum).Minimum
    $maxX = ($allHexPoints | Measure-Object X -Maximum).Maximum
    $minY = ($allHexPoints | Measure-Object Y -Minimum).Minimum
    $maxY = ($allHexPoints | Measure-Object Y -Maximum).Maximum
    $scale = [Math]::Min(1200.0 / [Math]::Max(1.0, $maxX - $minX), 780.0 / [Math]::Max(1.0, $maxY - $minY))
    $transform = @{ Bounds = @{ MinX = $minX; MinY = $minY }; Scale = $scale }

    $bmp = [System.Drawing.Bitmap]::new(1280, 900)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(255, 232, 224, 202))

    foreach ($tile in $context) {
        $hex = @(Get-Hex $tile.Center | ForEach-Object { To-PointF $_ $transform.Bounds $transform.Scale })
        $color = if ($TerrainColors.ContainsKey($tile.Type)) { $TerrainColors[$tile.Type] } else { $TerrainColors.rural }
        $brush = [System.Drawing.SolidBrush]::new($color)
        $g.FillPolygon($brush, [System.Drawing.PointF[]]$hex)
        $brush.Dispose()
        $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(80, 60, 55, 45), 1.0)
        $g.DrawPolygon($pen, [System.Drawing.PointF[]]$hex)
        $pen.Dispose()
    }

    $memberIds = @{}
    foreach ($m in $members) { $memberIds[$m.Id] = $true }
    foreach ($tile in $members) {
        $hex = @(Get-Hex $tile.Center | ForEach-Object { To-PointF $_ $transform.Bounds $transform.Scale })
        $brush = [System.Drawing.SolidBrush]::new($HighlightColors[$identity])
        $g.FillPolygon($brush, [System.Drawing.PointF[]]$hex)
        $brush.Dispose()
        $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(190, 45, 38, 30), 2.3)
        $g.DrawPolygon($pen, [System.Drawing.PointF[]]$hex)
        $pen.Dispose()
    }

    $routeKey = Shot-Key $identity $regionId $shotSuffix
    $terrainEdges = if ($TerrainRoutesByKey.ContainsKey($routeKey)) { Convert-TerrainEdges $TerrainRoutesByKey[$routeKey] } else { $null }
    $usingTerrainRoutes = $null -ne $terrainEdges -and $terrainEdges.Count -gt 0
    $edges = if ($usingTerrainRoutes) { $terrainEdges } else { Constrain-EdgesToLand (Generate-Edges $members $identity) $context }
    foreach ($edge in $edges) { Draw-LinePath $g $transform $edge.Path ([System.Drawing.Color]::FromArgb(235, 38, 25, 15)) ([Math]::Max(6.0, ($edge.Width + 4.0) * $scale * 0.70)) }
    foreach ($edge in $edges) {
        $color = if ($edge.Tier -eq "trunk") { [System.Drawing.Color]::FromArgb(246, 219, 104, 31) } else { [System.Drawing.Color]::FromArgb(246, 234, 192, 62) }
        Draw-LinePath $g $transform $edge.Path $color ([Math]::Max(3.5, $edge.Width * $scale * 0.70))
    }

    $font = [System.Drawing.Font]::new("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
    $subFont = [System.Drawing.Font]::new("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
    $suffix = if ($shot.ContainsKey("suffix")) { " ($($shot.suffix))" } else { "" }
    $title = "$($region.name)$suffix - $identity preview"
    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(220, 30, 25, 18))
    $fg = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 242, 201))
    $g.DrawString($title, $font, $shadow, 25, 23)
    $g.DrawString($title, $font, $fg, 23, 21)
    $subtitle = if ($usingTerrainRoutes) {
        "12u terrain-routed: orange = trunk/bypass/pass, yellow = local links/spokes"
    } else {
        "schematic fallback: orange = trunk/bypass/pass, yellow = local links/spokes"
    }
    $g.DrawString($subtitle, $subFont, $shadow, 25, 57)
    $g.DrawString($subtitle, $subFont, $fg, 23, 55)
    $shadow.Dispose(); $fg.Dispose(); $font.Dispose(); $subFont.Dispose()

    $safeName = "$identity`_$regionId"
    if ($shot.ContainsKey("suffix")) { $safeName = "$identity`_$($shot.suffix)_$regionId" }
    $path = Join-Path $OutDir "$safeName.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    $SavedPaths += $path
    Write-Host "road_region_preview_saved=$path"
}

if ($SavedPaths.Count -gt 0) {
    $thumbW = 640
    $thumbH = 450
    $cols = 2
    $rows = [Math]::Ceiling($SavedPaths.Count / [double]$cols)
    $sheet = [System.Drawing.Bitmap]::new($thumbW * $cols, $thumbH * $rows)
    $sg = [System.Drawing.Graphics]::FromImage($sheet)
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.Clear([System.Drawing.Color]::FromArgb(255, 232, 224, 202))
    for ($i = 0; $i -lt $SavedPaths.Count; $i++) {
        $img = [System.Drawing.Image]::FromFile($SavedPaths[$i])
        $x = ($i % $cols) * $thumbW
        $y = [Math]::Floor($i / $cols) * $thumbH
        $sg.DrawImage($img, $x, $y, $thumbW, $thumbH)
        $img.Dispose()
    }
    $sheetPath = Join-Path $OutDir "contact_sheet.png"
    $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $sg.Dispose()
    $sheet.Dispose()
    Write-Host "road_region_preview_contact_sheet=$sheetPath"
}
