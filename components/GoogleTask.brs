sub init()
    m.top.functionName = "runTask"
    cfg = GetConfig()
    m.clientId = cfg.google.clientId
    m.clientSecret = cfg.google.clientSecret
end sub

sub runTask()
    loadSavedTokens()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    handleStatus(m.top.status)
    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGNodeEvent" and msg.getField() = "status" then
            handleStatus(msg.getData())
        end if
    end while
end sub

sub handleStatus(status as string)
    if status = "AUTHENTICATE" then
        getDeviceCode()
    else if status = "FETCH_CALENDAR" then
        fetchGoogleCalendar()
    end if
end sub

function loadSavedTokens() as boolean
    sec = CreateObject("roRegistrySection", "Authentication")
    if sec.Exists("google_refresh_token") then
        m.refreshToken = sec.Read("google_refresh_token")
        m.accessToken = sec.Read("google_access_token")
        m.top.status = "SUCCESS"
        return true
    end if
    return false
end function

sub saveTokens(json as object)
    sec = CreateObject("roRegistrySection", "Authentication")
    if json.refresh_token <> invalid then 
        m.refreshToken = json.refresh_token
        sec.Write("google_refresh_token", json.refresh_token)
    end if
    if json.access_token <> invalid then 
        m.accessToken = json.access_token
        sec.Write("google_access_token", json.access_token)
    end if
    sec.Flush()
end sub

sub getDeviceCode()
    url = "https://oauth2.googleapis.com/device/code"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    params = "client_id=" + m.clientId + "&scope=https://www.googleapis.com/auth/calendar.readonly"
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            if msg.GetResponseCode() = 200 then
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if json <> invalid then
                        m.top.authResult = json
                        pollForToken(json.device_code, json.interval)
                    end if
                end if
            else
                m.top.status = "GOOG_AUTH_ERR_" + msg.GetResponseCode().toStr()
            end if
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    url = "https://oauth2.googleapis.com/token"
    params = "client_id=" + m.clientId + "&client_secret=" + m.clientSecret + "&device_code=" + deviceCode + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
    while true
        xfer = CreateObject("roUrlTransfer")
        xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
        port = CreateObject("roMessagePort")
        xfer.SetMessagePort(port)
        if xfer.AsyncPostFromString(params) then
            msg = wait(10000, port)
            if type(msg) = "roUrlEvent" then
                code = msg.GetResponseCode()
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if code = 200 and json <> invalid and json.access_token <> invalid then
                        saveTokens(json)
                        m.top.status = "SUCCESS"
                        return
                    else if json <> invalid and json.error <> "authorization_pending" then
                        m.top.status = "GOOG_TOKEN_ERR_" + json.error
                        return
                    end if
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

sub fetchGoogleCalendar()
    if m.accessToken = invalid then 
        m.top.status = "GOOG_FETCH_NO_TOKEN"
        return
    end if
    now = CreateObject("roDateTime")
    timeMin = now.toISOString()
    url = "https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=" + timeMin + "&singleEvents=true&orderBy=startTime"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncGetToString() then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            if code = 200 then
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if json <> invalid and json.items <> invalid then
                        eventsAA = {}
                        for each item in json.items
                            dayPart = invalid
                            if item.start <> invalid and item.start.date <> invalid then
                                dayPart = item.start.date
                            else if item.start <> invalid and item.start.dateTime <> invalid then
                                dayPart = item.start.dateTime.split("T")[0]
                            end if
                            if dayPart <> invalid then
                                daySegments = dayPart.split("-")
                                if daySegments.count() >= 3 then
                                    dayNum = Val(daySegments[2]).toStr()
                                    if not eventsAA.doesExist(dayNum) then eventsAA[dayNum] = item.summary
                                end if
                            end if
                        end for
                        m.top.calendarData = eventsAA
                        m.top.status = "GOOG_FETCH_OK_" + json.items.count().toStr()
                    end if
                end if
            else
                m.top.status = "GOOG_FETCH_ERR_" + code.toStr()
            end if
        end if
    end if
end sub
