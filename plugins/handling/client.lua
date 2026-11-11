local CLASS = "CHandlingData"
local PRECISION = 10000.0
local POLL_MS = 500

local GROUPS = {
    { label = "ตัวรถ", fields = {
        { "fMass", "float" },
        { "fInitialDragCoeff", "float" },
        { "fDownforceModifier", "float" },
        { "fPercentSubmerged", "float" },
        { "vecCentreOfMassOffset", "vector" },
        { "vecInertiaMultiplier", "vector" }
    } },
    { label = "เครื่องยนต์และเกียร์", fields = {
        { "fDriveBiasFront", "float" },
        { "nInitialDriveGears", "integer" },
        { "fInitialDriveForce", "float" },
        { "fDriveInertia", "float" },
        { "fClutchChangeRateScaleUpShift", "float" },
        { "fClutchChangeRateScaleDownShift", "float" },
        { "fInitialDriveMaxFlatVel", "float" }
    } },
    { label = "เบรก", fields = {
        { "fBrakeForce", "float" },
        { "fBrakeBiasFront", "float" },
        { "fHandBrakeForce", "float" }
    } },
    { label = "พวงมาลัยและการยึดเกาะ", fields = {
        { "fSteeringLock", "float" },
        { "fTractionCurveMax", "float" },
        { "fTractionCurveMin", "float" },
        { "fTractionCurveLateral", "float" },
        { "fTractionSpringDeltaMax", "float" },
        { "fLowSpeedTractionLossMult", "float" },
        { "fCamberStiffnesss", "float" },
        { "fTractionBiasFront", "float" },
        { "fTractionLossMult", "float" }
    } },
    { label = "ช่วงล่าง", fields = {
        { "fSuspensionForce", "float" },
        { "fSuspensionCompDamp", "float" },
        { "fSuspensionReboundDamp", "float" },
        { "fSuspensionUpperLimit", "float" },
        { "fSuspensionLowerLimit", "float" },
        { "fSuspensionRaise", "float" },
        { "fSuspensionBiasFront", "float" },
        { "fAntiRollBarForce", "float" },
        { "fAntiRollBarBiasFront", "float" },
        { "fRollCentreHeightFront", "float" },
        { "fRollCentreHeightRear", "float" }
    } },
    { label = "ความเสียหาย", fields = {
        { "fCollisionDamageMult", "float" },
        { "fWeaponDamageMult", "float" },
        { "fDeformationDamageMult", "float" },
        { "fEngineDamageMult", "float" }
    } },
    { label = "อื่น ๆ", fields = {
        { "fPetrolTankVolume", "float" },
        { "fOilVolume", "float" },
        { "fSeatOffsetDistX", "float" },
        { "fSeatOffsetDistY", "float" },
        { "fSeatOffsetDistZ", "float" },
        { "nMonetaryValue", "integer" }
    } }
}

local types = {}
local layout = {}
for i, group in ipairs(GROUPS) do
    local fields = {}
    for j, field in ipairs(group.fields) do
        types[field[1]] = field[2]
        fields[j] = { name = field[1], type = field[2] }
    end
    layout[i] = { label = group.label, fields = fields }
end

local current = 0
local originals = {}

local function round(value)
    return math.floor(value * PRECISION + 0.5) / PRECISION
end

local function read(vehicle, name)
    local kind = types[name]
    if kind == "float" then
        return round(GetVehicleHandlingFloat(vehicle, CLASS, name))
    elseif kind == "integer" then
        return GetVehicleHandlingInt(vehicle, CLASS, name)
    end
    local v = GetVehicleHandlingVector(vehicle, CLASS, name)
    return { x = round(v.x), y = round(v.y), z = round(v.z) }
end

local function write(vehicle, name, value)
    local kind = types[name]
    if kind == "float" then
        SetVehicleHandlingFloat(vehicle, CLASS, name, value + 0.0)
    elseif kind == "integer" then
        SetVehicleHandlingInt(vehicle, CLASS, name, math.floor(value))
    elseif kind == "vector" then
        SetVehicleHandlingVector(vehicle, CLASS, name, vector3(value.x + 0.0, value.y + 0.0, value.z + 0.0))
    else
        error(("unknown handling field %s"):format(tostring(name)))
    end
end

local function snapshot(vehicle)
    local values = {}
    for name in pairs(types) do
        values[name] = read(vehicle, name)
    end
    return values
end

local function state()
    if current == 0 then
        return { vehicle = false }
    end
    originals[current] = originals[current] or snapshot(current)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(current))
    local label = GetLabelText(model)
    return {
        vehicle = {
            label = label == "NULL" and model or label,
            model = model:lower(),
            plate = (GetVehicleNumberPlateText(current):gsub("^%s+", ""):gsub("%s+$", ""))
        },
        values = snapshot(current),
        originals = originals[current]
    }
end

CreateThread(function()
    while true do
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle ~= current then
            current = vehicle
            for handle in pairs(originals) do
                if not DoesEntityExist(handle) then
                    originals[handle] = nil
                end
            end
            plugin.nui.send("state", state())
        end
        Wait(POLL_MS)
    end
end)

plugin.nui.on("load", function(_, cb)
    cb({ groups = layout, state = state() })
end)

plugin.nui.on("set", function(data, cb)
    if current ~= 0 then
        write(current, data.name, data.value)
    end
    cb(state())
end)

plugin.nui.on("reset", function(_, cb)
    if current ~= 0 then
        for name, value in pairs(originals[current]) do
            write(current, name, value)
        end
    end
    cb(state())
end)
