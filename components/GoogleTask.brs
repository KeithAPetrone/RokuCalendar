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
    
    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGNodeEvent" and msg.getField() = "status" then
            status = m.top.status
            if status = "AUTHENTICATE" then
                getDeviceCode()
            else if status = "FETCH_CALENDAR" then
                fetchGoogleCalendar()
            end if
        end if
    end while
end sub

' --- Persistence ---
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

' --- OAuth Flow ---
sub getDeviceCode()
    url = "https://oauth2.googleapis.com/device/code"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    params = "client_id=" + m.clientId + "&scope=https://www.googleapis.com/auth/calendar.readonly"
    response = xfer.PostFromString(params)
    if response <> "" then
        json = ParseJson(response)
        if json <> invalid then
            m.top.authResult = json
            pollForToken(json.device_code, json.interval)
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    url = "https://oauth2.googleapis.com/token"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    params = "client_id=" + m.clientId + "&client_secret=" + m.clientSecret
    params += "&device_code=" + deviceCode + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
    while true
        response = xfer.PostFromString(params)
        if response <> "" then
            json = ParseJson(response)
            if json <> invalid then
                if json.access_token <> invalid then
                    saveTokens(json)
                    m.top.status = "SUCCESS"
                    return
                else if json.error <> "authorization_pending" then
                    m.top.status = "ERROR"
                    return
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

' --- Data Fetching ---
sub fetchGoogleCalendar()
    if m.accessToken = invalid then return
    now = CreateObject("roDateTime")
    timeMin = now.ToISO8601String()
    url = "https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=" + timeMin + "&singleEvents=true&orderBy=startTime"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    response = xfer.GetToString()
    if response <> "" then
        json = ParseJson(response)
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
        end if
    end if
end sub
