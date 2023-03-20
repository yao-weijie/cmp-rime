local M = {}

M.order = function(entry1, entry2)
    local rime1 = entry1.source.name == "rime"
    local rime2 = entry2.source.name == "rime"

    if rime1 and rime2 then
        return entry1.id < entry2.id
    end

    if rime1 and not rime2 then
        return true
    end

    if not rime1 and rime2 then
        return false
    end

    -- 剩下两个都不是rime entry, 不进行排序
end

return M
