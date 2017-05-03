local t_insert = table.insert
local t_remove = table.remove
local t_concat = table.concat
local strbyte = string.byte
local strformat = string.format


local cursor_methods = { }
local cursor_mt = { __index = cursor_methods }

local function new_cursor(col, query, returnfields, num_each_query, limit, offset)
    return setmetatable ( {
            col = col ;
            query = query ;
            returnfields = returnfields ;

            id = false ;
            results = { } ;

            done = false ;
            i = 0;
            localIndex = 0;
            offset = offset;
            limit_n = limit;
            num_each = num_each_query;
        } , cursor_mt )
end

cursor_mt.__gc = function( self )
    self.col:kill_cursors({ self.id })
end

cursor_mt.__tostring = function ( ob )
    local t = { }
    for i = 1 , 8 do
        t_insert(t, strformat("%02x", strbyte(ob.id, i, i)))
    end
    return "CursorId(" .. t_concat ( t ) .. ")"
end

function cursor_methods:limit(n)
    assert(n)
    self.limit_n = n
end

--todo
--function cursor_methods:skip(n)

function cursor_methods:sort(field)
    if not field then return nil, "field should not be nil" end

    local key, asc, t
    for k,v in pairs(field) do
        key = k
        asc = v
        break
    end
    if asc ~= 1 and asc ~= -1 then return nil, "order must be 1 or -1" end

    local sort_f =
            function(a, b)
                if not a and not b then return false end
                if not a then return true end
                if not b then return false end
                if not a[key] and not b[key] then return false end
                if not a[key] then return true end
                if not b[key] then return false end
                if asc == 1 then
                    return a[key] < b[key]
                else
                    return a[key] > b[key]
                end
            end

    local size = self.num_each
    if #self.results > 0 then
        table.sort(self.results, sort_f)
    elseif #self.results == 0 and self.i == 0 then
        if self.limit_n == 0 then
            size = self.num_each
        else
            size = (self.num_each < self.limit_n
                        and self.num_each) or self.limit_n
        end

        self.id, self.results, t = self.col:query(self.query,
                        self.returnfields, self.offset, size)
        table.sort(self.results, sort_f)
    else
        return nil, "sort must be an array"
    end
    return self.results
end

function cursor_methods:next()
    if self.limit_n > 0 and self.i >= self.limit_n then return nil end

    local v = self.results [ self.localIndex + 1 ]
    if v ~= nil then
        self.i = self.i + 1
        self.localIndex = self.localIndex + 1
        self.results [ self.localIndex ] = nil
        return self.i , v
    end

    if self.done then return nil end

    local t
    self.localIndex = 0
    if not self.id then
        self.id, self.results, t = self.col:query(self.query,
                        self.returnfields, self.offset, self.num_each)
        if self.id == "\0\0\0\0\0\0\0\0" then
            self.done = true
        end
    else
        self.id, self.results, t = self.col:getmore(self.id, self.num_each)
        if self.id == "\0\0\0\0\0\0\0\0" then
            self.done = true
        elseif t.CursorNotFound then
            self.id = false
        end
    end
    return self:next ( )
end

function cursor_methods:pairs( )
    return self.next, self
end

return new_cursor
