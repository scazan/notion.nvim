local M = {}

--Get the full object and its type from its ID (NoteL type shouldnt be required, but simplifies and makes the code breath)
M.objectFromID = function(id)
    local raw = vim.json.decode(require "notion".raw()).results
    for _, v in pairs(raw) do
        if v.id == id then
            return {
                object = v.parent.type,
                result = v
            }
        end
    end
    return vim.err_writeln("[Notion] Cannot find object with id: " .. id)
end

--Converts notion objects to markdown
M.notionToMarkdown = function(selection)
    local data = M.objectFromID(selection.value.id)
    local markdownParser = require "notion.markdown"
    if data.object == "database_id" then
        return markdownParser.databaseEntry(data.result, selection.value.id, false)
    elseif data.object == "page_id" then
        return markdownParser.page(data.result, selection.value.id, false)
    else
        return vim.print("[Notion] Cannot view or edit this event")
    end
end

--Parse ISO8601 date, and return the values separated
M.parseISO8601Date = function(isoDate)
    local year, month, day, hour, minute, second, timezone = isoDate:match(
        "(%d+)-(%d+)-(%d+)T?(%d*):?(%d*):?(%d*).?([%+%-]?)(%d*:?%d*)")
    return tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(minute), tonumber(second),
        timezone,
        timezone and
        (tonumber(timezone) or timezone)
end

--Gets date as comparable (integer)
M.getDate = function(v)
    if v.properties.Dates == nil or v.properties.Dates.date == vim.NIL or v.properties.Dates.date.start == nil then
        return
        "No Date"
    end
    local str = v.properties.Dates.date.start
    local date = str:gsub("-", ""):gsub("T", ""):gsub(":", ""):gsub("+", "")

    return date
end

--Returns full display date of the notion event
M.displayDate = function(inputDate)
    local year, month, day, hour, minute, second, timezone, timezoneValue = M.parseISO8601Date(inputDate)
    local humanReadableDate

    if hour and minute and second then
        local timezoneSign = (timezone == "+") and "+" or "-"
        local timezoneHoursDiff = tonumber(timezoneValue) or 0
        humanReadableDate = string.format("%s %d, %d at %02d:%02d %s%02d:%02d",
            os.date("%B", os.time({ year = year, month = month, day = day })), day, year, hour, minute, timezoneSign,
            timezoneHoursDiff, 0)
    else
        humanReadableDate = string.format("%s %d, %d",
            os.date("%B", os.time({ year = year, month = month, day = day })),
            day, year)
    end
    return humanReadableDate
end


-- Returns only the time of day of the notion event
M.displayShortDate = function(inputDate)
    local year, month, day, hour, minute, _, _, _ = M.parseISO8601Date(inputDate)
    local currentDateTime = os.date("*t")

    local currentYear = currentDateTime.year
    local currentMonth = currentDateTime.month
    local currentDay = currentDateTime.day

    if year == currentYear and month == currentMonth and day == currentDay then
        local formattedTime = string.format("%02d:%02d", hour, minute)
        return formattedTime
    else
        return M.displayDate(inputDate)
    end
end

--Returns the earliest event as a block
M.earliest = function(opts)
    if opts == " " or opts == nil then return vim.err_writeln("[Notion] Unexpected argument") end
    local content = (vim.json.decode(opts)).results
    local biggestDate = " "
    local data
    for _, v in pairs(content) do
        if v.properties.Dates ~= nil and v.properties.Dates.date ~= vim.NIL and v.properties.Dates.date.start ~= nil then
            local final = M.getDate(v)

            if (final < biggestDate or data == nil) and final > vim.fn.strftime("%Y%m%d") then
                biggestDate = final
                data = v
            end
        end
    end
    return data
end

--Get list of event - Only supports databse entries and pages
M.eventList = function(opts)
    if opts == " " or opts == nil then return nil end
    local content = vim.json.decode(opts).results
    local data = {}
    for _, v in pairs(content) do
        if v == vim.NIL or v.parent == vim.NIL then return end
        if v.parent.type == "database_id" then
            vim.print("added databse element")
            local added = false
            for i, k in pairs(v.properties) do
                if k.type == "title" and added == false and k.title[1] ~= nil and k.title[1].plain_text ~= nil then
                    table.insert(data, {
                        displayName = k.title[1].plain_text,
                        id = v.id
                    })
                    added = true
                end
            end
        elseif v.parent.type == "page_id" then
            vim.print('added page element')
            table.insert(data, {
                displayName = v.properties.title.title[1].plain_text,
                id = v.id
            })
        end
    end
    return data
end

--Event previewer, returns array of string
M.eventPreview = function(data)
    local id = data.value.id

    local block = (M.objectFromID(id)).result
    local final = { "Name: " .. data.value.displayName, " " }

    --Display every individual property block
    for i, v in pairs(block.properties) do
        if v.type == "date" then
            table.insert(final, i .. ": " .. M.displayDate(v.date.start))
            table.insert(final, " ")
        elseif v.type == "select" and v.select ~= nil then
            table.insert(final, i .. ": " .. v.select.name)
            table.insert(final, " ")
        elseif v.type == "multi_select" then
            local temp = {}
            for _, j in pairs(v.multi_select) do
                table.insert(temp, j.name)
            end
            table.insert(final, i .. ": " .. table.concat(temp, ", "))
            table.insert(final, " ")
        elseif v.type == "number" and v.number ~= vim.NIL then
            table.insert(final, i .. ": " .. v.number)
            table.insert(final, " ")
        elseif v.type == "email" and v.email ~= vim.NIL then
            table.insert(final, i .. ": " .. v.email)
            table.insert(final, " ")
        elseif v.type == "url" and v.url ~= vim.NIL then
            table.insert(final, i .. ": " .. v.url)
            table.insert(final, " ")
        elseif v.type == "people" and v.people[1] ~= nil then
            table.insert(final, i .. ": " .. v.people[1].name)
            table.insert(final, " ")
        end
    end

    return final
end

M.databaseName = function(object)
    return object.icon.emoji .. " " .. object.title.text.content
end

return M
