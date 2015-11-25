return function (conn, chunk)
  local band = bit.band
  local bor = bit.bor
  local rshift = bit.rshift
  local lshift = bit.lshift
  local char = string.char
  local byte = string.byte
  local sub = string.sub
  local applyMask = crypto.mask

  local function decode(chunk)
    if #chunk < 2 then return end
    local second = byte(chunk, 2)
    local len = band(second, 0x7f)
    local offset
    if len == 126 then
      if #chunk < 4 then return end
      len = bor(
        lshift(byte(chunk, 3), 8),
        byte(chunk, 4))
      offset = 4
    elseif len == 127 then
      if #chunk < 10 then return end
      len = bor(
        -- Ignore lengths longer than 32bit
        lshift(byte(chunk, 7), 24),
        lshift(byte(chunk, 8), 16),
        lshift(byte(chunk, 9), 8),
        byte(chunk, 10))
      offset = 10
    else
      offset = 2
    end
    local mask = band(second, 0x80) > 0
    if mask then
      offset = offset + 4
    end
    if #chunk < offset + len then return end

    local first = byte(chunk, 1)
    local payload = sub(chunk, offset + 1, offset + len)
    assert(#payload == len, "Length mismatch")
    if mask then
      payload = applyMask(payload, sub(chunk, offset - 3, offset))
    end
    local extra = sub(chunk, offset + len + 1)
    local opcode = band(first, 0xf)
    return extra, payload, opcode
  end

  local function encode(payload, opcode)
    opcode = opcode or 2
    assert(type(opcode) == "number", "opcode must be number")
    assert(type(payload) == "string", "payload must be string")
    local len = #payload
    local head = char(
      bor(0x80, opcode),
      len < 126 and len or (len < 0x10000) and 126 or 127
    )
    if len >= 0x10000 then
      head = head .. char(
      0,0,0,0, -- 32 bit length is plenty, assume zero for rest
      band(rshift(len, 24), 0xff),
      band(rshift(len, 16), 0xff),
      band(rshift(len, 8), 0xff),
      band(len, 0xff)
    )
    elseif len >= 126 then
      head = head .. char(band(rshift(len, 8), 0xff), band(len, 0xff))
    end
    return head .. payload
  end

  local function setBit(io, keydown)
    end

  function onmessage(payload, opcode)
    if opcode == 1 then--text
    elseif opcode == 2 then--binary
      local p = byte(payload, 1)
      local io = bit.band(p, 63)
      if bit.band(p, 128) == 0 then
        --short
        gpio.mode(io, gpio.OUTPUT)
        gpio.write(io, gpio.LOW)
      else
        --float/open
        gpio.mode(io, gpio.INPUT, gpio.FLOAT)
      end
  end
  end

  local function onChunk(conn, chunk)
    buffer = buffer .. chunk
    while true do
      collectgarbage()
      local extra, payload, opcode = decode(buffer)
      if not extra then return end
      buffer = extra
      if opcode == 9 then--ping
        print("ping")
        conn:send(encode(payload, 10))--pong
      elseif opcode == 8 then--bye
        conn:close()
      else
        onmessage(payload, opcode)
      end
    end
  end

  local key = chunk:match("\r\nSec%-WebSocket%-Key: *([^\r]+)\r\n")
  assert(key, "Got WebSocket request without key")

  buffer = ""
  conn:on("receive", onChunk)
  conn:send("HTTP/1.1 101 Switching Protocols\r\n")
  conn:send("Upgrade: websocket\r\n")
  conn:send("Connection: Upgrade\r\n")
  conn:send("Sec-WebSocket-Accept: " .. crypto.toBase64(crypto.sha1(key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")) .. "\r\n\r\n")
end
