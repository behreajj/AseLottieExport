local frameTargets <const> = { "ACTIVE", "ALL", "TAG" }
local shapePresets <const> = { "PATH", "RECT" }

local defaults <const> = {
    -- TODO: Allow padding between pixels?
    -- TODO: Use AseSwatchIO tech to convert from Adobe or display to sRGB?
    frameTarget = "ALL",
    fps = 12,
    scale = 1,
    usePixelAspect = true,
    shapePreset = "RECT",
    roundPercent = 0,
}

-- 5.5.1 latest possible with VS code extension
local lottieVersion <const> = "5.5.1"

local mainFormat <const> = table.concat({
    "{\"v\":\"%s\"",    -- Version
    "\"fr\":%d",        -- FPS
    "\"ip\":%d",        -- First frame
    "\"op\":%d",        -- Last frame
    "\"w\":%d",         -- Width
    "\"h\":%d",         -- Height
    "\"nm\":\"%s\"",    -- Name
    "\"layers\":[%s]}", -- Layers
}, ",")

local transformFormat <const> = table.concat({
    "{\"a\":{\"a\":0,\"k\":[%.1f,%.1f]}", -- Anchor
    "\"p\":{\"a\":0,\"k\":[%.1f,%.1f]}",  -- Position
    "\"o\":{\"a\":0,\"k\":%d}}",          -- Opacity
}, ",")

-- Index property is needed to prevent some frames from
-- falling beneath background layer.
local layerFillFormat <const> = table.concat({
    "{\"ty\":1",        -- Type (1: solid color)
    "\"ind\":%d",       -- Index (starting at 0)
    "\"ip\":%d",        -- From frame
    "\"op\":%d",        -- To frame
    "\"st\":0",         -- Start time
    "\"nm\":\"%s\"",    -- Name
    "\"ks\":{}",        -- Transform
    "\"sc\":\"#%06x\"", -- Color as web hex
    "\"sw\":%d",        -- Width
    "\"sh\":%d}"        -- Height
}, ",")

local flatShapeFormat <const> = table.concat({
    "{\"ty\":4",        -- Type (4: shape)
    "\"ind\":%d",       -- Index (starting at 0)
    "\"ip\":%d",        -- From frame
    "\"op\":%d",        -- To frame
    "\"st\":0",         -- Start time
    "\"nm\":\"%s\"",    -- Name
    "\"ks\":%s",        -- Transform
    "\"shapes\":[%s]}", -- Shapes
}, ",")

local shapeGroupFormat <const> = table.concat({
    "{\"ty\":\"gr\"", -- Type
    "\"nm\":\"%s\"",  -- Name
    "\"it\":[%s]}"    -- Sub shapes
}, ",")

-- Bezier shape format: v, i and o are required.
-- o is fore tangent. i is rear tangent.
-- i and o are relative to v.
-- v0 --> o0  i1 <-- v1
--  |                 |
-- \/                \/
-- i0                o1
--
-- o3                 i2
-- /\                 /\
-- |                  |
-- v3 --> i3  o2 <-- v2
local bezFormat4 <const> = table.concat({
    "{\"ty\":\"sh\"",
    "\"ks\":{\"a\":0",
    "\"k\":{\"c\":%s", -- isClosed
    "\"v\":[[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]]",
    "\"i\":[[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]]",
    "\"o\":[[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]]}}}"
}, ",")

local bezFormat8 <const> = table.concat({
    "{\"ty\":\"sh\"",
    "\"ks\":{\"a\":0",
    "\"k\":{\"c\":%s", -- isClosed
    "\"v\":[[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]]",
    "\"i\":[[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]]",
    "\"o\":[[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f],[%.3f,%.3f]]}}}"
}, ",")

local shapeRectFormat <const> = table.concat({
    "{\"ty\":\"rc\"",                    -- Type
    "\"p\":{\"a\":0,\"k\":[%.1f,%.1f]}", -- Center
    "\"s\":{\"a\":0,\"k\":[%d,%d]}",     -- Size
    "\"r\":{\"a\":0,\"k\":%.3f}}",       -- Rounding
}, ",")

local shapeFillFormat <const> = table.concat({
    "{\"ty\":\"fl\"",                          -- Type
    "\"o\":{\"a\":0,\"k\":%d}",                -- Opacity in 0 to 100
    "\"c\":{\"a\":0,\"k\":[%.4f,%.4f,%.4f]}}", -- RGB color in 0.0 to 1.0
}, ",")

local shapeTransformFormat <const> = table.concat({
    "{\"ty\":\"tr\"",            -- Type
    "\"o\":{\"a\":0,\"k\":%d}}", -- Opacity
}, ",")

---@param aIdx integer
---@param bIdx integer
---@param imgWidth integer
---@return boolean
local function comparator(aIdx, bIdx, imgWidth)
    local ay <const> = aIdx // imgWidth
    local by <const> = bIdx // imgWidth
    if ay < by then return true end
    if ay > by then return false end
    return (aIdx % imgWidth) < (bIdx % imgWidth)
end

---@param img Image
---@param palette Palette
---@param wPixel integer
---@param hPixel integer
---@param rounding number
---@param useBezPath boolean
---@return string[]
local function imgToLotStr(
    img, palette,
    wPixel, hPixel,
    rounding, useBezPath)
    local strfmt <const> = string.format
    local floor <const> = math.floor
    local tconcat <const> = table.concat

    local imgSpec <const> = img.spec
    local imgWidth <const> = imgSpec.width
    local colorMode <const> = imgSpec.colorMode

    local wo3 <const> = wPixel / 3.0
    local ho3 <const> = hPixel / 3.0
    local rk <const> = 0.55228474983079 * rounding
    local r2 <const> = rounding + rounding
    local xHnd <const> = (wPixel - r2) / 3.0
    local yHnd <const> = (hPixel - r2) / 3.0
    local wHalf <const> = wPixel * 0.5
    local hHalf <const> = hPixel * 0.5
    local roundLtEq0 <const> = rounding <= 0.0
    local roundGtEq1 <const> = rounding >= math.min(wHalf, hHalf)

    ---@type table<integer, integer[]>
    local pixelDict <const> = {}
    local pxItr <const> = img:pixels()

    if colorMode == ColorMode.INDEXED then
        local alphaIdx <const> = imgSpec.transparentColor
        ---@type table<integer, integer>
        local clrIdxToHex <const> = {}
        for pixel in pxItr do
            local clrIdx <const> = pixel()
            if clrIdx ~= alphaIdx then
                local hex = clrIdxToHex[clrIdx]
                if not hex then
                    local aseColor <const> = palette:getColor(clrIdx)
                    hex = aseColor.rgbaPixel
                    clrIdxToHex[clrIdx] = hex
                end

                if hex & 0xff000000 ~= 0 then
                    local pxIdx <const> = pixel.x + pixel.y * imgWidth
                    local idcs <const> = pixelDict[hex]
                    if idcs then
                        idcs[#idcs + 1] = pxIdx
                    else
                        pixelDict[hex] = { pxIdx }
                    end
                end
            end
        end
    elseif colorMode == ColorMode.GRAY then
        for pixel in pxItr do
            local gray <const> = pixel()
            if gray & 0xff00 ~= 0 then
                local idx <const> = pixel.x + pixel.y * imgWidth

                local a <const> = (gray >> 0x08) & 0xff
                local v <const> = gray & 0xff
                local hex <const> = a << 0x18 | v << 0x10 | v << 0x08 | v

                local idcs <const> = pixelDict[hex]
                if idcs then
                    idcs[#idcs + 1] = idx
                else
                    pixelDict[hex] = { idx }
                end
            end
        end
    elseif colorMode == ColorMode.RGB then
        for pixel in pxItr do
            local hex <const> = pixel()
            if hex & 0xff000000 ~= 0 then
                local idx <const> = pixel.x + pixel.y * imgWidth
                local idcs <const> = pixelDict[hex]
                if idcs then
                    idcs[#idcs + 1] = idx
                else
                    pixelDict[hex] = { idx }
                end
            end
        end
    end

    ---@type integer[]
    local hexArr <const> = {}
    ---@type integer[][]
    local idcsArr <const> = {}
    local lenUniques = 0
    for hex, idcs in pairs(pixelDict) do
        lenUniques = lenUniques + 1
        hexArr[lenUniques] = hex
        idcsArr[lenUniques] = idcs
    end

    table.sort(hexArr, function(a, b)
        return comparator(pixelDict[a][1], pixelDict[b][1], imgWidth)
    end)
    table.sort(idcsArr, function(a, b)
        return comparator(a[1], b[1], imgWidth)
    end)

    ---@type string[]
    local shapeGroupsArr <const> = {}

    local h = 0
    while h < lenUniques do
        h = h + 1
        local hex <const> = hexArr[h]
        local idcs <const> = idcsArr[h]

        ---@type string[]
        local subShapesArr <const> = {}
        local lenIdcs <const> = #idcs
        if useBezPath then
            if roundLtEq0 then
                -- Draw squares.
                local i = 0
                while i < lenIdcs do
                    i = i + 1
                    local idx <const> = idcs[i]
                    local x <const> = idx % imgWidth
                    local y <const> = idx // imgWidth

                    local x0 <const> = x * wPixel
                    local y0 <const> = y * hPixel
                    local x1 <const> = x0 + wPixel
                    local y1 <const> = y0 + hPixel

                    local sqBezStr <const> = strfmt(bezFormat4,
                        "true",
                        x0, y0, x1, y0, x1, y1, x0, y1,   -- v
                        0, ho3, -wo3, 0, 0, -ho3, wo3, 0, -- i
                        wo3, 0, 0, ho3, -wo3, 0, 0, -ho3) -- o
                    subShapesArr[#subShapesArr + 1] = sqBezStr
                end
            elseif roundGtEq1 then
                -- Draw circles.
                local i = 0
                while i < lenIdcs do
                    i = i + 1
                    local idx <const> = idcs[i]
                    local x <const> = idx % imgWidth
                    local y <const> = idx // imgWidth

                    local x0 <const> = x * wPixel
                    local y0 <const> = y * hPixel
                    local x1 <const> = x0 + wPixel
                    local y1 <const> = y0 + hPixel
                    local xc <const> = x0 + wHalf
                    local yc <const> = y0 + hHalf

                    local rdBezStr <const> = strfmt(bezFormat4,
                        "true",
                        xc, y0, x1, yc, xc, y1, x0, yc, -- v
                        -rk, 0, 0, -rk, rk, 0, 0, rk,   -- i
                        rk, 0, 0, rk, -rk, 0, 0, -rk)   -- o
                    subShapesArr[#subShapesArr + 1] = rdBezStr
                end
            else
                local i = 0
                while i < lenIdcs do
                    i = i + 1
                    local idx <const> = idcs[i]
                    local x <const> = idx % imgWidth
                    local y <const> = idx // imgWidth

                    local x0 <const> = x * wPixel
                    local y0 <const> = y * hPixel
                    local x1 <const> = x0 + wPixel
                    local y1 <const> = y0 + hPixel

                    local x0In <const> = x0 + rounding
                    local x1In <const> = x1 - rounding
                    local y0In <const> = y0 + rounding
                    local y1In <const> = y1 - rounding

                    local crnrBezStr <const> = strfmt(bezFormat8,
                        "true",
                        x0In, y0, x1In, y0, x1, y0In, x1, y1In, -- v
                        x1In, y1, x0In, y1, x0, y1In, x0, y0In, -- v
                        -rk, 0, -xHnd, 0, 0, -rk, 0, -yHnd,     -- i
                        rk, 0, xHnd, 0, 0, rk, 0, yHnd,         -- i
                        xHnd, 0, rk, 0, 0, yHnd, 0, rk,         -- o
                        -xHnd, 0, -rk, 0, 0, -yHnd, 0, -rk)     -- o
                    subShapesArr[#subShapesArr + 1] = crnrBezStr
                end
            end
        else
            local i = 0
            while i < lenIdcs do
                i = i + 1
                local idx <const> = idcs[i]
                local x <const> = idx % imgWidth
                local y <const> = idx // imgWidth
                local xc <const> = x * wPixel + wHalf
                local yc <const> = y * hPixel + hHalf
                local rectStr <const> = strfmt(shapeRectFormat,
                    xc, yc, wPixel, hPixel, rounding)
                subShapesArr[#subShapesArr + 1] = rectStr
            end
        end


        local b8 <const> = (hex >> 0x10) & 0xff
        local g8 <const> = (hex >> 0x08) & 0xff
        local r8 <const> = hex & 0xff
        local name = strfmt("%06x", (r8 << 0x10) |(g8 << 0x08) | b8)

        local lenSubShapes <const> = #subShapesArr
        if lenSubShapes > 0 then
            local a8 <const> = (hex >> 0x18) & 0xff
            local a100 = floor((a8 / 255.0) * 100.0 + 0.5)

            local fillShape <const> = strfmt(shapeFillFormat,
                a100,
                r8 / 255.0, g8 / 255.0, b8 / 255.0)
            subShapesArr[#subShapesArr + 1] = fillShape

            -- A transform shape is mandatory for a group shape to be valid!
            local transformShape <const> = strfmt(
                shapeTransformFormat,
                100)
            subShapesArr[#subShapesArr + 1] = transformShape
        end

        local shapeGroup <const> = strfmt(
            shapeGroupFormat,
            name,
            tconcat(subShapesArr, ","))
        shapeGroupsArr[#shapeGroupsArr + 1] = shapeGroup
    end

    return shapeGroupsArr
end

---@param tag Tag
---@return integer[]
local function tagToFrIdcs(tag)
    local destFrObj <const> = tag.toFrame
    if not destFrObj then return {} end

    local origFrObj <const> = tag.fromFrame
    if not origFrObj then return {} end

    local origIdx <const> = origFrObj.frameNumber
    local destIdx <const> = destFrObj.frameNumber
    if origIdx == destIdx then return { destIdx } end

    ---@type integer[]
    local arr <const> = {}
    local idxArr = 0
    local aniDir <const> = tag.aniDir
    if aniDir == AniDir.REVERSE then
        local j = destIdx + 1
        while j > origIdx do
            j = j - 1
            idxArr = idxArr + 1
            arr[idxArr] = j
        end
    elseif aniDir == AniDir.PING_PONG then
        local j = origIdx - 1
        while j < destIdx do
            j = j + 1
            idxArr = idxArr + 1
            arr[idxArr] = j
        end
        local op1 <const> = origIdx + 1
        while j > op1 do
            j = j - 1
            idxArr = idxArr + 1
            arr[idxArr] = j
        end
    elseif aniDir == AniDir.PING_PONG_REVERSE then
        local j = destIdx + 1
        while j > origIdx do
            j = j - 1
            idxArr = idxArr + 1
            arr[idxArr] = j
        end
        local dn1 <const> = destIdx - 1
        while j < dn1 do
            j = j + 1
            idxArr = idxArr + 1
            arr[idxArr] = j
        end
    else
        -- Default to AniDir.FORWARD
        local j = origIdx - 1
        while j < destIdx do
            j = j + 1
            idxArr = idxArr + 1
            arr[idxArr] = j
        end
    end

    return arr
end

local dlg <const> = Dialog { title = "Lottie Export" }

dlg:combobox {
    id = "frameTarget",
    label = "Frames:",
    option = defaults.frameTarget,
    options = frameTargets
}

dlg:newrow { always = false }

dlg:slider {
    id = "fps",
    label = "FPS:",
    min = 1,
    max = 60,
    value = defaults.fps,
}

dlg:newrow { always = false }

dlg:slider {
    id = "scale",
    label = "Scale:",
    min = 1,
    max = 32,
    value = defaults.scale
}

dlg:newrow { always = false }

dlg:check {
    id = "usePixelAspect",
    label = "Apply:",
    text = "Pixel Aspect",
    selected = defaults.usePixelAspect
}

dlg:newrow { always = false }

dlg:slider {
    id = "roundPercent",
    label = "Rounding:",
    min = 0,
    max = 100,
    value = defaults.roundPercent
}

dlg:newrow { always = false }

dlg:combobox {
    id = "shapePreset",
    label = "Shape:",
    option = defaults.shapePreset,
    options = shapePresets
}

dlg:newrow { always = false }

dlg:color {
    id = "bkgColor",
    label = "Bkg:",
    color = Color { r = 0, g = 0, b = 0, a = 0 }
}

dlg:newrow { always = false }

dlg:file {
    id = "filepath",
    label = "Path:",
    filetypes = { "json" },
    save = true,
    focus = true
}

dlg:newrow { always = false }

dlg:button {
    id = "confirm",
    text = "&OK",
    focus = false,
    onclick = function()
        -- Early returns.
        local site <const> = app.site
        local activeSprite <const> = site.sprite
        if not activeSprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        -- Unpack file path.
        local args <const> = dlg.data
        local filepath <const> = args.filepath --[[@as string]]
        if (not filepath) or (#filepath < 1) then
            app.alert { title = "Error", text = "Filepath is empty." }
            return
        end

        local ext <const> = app.fs.fileExtension(filepath)
        local extlc <const> = string.lower(ext)
        if extlc ~= "json" then
            app.alert { title = "Error", text = "Extension is not json." }
            return
        end

        -- Set tool to hand to prevent any issues with slice tool context bar
        -- UI or with uncommitted selection mask transformations.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        -- Unpack sprite spec.
        local spriteSpec <const> = activeSprite.spec
        local wSprite <const> = spriteSpec.width
        local hSprite <const> = spriteSpec.height
        local colorMode <const> = spriteSpec.colorMode
        local alphaIndex <const> = spriteSpec.transparentColor
        local colorSpace <const> = spriteSpec.colorSpace

        -- Unpack arguments.
        local frameTarget <const> = args.frameTarget
            or defaults.frameTarget --[[@as string]]
        local fps <const> = args.fps
            or defaults.fps --[[@as integer]]
        local scale <const> = args.scale
            or defaults.scale --[[@as integer]]
        local roundPercent <const> = args.roundPercent
            or defaults.roundPercent --[[@as integer]]
        local shapePreset <const> = args.shapePreset
            or defaults.shapePreset --[[@as string]]
        local usePixelAspect <const> = args.usePixelAspect --[[@as boolean]]
        local bkgColor <const> = args.bkgColor --[[@as Color]]

        local spriteFrObjs <const> = activeSprite.frames
        local lenSpriteFrObjs <const> = #spriteFrObjs

        ---@type integer[]
        local chosenFrames = {}
        if frameTarget == "TAG" then
            local activeTag <const> = app.tag
            if activeTag then
                chosenFrames = tagToFrIdcs(activeTag)
            else
                -- Default to all.
                local h = 0
                while h < lenSpriteFrObjs do
                    h = h + 1
                    chosenFrames[h] = h
                end
            end
        elseif frameTarget == "ACTIVE" then
            local activeFrObj <const> = app.frame or spriteFrObjs[1]
            chosenFrames = { activeFrObj.frameNumber }
        else
            local h = 0
            while h < lenSpriteFrObjs do
                h = h + 1
                chosenFrames[h] = h
            end
        end
        local lenChosenFrames <const> = #chosenFrames

        if lenChosenFrames <= 0 then
            app.alert { title = "Error", text = "No frames selected." }
            return
        end

        local frUiOffset = 1
        local appPrefs <const> = app.preferences
        if appPrefs then
            local docPrefs <const> = appPrefs.document(activeSprite)
            if docPrefs then
                local tlPrefs <const> = docPrefs.timeline
                if tlPrefs then
                    local fruiPref <const> = tlPrefs.first_frame
                    if fruiPref then
                        frUiOffset = fruiPref --[[@as integer]]
                    end
                end
            end
        end

        -- Last frame is inclusive of the right edge of the last frame.
        local firstFrame <const> = 0
        local lastFrame <const> = lenChosenFrames

        -- Cache methods used in loops.
        local strfmt <const> = string.format
        local fileSys <const> = app.fs
        local max <const> = math.max
        local abs <const> = math.abs
        local tconcat <const> = table.concat

        local spriteName = fileSys.fileTitle(activeSprite.filename)
        if #spriteName <= 0 then spriteName = "Sprite" end

        local wPixel = scale
        local hPixel = scale
        if usePixelAspect then
            local pxRatio <const> = activeSprite.pixelRatio
            wPixel = wPixel * max(1, abs(pxRatio.width))
            hPixel = hPixel * max(1, abs(pxRatio.height))
        end

        local wSpriteScaled <const> = wSprite * wPixel
        local hSpriteScaled <const> = hSprite * hPixel

        local roundFac <const> = roundPercent * 0.01
        local shortEdge <const> = 0.5 * math.min(wPixel, hPixel)
        local rdVerif <const> = shortEdge * roundFac

        ---@type string[]
        local layerStrsArr <const> = {}
        local palette <const> = activeSprite.palettes[1]
        local bkgIdxOffset <const> = bkgColor.alpha > 0 and 1 or 0
        local useBezPath <const> = shapePreset == "PATH"

        local i = 0
        while i < lenChosenFrames do
            i = i + 1
            local frIdx <const> = chosenFrames[i]
            local flat <const> = Image(spriteSpec)
            flat:drawSprite(activeSprite, frIdx)
            local aabb <const> = flat:shrinkBounds(alphaIndex)
            if aabb.width > 0 and aabb.height > 0 then
                local xtlCel <const> = aabb.x
                local ytlCel <const> = aabb.y
                local wCel <const> = aabb.width
                local hCel <const> = aabb.height

                local trimSpec <const> = ImageSpec {
                    width = wCel,
                    height = hCel,
                    colorMode = colorMode,
                    transparentColor = alphaIndex
                }
                trimSpec.colorSpace = colorSpace
                local trim <const> = Image(trimSpec)
                trim:drawImage(flat, Point(-xtlCel, -ytlCel), 255, BlendMode.SRC)

                local shapeStrArr <const> = imgToLotStr(
                    trim, palette, wPixel, hPixel, rdVerif, useBezPath)

                local xtlScl <const> = xtlCel * wPixel
                local ytlScl <const> = ytlCel * hPixel
                local wScl <const> = wCel * wPixel
                local hScl <const> = hCel * hPixel

                local xAnchor <const> = wScl * 0.5
                local yAnchor <const> = hScl * 0.5
                local xPos <const> = xtlScl + wScl * 0.5
                local yPos <const> = ytlScl + hScl * 0.5
                local transformStr = strfmt(transformFormat,
                    xAnchor, yAnchor,
                    xPos, yPos, 100)

                local layerName = strfmt("Fr %d", frUiOffset + frIdx - 1)
                local layerStr <const> = strfmt(flatShapeFormat,
                    bkgIdxOffset + lenChosenFrames - i,
                    i - 1, i, -- From, To frame
                    layerName,
                    transformStr,
                    tconcat(shapeStrArr, ","))

                layerStrsArr[#layerStrsArr + 1] = layerStr
            end
        end

        if bkgColor.alpha > 0 then
            local bkgWebHex <const> = bkgColor.red << 0x10
                | bkgColor.green << 0x08
                | bkgColor.blue
            local bkgStr <const> = strfmt(layerFillFormat,
                0,
                firstFrame, lastFrame,
                "Background",
                bkgWebHex,
                wSpriteScaled,
                hSpriteScaled)
            layerStrsArr[#layerStrsArr + 1] = bkgStr
        end

        local lotStr <const> = strfmt(
            mainFormat,
            lottieVersion,
            fps,
            firstFrame,
            lastFrame,
            wSpriteScaled,
            hSpriteScaled,
            spriteName,
            tconcat(layerStrsArr, ","))

        local file <const>, err <const> = io.open(filepath, "w")
        if file then
            file:write(lotStr)
            file:close()
        end

        if err then
            app.alert { title = "Error", text = err }
            return
        end

        if colorSpace ~= ColorSpace { sRGB = true }
            and colorSpace ~= ColorSpace() then
            app.alert {
                title = "Warning",
                text = {
                    "Lotties do not contain color profiles.",
                    "Export colors may differ from original."
                }
            }
        else
            app.alert { title = "Success", text = "File exported." }
        end
    end
}

dlg:button {
    id = "cancel",
    text = "&CANCEL",
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show {
    autoscrollbars = true,
    wait = false
}