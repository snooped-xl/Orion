--[[
                    Better script dumper
    basicaly a script dumper but it keeps the Instance hierarchy
    problems: does not check if path is valid
    tba: maybe somehow make the filenames consistent but i doubt thats gonna be easily done
    Discord: fyz#7690
]]
local ignore_empty_scripts = true
local randomize_name = false
local prefix = "scripts_"..tostring(game.PlaceId)
local CoreGui = game.CoreGui
local CorePackages = game.CorePackages
local decomp_idx = 0
local scriptslen = 0
local scripts = {}
local tree = {}

local invalid_chars = {string.char(127), "\\", ":", "*", "?", "\"", "<", ">", "|"}
for i=0  , 32  do table.insert(invalid_chars, string.char(i)) end
for i=128, 255 do table.insert(invalid_chars, string.char(i)) end

local function gatherscripts(inst)
    if (inst.ClassName == "LocalScript" or inst.ClassName == "ModuleScript") and not (inst:IsDescendantOf(CoreGui) or inst:IsDescendantOf(CorePackages)) then
        table.insert(scripts, inst)
    end
    for _,v in next, inst:GetChildren() do
        gatherscripts(v)
    end
end

for _, v in next, getnilinstances() do
    gatherscripts(v)
end

gatherscripts(settings())

for _,v in next, scripts do
    local split = string.split(v:GetFullName(), ".")
    local slen = #split
    local top_parent = nil

    if #split > 1 then
        local parent_tmp = v
        repeat
            top_parent = parent_tmp
            parent_tmp = parent_tmp.Parent
        until parent_tmp == nil

        if not tree[top_parent.Name] then
            tree[top_parent.Name] = {}
        end
        local ct = tree[top_parent.Name]
        for idx, s in next, split do
            if idx == slen then
                break
            end
            if not ct[s] then
                ct[s] = {}
            end
            ct = ct[s]
        end
        if randomize_name then
            ct[v:GetDebugId().."_"..v.Name.."."..v.ClassName..".lua"] = v;
        else
            if ct[v.Name.."."..v.ClassName..".lua"] then
                warn("Duplicate script name found, ignoring:", v:GetFullName())
            end
            ct[v.Name.."."..v.ClassName..".lua"] = v;
        end
    else
        if randomize_name then
            tree[v:GetDebugId().."_"..v.Name.."."..v.ClassName..".lua"] = v
        else
            if tree[v.Name.."."..v.ClassName..".lua"] then
                warn("Duplicate script name in nil found, ignoring:", v:GetFullName())
            end
            tree[v.Name.."."..v.ClassName..".lua"] = v;
        end
    end
end

local function makevalid(str)
    for _, c in next, invalid_chars do
        str = str.gsub(str, c, "")
    end
    return str
end

scriptslen = #scripts
local function walk_tree(t, path)
    for i,v in next, t do
        i = makevalid(i)
        local p = path
        if typeof(v) == "table" then
            walk_tree(v, p.."/"..i)
        elseif typeof(v) == "Instance" then
            if p == "" then
                p = "/"
            end
            print(p,i,v)
            decomp_idx = decomp_idx+1
            print("Decompiling "..decomp_idx.."/"..scriptslen)
            local stat, src = pcall(decompile, v)
            if not stat then
                print("Script with no bytecode", v:GetFullName())
                continue
            end
            if ignore_empty_scripts and #src < 200 then
                local is_not_comment_only = false
                for _,y in next, string.split(src, "\
") do
                    if string.sub(y, 1, 2) ~= "--" then
                        is_not_comment_only = true
                        break
                    end
                end
                if not is_not_comment_only then
                    print("Empty script not saved", v:GetFullName())
                    continue
                end
            end
            p = prefix..p
            if not isfolder(p) then
                makefolder(p)
            end
            if not pcall(function()
                writefile(p.."/"..i, src);
            end) then
                print(p.."/"..i)
                error()
            end
        else
            print("how the fuck")
        end
    end
end

walk_tree(tree, "")